#!/usr/bin/env bash
# lib/caddy.sh - Caddy automatic TLS management
# Part of sbx-lite modular architecture
# Based on xray-fusion implementation

# Prevent multiple sourcing
[[ -n "${_SBX_CADDY_LOADED:-}" ]] && return 0
readonly _SBX_CADDY_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${_LIB_DIR}/common.sh"
# shellcheck source=lib/network.sh
source "${_LIB_DIR}/network.sh"

#==============================================================================
# Caddy File Paths
#==============================================================================

caddy_bin() { echo "/usr/local/bin/caddy"; }
caddy_config_dir() { echo "/usr/local/etc/caddy"; }
caddy_config_file() { echo "$(caddy_config_dir)/Caddyfile"; }
caddy_systemd_file() { echo "/etc/systemd/system/caddy.service"; }

# Caddy stores certificates in data directory
caddy_data_dir() { echo "$HOME/.local/share/caddy"; }
caddy_cert_path() {
  local domain="$1"
  local data_dir
  data_dir=$(caddy_data_dir)

  # Primary path structure (Let's Encrypt ACME v2)
  local cert_dir="${data_dir}/certificates/acme-v02.api.letsencrypt.org-directory/${domain}"
  if [[ -d "$cert_dir" ]]; then
    echo "$cert_dir"
    return 0
  fi

  # Fallback: Try staging directory
  cert_dir="${data_dir}/certificates/acme-staging-v02.api.letsencrypt.org-directory/${domain}"
  if [[ -d "$cert_dir" ]]; then
    echo "$cert_dir"
    return 0
  fi

  # Last resort: Search for domain directory (with safety limits)
  if [[ -d "${data_dir}/certificates" ]]; then
    cert_dir=$(find "${data_dir}/certificates" -maxdepth 3 -type d -name "${domain}" -print -quit 2>/dev/null)
    if [[ -n "$cert_dir" && -d "$cert_dir" ]]; then
      echo "$cert_dir"
      return 0
    fi
  fi

  # Return primary path even if it doesn't exist (caller should check)
  echo "${data_dir}/certificates/acme-v02.api.letsencrypt.org-directory/${domain}"
  return 1
}

#==============================================================================
# Architecture Detection
#==============================================================================

caddy_detect_arch() {
  local arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "armv7" ;;
    *)
      err "Unsupported architecture for Caddy: $arch"
      return 1
      ;;
  esac
}

#==============================================================================
# Caddy Installation
#==============================================================================

# Get latest Caddy version from GitHub
caddy_get_latest_version() {
  curl -fsSL https://api.github.com/repos/caddyserver/caddy/releases/latest \
    | grep -o '"tag_name":[[:space:]]*"[^"]*"' \
    | cut -d'"' -f4
}

# Install Caddy binary
caddy_install() {
  if [[ -x "$(caddy_bin)" ]]; then
    local version
    version=$("$(caddy_bin)" version 2>/dev/null | head -n1 | awk '{print $1}')
    info "Caddy already installed: $version"
    return 0
  fi

  local version arch tmpdir tmpfile url

  msg "Installing Caddy for automatic TLS management..."

  version=$(caddy_get_latest_version) || {
    err "Failed to get Caddy latest version"
    return 1
  }

  arch=$(caddy_detect_arch) || return 1

  tmpdir=$(mktemp -d)
  chmod 700 "$tmpdir"
  tmpfile="${tmpdir}/caddy.tar.gz"

  url="https://github.com/caddyserver/caddy/releases/download/${version}/caddy_${version:1}_linux_${arch}.tar.gz"

  msg "  - Downloading Caddy ${version} for ${arch}..."
  curl -fsSL "$url" -o "$tmpfile" || {
    rm -rf "$tmpdir"
    err "Failed to download Caddy from: $url"
    return 1
  }

  msg "  - Extracting Caddy..."
  tar -xzf "$tmpfile" -C "$tmpdir" caddy || {
    rm -rf "$tmpdir"
    err "Failed to extract Caddy package"
    return 1
  }

  msg "  - Installing Caddy binary..."
  install -m 755 "${tmpdir}/caddy" "$(caddy_bin)" || {
    rm -rf "$tmpdir"
    err "Failed to install Caddy binary"
    return 1
  }

  rm -rf "$tmpdir"

  success "Caddy ${version} installed successfully"
  return 0
}

