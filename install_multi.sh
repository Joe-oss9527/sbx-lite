#!/usr/bin/env bash
# install_multi.sh v2.0 - Modular sing-box installer
# One-click official sing-box with VLESS-REALITY, VLESS-WS-TLS, and Hysteria2
#
# Usage (install):
#   bash install_multi.sh                                    # Reality-only with auto IP
#   DOMAIN=example.com bash install_multi.sh                 # Full setup
#   DOMAIN=example.com CERT_MODE=cf_dns CF_Token='xxx' ...  # With certificates
#
# Usage (uninstall):
#   FORCE=1 bash install_multi.sh uninstall

set -euo pipefail

#==============================================================================
# Module Loading
#==============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load all library modules
for module in common network validation certificate config service ui backup export; do
    module_path="${SCRIPT_DIR}/lib/${module}.sh"
    if [[ -f "$module_path" ]]; then
        # shellcheck source=/dev/null
        source "$module_path"
    else
        echo "ERROR: Required module not found: $module_path"
        echo "Please ensure all lib/*.sh files are present."
        exit 1
    fi
done

# Note: The following variables are defined in lib/common.sh and sourced above
# ShellCheck cannot trace them through dynamic sourcing, so we declare them here
# to suppress SC2154 warnings. They are actually defined and exported by the modules.
: "${SB_BIN:=/usr/local/bin/sing-box}"
: "${SB_CONF_DIR:=/etc/sing-box}"
: "${SB_CONF:=$SB_CONF_DIR/config.json}"
: "${SB_SVC:=/etc/systemd/system/sing-box.service}"
: "${CLIENT_INFO:=$SB_CONF_DIR/client-info.txt}"
: "${REALITY_PORT:=443}"
: "${REALITY_PORT_FALLBACK:=24443}"
: "${WS_PORT:=8444}"
: "${WS_PORT_FALLBACK:=24444}"
: "${HY2_PORT:=8443}"
: "${HY2_PORT_FALLBACK:=24445}"
: "${SNI_DEFAULT:=www.microsoft.com}"
: "${CERT_DIR_BASE:=/etc/ssl/sbx}"
: "${CERT_FULLCHAIN:=}"
: "${CERT_KEY:=}"
: "${B:=}"
: "${N:=}"
: "${G:=}"
: "${Y:=}"
: "${R:=}"
: "${CYAN:=}"
: "${BLUE:=}"
: "${PURPLE:=}"

#==============================================================================
# Additional Helper Functions
#==============================================================================

# Detect system architecture
detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l) echo "armv7" ;;
        *) die "Unsupported architecture: $arch" ;;
    esac
}

