#!/usr/bin/env bash
# lib/generators.sh - Random data and key generation functions
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Provides UUID, Reality keypair, hex string, and QR code generation
# Dependencies: lib/common.sh, lib/logging.sh
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_GENERATORS_LOADED:-}" ]] && return 0
readonly _SBX_GENERATORS_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: common.sh will source us, so only source if not already loaded
if [[ -z "${_SBX_COMMON_LOADED:-}" ]]; then
    source "${_LIB_DIR}/common.sh"
fi
if [[ -z "${_SBX_LOGGING_LOADED:-}" ]]; then
    source "${_LIB_DIR}/logging.sh"
fi

#==============================================================================
# UUID Generation
#==============================================================================

# Generate UUID with multiple fallback methods
#
# Tries methods in order of reliability:
# 1. Linux kernel UUID
# 2. uuidgen command
# 3. Python (python3 or python)
# 4. OpenSSL with proper UUID v4 format
#
# Returns: UUID string in format xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
# Exit code: 0 on success, 1 on failure
generate_uuid() {
  # Method 1: Linux kernel UUID (most reliable on Linux)
  if [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi

  # Method 2: uuidgen command (available on most Unix systems)
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  # Method 3: Python (widely available)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(str(uuid.uuid4()))'
    return 0
  elif command -v python >/dev/null 2>&1; then
    python -c 'import uuid; print(str(uuid.uuid4()))'
    return 0
  fi

  # Method 4: OpenSSL with proper UUID v4 format
  # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  # where y is one of [8, 9, a, b] (variant bits: 10xx in binary)
  local hex variant_byte variant_value
  hex=$(openssl rand -hex 16) || return 1

  # Use cryptographically secure random for variant bits
  # Use bitwise AND to get last 2 bits (0-3), then add to 8 to get 8-11
  variant_byte=$(openssl rand -hex 1)
  # Extract lower 2 bits using bitwise AND, ensuring uniform distribution
  variant_value=$(( 8 + (0x${variant_byte} & 0x3) ))

  printf '%s-%s-4%s-%x%s-%s' \
    "${hex:0:8}" \
    "${hex:8:4}" \
    "${hex:13:3}" \
    "$variant_value" \
    "${hex:17:3}" \
    "${hex:20:12}"
}

#==============================================================================
# Reality Keypair Generation
#==============================================================================

# Generate Reality keypair with proper error handling
#
# Usage: generate_reality_keypair
# Returns: "private_key public_key" (space-separated)
# Exit code: 0 on success, 1 on failure
#
# Requires: sing-box binary at $SB_BIN
generate_reality_keypair() {
  local output
  output=$("$SB_BIN" generate reality-keypair 2>&1) || {
    err "Failed to generate Reality keypair: $output"
    return 1
  }

  # Extract and validate keys
  local priv pub
  priv=$(echo "$output" | grep "PrivateKey:" | awk '{print $2}')
  pub=$(echo "$output" | grep "PublicKey:" | awk '{print $2}')

  if [[ -z "$priv" || -z "$pub" ]]; then
    err "Failed to extract keys from Reality keypair output"
    return 1
  fi

  echo "$priv $pub"
  return 0
}

#==============================================================================
# Hex String Generation
#==============================================================================

# Generate secure random hex string
#
# Usage: generate_hex_string [length]
# Example: generate_hex_string 16  # Generates 32 hex characters (16 bytes)
#
# Args:
#   $1: Length in bytes (default: 16)
# Returns: Hex string (length * 2 characters)
# Exit code: 0 on success, 1 on failure
generate_hex_string() {
  local length="${1:-16}"
  openssl rand -hex "$length"
}

#==============================================================================
# QR Code Generation
#==============================================================================

# Generate ASCII QR code for URI (terminal display only)
#
# Usage: generate_qr_code <uri> [name]
# Example: generate_qr_code "vless://..." "Reality"
#
# Args:
#   $1: URI string to encode
#   $2: Name for display (default: "Config")
#
# Returns: Prints QR code to terminal
# Exit code: 0 on success, 1 on failure
#
# Requires: qrencode command
generate_qr_code() {
  local uri="$1"
  local name="${2:-Config}"

  # Validate input
  if [[ -z "$uri" ]]; then
    return 1
  fi

  # Check if qrencode is available
  if ! have qrencode; then
    return 1
  fi

  # Check URI length (QR code capacity limitation)
  local uri_length=${#uri}
  if [[ $uri_length -gt 1500 ]]; then
    warn "URI is long ($uri_length chars), QR code may be dense"
  fi

  echo
  success "$name configuration QR code:"
  echo "┌─────────────────────────────────────┐"
  # Generate ASCII QR code for terminal display
  if qrencode -t UTF8 -m 0 "$uri" 2>/dev/null; then
    echo "└─────────────────────────────────────┘"
    info "Scan QR code to import config to client"
  else
    warn "QR code generation failed"
    return 1
  fi
  echo

  return 0
}

# Generate all QR codes for configured protocols
#
# Usage: generate_all_qr_codes <uuid> <domain> <reality_port> <public_key> <short_id> [sni] [ws_port] [hy2_port] [hy2_pass]
#
# Args:
#   $1: UUID for authentication
#   $2: Domain or IP address
#   $3: Reality port
#   $4: Reality public key
#   $5: Reality short ID
#   $6: SNI for Reality (optional, defaults to $SNI_DEFAULT)
#   $7: WS-TLS port (optional)
#   $8: Hysteria2 port (optional)
#   $9: Hysteria2 password (optional)
#
# Returns: Prints QR codes to terminal
# Exit code: Always 0
generate_all_qr_codes() {
  local uuid="$1"
  local domain="$2"
  local reality_port="$3"
  local public_key="$4"
  local short_id="$5"
  local sni="${6:-$SNI_DEFAULT}"

  # Optional parameters for WS-TLS and Hysteria2
  local ws_port="${7:-}"
  local hy2_port="${8:-}"
  local hy2_pass="${9:-}"

  # Reality QR code (always generated)
  local reality_uri="vless://${uuid}@${domain}:${reality_port}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${sni}&pbk=${public_key}&sid=${short_id}&type=tcp&fp=chrome#Reality-${domain}"
  generate_qr_code "$reality_uri" "Reality"

  # WS-TLS QR code (if configured)
  if [[ -n "$ws_port" ]]; then
    local ws_uri="vless://${uuid}@${domain}:${ws_port}?encryption=none&security=tls&type=ws&host=${domain}&path=/ws&sni=${domain}&fp=chrome#WS-TLS-${domain}"
    generate_qr_code "$ws_uri" "WS-TLS"
  fi

  # Hysteria2 QR code (if configured)
  if [[ -n "$hy2_port" && -n "$hy2_pass" ]]; then
    local hy2_uri="hysteria2://${hy2_pass}@${domain}:${hy2_port}/?sni=${domain}&alpn=h3&insecure=0#Hysteria2-${domain}"
    generate_qr_code "$hy2_uri" "Hysteria2"
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f generate_uuid generate_reality_keypair generate_hex_string
export -f generate_qr_code generate_all_qr_codes
