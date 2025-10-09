#!/usr/bin/env bash
# lib/validation.sh - Input validation and security checks
# Part of sbx-lite modular architecture

# Prevent multiple sourcing
[[ -n "${_SBX_VALIDATION_LOADED:-}" ]] && return 0
readonly _SBX_VALIDATION_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Input Sanitization
#==============================================================================

# Enhanced input sanitization to prevent command injection
sanitize_input() {
  local input="$1"
  # Remove potential dangerous characters and limit length
  input="${input//[;&|\`\$()]/}"  # Remove shell metacharacters
  input="${input:0:256}"          # Limit length
  printf '%s' "$input"
}

#==============================================================================
# Domain and Network Validation
#==============================================================================

# Validate domain format with comprehensive checks
validate_domain() {
  local domain="$1"

  # Enhanced domain validation
  [[ -n "$domain" ]] || return 1

  # Check length (max 253 characters for FQDN)
  [[ ${#domain} -le 253 ]] || return 1

  # Check for valid domain format (letters, numbers, dots, hyphens only)
  [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1

  # Must not start or end with hyphen or dot
  [[ ! "$domain" =~ ^[-.]|[-.]$ ]] || return 1

  # Must not contain consecutive dots
  [[ ! "$domain" =~ \.\. ]] || return 1

  # Reserved names
  [[ "$domain" != "localhost" ]] || return 1
  [[ "$domain" != "127.0.0.1" ]] || return 1
  [[ ! "$domain" =~ ^[0-9.]+$ ]] || return 1  # Not an IP address

  return 0
}

#==============================================================================
# Certificate Validation
#==============================================================================

# Validate certificate files with security checks
validate_cert_files() {
  local fullchain="$1"
  local key="$2"

  # Enhanced certificate file validation
  [[ -n "$fullchain" && -n "$key" ]] || {
    err "Certificate paths cannot be empty"
    return 1
  }

  [[ -f "$fullchain" && -f "$key" ]] || {
    err "Certificate files not found"
    return 1
  }

  [[ -r "$fullchain" && -r "$key" ]] || {
    err "Certificate files not readable"
    return 1
  }

  # Check if files are not empty
  [[ -s "$fullchain" && -s "$key" ]] || {
    err "Certificate files are empty"
    return 1
  }

  # Validate certificate format
  if ! openssl x509 -in "$fullchain" -noout 2>/dev/null; then
    err "Invalid certificate format: $fullchain"
    return 1
  fi

  # Validate private key format
  if ! openssl rsa -in "$key" -check -noout 2>/dev/null && \
     ! openssl ec -in "$key" -check -noout 2>/dev/null; then
    err "Invalid private key format: $key"
    return 1
  fi

  # Check certificate expiration
  if ! openssl x509 -in "$fullchain" -checkend 0 -noout 2>/dev/null; then
    warn "Certificate is expired or will expire soon"
  fi

  # Verify certificate and key match (support both RSA and EC keys)
  local cert_pubkey key_pubkey
  local empty_md5="d41d8cd98f00b204e9800998ecf8427e"

  # Extract public key from certificate
  cert_pubkey=$(openssl x509 -in "$fullchain" -noout -pubkey 2>/dev/null | openssl md5)

  # Validate certificate extraction succeeded
  if [[ -z "$cert_pubkey" || "$cert_pubkey" == "$empty_md5" ]]; then
    err "Failed to extract public key from certificate"
    return 1
  fi

  # Try EC key extraction first (suppress errors)
  key_pubkey=$(openssl ec -in "$key" -pubout 2>/dev/null | openssl md5)

  # If EC failed (empty or error hash), try RSA
  if [[ -z "$key_pubkey" || "$key_pubkey" == "$empty_md5" ]]; then
    key_pubkey=$(openssl rsa -in "$key" -pubout 2>/dev/null | openssl md5)
  fi

  # Final validation of key extraction
  if [[ -z "$key_pubkey" || "$key_pubkey" == "$empty_md5" ]]; then
    err "Failed to extract public key from private key (unsupported key type?)"
    return 1
  fi

  # Compare public keys
  if [[ "$cert_pubkey" != "$key_pubkey" ]]; then
    err "Certificate and private key do not match"
    err "  Certificate pubkey hash: $cert_pubkey"
    err "  Private key pubkey hash: $key_pubkey"
    return 1
  fi

  # All validations passed
  return 0
}

#==============================================================================
# Environment Variables Validation
#==============================================================================

# Validate environment variables on startup
validate_env_vars() {
  # Validate DOMAIN if provided
  if [[ -n "$DOMAIN" ]]; then
    # Check if it's an IP address or domain
    if validate_ip_address "$DOMAIN" 2>/dev/null; then
      msg "Using IP address mode: $DOMAIN"
    elif validate_domain "$DOMAIN"; then
      msg "Using domain mode: $DOMAIN"
    else
      die "Invalid DOMAIN format: $DOMAIN"
    fi
  fi

  # Validate certificate mode
  if [[ -n "$CERT_MODE" ]]; then
    case "$CERT_MODE" in
      cf_dns)
        [[ -n "$CF_Token" ]] || die "CF_Token required for Cloudflare DNS-01 challenge"
        ;;
      le_http)
        # No additional validation needed
        ;;
      *)
        die "Invalid CERT_MODE: $CERT_MODE (must be cf_dns or le_http)"
        ;;
    esac
  fi

  # Validate certificate files if provided
  if [[ -n "$CERT_FULLCHAIN" || -n "$CERT_KEY" ]]; then
    [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]] || \
      die "Both CERT_FULLCHAIN and CERT_KEY must be specified together"

    validate_cert_files "$CERT_FULLCHAIN" "$CERT_KEY" || \
      die "Certificate file validation failed"
  fi

  # Validate port numbers if custom values provided
  if [[ -n "${REALITY_PORT}" && "${REALITY_PORT}" != "$REALITY_PORT_DEFAULT" ]]; then
    validate_port "$REALITY_PORT" || die "Invalid REALITY_PORT: $REALITY_PORT"
  fi

  if [[ -n "${WS_PORT}" && "${WS_PORT}" != "$WS_PORT_DEFAULT" ]]; then
    validate_port "$WS_PORT" || die "Invalid WS_PORT: $WS_PORT"
  fi

  if [[ -n "${HY2_PORT}" && "${HY2_PORT}" != "$HY2_PORT_DEFAULT" ]]; then
    validate_port "$HY2_PORT" || die "Invalid HY2_PORT: $HY2_PORT"
  fi

  # Validate version string if provided
  if [[ -n "$SINGBOX_VERSION" ]]; then
    [[ "$SINGBOX_VERSION" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]] || \
      die "Invalid SINGBOX_VERSION format: $SINGBOX_VERSION"
  fi

  return 0
}

