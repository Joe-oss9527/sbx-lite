#!/usr/bin/env bash
# lib/certificate.sh - Caddy-based certificate management
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_CERTIFICATE_LOADED:-}" ]] && return 0
readonly _SBX_CERTIFICATE_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"
# shellcheck source=lib/network.sh
source "${_LIB_DIR}/network.sh"
# shellcheck source=lib/validation.sh
source "${_LIB_DIR}/validation.sh"
# shellcheck source=lib/caddy.sh
source "${_LIB_DIR}/caddy.sh"

#==============================================================================
# Certificate Management
#==============================================================================

# Issue certificate based on CERT_MODE or use existing
maybe_issue_cert() {
  # Check if certificate files already provided
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    msg "Using provided certificate paths."
    validate_cert_files "$CERT_FULLCHAIN" "$CERT_KEY" || die "Certificate validation failed"
    return 0
  fi

  # Auto-enable certificate issuance if domain is provided but CERT_MODE is not set
  if [[ -z "$CERT_MODE" ]]; then
    if [[ -n "$DOMAIN" && "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      info "No CERT_MODE specified - using Caddy for automatic certificate management"
      info "  ℹ Caddy will automatically obtain and renew certificates via Let's Encrypt"
      export CERT_MODE="caddy"
      debug "Auto-enabled certificate mode: caddy (domain: $DOMAIN)"
    else
      # No domain or Reality-only mode - skip certificate issuance
      debug "Skipping certificate issuance (Reality-only mode or no domain)"
      return 0
    fi
  else
    msg "Certificate mode: $CERT_MODE"
  fi

  # Issue certificate based on mode
  case "$CERT_MODE" in
    caddy)
      # Install Caddy
      caddy_install || die "Failed to install Caddy"

      # Setup Caddy with automatic TLS
      caddy_setup_auto_tls "$DOMAIN" "${REALITY_PORT_CHOSEN:-443}" || die "Failed to setup Caddy auto TLS"

      # Setup certificate synchronization
      caddy_setup_cert_sync "$DOMAIN" || die "Failed to setup certificate sync"
      ;;

    *)
      die "Unknown CERT_MODE: $CERT_MODE (only 'caddy' is supported)"
      ;;
  esac

  success "Certificate installed: $CERT_FULLCHAIN"
  return 0
}

# Check certificate expiration
check_cert_expiry() {
  local cert_file="${1:-$CERT_FULLCHAIN}"
  [[ -f "$cert_file" ]] || return 1

  local expiry_date
  expiry_date=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)

  if [[ -n "$expiry_date" ]]; then
    local expiry_epoch
    expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry_date" +%s 2>/dev/null)
    local now_epoch
    now_epoch=$(date +%s)
    local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

    if [[ $days_left -lt 30 ]]; then
      warn "Certificate expires in $days_left days: $cert_file"
      return 2
    elif [[ $days_left -lt 0 ]]; then
      err "Certificate has expired: $cert_file"
      return 1
    else
      info "Certificate valid for $days_left days"
      return 0
    fi
  fi

  return 1
}

#==============================================================================
# Export Functions
#==============================================================================

export -f maybe_issue_cert check_cert_expiry
