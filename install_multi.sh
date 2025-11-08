#!/usr/bin/env bash
# install_multi.sh v2.0 - Modular sing-box installer
# One-click official sing-box with VLESS-REALITY, VLESS-WS-TLS, and Hysteria2
#
# Usage (install):
#   bash install_multi.sh                                    # Interactive mode
#   AUTO_INSTALL=1 bash install_multi.sh                     # Non-interactive (auto-detect IP)
#   DOMAIN=example.com bash install_multi.sh                 # Full setup with domain
#   DOMAIN=example.com CERT_MODE=cf_dns CF_Token='xxx' ...  # With certificates
#
# Usage (uninstall):
#   FORCE=1 bash install_multi.sh uninstall

set -euo pipefail

#==============================================================================
# Early Constants (used before module loading)
#==============================================================================

# Download configuration
readonly DOWNLOAD_CONNECT_TIMEOUT_SEC=10
readonly DOWNLOAD_MAX_TIMEOUT_SEC=30
readonly MIN_MODULE_FILE_SIZE_BYTES=100

# File permissions (octal)
readonly SECURE_DIR_PERMISSIONS=700
readonly SECURE_FILE_PERMISSIONS=600

#==============================================================================
# Module Loading with Smart Download
#==============================================================================

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

#==============================================================================
# Module Download Helper Functions
#==============================================================================

# Download and verify a single module (for parallel execution)
# This function is designed to be called by xargs in parallel
_download_single_module() {
    local temp_lib_dir="$1"
    local github_repo="$2"
    local module="$3"

    local module_file="${temp_lib_dir}/${module}.sh"
    local module_url="${github_repo}/lib/${module}.sh"

    # Download module
    if command -v curl >/dev/null 2>&1; then
        if ! curl -fsSL --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -o "${module_file}" 2>&1; then
            echo "DOWNLOAD_FAILED:${module}" >&2
            return 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if ! wget -q --timeout="${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -O "${module_file}" 2>&1; then
            echo "DOWNLOAD_FAILED:${module}" >&2
            return 1
        fi
    else
        echo "NO_DOWNLOADER:${module}" >&2
        return 1
    fi

    # Verify downloaded file
    if [[ ! -f "${module_file}" ]]; then
        echo "FILE_NOT_FOUND:${module}" >&2
        return 1
    fi

    # Check file size
    local file_size
    file_size=$(stat -c%s "${module_file}" 2>/dev/null || stat -f%z "${module_file}" 2>/dev/null || echo "0")
    if [[ "${file_size}" -lt "${MIN_MODULE_FILE_SIZE_BYTES}" ]]; then
        echo "FILE_TOO_SMALL:${module}:${file_size}" >&2
        return 1
    fi

    # Validate bash syntax
    if ! bash -n "${module_file}" 2>/dev/null; then
        echo "SYNTAX_ERROR:${module}" >&2
        return 1
    fi

    # Success - output for progress tracking
    echo "SUCCESS:${module}:${file_size}"
    return 0
}

# Download modules in parallel using xargs
_download_modules_parallel() {
    local temp_lib_dir="$1"
    local github_repo="$2"
    shift 2
    local modules=("$@")

    local parallel_jobs="${PARALLEL_JOBS:-5}"
    local total="${#modules[@]}"

    echo "  Downloading ${total} modules in parallel (${parallel_jobs} jobs)..."

    # Export function and variables for subshells
    export -f _download_single_module
    export temp_lib_dir github_repo

    # Track results
    local failed_modules=()
    local success_count=0
    local current=0

    # Use xargs for parallel execution
    while IFS= read -r result; do
        ((current++))

        # Parse result
        if [[ "$result" =~ ^SUCCESS:(.+):([0-9]+)$ ]]; then
            local mod_name="${BASH_REMATCH[1]}"
            local mod_size="${BASH_REMATCH[2]}"
            ((success_count++))

            # Progress indicator
            local percent=$((current * 100 / total))
            printf "\r  [%3d%%] %d/%d modules downloaded" "$percent" "$current" "$total"

        elif [[ "$result" =~ ^(DOWNLOAD_FAILED|FILE_NOT_FOUND|FILE_TOO_SMALL|SYNTAX_ERROR|NO_DOWNLOADER):(.+) ]]; then
            local error_type="${BASH_REMATCH[1]}"
            local mod_name="${BASH_REMATCH[2]}"
            failed_modules+=("${mod_name}:${error_type}")
        fi
    done < <(printf '%s\n' "${modules[@]}" | xargs -P "$parallel_jobs" -I {} bash -c '_download_single_module "$temp_lib_dir" "$github_repo" "$@"' _ {})

    echo ""  # New line after progress

    # Check results
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        echo ""
        echo "ERROR: Failed to download ${#failed_modules[@]} module(s):"
        for failure in "${failed_modules[@]}"; do
            echo "  • ${failure}"
        done
        echo ""
        echo "Falling back to sequential download..."
        return 1
    fi

    echo "  ✓ All ${success_count} modules downloaded and verified"
    return 0
}

