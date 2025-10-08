#!/usr/bin/env bash
# lib/service.sh - systemd service management
# Part of sbx-lite modular architecture

# Prevent multiple sourcing
[[ -n "${_SBX_SERVICE_LOADED:-}" ]] && return 0
readonly _SBX_SERVICE_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/common.sh"
# shellcheck source=lib/network.sh
source "${SCRIPT_DIR}/network.sh"

#==============================================================================
# Service File Creation
#==============================================================================

# Create systemd service unit file
create_service_file() {
  msg "Creating systemd service ..."

  cat >"$SB_SVC" <<'EOF'
[Unit]
Description=sing-box
After=network.target nss-lookup.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=root
# If you later switch to a non-root user, add capabilities below:
# CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
# AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

  success "  ✓ Service file created"
  return 0
}

#==============================================================================
# Service Management
#==============================================================================

# Setup and start sing-box service
setup_service() {
  create_service_file || die "Failed to create service file"

  # Reload systemd daemon
  systemctl daemon-reload || die "Failed to reload systemd daemon"

  # Validate configuration before starting service
  msg "Validating configuration before starting service..."
  if ! "$SB_BIN" check -c "$SB_CONF" 2>&1; then
    die "Configuration validation failed. Service not started."
  fi
  success "  ✓ Configuration validated"

  # Enable service for auto-start on boot
  msg "Enabling sing-box service..."
  systemctl enable sing-box || warn "Failed to enable service (continuing anyway)"

  # Start the service
  msg "Starting sing-box service..."
  systemctl start sing-box || die "Failed to start sing-box service"

  # Wait for service to fully initialize
  sleep 3

  # Verify service is running
  if systemctl is-active sing-box >/dev/null 2>&1; then
    success "  ✓ sing-box service is running"
  else
    err "sing-box service failed to start"
    msg "Checking service status and logs..."
    systemctl status sing-box --no-pager || true
    journalctl -u sing-box -n 50 --no-pager || true
    die "Service startup failed. Check logs above for details."
  fi

  # Validate port listening (Reality-only mode check)
  local reality_port="${REALITY_PORT_CHOSEN:-$REALITY_PORT}"
  if validate_port_listening "$reality_port" "Reality"; then
    success "  ✓ Reality service listening on port $reality_port"
  fi

  # Check WS and Hysteria2 ports if certificates are configured
  if [[ -n "${CERT_FULLCHAIN:-}" && -f "${CERT_FULLCHAIN:-}" ]]; then
    local ws_port="${WS_PORT_CHOSEN:-$WS_PORT}"
    local hy2_port="${HY2_PORT_CHOSEN:-$HY2_PORT}"

    validate_port_listening "$ws_port" "WS-TLS" || warn "WS-TLS may not be listening properly"
    validate_port_listening "$hy2_port" "Hysteria2" || warn "Hysteria2 may not be listening properly"
  fi

  return 0
}

# Validate that service is listening on specified port
validate_port_listening() {
  local port="$1"
  local service_name="${2:-Service}"
  local max_attempts=5
  local attempt=0

  while [[ $attempt -lt $max_attempts ]]; do
    if ss -lntp 2>/dev/null | grep -q ":$port " || \
       lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$port"; then
      return 0
    fi

    ((attempt++))
    if [[ $attempt -lt $max_attempts ]]; then
      sleep 1
    fi
  done

  warn "$service_name port $port not listening after $max_attempts attempts"
  return 1
}

#==============================================================================
# Service Status Checking
#==============================================================================

# Check if sing-box service is running
check_service_status() {
  if systemctl is-active sing-box >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Stop sing-box service
stop_service() {
  if check_service_status; then
    msg "Stopping sing-box service..."
    systemctl stop sing-box || warn "Failed to stop service gracefully"

    # Wait for service to fully stop
    local max_wait=10
    local waited=0
    while systemctl is-active sing-box >/dev/null 2>&1 && [[ $waited -lt $max_wait ]]; do
      sleep 1
      ((waited++))
    done

    if systemctl is-active sing-box >/dev/null 2>&1; then
      warn "Service did not stop within ${max_wait}s"
      return 1
    fi

    success "  ✓ Service stopped"
  fi
  return 0
}

# Restart sing-box service
restart_service() {
  msg "Restarting sing-box service..."

  # Validate configuration before restart
  if [[ -f "$SB_CONF" ]]; then
    if ! "$SB_BIN" check -c "$SB_CONF" 2>&1; then
      die "Configuration validation failed. Service not restarted."
    fi
  fi

  systemctl restart sing-box || die "Failed to restart service"
  sleep 2

  if check_service_status; then
    success "  ✓ Service restarted successfully"
    return 0
  else
    err "Service failed to restart"
    systemctl status sing-box --no-pager || true
    return 1
  fi
}

# Reload sing-box service configuration
reload_service() {
  if check_service_status; then
    msg "Reloading sing-box service configuration..."
    systemctl reload sing-box 2>/dev/null || restart_service
  else
    msg "Service not running, starting instead..."
    systemctl start sing-box || die "Failed to start service"
  fi
}

#==============================================================================
# Service Uninstallation
#==============================================================================

# Remove sing-box service
remove_service() {
  msg "Removing sing-box service..."

  # Stop service if running
  if systemctl is-active sing-box >/dev/null 2>&1; then
    systemctl stop sing-box || warn "Failed to stop service"
  fi

  # Disable service
  if systemctl is-enabled sing-box >/dev/null 2>&1; then
    systemctl disable sing-box || warn "Failed to disable service"
  fi

  # Remove service file
  if [[ -f "$SB_SVC" ]]; then
    rm -f "$SB_SVC"
    success "  ✓ Service file removed"
  fi

  # Reload systemd daemon
  systemctl daemon-reload

  success "Service removed successfully"
  return 0
}

#==============================================================================
# Service Logs
#==============================================================================

# Show service logs
show_service_logs() {
  local lines="${1:-50}"
  local follow="${2:-false}"

  if [[ "$follow" == "true" ]]; then
    journalctl -u sing-box -f
  else
    journalctl -u sing-box -n "$lines" --no-pager
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f create_service_file setup_service validate_port_listening
export -f check_service_status stop_service restart_service reload_service
export -f remove_service show_service_logs