#==============================================================================
# Caddy Service Management
#==============================================================================

# Create systemd service for Caddy
caddy_create_service() {
  msg "  - Creating Caddy systemd service..."

  cat > "$(caddy_systemd_file)" <<'EOF'
[Unit]
Description=Caddy HTTP/2 web server
Documentation=https://caddyserver.com/docs/
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=root
Group=root
ExecStart=/usr/local/bin/caddy run --environ --config /usr/local/etc/caddy/Caddyfile
ExecReload=/usr/local/bin/caddy reload --config /usr/local/etc/caddy/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
LimitNPROC=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  success "  ✓ Caddy service created"
  return 0
}

#==============================================================================
# Caddy Configuration
#==============================================================================

# Setup Caddy for automatic TLS
caddy_setup_auto_tls() {
  local domain="$1"
  local singbox_reality_port="${2:-443}"

  # Caddy ports (avoid conflicts with sing-box)
  # Caddy uses port 8445 for HTTPS certificate management
  # sing-box uses: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)
  local caddy_http_port="${CADDY_HTTP_PORT:-80}"
  local caddy_https_port="${CADDY_HTTPS_PORT:-8445}"
  local caddy_fallback_port="${CADDY_FALLBACK_PORT:-8080}"

  msg "  - Configuring Caddy for domain: $domain"
  info "  ℹ Caddy HTTPS port: $caddy_https_port (certificate management only)"
  info "  ℹ sing-box ports: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)"

  # Validate ports
  for port in "$caddy_http_port" "$caddy_https_port" "$caddy_fallback_port"; do
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
      err "Invalid port number: $port"
      return 1
    fi
  done

  # Check for port conflicts with sing-box
  if [[ "$caddy_https_port" == "443" ]] || [[ "$caddy_https_port" == "8444" ]] || [[ "$caddy_https_port" == "8443" ]]; then
    err "Port conflict: Caddy HTTPS port ($caddy_https_port) conflicts with sing-box"
    info "  ℹ Use a different port (default: 8445)"
    return 1
  fi

  # Create directories
  mkdir -p "$(caddy_config_dir)" "$(caddy_data_dir)"
  chmod 755 "$(caddy_config_dir)"
  chmod 700 "$(caddy_data_dir)"

  # Create Caddyfile - Caddy on dedicated port for certificate management
  msg "  - Writing Caddyfile configuration..."
  cat > "$(caddy_config_file)" <<EOF
{
  admin off
  http_port ${caddy_http_port}
  https_port ${caddy_https_port}
  email admin@${domain}
}

# Caddy on port ${caddy_https_port} for automatic certificate management
# sing-box handles production traffic on standard ports
${domain}:${caddy_https_port} {
  respond "Caddy Certificate Management (Port ${caddy_https_port})" 200
}

# HTTP fallback
:${caddy_fallback_port} {
  respond "404 - Not Found" 404
}
EOF

  success "  ✓ Caddyfile configured"

  # Create and enable service
  caddy_create_service || return 1

  # Enable and start Caddy
  msg "  - Starting Caddy service..."
  systemctl enable caddy >/dev/null 2>&1
  systemctl start caddy || {
    err "Failed to start Caddy service"
    return 1
  }

  # Wait for Caddy to be ready
  sleep 2

  if ! systemctl is-active caddy >/dev/null 2>&1; then
    err "Caddy service failed to start"
    journalctl -u caddy --no-pager -n 20 >&2
    return 1
  fi

  success "  ✓ Caddy service started"
  return 0
}

#==============================================================================
# Certificate Synchronization
#==============================================================================

# Wait for Caddy to obtain certificate
caddy_wait_for_cert() {
  local domain="$1"
  local max_wait="${2:-60}"  # Wait up to 60 seconds
  local cert_dir

  cert_dir=$(caddy_cert_path "$domain")

  msg "  - Checking for certificate..."
  msg "    Certificate directory: $cert_dir"

  # Check if certificate already exists
  if [[ -f "${cert_dir}/${domain}.crt" && -f "${cert_dir}/${domain}.key" ]]; then
    success "  ✓ Certificate found (already obtained)"
    return 0
  fi

  # Wait for new certificate
  msg "  - Waiting for Caddy to obtain new certificate..."

  local elapsed=0
  while [[ $elapsed -lt $max_wait ]]; do
    if [[ -f "${cert_dir}/${domain}.crt" && -f "${cert_dir}/${domain}.key" ]]; then
      success "  ✓ Certificate obtained from Let's Encrypt"
      return 0
    fi

    sleep 3
    elapsed=$((elapsed + 3))

    if [[ $((elapsed % 15)) -eq 0 ]]; then
      msg "    Still waiting... (${elapsed}s/${max_wait}s)"
    fi
  done

  err "Timeout waiting for certificate after ${max_wait}s"
  err "Check Caddy logs: journalctl -u caddy -n 50"
  return 1
}