# Download modules sequentially (fallback method)
_download_modules_sequential() {
    local temp_lib_dir="$1"
    local github_repo="$2"
    shift 2
    local modules=("$@")

    local total="${#modules[@]}"
    local current=0

    echo "  Downloading ${total} modules sequentially..."

    for module in "${modules[@]}"; do
        ((current++))
        local module_file="${temp_lib_dir}/${module}.sh"
        local module_url="${github_repo}/lib/${module}.sh"

        printf "  [%d/%d] Downloading %s..." "$current" "$total" "${module}.sh"

        # Download
        if command -v curl >/dev/null 2>&1; then
            if ! curl -fsSL --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -o "${module_file}" 2>/dev/null; then
                echo " ✗ FAILED"
                rm -rf "${temp_lib_dir}"
                _show_download_error_help "${module}" "${module_url}"
                exit 1
            fi
        elif command -v wget >/dev/null 2>&1; then
            if ! wget -q --timeout="${DOWNLOAD_MAX_TIMEOUT_SEC}" "${module_url}" -O "${module_file}" 2>/dev/null; then
                echo " ✗ FAILED"
                rm -rf "${temp_lib_dir}"
                _show_download_error_help "${module}" "${module_url}"
                exit 1
            fi
        else
            echo " ✗ NO DOWNLOADER"
            rm -rf "${temp_lib_dir}"
            _show_no_downloader_error
            exit 1
        fi

        # Verify
        local file_size
        file_size=$(stat -c%s "${module_file}" 2>/dev/null || stat -f%z "${module_file}" 2>/dev/null || echo "0")

        if [[ ! -f "${module_file}" ]] || [[ "${file_size}" -lt "${MIN_MODULE_FILE_SIZE_BYTES}" ]]; then
            echo " ✗ VERIFY FAILED"
            rm -rf "${temp_lib_dir}"
            _show_verification_error "${module}" "${file_size}"
            exit 1
        fi

        if ! bash -n "${module_file}" 2>/dev/null; then
            echo " ✗ SYNTAX ERROR"
            rm -rf "${temp_lib_dir}"
            _show_syntax_error "${module}"
            exit 1
        fi

        echo " ✓ (${file_size} bytes)"
    done

    echo "  ✓ All ${total} modules downloaded and verified"
    return 0
}

# Show download error help
_show_download_error_help() {
    local module="$1"
    local url="$2"
    echo ""
    echo "ERROR: Failed to download module: ${module}.sh"
    echo "URL: ${url}"
    echo ""
    echo "Possible causes:"
    echo "  1. Network connectivity issues"
    echo "  2. GitHub rate limiting (try again in a few minutes)"
    echo "  3. Repository branch/tag does not exist"
    echo "  4. Firewall blocking GitHub access"
    echo ""
    echo "Troubleshooting:"
    echo "  • Test connectivity: curl -I https://github.com"
    echo "  • Use git clone instead:"
    echo "    git clone https://github.com/Joe-oss9527/sbx-lite.git"
    echo "    cd sbx-lite && bash install_multi.sh"
    echo ""
}

