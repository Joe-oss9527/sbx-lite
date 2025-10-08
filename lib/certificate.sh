#!/usr/bin/env bash
# lib/certificate.sh - Certificate management and ACME integration
# Part of sbx-lite modular architecture

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

#==============================================================================
# ACME Installation
#==============================================================================

# Install acme.sh if not present
acme_install() {
  [[ -x "$HOME/.acme.sh/acme.sh" ]] && return 0

  msg "Installing acme.sh..."

  # Use a default email for ACME installation
  local email="admin@yourdomain.com"

  if have curl; then
    curl -fsSL https://get.acme.sh | sh -s "email=${email}" >/dev/null || {
      err "Failed to install acme.sh via curl"
      return 1
    }
  elif have wget; then
    wget -qO- https://get.acme.sh | sh -s "email=${email}" >/dev/null || {
      err "Failed to install acme.sh via wget"
      return 1
    }
  else
    die "Neither curl nor wget available for acme.sh installation"
  fi

  # Load acme.sh environment
  # shellcheck disable=SC1091
  [[ -f "$HOME/.acme.sh/acme.sh.env" ]] && . "$HOME/.acme.sh/acme.sh.env"

  success "acme.sh installed successfully"
  return 0
}

#==============================================================================
# Certificate Issuance - Cloudflare DNS-01
#==============================================================================

# Issue certificate using Cloudflare DNS-01 challenge
acme_issue_cf_dns() {
  [[ -n "$CF_Token" ]] || die "CF_Token is required for CERT_MODE=cf_dns"

  export CF_Token CF_Zone_ID CF_Account_ID
  local ac="$HOME/.acme.sh/acme.sh"
  local force=()
  [[ "$CERT_FORCE" = "1" ]] && force+=(--force)

  msg "Issuing certificate via Cloudflare DNS-01 for: $DOMAIN"

  set +e
  local out
  out="$("$ac" --issue -d "$DOMAIN" --dns dns_cf -k ec-256 --server letsencrypt "${force[@]}" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$out" | grep -qiE 'Skipping|Domains not changed|Next renewal time'; then
      warn "ACME says not due for renewal; will reuse existing order."
    else
      err "ACME issue failed"
      echo "$out" >&2
      die "Certificate issuance failed"
    fi
  fi

  # Install certificate to destination directory
  local dir="$CERT_DIR_BASE/$DOMAIN"
  mkdir -p "$dir"

  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem" || {
      die "Failed to install certificate"
    }

  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"

  # Set secure permissions for certificate files
  chmod 600 "$CERT_FULLCHAIN" "$CERT_KEY"
  chown root:root "$CERT_FULLCHAIN" "$CERT_KEY"

  # Clear CF variables from environment
  unset CF_Token CF_Zone_ID CF_Account_ID

  success "Certificate issued via Cloudflare DNS-01"
  return 0
}

#==============================================================================
# Certificate Issuance - HTTP-01
#==============================================================================

# Issue certificate using Let's Encrypt HTTP-01 challenge
acme_issue_le_http() {
  # Install socat for standalone mode (required by acme.sh HTTP-01)
  if ! have socat; then
    msg "Installing socat for ACME HTTP-01 challenge..."
    if have apt-get; then
      apt-get update && apt-get install -y socat
    elif have dnf; then
      dnf install -y socat
    elif have yum; then
      yum install -y socat
    else
      die "Failed to install socat. Please install it manually: apt install socat / yum install socat"
    fi
    success "  ✓ socat installed"
  fi

  # Check port 80 availability
  port_in_use 80 && die "Port 80 is in use; stop the service or use CERT_MODE=cf_dns"

  local ac="$HOME/.acme.sh/acme.sh"
  local force=()
  [[ "$CERT_FORCE" = "1" ]] && force+=(--force)

  msg "Issuing certificate via Let's Encrypt HTTP-01 for: $DOMAIN"

  set +e
  local out
  out="$("$ac" --issue -d "$DOMAIN" --standalone -k ec-256 --server letsencrypt "${force[@]}" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$out" | grep -qiE 'Skipping|Domains not changed|Next renewal time'; then
      warn "ACME says not due for renewal; will reuse existing order."
    else
      err "ACME issue failed"
      echo "$out" >&2
      die "Certificate issuance failed"
    fi
  fi

  # Install certificate to destination directory
  local dir="$CERT_DIR_BASE/$DOMAIN"
  mkdir -p "$dir"

  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem" || {
      die "Failed to install certificate"
    }

  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"

  # Set secure permissions for certificate files
  chmod 600 "$CERT_FULLCHAIN" "$CERT_KEY"
  chown root:root "$CERT_FULLCHAIN" "$CERT_KEY"

  success "Certificate issued via Let's Encrypt HTTP-01"
  return 0
}

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
      warn "No CERT_MODE specified - enabling automatic certificate issuance via HTTP-01"
      info "  ℹ Port 80 must be open for ACME HTTP-01 challenge"
      info "  ℹ To use DNS validation, set: CERT_MODE=cf_dns CF_Token='your-token'"
      export CERT_MODE="le_http"
    else
      # No domain or Reality-only mode - skip certificate issuance
      return 0
    fi
  fi

  # Install acme.sh
  acme_install || die "Failed to install acme.sh"

  # Issue certificate based on mode
  case "$CERT_MODE" in
    cf_dns)
      acme_issue_cf_dns
      ;;
    le_http)
      acme_issue_le_http
      ;;
    *)
      die "Unknown CERT_MODE: $CERT_MODE (supported: cf_dns, le_http)"
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

# Renew certificate using acme.sh
renew_cert() {
  local domain="${1:-$DOMAIN}"
  [[ -n "$domain" ]] || die "Domain required for certificate renewal"

  local ac="$HOME/.acme.sh/acme.sh"
  [[ -x "$ac" ]] || die "acme.sh not installed"

  msg "Renewing certificate for: $domain"

  "$ac" --renew -d "$domain" --ecc || {
    err "Certificate renewal failed"
    return 1
  }

  success "Certificate renewed successfully"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f acme_install acme_issue_cf_dns acme_issue_le_http maybe_issue_cert
export -f check_cert_expiry renew_cert
