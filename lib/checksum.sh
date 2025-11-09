#!/usr/bin/env bash
# lib/checksum.sh - SHA256 checksum verification for sing-box binaries
#
# This module provides functions for verifying the integrity of downloaded
# sing-box binaries using SHA256 checksums from official GitHub releases.
#
# Functions:
#   - verify_file_checksum: Verify file against checksum file
#   - verify_singbox_binary: Download and verify sing-box binary checksum

# Strict mode for error handling and safety
set -euo pipefail

[[ -n "${_SBX_CHECKSUM_LOADED:-}" ]] && return 0
readonly _SBX_CHECKSUM_LOADED=1

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load dependencies
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

#==============================================================================
# Checksum Verification Functions
#==============================================================================

# Verify file against checksum file
#
# Args:
#   $1: file_path - Path to file to verify
#   $2: checksum_file - Path to checksum file
#
# Returns:
#   0: Checksum valid
#   1: Checksum invalid or verification failed
#
# Example:
#   verify_file_checksum "/tmp/package.tar.gz" "/tmp/checksum.txt"
#
verify_file_checksum() {
    local file_path="$1"
    local checksum_file="$2"

    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        err "File not found: $file_path"
        return 1
    fi

    # Check if checksum file exists
    if [[ ! -f "$checksum_file" ]]; then
        warn "Checksum file not found: $checksum_file"
        return 1
    fi

    # Extract expected checksum (first field of first line)
    local expected_sum
    expected_sum=$(awk '{print $1}' "$checksum_file" | head -1)

    # Validate checksum format (64 hex characters for SHA256)
    if [[ ! "$expected_sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
        warn "Invalid checksum format: $expected_sum"
        warn "Expected 64 hexadecimal characters (SHA256)"
        return 1
    fi

    # Calculate actual checksum using available tool
    local actual_sum=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual_sum=$(sha256sum "$file_path" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual_sum=$(shasum -a 256 "$file_path" | awk '{print $1}')
    else
        warn "No SHA256 tool available (sha256sum/shasum)"
        warn "Cannot verify checksum without SHA256 utility"
        return 1
    fi

    # Ensure we got a checksum
    if [[ -z "$actual_sum" ]]; then
        err "Failed to calculate checksum for: $file_path"
        return 1
    fi

    # Compare checksums (case-insensitive)
    if [[ "${expected_sum,,}" == "${actual_sum,,}" ]]; then
        return 0
    else
        err "Checksum mismatch!"
        err "  Expected: $expected_sum"
        err "  Actual:   $actual_sum"
        err "  File may be corrupted or tampered"
        return 1
    fi
}

# Download and verify sing-box binary checksum
#
# Downloads the official SHA256 checksum file from GitHub releases
# and verifies the downloaded binary against it.
#
# Args:
#   $1: binary_path - Path to downloaded binary archive
#   $2: version - sing-box version (e.g., "v1.10.7")
#   $3: arch - Platform architecture (e.g., "linux-amd64")
#
# Returns:
#   0: Verification successful or skipped (non-fatal)
#   1: Verification failed (fatal - binary should not be used)
#
# Example:
#   verify_singbox_binary "/tmp/package.tar.gz" "v1.10.7" "linux-amd64"
#
# Note:
#   If checksum file is not available from GitHub, verification is skipped
#   with a warning. This is non-fatal to handle cases where GitHub might
#   be temporarily unavailable or checksum files might be missing for some
#   versions.
#
verify_singbox_binary() {
    local binary_path="$1"
    local version="$2"
    local arch="$3"

    msg "Verifying binary integrity..."

    # Validate inputs
    if [[ -z "$binary_path" ]] || [[ -z "$version" ]] || [[ -z "$arch" ]]; then
        err "Invalid arguments to verify_singbox_binary"
        return 1
    fi

    # Check if binary file exists
    if [[ ! -f "$binary_path" ]]; then
        err "Binary file not found: $binary_path"
        return 1
    fi

    # Construct checksum filename and URL
    # Format: sing-box-1.10.7-linux-amd64.tar.gz.sha256sum
    local filename="sing-box-${version#v}-${arch}.tar.gz"
    local checksum_url="https://github.com/SagerNet/sing-box/releases/download/${version}/${filename}.sha256sum"

    msg "  Checksum URL: $checksum_url"

    # Create temporary file for checksum
    local checksum_file
    checksum_file=$(mktemp) || {
        err "Failed to create temporary file"
        return 1
    }

    # Ensure cleanup (use variable expansion at trap time to avoid unbound variable in set -u)
    # shellcheck disable=SC2064
    trap "rm -f \"$checksum_file\"" RETURN

    # Download checksum file
    if ! safe_http_get "$checksum_url" "$checksum_file" 2>/dev/null; then
        warn "  ⚠ Checksum file not available from GitHub"
        warn "  ⚠ URL: $checksum_url"
        warn "  ⚠ Proceeding without verification (use at your own risk)"
        return 0  # Non-fatal - allow installation to continue
    fi

    # Check if downloaded file has content
    if [[ ! -s "$checksum_file" ]]; then
        warn "  ⚠ Checksum file is empty"
        warn "  ⚠ Proceeding without verification"
        return 0  # Non-fatal
    fi

    # Verify checksum
    if verify_file_checksum "$binary_path" "$checksum_file"; then
        success "  ✓ Binary integrity verified (SHA256 match)"
        return 0
    else
        # Verification failed - this is FATAL
        err "Binary verification FAILED!"
        err "The downloaded package failed SHA256 checksum verification."
        err "Package may be:"
        err "  • Corrupted during download"
        err "  • Tampered with"
        err "  • Incomplete"
        err ""
        err "For security reasons, installation cannot continue."
        return 1  # Fatal - abort installation
    fi
}

# Export functions for use in other modules
export -f verify_file_checksum
export -f verify_singbox_binary
