#!/usr/bin/env bash
# lib/download.sh - Secure download abstraction with retry support
# Part of sbx-lite modular architecture
# Based on Rustup downloader patterns and OWASP security practices

# Prevent multiple sourcing
[[ -n "${_SBX_DOWNLOAD_LOADED:-}" ]] && return 0
readonly _SBX_DOWNLOAD_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -z "${_SBX_COMMON_LOADED:-}" ]] && source "${SCRIPT_DIR}/common.sh"
# shellcheck source=/dev/null
[[ -z "${_SBX_RETRY_LOADED:-}" ]] && source "${SCRIPT_DIR}/retry.sh"

#==============================================================================
# Configuration Constants
#==============================================================================

# Download configuration
readonly DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-30}"
readonly DOWNLOAD_CONNECT_TIMEOUT="${DOWNLOAD_CONNECT_TIMEOUT:-10}"
readonly DOWNLOAD_MAX_RETRIES="${DOWNLOAD_MAX_RETRIES:-3}"

# Preferred downloader (can be overridden)
DOWNLOADER="${DOWNLOADER:-auto}"

#==============================================================================
# Downloader Detection and Capabilities
#==============================================================================

# Check if curl supports retry flag
# Rustup pattern: conditionally enable features
#
# Returns:
#   0 if curl supports --retry, 1 otherwise
check_curl_retry_support() {
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    # Test if curl accepts --retry flag (without network request)
    # Check help output for --retry flag
    if curl --help all 2>/dev/null | grep -q -- '--retry'; then
        return 0
    fi

    return 1
}

# Check if curl supports continue-at flag
# Useful for resuming interrupted downloads
#
# Returns:
#   0 if curl supports -C -, 1 otherwise
check_curl_continue_support() {
    if ! command -v curl >/dev/null 2>&1; then
        return 1
    fi

    # Test if curl accepts -C flag
    if curl -C - --help >/dev/null 2>&1; then
        return 0
    fi

    return 1
}

# Detect best available downloader
# Priority: curl > wget > fail
#
# Returns:
#   "curl", "wget", or "none"
detect_downloader() {
    if command -v curl >/dev/null 2>&1; then
        echo "curl"
    elif command -v wget >/dev/null 2>&1; then
        echo "wget"
    else
        echo "none"
    fi
}

#==============================================================================
# Download Implementation Functions
#==============================================================================

# Download file using curl
# Implements Rustup-style secure download with optional retry
#
# Arguments:
#   $1 - source URL (must be HTTPS)
#   $2 - destination file path
#
# Returns:
#   0 on success, curl exit code on failure
_download_with_curl() {
    local url="$1"
    local output="$2"

    # Build curl arguments
    local args=(
        -fsSL                                      # fail silently, show errors, follow redirects, silent progress
        --proto '=https'                           # only HTTPS (security requirement)
        --tlsv1.2                                  # TLS 1.2+ only (security requirement)
        --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT}"  # connection timeout
        --max-time "${DOWNLOAD_TIMEOUT}"           # total operation timeout
    )

    # Add retry support if available (Rustup pattern)
    # Note: Retry is handled by retry_with_backoff, so we set --retry 0
    if check_curl_retry_support; then
        args+=(--retry 0)  # Disable curl's internal retry (we handle it)
    fi

    # Add continue-at support if available
    # Useful for large file downloads that may be interrupted
    if check_curl_continue_support; then
        args+=(-C -)  # Resume from where it left off
    fi

    # Execute download
    curl "${args[@]}" "$url" -o "$output" 2>&1
    return $?
}

# Download file using wget
# Fallback downloader with similar security settings
#
# Arguments:
#   $1 - source URL (must be HTTPS)
#   $2 - destination file path
#
# Returns:
#   0 on success, wget exit code on failure
_download_with_wget() {
    local url="$1"
    local output="$2"

    # Build wget arguments
    local args=(
        --quiet                                    # quiet mode (no progress bar)
        --timeout="${DOWNLOAD_TIMEOUT}"            # timeout for all operations
        --secure-protocol=TLSv1_2                  # TLS 1.2+ only
        --https-only                               # reject non-HTTPS URLs
    )

    # Execute download
    wget "${args[@]}" "$url" -O "$output" 2>&1
    return $?
}

#==============================================================================
# Public API
#==============================================================================

