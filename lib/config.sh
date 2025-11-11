#!/usr/bin/env bash
# lib/config.sh - sing-box configuration generation
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CONFIG_LOADED:-}" ]] && return 0
readonly _SBX_CONFIG_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/network.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/validation.sh"
# shellcheck source=/dev/null
source "${_LIB_DIR}/config_validator.sh"

#==============================================================================
# Configuration Variables Validation
#==============================================================================

# Validate all required configuration variables are set
validate_config_vars() {
  local errors=0
  local var_name var_value var_desc

  msg "Validating configuration parameters..."

  # Required variables for all installations
  for var_spec in \
    "UUID:UUID" \
    "REALITY_PORT_CHOSEN:Reality port" \
    "PRIV:Reality private key" \
    "SID:Reality short ID"; do

    IFS=':' read -r var_name var_desc <<< "$var_spec"
    var_value="${!var_name:-}"

    if [[ -z "$var_value" ]]; then
      err "  ✗ $var_desc is not set"
      ((errors++))
    else
      success "  ✓ $var_desc configured"
    fi
  done

  return $errors
}

#==============================================================================
# Base Configuration Generation
#==============================================================================

# Create base sing-box configuration
create_base_config() {
  local ipv6_supported="${1:-false}"
  local log_level="${2:-warn}"

  local base_config

  if [[ "$ipv6_supported" == "false" ]]; then
    msg "  - Applying IPv4-only DNS configuration for network compatibility"
    if ! base_config=$(jq -n \
      --arg log_level "$log_level" \
      '{
        log: { level: $log_level, timestamp: true },
        dns: {
          servers: [{
            type: "local",
            tag: "dns-local"
          }],
          strategy: "ipv4_only"
        },
        inbounds: [],
        outbounds: [
          { type: "direct", tag: "direct" },
          { type: "block", tag: "block" }
        ]
      }' 2>/dev/null); then
      err "Failed to create base configuration with jq"
      return 1
    fi
  else
    msg "  - Using default DNS configuration for dual-stack network"
    if ! base_config=$(jq -n \
      --arg log_level "$log_level" \
      '{
        log: { level: $log_level, timestamp: true },
        dns: {
          servers: [{
            type: "local",
            tag: "dns-local"
          }]
        },
        inbounds: [],
        outbounds: [
          { type: "direct", tag: "direct" },
          { type: "block", tag: "block" }
        ]
      }' 2>/dev/null); then
      err "Failed to create base configuration with jq"
      return 1
    fi
  fi

  echo "$base_config"
}

#==============================================================================
# Inbound Configuration Generation
#==============================================================================

# Create Reality inbound configuration
create_reality_inbound() {
  local uuid="$1"
  local port="$2"
  local listen_addr="$3"
  local sni="$4"
  local priv_key="$5"
  local short_id="$6"

  # Input validation
  [[ -n "$uuid" ]] || { err "UUID cannot be empty"; return 1; }
  [[ -n "$priv_key" ]] || { err "Private key cannot be empty"; return 1; }
  [[ -n "$short_id" ]] || { err "Short ID cannot be empty"; return 1; }

  # Validate port range
  if ! validate_port "$port" 2>/dev/null; then
    err "Invalid port: $port (must be 1-65535)"
    return 1
  fi

  local reality_config

  msg "  - Creating Reality inbound configuration..."

  if ! reality_config=$(jq -n \
    --arg uuid "$uuid" \
    --arg port "$port" \
    --arg listen_addr "$listen_addr" \
    --arg sni "$sni" \
    --arg priv "$priv_key" \
    --arg sid "$short_id" \
    '{
      type: "vless",
      tag: "in-reality",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid, flow: "xtls-rprx-vision" }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: {
        enabled: true,
        server_name: $sni,
        reality: {
          enabled: true,
          private_key: $priv,
          short_id: [$sid],
          handshake: { server: $sni, server_port: 443 },
          max_time_difference: "1m"
        },
        alpn: ["h2", "http/1.1"]
      }
    }' 2>&1); then
    err "Failed to create Reality configuration. jq output:"
    err "$reality_config"
    return 1
  fi

  success "  ✓ Reality inbound configured"
  echo "$reality_config"
}