# Show no downloader error
_show_no_downloader_error() {
    echo ""
    echo "ERROR: Neither curl nor wget is available"
    echo "Please install one of the following:"
    echo "  • curl: apt-get install curl  (Debian/Ubuntu)"
    echo "  • wget: apt-get install wget  (Debian/Ubuntu)"
    echo "  • curl: yum install curl      (CentOS/RHEL)"
    echo "  • wget: yum install wget      (CentOS/RHEL)"
    echo ""
}

# Show verification error
_show_verification_error() {
    local module="$1"
    local file_size="$2"
    echo ""
    echo "ERROR: Downloaded file verification failed: ${module}.sh"
    echo "File size: ${file_size} bytes (minimum: ${MIN_MODULE_FILE_SIZE_BYTES} bytes)"
    echo ""
    echo "This usually indicates:"
    echo "  1. Network error during download (partial file)"
    echo "  2. GitHub returned an error page instead of the file"
    echo "  3. Rate limiting or authentication issues"
    echo ""
    echo "Please try again in a few minutes or use git clone method."
    echo ""
}

# Show syntax error
_show_syntax_error() {
    local module="$1"
    echo ""
    echo "ERROR: Invalid bash syntax in downloaded file: ${module}.sh"
    echo ""
    echo "This may indicate:"
    echo "  1. Corrupted download (network issue)"
    echo "  2. Partial/incomplete download"
    echo "  3. Potential security issue (MITM attack)"
    echo ""
    echo "For security, the installation has been aborted."
    echo "Please try again or use the git clone method."
    echo ""
}

#==============================================================================
# Smart Module Loader
#==============================================================================

