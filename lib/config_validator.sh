#!/usr/bin/env bash
# lib/config_validator.sh - Configuration validation pipeline for sing-box
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Validates sing-box configuration files before applying them
# Dependencies: lib/common.sh, lib/logging.sh, lib/tools.sh
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_CONFIG_VALIDATOR_LOADED:-}" ]] && return 0
readonly _SBX_CONFIG_VALIDATOR_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${_SBX_COMMON_LOADED:-}" ]]; then
    source "${_LIB_DIR}/common.sh"
fi
if [[ -z "${_SBX_LOGGING_LOADED:-}" ]]; then
    source "${_LIB_DIR}/logging.sh"
fi
if [[ -z "${_SBX_TOOLS_LOADED:-}" ]]; then
    source "${_LIB_DIR}/tools.sh"
fi

#==============================================================================
# JSON Syntax Validation
#==============================================================================

# Validate JSON syntax using jq or python
#
# Usage: validate_json_syntax <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 on valid JSON, 1 on invalid JSON
# Example:
#   validate_json_syntax "/etc/sing-box/config.json"
validate_json_syntax() {
    local config_file="$1"

    # Check file exists
    if [[ ! -f "$config_file" ]]; then
        err "Configuration file not found: $config_file"
        return 1
    fi

    # Check file is not empty and contains non-whitespace content
    if [[ ! -s "$config_file" ]] || ! grep -q '[^[:space:]]' "$config_file" 2>/dev/null; then
        err "Configuration file is empty: $config_file"
        return 1
    fi

    # Validate JSON syntax using jq
    if have jq; then
        if ! jq '.' "$config_file" >/dev/null 2>&1; then
            err "Invalid JSON syntax in: $config_file"
            return 1
        fi
        return 0
    fi

    # Fallback to python3
    if have python3; then
        if ! python3 -c "import json; json.load(open('$config_file'))" 2>/dev/null; then
            err "Invalid JSON syntax in: $config_file"
            return 1
        fi
        return 0
    fi

    # No JSON validator available
    warn "No JSON validator available (jq or python3), skipping syntax check"
    return 0
}

#==============================================================================
# sing-box Schema Validation
#==============================================================================

# Validate sing-box configuration schema
#
# Checks for required sections: inbounds, outbounds
# Optional sections: log, dns, route
#
# Usage: validate_singbox_schema <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 on valid schema, 1 on invalid schema
# Example:
#   validate_singbox_schema "/etc/sing-box/config.json"
validate_singbox_schema() {
    local config_file="$1"

    # First validate JSON syntax
    validate_json_syntax "$config_file" || return 1

    # Check required sections using jq
    if have jq; then
        # Check for inbounds section
        if ! jq -e '.inbounds' "$config_file" >/dev/null 2>&1; then
            err "Missing required section 'inbounds' in config"
            return 1
        fi

        # Check for outbounds section
        if ! jq -e '.outbounds' "$config_file" >/dev/null 2>&1; then
            err "Missing required section 'outbounds' in config"
            return 1
        fi

        # Validate inbounds is an array
        if ! jq -e '.inbounds | if type == "array" then true else false end' "$config_file" >/dev/null 2>&1; then
            err "'inbounds' must be an array"
            return 1
        fi

        # Validate outbounds is an array
        if ! jq -e '.outbounds | if type == "array" then true else false end' "$config_file" >/dev/null 2>&1; then
            err "'outbounds' must be an array"
            return 1
        fi

        debug "Schema validation passed: inbounds and outbounds present"
        return 0
    fi

    # Fallback to python3
    if have python3; then
        if ! python3 -c "
import json, sys
with open('$config_file') as f:
    config = json.load(f)
    if 'inbounds' not in config:
        print('Missing required section: inbounds', file=sys.stderr)
        sys.exit(1)
    if 'outbounds' not in config:
        print('Missing required section: outbounds', file=sys.stderr)
        sys.exit(1)
    if not isinstance(config['inbounds'], list):
        print('inbounds must be an array', file=sys.stderr)
        sys.exit(1)
    if not isinstance(config['outbounds'], list):
        print('outbounds must be an array', file=sys.stderr)
        sys.exit(1)
" 2>&1; then
            return 1
        fi
        return 0
    fi

    # No validator available
    warn "No schema validator available, skipping schema check"
    return 0
}

#==============================================================================
# Port Conflict Detection
#==============================================================================