# Create WS-TLS inbound configuration
create_ws_inbound() {
  local uuid="$1"
  local port="$2"
  local listen_addr="$3"
  local domain="$4"
  local cert_path="$5"
  local key_path="$6"

  local ws_config

  if ! ws_config=$(jq -n \
    --arg uuid "$uuid" \
    --arg port "$port" \
    --arg listen_addr "$listen_addr" \
    --arg domain "$domain" \
    --arg cert_path "$cert_path" \
    --arg key_path "$key_path" \
    '{
      type: "vless",
      tag: "in-ws",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: {
        enabled: true,
        server_name: $domain,
        certificate_path: $cert_path,
        key_path: $key_path,
        alpn: ["h2", "http/1.1"]
      },
      transport: { type: "ws", path: "/ws" }
    }' 2>/dev/null); then
    err "Failed to create WS-TLS configuration with jq"
    return 1
  fi

  echo "$ws_config"
}

# Create Hysteria2 inbound configuration
create_hysteria2_inbound() {
  local password="$1"
  local port="$2"
  local listen_addr="$3"
  local cert_path="$4"
  local key_path="$5"

  local hy2_config

  if ! hy2_config=$(jq -n \
    --arg password "$password" \
    --arg port "$port" \
    --arg listen_addr "$listen_addr" \
    --arg cert_path "$cert_path" \
    --arg key_path "$key_path" \
    '{
      type: "hysteria2",
      tag: "in-hy2",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ password: $password }],
      up_mbps: 100,
      down_mbps: 100,
      tls: {
        enabled: true,
        certificate_path: $cert_path,
        key_path: $key_path,
        alpn: ["h3"]
      }
    }' 2>/dev/null); then
    err "Failed to create Hysteria2 configuration with jq"
    return 1
  fi

  echo "$hy2_config"
}

#==============================================================================
# Route Configuration
#==============================================================================

# Add route configuration for sing-box 1.12.0+ compatibility
add_route_config() {
  local config="$1"
  local has_certs="${2:-false}"

  local route_inbounds='["in-reality"]'
  if [[ "$has_certs" == "true" ]]; then
    route_inbounds='["in-reality", "in-ws", "in-hy2"]'
  fi

  local updated_config
  if ! updated_config=$(echo "$config" | jq --argjson inbounds "$route_inbounds" '.route = {
    "rules": [
      {
        "inbound": $inbounds,
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ],
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-local"
    }
  }' 2>/dev/null); then
    err "Failed to add route configuration"
    return 1
  fi

  echo "$updated_config"
}

#==============================================================================
# Outbound Configuration
#==============================================================================

# Add outbound configuration parameters
add_outbound_config() {
  local config="$1"

  msg "  - Configuring outbound connection parameters"

  local updated_config
  if ! updated_config=$(echo "$config" | jq '.outbounds[0] += {
    "bind_interface": "",
    "routing_mark": 0,
    "reuse_addr": false,
    "connect_timeout": "5s",
    "tcp_fast_open": true,
    "udp_fragment": true
  }' 2>/dev/null); then
    warn "Failed to add outbound parameters, continuing with default configuration"
    echo "$config"
    return 0
  fi

  success "  ✓ Outbound configuration applied"
  echo "$updated_config"
}

#==============================================================================
# Main Configuration Generation
#==============================================================================