# Get installed sing-box version
get_installed_version() {
    if [[ -x "$SB_BIN" ]]; then
        local version
        version=$("$SB_BIN" version 2>/dev/null | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
        echo "$version"
    else
        echo "not_installed"
    fi
}

# Get latest version from GitHub
get_latest_version() {
    local api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local response
    response=$(safe_http_get "$api") || {
        warn "Failed to fetch latest version from GitHub"
        echo "unknown"
        return 1
    }

    local version
    version=$(echo "$response" | grep -oE '"tag_name":\s*"v[0-9]+\.[0-9]+\.[0-9]+"' | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
    echo "${version:-unknown}"
}

# Compare versions (semantic versioning)
compare_versions() {
    local current="$1"
    local latest="$2"

    # Remove 'v' prefix
    current="${current#v}"
    latest="${latest#v}"

    # Handle unknown versions
    if [[ "$current" == "unknown" || "$latest" == "unknown" ]]; then
        echo "unknown"
        return 0
    fi

    # Exact match
    if [[ "$current" == "$latest" ]]; then
        echo "current"
        return 0
    fi

    # Semantic version comparison (major.minor.patch)
    IFS='.' read -r -a current_parts <<< "$current"
    IFS='.' read -r -a latest_parts <<< "$latest"

    # Compare each component
    for i in 0 1 2; do
        local curr_part="${current_parts[$i]:-0}"
        local late_part="${latest_parts[$i]:-0}"

        # Remove non-numeric suffixes (e.g., "1-beta")
        curr_part="${curr_part%%-*}"
        late_part="${late_part%%-*}"

        if [[ "$curr_part" -lt "$late_part" ]]; then
            echo "outdated"
            return 0
        elif [[ "$curr_part" -gt "$late_part" ]]; then
            echo "newer"
            return 0
        fi
    done

    # All components equal (shouldn't reach here if equality check worked)
    echo "current"
}

#==============================================================================
# Installation Functions
#==============================================================================

# Check for existing installation
check_existing_installation() {
    local current_version service_status latest_version version_status
    current_version="$(get_installed_version)"
    service_status="$(check_service_status && echo "running" || echo "stopped")"

    if [[ "$current_version" != "not_installed" || -f "$SB_CONF" || -f "$SB_SVC" ]]; then
        latest_version="$(get_latest_version)"
        version_status="$(compare_versions "$current_version" "$latest_version")"

        # Show existing installation menu
        show_existing_installation_menu "$current_version" "$service_status" "$latest_version" "$version_status"

        # Get user choice
        local choice
        set +e
        choice=$(prompt_menu_choice 1 6)
        local prompt_result=$?
        set -e

        if [[ $prompt_result -ne 0 ]]; then
            die "Invalid choice. Exiting."
        fi

        case "$choice" in
            1)  # Fresh install
                msg "Performing fresh install..."
                if [[ -f "$SB_CONF" ]]; then
                    local backup_file
                    backup_file="${SB_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
                    cp "$SB_CONF" "$backup_file"
                    success "  ✓ Backed up existing config to: $backup_file"
                fi
                export SKIP_CONFIG_GEN=0
                export SKIP_BINARY_DOWNLOAD=0
                ;;
            2)  # Upgrade binary only
                msg "Upgrading binary only, preserving configuration..."
                export SKIP_CONFIG_GEN=1
                export SKIP_BINARY_DOWNLOAD=0
                ;;
            3)  # Reconfigure
                msg "Reconfiguring (keeping binary)..."
                export SKIP_CONFIG_GEN=0
                export SKIP_BINARY_DOWNLOAD=1
                ;;
            4)  # Uninstall
                uninstall_flow
                exit 0
                ;;
            5)  # Show current config
                if [[ -f "$SB_CONF" ]]; then
                    echo
                    msg "Current configuration:"
                    cat "$SB_CONF"
                else
                    warn "No configuration file found"
                fi
                exit 0
                ;;
            6)  # Exit
                msg "Exiting..."
                exit 0
                ;;
        esac
    fi
}

# Ensure required tools are installed
ensure_tools() {
    local missing=()

    for tool in curl tar gzip jq openssl systemctl; do
        if ! have "$tool"; then
            missing+=("$tool")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing required tools: ${missing[*]}"
        msg "Installing missing tools..."

        if have apt-get; then
            apt-get update && apt-get install -y "${missing[@]}"
        elif have dnf; then
            dnf install -y "${missing[@]}"
        elif have yum; then
            yum install -y "${missing[@]}"
        else
            die "Cannot install missing tools automatically. Please install: ${missing[*]}"
        fi
    fi

    success "All required tools are available"
}

