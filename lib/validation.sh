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
  # Remove potential dangerous characters using tr for explicit character removal
  # This avoids escaping issues with backticks in parameter expansion
  input="$(printf '%s' "$input" | tr -d ';|&`$()<>')"
  # Limit length after sanitization
  input="${input:0:256}"
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

# Validate certificate files with comprehensive security checks
validate_cert_files() {
  local fullchain="$1"
  local key="$2"

  # Step 1: Basic path validation
  if [[ -z "$fullchain" || -z "$key" ]]; then
    err "Certificate paths cannot be empty"
    return 1
  fi

  # Step 2: File existence check
  if [[ ! -f "$fullchain" ]]; then
    err "Certificate file not found: $fullchain"
    return 1
  fi
  if [[ ! -f "$key" ]]; then
    err "Private key file not found: $key"
    return 1
  fi

  # Step 3: File readability check
  if [[ ! -r "$fullchain" ]]; then
    err "Certificate file not readable: $fullchain"
    return 1
  fi
  if [[ ! -r "$key" ]]; then
    err "Private key file not readable: $key"
    return 1
  fi

  # Step 4: Non-empty file check
  if [[ ! -s "$fullchain" ]]; then
    err "Certificate file is empty: $fullchain"
    return 1
  fi
  if [[ ! -s "$key" ]]; then
    err "Private key file is empty: $key"
    return 1
  fi

  # Step 5: Certificate format validation
  if ! openssl x509 -in "$fullchain" -noout 2>/dev/null; then
    err "Invalid certificate format (not a valid X.509 certificate)"
    err "  File: $fullchain"
    return 1
  fi

  # Step 6: Private key format validation
  # Try to parse as any valid key type (RSA, EC, Ed25519, etc.)
  if ! openssl pkey -in "$key" -noout 2>/dev/null; then
    err "Invalid private key format (not a valid private key)"
    err "  File: $key"
    return 1
  fi

  # Step 7: Certificate expiration check (warning only)
  if ! openssl x509 -in "$fullchain" -checkend 2592000 -noout 2>/dev/null; then
    warn "Certificate will expire within 30 days"
  fi

  # Step 8: Certificate-Key matching validation
  # MD5 hash constant for empty input (indicates extraction failure)
  readonly EMPTY_MD5_HASH="d41d8cd98f00b204e9800998ecf8427e"

  # Extract public key hash from certificate
  local cert_pubkey
  cert_pubkey=$(openssl x509 -in "$fullchain" -noout -pubkey 2>/dev/null | openssl md5 2>/dev/null | awk '{print $2}')

  if [[ -z "$cert_pubkey" || "$cert_pubkey" == "$EMPTY_MD5_HASH" ]]; then
    err "Failed to extract public key from certificate"
    err "  This may indicate a corrupted certificate file"
    return 1
  fi

  # Extract public key hash from private key using generic pkey command
  local key_pubkey
  key_pubkey=$(openssl pkey -in "$key" -pubout 2>/dev/null | openssl md5 2>/dev/null | awk '{print $2}')

  if [[ -z "$key_pubkey" || "$key_pubkey" == "$EMPTY_MD5_HASH" ]]; then
    err "Failed to extract public key from private key"
    err "  This may indicate a corrupted or unsupported key file"
    return 1
  fi

  # Compare public key hashes
  if [[ "$cert_pubkey" != "$key_pubkey" ]]; then
    err "Certificate and private key do not match"
    err "  Certificate pubkey MD5: $cert_pubkey"
    err "  Private key pubkey MD5: $key_pubkey"
    err "  Make sure the certificate was generated from this private key"
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
# Export Functions
#==============================================================================

export -f sanitize_input validate_domain validate_cert_files validate_env_vars
export -f validate_short_id validate_reality_sni validate_menu_choice validate_yes_no
export -f validate_singbox_config validate_json_syntax