# Setup certificate sync from Caddy to sing-box
caddy_setup_cert_sync() {
  local domain="$1"
  local target_dir="${CERT_DIR_BASE}/${domain}"

  msg "  - Setting up certificate synchronization..."

  # Wait for initial certificate
  caddy_wait_for_cert "$domain" || return 1

  local caddy_cert_dir
  caddy_cert_dir=$(caddy_cert_path "$domain")

  # Create target directory
  mkdir -p "$target_dir"
  chmod 700 "$target_dir"

  # Sync certificates
  msg "  - Copying certificates to sing-box directory..."
  cp "${caddy_cert_dir}/${domain}.crt" "${target_dir}/fullchain.pem" || {
    err "Failed to copy certificate"
    return 1
  }

  cp "${caddy_cert_dir}/${domain}.key" "${target_dir}/privkey.pem" || {
    err "Failed to copy private key"
    return 1
  }

  # Set permissions
  chmod 600 "${target_dir}/fullchain.pem" "${target_dir}/privkey.pem"
  chown root:root "${target_dir}/fullchain.pem" "${target_dir}/privkey.pem"

  # Export certificate paths
  export CERT_FULLCHAIN="${target_dir}/fullchain.pem"
  export CERT_KEY="${target_dir}/privkey.pem"

  success "  ✓ Certificates synced to: $target_dir"

  # Create certificate renewal hook
  caddy_create_renewal_hook "$domain" "$target_dir" || return 1

  return 0
}