# Detect port conflicts in inbound configurations
#
# Usage: validate_port_conflicts <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 if no conflicts, 1 if conflicts detected
# Example:
#   validate_port_conflicts "/etc/sing-box/config.json"
validate_port_conflicts() {
    local config_file="$1"

    # First validate JSON syntax
    validate_json_syntax "$config_file" || return 1

    if have jq; then
        # Extract all listen_port values
        local ports
        ports=$(jq -r '.inbounds[]?.listen_port // empty' "$config_file" 2>/dev/null | sort)

        # Check for empty result (no ports configured or no inbounds)
        if [[ -z "$ports" ]]; then
            debug "No ports configured in inbounds"
            return 0
        fi

        # Check for duplicates
        local unique_ports
        unique_ports=$(echo "$ports" | uniq)

        if [[ "$ports" != "$unique_ports" ]]; then
            local duplicate_port
            duplicate_port=$(echo "$ports" | uniq -d | head -1)
            err "Port conflict detected: port $duplicate_port is used by multiple inbounds"
            return 1
        fi

        debug "Port conflict check passed: all ports unique"
        return 0
    fi

    # Fallback to python3
    if have python3; then
        if ! python3 -c "
import json, sys
with open('$config_file') as f:
    config = json.load(f)
    ports = []
    for inbound in config.get('inbounds', []):
        if 'listen_port' in inbound:
            port = inbound['listen_port']
            if port in ports:
                print(f'Port conflict detected: port {port} is used by multiple inbounds', file=sys.stderr)
                sys.exit(1)
            ports.append(port)
" 2>&1; then
            return 1
        fi
        return 0
    fi

    # No validator available
    warn "No port validator available, skipping port conflict check"
    return 0
}

#==============================================================================
# TLS Configuration Validation
#==============================================================================

# Validate TLS configuration
#
# Checks for:
# - Valid certificate paths (if not using Reality)
# - Reality configuration completeness
#
# Usage: validate_tls_config <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 if TLS config valid, 1 if invalid
# Example:
#   validate_tls_config "/etc/sing-box/config.json"
validate_tls_config() {
    local config_file="$1"

    # First validate JSON syntax
    validate_json_syntax "$config_file" || return 1

    if have jq; then
        # Check each inbound with TLS enabled
        local tls_inbounds
        tls_inbounds=$(jq -c '.inbounds[]? | select(.tls.enabled == true)' "$config_file" 2>/dev/null)

        # If no TLS inbounds, validation passes
        if [[ -z "$tls_inbounds" ]]; then
            debug "No TLS-enabled inbounds found"
            return 0
        fi

        # Check each TLS inbound
        while IFS= read -r inbound; do
            # Check if Reality is enabled
            local reality_enabled
            reality_enabled=$(echo "$inbound" | jq -r '.tls.reality.enabled // false' 2>/dev/null)

            if [[ "$reality_enabled" == "true" ]]; then
                debug "Reality TLS configuration detected (no certificate paths required)"
                continue
            fi

            # For non-Reality TLS, check certificate paths
            local cert_path key_path
            cert_path=$(echo "$inbound" | jq -r '.tls.certificate_path // empty' 2>/dev/null)
            key_path=$(echo "$inbound" | jq -r '.tls.key_path // empty' 2>/dev/null)

            if [[ -z "$cert_path" || -z "$key_path" ]]; then
                warn "TLS enabled but certificate_path or key_path not specified"
                # Note: Not a fatal error as files might be provided via other means
            fi
        done <<< "$tls_inbounds"

        debug "TLS configuration check passed"
        return 0
    fi

    # No validator available
    warn "No TLS validator available, skipping TLS config check"
    return 0
}

#==============================================================================
# Route Rules Validation
#==============================================================================