#==============================================================================
# Reality Configuration Validation
#==============================================================================

# Validate Reality short ID (must be exactly 8 hex characters for sing-box)
validate_short_id() {
  local sid="$1"
  [[ "$sid" =~ ^[0-9a-fA-F]{8}$ ]] || {
    err "Short ID must be exactly 8 hexadecimal characters, got: $sid"
    return 1
  }
  return 0
}

# Validate Reality destination SNI
validate_reality_sni() {
  local sni="$1"

  # Must be a valid domain name
  [[ -n "$sni" ]] || return 1

  # Allow wildcard domains for Reality
  local cleaned_sni="${sni#\*.}"

  # Check basic domain format
  [[ "$cleaned_sni" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1

  return 0
}

#==============================================================================
# User Input Validation
#==============================================================================

# Validate numeric choice from menu
validate_menu_choice() {
  local choice="$1"
  local min="${2:-1}"
  local max="${3:-9}"

  [[ "$choice" =~ ^[0-9]+$ ]] || return 1
  [[ "$choice" -ge "$min" && "$choice" -le "$max" ]] || return 1

  return 0
}

# Validate Yes/No input
validate_yes_no() {
  local input="$1"
  [[ "$input" =~ ^[YyNn]$ ]] || return 1
  return 0
}

#==============================================================================
# Configuration File Validation
#==============================================================================

# Validate sing-box configuration JSON syntax
validate_singbox_config() {
  local config_file="${1:-$SB_CONF}"

  [[ -f "$config_file" ]] || {
    err "Configuration file not found: $config_file"
    return 1
  }

  # Check if sing-box binary exists
  [[ -f "$SB_BIN" ]] || {
    err "sing-box binary not found: $SB_BIN"
    return 1
  }

  # Use sing-box built-in validation
  if ! "$SB_BIN" check -c "$config_file" 2>&1; then
    err "Configuration validation failed"
    return 1
  fi

  return 0
}

# Validate JSON syntax using jq
validate_json_syntax() {
  local json_file="$1"

  [[ -f "$json_file" ]] || return 1

  if have jq; then
    jq empty < "$json_file" 2>/dev/null || return 1
  else
    # Fallback: basic JSON validation with python
    if have python3; then
      python3 -c "import json; json.load(open('$json_file'))" 2>/dev/null || return 1
    elif have python; then
      python -c "import json; json.load(open('$json_file'))" 2>/dev/null || return 1
    else
      warn "Neither jq nor python available for JSON validation"
      return 0
    fi
  fi

  return 0
}

#==============================================================================
# System Requirements Validation
#==============================================================================

# Check system requirements for installation
validate_system_requirements() {
  # Check for required commands
  local required_cmds=("curl" "tar" "gzip" "systemctl")
  local missing_cmds=()

  for cmd in "${required_cmds[@]}"; do
    if ! have "$cmd"; then
      missing_cmds+=("$cmd")
    fi
  done

  if [[ ${#missing_cmds[@]} -gt 0 ]]; then
    err "Missing required commands: ${missing_cmds[*]}"
    return 1
  fi

  # Check for systemd
  if ! systemctl --version >/dev/null 2>&1; then
    err "systemd is required but not available"
    return 1
  fi

  # Check disk space (minimum 100MB free)
  local free_space
  free_space=$(df /usr/local/bin 2>/dev/null | awk 'NR==2 {print $4}')
  if [[ -n "$free_space" && "$free_space" -lt 102400 ]]; then
    warn "Low disk space: less than 100MB available"
  fi

  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f sanitize_input validate_domain validate_cert_files validate_env_vars
export -f validate_short_id validate_reality_sni validate_menu_choice validate_yes_no
export -f validate_singbox_config validate_json_syntax validate_system_requirements