# Download sing-box binary
download_singbox() {
    if [[ "${SKIP_BINARY_DOWNLOAD:-0}" = "1" ]]; then
        if [[ -x "$SB_BIN" ]]; then
            success "Using existing sing-box binary at $SB_BIN"
            return 0
        else
            warn "SKIP_BINARY_DOWNLOAD set but no binary found, proceeding with download"
        fi
    fi

    local arch tmp api url tag raw
    arch="$(detect_arch)"
    tmp="$(mktemp -d)" || die "Failed to create temporary directory"
    chmod 700 "$tmp"

    # Get release information
    if [[ -n "${SINGBOX_VERSION:-}" ]]; then
        tag="$SINGBOX_VERSION"
        api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"
    else
        api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    fi

    msg "Fetching sing-box release info for $arch..."
    raw=$(safe_http_get "$api") || {
        rm -rf "$tmp"
        die "Failed to fetch release information from GitHub"
    }

    if [[ -z "${SINGBOX_VERSION:-}" ]]; then
        tag=$(echo "$raw" | grep '"tag_name":' | head -1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
    fi

    # Extract download URL (explicitly match linux-${arch}.tar.gz to avoid android builds)
    url=$(echo "$raw" | grep '"browser_download_url":' | grep -E "linux-${arch}\.tar\.gz\"" | head -1 | cut -d'"' -f4)

    if [[ -z "$url" ]]; then
        rm -rf "$tmp"
        die "Failed to find download URL for architecture: $arch"
    fi

    msg "Downloading sing-box ${tag}..."
    local pkg="$tmp/sb.tgz"
    safe_http_get "$url" "$pkg" || {
        rm -rf "$tmp"
        die "Failed to download sing-box package"
    }

    msg "Extracting package..."
    tar -xzf "$pkg" -C "$tmp" || {
        rm -rf "$tmp"
        die "Failed to extract package"
    }

    # Find and install binary
    local extracted_bin
    extracted_bin=$(find "$tmp" -name "sing-box" -type f | head -1)

    if [[ -z "$extracted_bin" ]]; then
        rm -rf "$tmp"
        die "sing-box binary not found in package"
    fi

    msg "Installing sing-box binary..."
    cp "$extracted_bin" "$SB_BIN"
    chmod +x "$SB_BIN"

    rm -rf "$tmp"
    success "sing-box ${tag} installed successfully"
}

# Generate configuration materials (UUIDs, keys, ports, etc.)
gen_materials() {
    msg "Generating configuration materials..."

    # Handle DOMAIN/IP detection
    if [[ -z "${DOMAIN:-}" ]]; then
        echo
        echo "========================================"
        echo "Server Address Configuration"
        echo "========================================"
        echo "Options:"
        echo "  1. Press Enter for Reality-only (auto-detect IP)"
        echo "  2. Enter domain name for full setup (Reality + WS-TLS + Hysteria2)"
        echo "  3. Enter IP address manually for Reality-only"
        echo
        echo "Note: Domain must be 'DNS only' (gray cloud) in Cloudflare"
        echo

        local input
        read -rp "Domain or IP (press Enter to auto-detect): " input
        input=$(sanitize_input "$input")

        if [[ -z "$input" ]]; then
            msg "Auto-detecting server IP..."
            DOMAIN=$(get_public_ip) || die "Failed to detect server IP"
            success "Detected server IP: $DOMAIN"
            export REALITY_ONLY_MODE=1
        elif validate_ip_address "$input"; then
            DOMAIN="$input"
            success "Using IP address: $DOMAIN"
            export REALITY_ONLY_MODE=1
        elif validate_domain "$input"; then
            DOMAIN="$input"
            success "Using domain: $DOMAIN"
            export REALITY_ONLY_MODE=0
        else
            die "Invalid domain or IP address: $input"
        fi
    else
        # Determine if domain or IP
        if validate_ip_address "$DOMAIN"; then
            export REALITY_ONLY_MODE=1
        else
            export REALITY_ONLY_MODE=0
        fi
    fi

    # Generate UUID
    export UUID
    UUID=$(generate_uuid)
    success "  ✓ UUID generated"

    # Generate Reality keypair
    local keypair
    keypair=$(generate_reality_keypair) || die "Failed to generate Reality keypair"
    export PRIV PUB
    read -r PRIV PUB <<< "$keypair"
    success "  ✓ Reality keypair generated"

    # Generate short ID (8 hex characters for sing-box)
    export SID
    SID=$(openssl rand -hex 4)
    validate_short_id "$SID" || die "Generated invalid short ID: $SID"
    success "  ✓ Short ID generated: $SID"

    # Allocate ports
    msg "Allocating ports..."
    export REALITY_PORT_CHOSEN
    REALITY_PORT_CHOSEN=$(allocate_port "$REALITY_PORT" "$REALITY_PORT_FALLBACK" "Reality") || die "Failed to allocate Reality port"
    success "  ✓ Reality port: $REALITY_PORT_CHOSEN"

    # Allocate additional ports if not Reality-only mode
    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
        export WS_PORT_CHOSEN HY2_PORT_CHOSEN HY2_PASS
        WS_PORT_CHOSEN=$(allocate_port "$WS_PORT" "$WS_PORT_FALLBACK" "WS-TLS") || die "Failed to allocate WS port"
        HY2_PORT_CHOSEN=$(allocate_port "$HY2_PORT" "$HY2_PORT_FALLBACK" "Hysteria2") || die "Failed to allocate Hysteria2 port"
        HY2_PASS=$(generate_hex_string 16)
        success "  ✓ WS-TLS port: $WS_PORT_CHOSEN"
        success "  ✓ Hysteria2 port: $HY2_PORT_CHOSEN"
    fi

    success "Configuration materials generated successfully"
}

# Save client information for sbx-manager
save_client_info() {
    msg "Saving client information..."

    cat > "$CLIENT_INFO" <<EOF
# sing-box client configuration
# Generated: $(date)

DOMAIN="$DOMAIN"
UUID="$UUID"
PUBLIC_KEY="$PUB"
SHORT_ID="$SID"
SNI="${SNI_DEFAULT}"
REALITY_PORT="${REALITY_PORT_CHOSEN}"
EOF

    if [[ "${REALITY_ONLY_MODE:-0}" != "1" && -n "${CERT_FULLCHAIN:-}" ]]; then
        cat >> "$CLIENT_INFO" <<EOF
WS_PORT="${WS_PORT_CHOSEN}"
HY2_PORT="${HY2_PORT_CHOSEN}"
HY2_PASS="${HY2_PASS}"
CERT_FULLCHAIN="${CERT_FULLCHAIN}"
CERT_KEY="${CERT_KEY}"
EOF
    fi

    chmod 600 "$CLIENT_INFO"
    success "  ✓ Client info saved to: $CLIENT_INFO"
}

# Install sbx-manager script
install_manager_script() {
    msg "Installing management script..."

    local manager_template="${SCRIPT_DIR}/bin/sbx-manager.sh"

    if [[ -f "$manager_template" ]]; then
        local manager_path="/usr/local/bin/sbx-manager"
        local symlink_path="/usr/local/bin/sbx"
        local lib_path="/usr/local/lib/sbx"

        # Safely handle existing manager binary
        if [[ -e "$manager_path" && ! -f "$manager_path" ]]; then
            die "$manager_path exists but is not a regular file"
        fi

        # Safely handle existing symlink
        if [[ -L "$symlink_path" ]]; then
            # It's a symlink, safe to remove and recreate
            rm "$symlink_path"
        elif [[ -e "$symlink_path" ]]; then
            # File exists but is not a symlink - backup and warn
            local backup_path
            backup_path="${symlink_path}.backup.$(date +%s)"
            warn "File exists at $symlink_path (not a symlink)"
            mv "$symlink_path" "$backup_path"
            warn "  Backed up to $backup_path"
        fi

        # Install manager using temporary file + atomic move
        local temp_manager
        temp_manager=$(mktemp) || die "Failed to create temporary file"
        chmod 755 "$temp_manager"
        cp "$manager_template" "$temp_manager" || {
            rm -f "$temp_manager"
            die "Failed to copy manager template"
        }

        # Atomic move to final location
        mv "$temp_manager" "$manager_path" || die "Failed to install manager"

        # Create symlink safely
        ln -sf "$manager_path" "$symlink_path"

        # Safely install library modules
        if [[ -e "$lib_path" && ! -d "$lib_path" ]]; then
            die "$lib_path exists but is not a directory"
        fi

        mkdir -p "$lib_path"
        cp "${SCRIPT_DIR}"/lib/*.sh "$lib_path/"
        chmod 644 "$lib_path"/*.sh

        success "  ✓ Management commands installed: sbx-manager, sbx"
        success "  ✓ Library modules installed to $lib_path/"
    else
        warn "Manager template not found, creating basic version..."
        # Fallback to inline version if template not found
        cat > /usr/local/bin/sbx-manager <<'EOF'
#!/bin/bash
case "$1" in
    info) [[ -f /etc/sing-box/client-info.txt ]] && cat /etc/sing-box/client-info.txt ;;
    status) systemctl status sing-box ;;
    restart) systemctl restart sing-box ;;
    *) echo "Usage: sbx {info|status|restart}"; exit 1 ;;
esac
EOF
        chmod +x /usr/local/bin/sbx-manager
        ln -sf /usr/local/bin/sbx-manager /usr/local/bin/sbx
        warn "  ⚠ Basic manager installed (template not found)"
    fi
}

# Open firewall ports
open_firewall() {
    local ports_to_open=("$REALITY_PORT_CHOSEN")

    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
        ports_to_open+=("$WS_PORT_CHOSEN" "$HY2_PORT_CHOSEN")
    fi

    msg "Configuring firewall..."

    # Try different firewall managers
    if have firewall-cmd; then
        for port in "${ports_to_open[@]}"; do
            firewall-cmd --permanent --add-port="${port}/tcp" 2>/dev/null || true
            [[ -n "${HY2_PORT_CHOSEN:-}" && "$port" == "$HY2_PORT_CHOSEN" ]] && firewall-cmd --permanent --add-port="${port}/udp" 2>/dev/null || true
        done
        firewall-cmd --reload 2>/dev/null || true
        success "  ✓ Firewall configured (firewalld)"
    elif have ufw; then
        for port in "${ports_to_open[@]}"; do
            ufw allow "${port}/tcp" 2>/dev/null || true
            [[ -n "${HY2_PORT_CHOSEN:-}" && "$port" == "$HY2_PORT_CHOSEN" ]] && ufw allow "${port}/udp" 2>/dev/null || true
        done
        success "  ✓ Firewall configured (ufw)"
    else
        info "  ℹ No firewall manager detected (firewall-cmd/ufw)"
        info "  ℹ Manually open ports: ${ports_to_open[*]}"
    fi
}

# Print installation summary
print_summary() {
    echo
    echo -e "${B}${G}═══════════════════════════════════════${N}"
    echo -e "${B}${G}   Installation Complete!${N}"
    echo -e "${B}${G}═══════════════════════════════════════${N}"
    echo
    echo -e "${G}✓${N} sing-box installed and running"
    echo -e "${G}✓${N} Configuration: $SB_CONF"
    echo -e "${G}✓${N} Service: systemctl status sing-box"
    echo
    echo -e "${CYAN}Server:${N} $DOMAIN"
    echo -e "${CYAN}Protocols:${N}"
    echo "  • VLESS-REALITY (port $REALITY_PORT_CHOSEN)"

    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
        echo "  • VLESS-WS-TLS (port $WS_PORT_CHOSEN)"
        echo "  • Hysteria2 (port $HY2_PORT_CHOSEN)"
    fi

    echo
    echo -e "${Y}Management Commands:${N}"
    echo "  sbx info      - Show configuration and connection URIs"
    echo "  sbx status    - Check service status"
    echo "  sbx restart   - Restart service"
    echo "  sbx log       - View live logs"
    echo "  sbx backup    - Backup/restore configuration"
    echo "  sbx export    - Export client configurations"
    echo "  sbx help      - Show all commands"
    echo
    echo -e "${G}For detailed configuration, run: ${B}sbx info${N}"
    echo
}

#==============================================================================
# Main Installation Flow
#==============================================================================

install_flow() {
    show_logo
    need_root

    # Validate environment variables if provided
    if [[ -n "${DOMAIN:-}" ]]; then
        validate_env_vars
    fi

    # Check for existing installation
    check_existing_installation

    # Ensure required tools
    ensure_tools

    # Download sing-box binary
    download_singbox

    # Generate configuration (unless skip flag is set)
    if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
        gen_materials

        # Issue certificate if not Reality-only mode
        if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
            maybe_issue_cert
        fi

        # Write configuration
        write_config

        # Setup and start service
        setup_service

        # Save client info
        save_client_info

        # Install manager script
        install_manager_script
    else
        success "Binary upgrade completed, preserving existing configuration"
        restart_service
    fi

    # Configure firewall
    open_firewall

    # Show summary
    if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
        print_summary
    else
        success "Upgrade complete! Run 'sbx info' to view configuration"
    fi
}

#==============================================================================
# Uninstall Flow
#==============================================================================

uninstall_flow() {
    show_logo
    need_root

    # Show what will be removed
    echo
    warn "The following will be completely removed:"
    [[ -x "$SB_BIN" ]] && echo "  - Binary: $SB_BIN"
    [[ -f "$SB_CONF" ]] && echo "  - Config: $SB_CONF"
    [[ -d "$SB_CONF_DIR" ]] && echo "  - Config directory: $SB_CONF_DIR"
    [[ -f "$SB_SVC" ]] && echo "  - Service: $SB_SVC"
    [[ -x "/usr/local/bin/sbx-manager" ]] && echo "  - Management commands: sbx-manager, sbx"
    [[ -d "/usr/local/lib/sbx" ]] && echo "  - Library modules: /usr/local/lib/sbx"
    [[ -d "$CERT_DIR_BASE" ]] && echo "  - Certificates: $CERT_DIR_BASE"

    if [[ "${FORCE:-0}" != "1" ]]; then
        echo
        if ! prompt_yes_no "Continue with complete removal?" N; then
            msg "Uninstall cancelled"
            exit 0
        fi
    fi

    echo
    msg "Removing sing-box..."

    # Stop and disable service
    if check_service_status; then
        stop_service
    fi

    # Remove service
    remove_service

    # Remove files
    msg "Removing files..."
    rm -f "$SB_BIN" /usr/local/bin/sbx-manager /usr/local/bin/sbx
    rm -rf "$SB_CONF_DIR" "$CERT_DIR_BASE" /usr/local/lib/sbx

    # Remove Caddy if installed
    if have caddy; then
        msg "Removing Caddy..."
        caddy_uninstall || warn "Failed to remove Caddy completely"
    fi

    success "sing-box uninstalled successfully"
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    # Parse command line arguments
    if [[ "${1:-}" == "uninstall" || "${1:-}" == "remove" ]]; then
        uninstall_flow
    else
        install_flow
    fi
}

# Execute main function
main "$@"