# Validate route rules and detect deprecated fields
#
# Checks for:
# - Deprecated 'sniff' field in inbounds (use route rules instead)
# - Deprecated 'domain_strategy' in outbounds (use dns.strategy instead)
# - Modern route rules with action: "sniff", "hijack-dns"
#
# Usage: validate_route_rules <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 if route rules valid, 1 if deprecated fields found
# Example:
#   validate_route_rules "/etc/sing-box/config.json"
validate_route_rules() {
    local config_file="$1"

    # First validate JSON syntax
    validate_json_syntax "$config_file" || return 1

    local has_errors=0

    if have jq; then
        # Check for deprecated 'sniff' field in inbounds
        local deprecated_sniff
        deprecated_sniff=$(jq -r '.inbounds[]? | select(.sniff != null) | .tag // .type' "$config_file" 2>/dev/null)

        if [[ -n "$deprecated_sniff" ]]; then
            err "Deprecated field 'sniff' found in inbound: $deprecated_sniff"
            err "Use route rules with action: 'sniff' instead (sing-box 1.12.0+)"
            has_errors=1
        fi

        # Check for deprecated 'sniff_override_destination' field
        local deprecated_sniff_override
        deprecated_sniff_override=$(jq -r '.inbounds[]? | select(.sniff_override_destination != null) | .tag // .type' "$config_file" 2>/dev/null)

        if [[ -n "$deprecated_sniff_override" ]]; then
            err "Deprecated field 'sniff_override_destination' found in inbound: $deprecated_sniff_override"
            err "Use route rules instead (sing-box 1.12.0+)"
            has_errors=1
        fi

        # Check for deprecated 'domain_strategy' in inbounds
        local deprecated_ds_inbound
        deprecated_ds_inbound=$(jq -r '.inbounds[]? | select(.domain_strategy != null) | .tag // .type' "$config_file" 2>/dev/null)

        if [[ -n "$deprecated_ds_inbound" ]]; then
            err "Deprecated field 'domain_strategy' found in inbound: $deprecated_ds_inbound"
            err "Use global dns.strategy instead (sing-box 1.12.0+)"
            has_errors=1
        fi

        # Check for deprecated 'domain_strategy' in outbounds
        local deprecated_ds_outbound
        deprecated_ds_outbound=$(jq -r '.outbounds[]? | select(.domain_strategy != null) | .tag // .type' "$config_file" 2>/dev/null)

        if [[ -n "$deprecated_ds_outbound" ]]; then
            err "Deprecated field 'domain_strategy' found in outbound: $deprecated_ds_outbound"
            err "Use global dns.strategy instead (sing-box 1.12.0+)"
            has_errors=1
        fi

        if [[ $has_errors -eq 1 ]]; then
            return 1
        fi

        debug "Route rules validation passed (no deprecated fields)"
        return 0
    fi

    # Fallback to python3
    if have python3; then
        if ! python3 -c "
import json, sys
has_errors = False
with open('$config_file') as f:
    config = json.load(f)

    # Check inbounds for deprecated fields
    for inbound in config.get('inbounds', []):
        tag = inbound.get('tag', inbound.get('type', 'unknown'))
        if 'sniff' in inbound:
            print(f\"Deprecated field 'sniff' found in inbound: {tag}\", file=sys.stderr)
            has_errors = True
        if 'sniff_override_destination' in inbound:
            print(f\"Deprecated field 'sniff_override_destination' found in inbound: {tag}\", file=sys.stderr)
            has_errors = True
        if 'domain_strategy' in inbound:
            print(f\"Deprecated field 'domain_strategy' found in inbound: {tag}\", file=sys.stderr)
            has_errors = True

    # Check outbounds for deprecated fields
    for outbound in config.get('outbounds', []):
        tag = outbound.get('tag', outbound.get('type', 'unknown'))
        if 'domain_strategy' in outbound:
            print(f\"Deprecated field 'domain_strategy' found in outbound: {tag}\", file=sys.stderr)
            has_errors = True

    if has_errors:
        sys.exit(1)
" 2>&1; then
            return 1
        fi
        return 0
    fi

    # No validator available
    warn "No route rules validator available, skipping deprecated field check"
    return 0
}

#==============================================================================
# Complete Validation Pipeline
#==============================================================================

# Run complete validation pipeline on configuration file
#
# Executes all validation checks in order:
# 1. JSON syntax validation
# 2. sing-box schema validation
# 3. Port conflict detection
# 4. TLS configuration validation
# 5. Route rules validation (deprecated fields)
# 6. sing-box binary check (if available)
#
# Usage: validate_config_pipeline <config_file>
# Args:
#   $1: Path to JSON configuration file
# Returns:
#   0 if all checks pass, 1 if any check fails
# Example:
#   validate_config_pipeline "/etc/sing-box/config.json"
validate_config_pipeline() {
    local config_file="$1"

    info "Running configuration validation pipeline..."

    # Step 1: JSON syntax
    msg "  [1/6] Validating JSON syntax..."
    if ! validate_json_syntax "$config_file"; then
        err "Configuration validation failed at step 1: JSON syntax"
        return 1
    fi

    # Step 2: sing-box schema
    msg "  [2/6] Validating sing-box schema..."
    if ! validate_singbox_schema "$config_file"; then
        err "Configuration validation failed at step 2: sing-box schema"
        return 1
    fi

    # Step 3: Port conflicts
    msg "  [3/6] Checking for port conflicts..."
    if ! validate_port_conflicts "$config_file"; then
        err "Configuration validation failed at step 3: port conflicts"
        return 1
    fi

    # Step 4: TLS configuration
    msg "  [4/6] Validating TLS configuration..."
    if ! validate_tls_config "$config_file"; then
        warn "Configuration validation warning at step 4: TLS config (non-fatal)"
        # Note: TLS validation warnings are non-fatal
    fi

    # Step 5: Route rules (deprecated fields)
    msg "  [5/6] Validating route rules..."
    if ! validate_route_rules "$config_file"; then
        err "Configuration validation failed at step 5: route rules (deprecated fields)"
        return 1
    fi

    # Step 6: sing-box binary check (if available)
    msg "  [6/6] Running sing-box binary check..."
    if [[ -x "${SB_BIN:-/usr/local/bin/sing-box}" ]]; then
        local sb_bin="${SB_BIN:-/usr/local/bin/sing-box}"
        if ! "$sb_bin" check -c "$config_file" 2>&1 | grep -q "configuration ok" 2>/dev/null; then
            err "Configuration validation failed at step 6: sing-box check"
            "$sb_bin" check -c "$config_file" 2>&1 || true
            return 1
        fi
        debug "sing-box binary validation passed"
    else
        debug "sing-box binary not available, skipping binary check"
    fi

    success "Configuration validation passed all checks"
    return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f validate_json_syntax validate_singbox_schema validate_port_conflicts
export -f validate_tls_config validate_route_rules validate_config_pipeline