# Create certificate renewal hook for automatic sync
caddy_create_renewal_hook() {
  local domain="$1"
  local target_dir="$2"
  local hook_script="/usr/local/bin/caddy-cert-sync"

  # CRITICAL: Validate domain BEFORE using it in any operation
  # Strict validation prevents command injection and path traversal
  if [[ ! "$domain" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$ ]]; then
    err "Invalid domain format for certificate sync hook: $domain"
    err "  Domain must contain only lowercase letters, numbers, dots, and hyphens"
    return 1
  fi

  # Validate domain length (RFC 1035)
  if [[ ${#domain} -gt 253 ]]; then
    err "Domain too long for certificate sync hook: ${#domain} characters (max: 253)"
    return 1
  fi

  msg "  - Creating certificate renewal hook..."

  # Create hook script with single-quoted HEREDOC to prevent variable expansion
  # Domain is passed as argument for security (prevents command injection)
  cat > "$hook_script" <<'EOFSCRIPT'
#!/usr/bin/env bash
# Caddy certificate sync hook
# Syncs certificates from Caddy to sing-box and restarts service

set -euo pipefail

# Domain and target directory are passed as arguments
DOMAIN="${1:?Domain not specified}"
TARGET_DIR="${2:?Target directory not specified}"

# Strict domain validation - only allow alphanumeric, dots, and hyphens
if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
    logger -t caddy-cert-sync "ERROR: Invalid domain format: $DOMAIN"
    exit 1
fi

# Validate domain length (max 253 characters per RFC)
if [[ ${#DOMAIN} -gt 253 ]]; then
    logger -t caddy-cert-sync "ERROR: Domain too long: $DOMAIN"
    exit 1
fi

# Determine Caddy data directory
CADDY_DATA_DIR="${HOME:-/root}/.local/share/caddy"

# Try primary path structure (Let's Encrypt ACME v2)
CADDY_CERT_DIR="${CADDY_DATA_DIR}/certificates/acme-v02.api.letsencrypt.org-directory/${DOMAIN}"

# Fallback to staging if primary doesn't exist
if [[ ! -d "$CADDY_CERT_DIR" ]]; then
    CADDY_CERT_DIR="${CADDY_DATA_DIR}/certificates/acme-staging-v02.api.letsencrypt.org-directory/${DOMAIN}"
fi

# Last resort: search with safety limits
if [[ ! -d "$CADDY_CERT_DIR" ]]; then
    if [[ -d "${CADDY_DATA_DIR}/certificates" ]]; then
        local found_dir
        found_dir=$(find "${CADDY_DATA_DIR}/certificates" -maxdepth 3 -type d -name "${DOMAIN}" -print -quit 2>/dev/null)
        if [[ -n "$found_dir" && -d "$found_dir" ]]; then
            CADDY_CERT_DIR="$found_dir"
        fi
    fi
fi

# Check if directory exists
if [[ ! -d "$CADDY_CERT_DIR" ]]; then
    logger -t caddy-cert-sync "WARNING: Certificate directory not found for domain: $DOMAIN"
    exit 0  # Not an error, cert may not be issued yet
fi

# Check if certificates exist
if [[ -f "${CADDY_CERT_DIR}/${DOMAIN}.crt" && -f "${CADDY_CERT_DIR}/${DOMAIN}.key" ]]; then
    # Ensure target directory exists
    mkdir -p "$TARGET_DIR"

    # Copy certificates with secure permissions
    cp "${CADDY_CERT_DIR}/${DOMAIN}.crt" "${TARGET_DIR}/fullchain.pem"
    cp "${CADDY_CERT_DIR}/${DOMAIN}.key" "${TARGET_DIR}/privkey.pem"
    chmod 600 "${TARGET_DIR}/fullchain.pem" "${TARGET_DIR}/privkey.pem"

    # Reload sing-box service
    if systemctl is-active sing-box >/dev/null 2>&1; then
        if systemctl reload sing-box 2>/dev/null; then
            logger -t caddy-cert-sync "Certificate synced and sing-box reloaded for ${DOMAIN}"
        else
            logger -t caddy-cert-sync "Certificate synced, restarting sing-box for ${DOMAIN}"
            systemctl restart sing-box
        fi
    else
        logger -t caddy-cert-sync "Certificate synced for ${DOMAIN} (sing-box not running)"
    fi
else
    logger -t caddy-cert-sync "WARNING: Certificate files not found in $CADDY_CERT_DIR"
fi
EOFSCRIPT

  chmod 750 "$hook_script"  # More restrictive: owner+group execute only
  chown root:root "$hook_script" 2>/dev/null || true

  # Create systemd service - pass domain and target_dir as arguments
  # Use printf %q to properly escape arguments
  local escaped_domain
  local escaped_target
  escaped_domain=$(printf '%q' "$domain")
  escaped_target=$(printf '%q' "$target_dir")

  cat > /etc/systemd/system/caddy-cert-sync.service <<EOF
[Unit]
Description=Sync Caddy certificates to sing-box for $domain
After=caddy.service

[Service]
Type=oneshot
ExecStart=$hook_script $escaped_domain $escaped_target
EOF

  cat > /etc/systemd/system/caddy-cert-sync.timer <<EOF
[Unit]
Description=Daily certificate sync check

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable caddy-cert-sync.timer >/dev/null 2>&1
  systemctl start caddy-cert-sync.timer

  success "  ✓ Certificate renewal hook created"
  return 0
}

#==============================================================================
# Caddy Uninstallation
#==============================================================================

# Remove Caddy and cleanup
caddy_uninstall() {
  msg "Removing Caddy..."

  # Stop and disable services
  systemctl stop caddy 2>/dev/null || true
  systemctl disable caddy 2>/dev/null || true
  systemctl stop caddy-cert-sync.timer 2>/dev/null || true
  systemctl disable caddy-cert-sync.timer 2>/dev/null || true

  # Remove files
  rm -f "$(caddy_bin)"
  rm -f "$(caddy_systemd_file)"
  rm -f /etc/systemd/system/caddy-cert-sync.service
  rm -f /etc/systemd/system/caddy-cert-sync.timer
  rm -f /usr/local/bin/caddy-cert-sync
  rm -rf "$(caddy_config_dir)"

  # Note: Keep $(caddy_data_dir) as it contains certificates
  warn "Certificate data preserved in: $(caddy_data_dir)"
  warn "Remove manually if needed: rm -rf $(caddy_data_dir)"

  systemctl daemon-reload

  success "Caddy removed successfully"
  return 0
}

#==============================================================================
# Export Functions
#==============================================================================

export -f caddy_install caddy_setup_auto_tls caddy_setup_cert_sync
export -f caddy_wait_for_cert caddy_uninstall