# Smart module loader: downloads modules if not present (for one-liner install)
_load_modules() {
    local github_repo="https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main"
    # Module loading order: common must be first, retry before download
    local modules=(common retry download network validation checksum version certificate caddy config service ui backup export)
    local temp_lib_dir=""

    # Check if lib directory exists
    if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
        echo "[*] One-liner install detected, downloading required modules..."

        # Create temporary directory for modules
        temp_lib_dir="$(mktemp -d)" || {
            echo "ERROR: Failed to create temporary directory"
            exit 1
        }
        chmod "${SECURE_DIR_PERMISSIONS}" "${temp_lib_dir}"

        # Determine download strategy: parallel or sequential
        local use_parallel=1
        if [[ "${ENABLE_PARALLEL_DOWNLOAD:-1}" == "0" ]]; then
            use_parallel=0
        fi

        # Download modules (parallel with fallback to sequential on failure)
        if [[ $use_parallel -eq 1 ]] && command -v xargs >/dev/null 2>&1; then
            # Try parallel download first
            if ! _download_modules_parallel "${temp_lib_dir}" "${github_repo}" "${modules[@]}"; then
                # Parallel failed, fallback to sequential
                echo "  Retrying with sequential download..."
                _download_modules_sequential "${temp_lib_dir}" "${github_repo}" "${modules[@]}"
            fi
        else
            _download_modules_sequential "${temp_lib_dir}" "${github_repo}" "${modules[@]}"
        fi

        # Create proper directory structure
        local parent_dir
        parent_dir="$(dirname "${temp_lib_dir}")"
        SCRIPT_DIR="${parent_dir}/sbx-install-$$"
        mkdir -p "${SCRIPT_DIR}/lib"
        mv "${temp_lib_dir}"/*.sh "${SCRIPT_DIR}/lib/"
        rmdir "${temp_lib_dir}"

        # Register cleanup for temporary files
        trap 'rm -rf "${SCRIPT_DIR}" 2>/dev/null || true' EXIT INT TERM
    fi

    # Load all library modules
    for module in "${modules[@]}"; do
        local module_path="${SCRIPT_DIR}/lib/${module}.sh"
        if [[ -f "${module_path}" ]]; then
            # shellcheck source=/dev/null
            source "${module_path}"
        else
            echo "ERROR: Required module not found: ${module_path}"
            echo "Please ensure all lib/*.sh files are present."
            exit 1
        fi
    done

    # Verify API contracts after loading all modules
    _verify_module_apis
}

# Verify that all required functions exist (API contract validation)
# Implements Design by Contract (DbC) principles for module compatibility
_verify_module_apis() {
    local all_ok=true

    # Define required functions per module (API contract)
    local -A module_contracts=(
        ["common"]="msg warn err success die generate_uuid have need_root"
        ["retry"]="retry_with_backoff calculate_backoff is_retriable_error"
        ["download"]="download_file download_file_with_retry verify_downloaded_file"
        ["network"]="get_public_ip allocate_port detect_ipv6_support"
        ["validation"]="validate_domain validate_ip_address sanitize_input"
        ["checksum"]="verify_file_checksum verify_singbox_binary"
        ["version"]="resolve_singbox_version"
        ["config"]="write_config create_reality_inbound add_route_config"
        ["service"]="setup_service validate_port_listening restart_service"
    )

    # Verify each module's API contract
    for module in "${!module_contracts[@]}"; do
        local required_functions="${module_contracts[$module]}"
        local missing_functions=()

        for func in $required_functions; do
            if ! declare -F "$func" >/dev/null 2>&1; then
                missing_functions+=("$func")
                all_ok=false
            fi
        done

        if [[ ${#missing_functions[@]} -gt 0 ]]; then
            echo "ERROR: Module API contract violation: ${module}"
            echo "Missing functions: ${missing_functions[*]}"
        fi
    done

    if [[ "$all_ok" != true ]]; then
        echo ""
        echo "This may indicate:"
        echo "  1. Module version mismatch between install_multi.sh and lib/*.sh"
        echo "  2. Incomplete module download"
        echo "  3. Corrupted module files"
        echo ""
        echo "Please try:"
        echo "  git clone https://github.com/Joe-oss9527/sbx-lite.git"
        echo "  cd sbx-lite && bash install_multi.sh"
        echo ""
        exit 1
    fi
}

# Execute module loading
_load_modules

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
        # Auto-install mode: default to fresh install without prompting
        if [[ "${AUTO_INSTALL:-0}" == "1" ]]; then
            msg "Auto-install mode: performing fresh install..."
            if [[ -f "$SB_CONF" ]]; then
                local backup_file
                backup_file="${SB_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
                cp "$SB_CONF" "$backup_file"
                success "  ✓ Backed up existing config to: $backup_file"
            fi
            export SKIP_CONFIG_GEN=0
            export SKIP_BINARY_DOWNLOAD=0
            return 0
        fi

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
    chmod "${SECURE_DIR_PERMISSIONS}" "$tmp"

    # Resolve version using modular version resolver
    # Supports: stable (default), latest, vX.Y.Z, X.Y.Z
    tag=$(resolve_singbox_version) || {
        rm -rf "$tmp"
        die "Failed to resolve sing-box version"
    }

    # Get release information for the resolved version
    api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"

    msg "Fetching sing-box ${tag} release info for $arch..."
    raw=$(safe_http_get "$api") || {
        rm -rf "$tmp"
        die "Failed to fetch release information from GitHub"
    }

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

    # ==================== SHA256 Checksum Verification ====================
    # Use modular checksum verification from lib/checksum.sh
    # Skip verification if SKIP_CHECKSUM environment variable is set
    if [[ "${SKIP_CHECKSUM:-0}" != "1" ]]; then
        if ! verify_singbox_binary "$pkg" "$tag" "linux-${arch}"; then
            rm -rf "$tmp"
            die "Binary verification failed, aborting installation"
        fi
    else
        warn "⚠ SKIP_CHECKSUM is set, bypassing SHA256 verification"
        warn "⚠ This is NOT recommended for production use"
    fi
    # ==================== Checksum Verification End ====================

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
        # Auto-install mode: auto-detect IP without prompting
        if [[ "${AUTO_INSTALL:-0}" == "1" ]]; then
            msg "Auto-install mode: detecting server IP..."
            DOMAIN=$(get_public_ip) || die "Failed to detect server IP"
            success "Detected server IP: $DOMAIN"
            export REALITY_ONLY_MODE=1
        else
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

    chmod "${SECURE_FILE_PERMISSIONS}" "$CLIENT_INFO"
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