# Generate complete sing-box configuration
write_config() {
  msg "Writing $SB_CONF ..."
  mkdir -p "$SB_CONF_DIR"

  # Detect network stack support
  msg "Detecting network stack support..."
  local ipv6_supported
  ipv6_supported=$(detect_ipv6_support)

  local listen_addr
  listen_addr=$(choose_listen_address "$ipv6_supported")

  if [[ "$ipv6_supported" == "true" ]]; then
    success "  ✓ IPv6 support detected - using dual-stack listen with default DNS strategy"
  else
    warn "  ⚠ IPv6 not available - using dual-stack listen with IPv4-only DNS strategy"
  fi

  # Validate all required variables
  validate_config_vars || die "Configuration validation failed. Please check the errors above."

  # Certificate validation if provided
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    validate_cert_files "$CERT_FULLCHAIN" "$CERT_KEY" || die "Certificate validation failed"

    # Validate additional variables for certificate-based configurations
    [[ -n "$WS_PORT_CHOSEN" ]] || die "WebSocket port is not set for certificate configuration."
    [[ -n "$HY2_PORT_CHOSEN" ]] || die "Hysteria2 port is not set for certificate configuration."
    [[ -n "$DOMAIN" ]] || die "Domain is not set for certificate configuration."
    [[ -n "$HY2_PASS" ]] || die "Hysteria2 password is not set for certificate configuration."
  fi

  # Create temporary file for atomic write with secure permissions
  local temp_conf
  temp_conf=$(mktemp) || die "Failed to create secure temporary file"
  chmod 600 "$temp_conf" || die "Failed to set secure permissions on temporary file"

  # Setup automatic cleanup on function exit/error
  # This trap will clean up temp file on RETURN, ERR, EXIT, INT, or TERM
  cleanup_write_config() {
    [[ -f "$temp_conf" ]] && rm -f "$temp_conf" 2>/dev/null || true
  }
  trap cleanup_write_config RETURN ERR EXIT INT TERM

  # Create base configuration
  local base_config
  base_config=$(create_base_config "$ipv6_supported" "${LOG_LEVEL:-warn}") || \
    die "Failed to create base configuration"

  # Add Reality inbound
  local reality_config
  reality_config=$(create_reality_inbound "$UUID" "$REALITY_PORT_CHOSEN" "$listen_addr" \
    "${SNI_DEFAULT:-www.microsoft.com}" "$PRIV" "$SID") || \
    die "Failed to create Reality inbound"

  # Add Reality inbound to base config
  base_config=$(echo "$base_config" | jq --argjson reality "$reality_config" \
    '.inbounds += [$reality]' 2>/dev/null) || \
    die "Failed to add Reality configuration to base config"

  # Add WS-TLS and Hysteria2 inbounds if certificates are available
  local has_certs="false"
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    has_certs="true"

    # Add WS-TLS inbound
    local ws_config
    ws_config=$(create_ws_inbound "$UUID" "$WS_PORT_CHOSEN" "$listen_addr" \
      "$DOMAIN" "$CERT_FULLCHAIN" "$CERT_KEY") || \
      die "Failed to create WS-TLS inbound"

    # Add Hysteria2 inbound
    local hy2_config
    hy2_config=$(create_hysteria2_inbound "$HY2_PASS" "$HY2_PORT_CHOSEN" "$listen_addr" \
      "$CERT_FULLCHAIN" "$CERT_KEY") || \
      die "Failed to create Hysteria2 inbound"

    # Add both WS and Hysteria2 inbounds
    base_config=$(echo "$base_config" | jq --argjson ws "$ws_config" \
      --argjson hy2 "$hy2_config" '.inbounds += [$ws, $hy2]' 2>/dev/null) || \
      die "Failed to add WS-TLS and Hysteria2 configurations"
  fi

  # Add route configuration
  base_config=$(add_route_config "$base_config" "$has_certs") || \
    die "Failed to add route configuration"

  # Add outbound configuration
  base_config=$(add_outbound_config "$base_config")

  # Write configuration to temporary file
  echo "$base_config" > "$temp_conf" || \
    die "Failed to write configuration to temporary file"

  # Run comprehensive validation pipeline before applying
  if ! validate_config_pipeline "$temp_conf"; then
    err "Configuration validation failed. See errors above."
    die "Generated configuration is invalid. This is a bug in the script."
  fi

  # Disable trap before successful move (we want to keep the file)
  trap - RETURN ERR EXIT INT TERM

  # Atomic move to final location
  if ! mv "$temp_conf" "$SB_CONF"; then
    # Re-enable trap for cleanup on failure
    trap cleanup_write_config RETURN
    die "Failed to move configuration to $SB_CONF"
  fi

  chmod 600 "$SB_CONF"

  success "Configuration written and validated: $SB_CONF"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f validate_config_vars create_base_config create_reality_inbound
export -f create_ws_inbound create_hysteria2_inbound add_route_config
export -f add_outbound_config write_config