# Validate URL before download
# OWASP: Input validation is critical for security
#
# Arguments:
#   $1 - URL to validate
#
# Returns:
#   0 if valid, 1 if invalid
validate_download_url() {
    local url="$1"

    # Must start with https://
    if [[ ! "$url" =~ ^https:// ]]; then
        err "Invalid URL: Must use HTTPS protocol"
        err "URL: $url"
        return 1
    fi

    # Check reasonable length (prevent buffer overflow attacks)
    if [[ ${#url} -gt 2048 ]]; then
        err "Invalid URL: Too long (max 2048 characters)"
        return 1
    fi

    # Check for suspicious patterns (basic injection prevention)
    if [[ "$url" =~ [[:space:]] ]]; then
        err "Invalid URL: Contains whitespace"
        return 1
    fi

    return 0
}

# Download file with automatic downloader selection
# Main public API for secure downloads
#
# Arguments:
#   $1 - source URL
#   $2 - destination file path
#   $3 - optional: downloader override ("curl", "wget", or "auto")
#
# Returns:
#   0 on success, error code on failure
#
# Example:
#   download_file "https://example.com/file.sh" "/tmp/file.sh"
#   download_file "$url" "$output" "curl"  # Force curl
download_file() {
    local url="$1"
    local output="$2"
    local downloader_pref="${3:-${DOWNLOADER}}"

    # Validate URL
    if ! validate_download_url "$url"; then
        return 1
    fi

    # Create output directory if needed
    local output_dir
    output_dir="$(dirname "$output")"
    if [[ ! -d "$output_dir" ]]; then
        mkdir -p "$output_dir" || {
            err "Failed to create directory: $output_dir"
            return 1
        }
    fi

    # Select downloader
    local downloader="$downloader_pref"
    if [[ "$downloader" == "auto" ]]; then
        downloader="$(detect_downloader)"
    fi

    # Execute download with selected tool
    case "$downloader" in
        curl)
            if ! command -v curl >/dev/null 2>&1; then
                err "curl not found. Please install curl or set DOWNLOADER=wget"
                return 1
            fi
            _download_with_curl "$url" "$output"
            ;;

        wget)
            if ! command -v wget >/dev/null 2>&1; then
                err "wget not found. Please install wget or set DOWNLOADER=curl"
                return 1
            fi
            _download_with_wget "$url" "$output"
            ;;

        none)
            err ""
            err "ERROR: No supported downloader found"
            err "Please install one of the following:"
            err "  • curl: apt-get install curl  (Debian/Ubuntu)"
            err "  • wget: apt-get install wget  (Debian/Ubuntu)"
            err "  • curl: yum install curl      (CentOS/RHEL)"
            err "  • wget: yum install wget      (CentOS/RHEL)"
            err ""
            return 1
            ;;

        *)
            err "Invalid downloader: $downloader"
            err "Supported: curl, wget, auto"
            return 1
            ;;
    esac
}

# Download file with retry support
# Combines download_file with exponential backoff retry
#
# Arguments:
#   $1 - source URL
#   $2 - destination file path
#   $3 - optional: max retry attempts (default: DOWNLOAD_MAX_RETRIES)
#
# Returns:
#   0 on success, error code on failure
#
# Example:
#   download_file_with_retry "https://example.com/file.sh" "/tmp/file.sh"
#   download_file_with_retry "$url" "$output" 5  # 5 attempts
download_file_with_retry() {
    local url="$1"
    local output="$2"
    local max_retries="${3:-${DOWNLOAD_MAX_RETRIES}}"

    retry_with_backoff "$max_retries" download_file "$url" "$output"
}

# Verify downloaded file
# Basic integrity checks after download
#
# Arguments:
#   $1 - file path
#   $2 - minimum size in bytes (optional, default: 100)
#
# Returns:
#   0 if valid, 1 if invalid
verify_downloaded_file() {
    local file_path="$1"
    local min_size="${2:-100}"

    # Check file exists
    if [[ ! -f "$file_path" ]]; then
        err "Downloaded file not found: $file_path"
        return 1
    fi

    # Check file size
    local file_size
    file_size=$(stat -c%s "$file_path" 2>/dev/null || stat -f%z "$file_path" 2>/dev/null || echo "0")

    if [[ "$file_size" -lt "$min_size" ]]; then
        err "Downloaded file too small: $file_path (${file_size} bytes, expected >= ${min_size})"
        return 1
    fi

    return 0
}

# Download and verify in one operation
# Convenience function combining download + verification
#
# Arguments:
#   $1 - source URL
#   $2 - destination file path
#   $3 - optional: minimum size (default: 100)
#   $4 - optional: max retries (default: DOWNLOAD_MAX_RETRIES)
#
# Returns:
#   0 on success, error code on failure
#
# Example:
#   download_and_verify "https://example.com/file.sh" "/tmp/file.sh" 1000
download_and_verify() {
    local url="$1"
    local output="$2"
    local min_size="${3:-100}"
    local max_retries="${4:-${DOWNLOAD_MAX_RETRIES}}"

    # Download with retry
    if ! download_file_with_retry "$url" "$output" "$max_retries"; then
        return 1
    fi

    # Verify
    if ! verify_downloaded_file "$output" "$min_size"; then
        rm -f "$output"  # Clean up invalid file
        return 1
    fi

    return 0
}

# Get download tool information
# Useful for debugging and diagnostics
get_download_info() {
    local downloader
    downloader="$(detect_downloader)"

    echo "Download configuration:"
    echo "  Preferred downloader: ${DOWNLOADER}"
    echo "  Detected downloader: ${downloader}"
    echo "  Connection timeout: ${DOWNLOAD_CONNECT_TIMEOUT}s"
    echo "  Total timeout: ${DOWNLOAD_TIMEOUT}s"
    echo "  Max retries: ${DOWNLOAD_MAX_RETRIES}"

    if [[ "$downloader" == "curl" ]]; then
        echo "  Curl version: $(curl --version 2>/dev/null | head -1)"
        echo "  Curl retry support: $(check_curl_retry_support && echo "Yes" || echo "No")"
        echo "  Curl continue support: $(check_curl_continue_support && echo "Yes" || echo "No")"
    elif [[ "$downloader" == "wget" ]]; then
        echo "  Wget version: $(wget --version 2>/dev/null | head -1)"
    fi
}

# Export functions for use in subshells
export -f check_curl_retry_support
export -f check_curl_continue_support
export -f detect_downloader
export -f validate_download_url
export -f download_file
export -f download_file_with_retry
export -f verify_downloaded_file
export -f download_and_verify
export -f get_download_info

# Module loaded successfully (silent load for cleaner output)
