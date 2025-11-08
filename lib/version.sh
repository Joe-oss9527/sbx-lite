#!/usr/bin/env bash
# lib/version.sh - Version alias resolution for sing-box
#
# This module provides version resolution functionality for sing-box installations.
# Supports version aliases (stable/latest) and specific version strings.
#
# Functions:
#   - resolve_singbox_version: Resolve version alias to actual version tag

[[ -n "${_SBX_VERSION_LOADED:-}" ]] && return 0
readonly _SBX_VERSION_LOADED=1

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load dependencies
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

#==============================================================================
# Version Resolution Functions
#==============================================================================

# Resolve version alias to actual version tag
#
# Uses SINGBOX_VERSION environment variable to determine which version to use.
# Supports: stable, latest, vX.Y.Z, X.Y.Z, vX.Y.Z-beta.N
#
# Args:
#   None (uses environment variable SINGBOX_VERSION)
#
# Returns:
#   Outputs resolved version tag to stdout (e.g., "v1.10.7")
#   Exit code 0 on success, 1 on failure
#
# Environment:
#   SINGBOX_VERSION: Version specifier (default: "stable")
#     - "stable" or "" : Latest stable release (no pre-releases)
#     - "latest"       : Absolute latest release (including pre-releases)
#     - "vX.Y.Z"       : Specific version tag (preserved as-is)
#     - "X.Y.Z"        : Specific version (auto-prefixed with 'v')
#     - "vX.Y.Z-beta.N": Pre-release version (preserved as-is)
#
#   GITHUB_TOKEN (optional): GitHub API token for higher rate limits
#
# Example:
#   SINGBOX_VERSION=stable resolve_singbox_version
#   # Output: v1.10.7
#
#   SINGBOX_VERSION=latest resolve_singbox_version
#   # Output: v1.11.0-beta.1
#
#   SINGBOX_VERSION=1.10.7 resolve_singbox_version
#   # Output: v1.10.7
#
resolve_singbox_version() {
    local version_input="${SINGBOX_VERSION:-stable}"
    local resolved_version=""

    # Normalize to lowercase for comparison
    local version_lower="${version_input,,}"

    msg "Resolving version: $version_input"

    case "$version_lower" in
        stable|"")
            # Fetch latest stable release (non-prerelease)
            msg "  Fetching latest stable release from GitHub..."

            local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
            local api_response

            # Use GitHub API with optional token
            if [[ -n "${GITHUB_TOKEN:-}" ]]; then
                # Note: safe_http_get doesn't support headers yet, use curl directly
                if have curl; then
                    api_response=$(curl -fsSL --max-time 30 \
                        -H "Authorization: token ${GITHUB_TOKEN}" \
                        "$api_url" 2>/dev/null)
                else
                    api_response=$(wget -q --timeout=30 -O - "$api_url" 2>/dev/null)
                fi
            else
                api_response=$(safe_http_get "$api_url")
            fi

            if [[ $? -ne 0 ]] || [[ -z "$api_response" ]]; then
                err "Failed to fetch release information from GitHub API"
                return 1
            fi

            # Extract tag_name from JSON response
            resolved_version=$(echo "$api_response" | \
                grep '"tag_name":' | \
                head -1 | \
                grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')

            if [[ -z "$resolved_version" ]]; then
                err "Failed to parse version from API response"
                return 1
            fi
            ;;

        latest)
            # Fetch absolute latest release (including pre-releases)
            msg "  Fetching latest release (including pre-releases) from GitHub..."

            local api_url="https://api.github.com/repos/SagerNet/sing-box/releases"
            local api_response

            # Use GitHub API with optional token
            if [[ -n "${GITHUB_TOKEN:-}" ]]; then
                # Note: safe_http_get doesn't support headers yet, use curl directly
                if have curl; then
                    api_response=$(curl -fsSL --max-time 30 \
                        -H "Authorization: token ${GITHUB_TOKEN}" \
                        "$api_url" 2>/dev/null)
                else
                    api_response=$(wget -q --timeout=30 -O - "$api_url" 2>/dev/null)
                fi
            else
                api_response=$(safe_http_get "$api_url")
            fi

            if [[ $? -ne 0 ]] || [[ -z "$api_response" ]]; then
                err "Failed to fetch release information from GitHub API"
                return 1
            fi

            # Extract first tag_name from releases array
            resolved_version=$(echo "$api_response" | \
                grep '"tag_name":' | \
                head -1 | \
                grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?')

            if [[ -z "$resolved_version" ]]; then
                err "Failed to parse version from API response"
                return 1
            fi
            ;;

        v[0-9]*)
            # Already a version tag with 'v' prefix
            # Validate format: vX.Y.Z or vX.Y.Z-pre-release
            if [[ "$version_input" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
                resolved_version="$version_input"
                msg "  Using specified version: $resolved_version"
            else
                err "Invalid version format: $version_input"
                err "Expected: vX.Y.Z or vX.Y.Z-pre-release"
                return 1
            fi
            ;;

        [0-9]*)
            # Version without 'v' prefix - add it
            # Validate format: X.Y.Z or X.Y.Z-pre-release
            if [[ "$version_input" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
                resolved_version="v${version_input}"
                msg "  Auto-prefixed version: $resolved_version"
            else
                err "Invalid version format: $version_input"
                err "Expected: X.Y.Z or X.Y.Z-pre-release"
                return 1
            fi
            ;;

        *)
            # Invalid format
            err "Invalid version specifier: $version_input"
            err "Supported formats:"
            err "  - stable           : Latest stable release"
            err "  - latest           : Latest release (including pre-releases)"
            err "  - vX.Y.Z           : Specific version with 'v' prefix"
            err "  - X.Y.Z            : Specific version without 'v' prefix"
            err "  - vX.Y.Z-beta.N    : Pre-release version"
            return 1
            ;;
    esac

    # Final validation
    if [[ -z "$resolved_version" ]]; then
        err "Failed to resolve version: $version_input"
        return 1
    fi

    # Validate resolved version format
    if [[ ! "$resolved_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        err "Resolved version has invalid format: $resolved_version"
        return 1
    fi

    success "  ✓ Resolved to: $resolved_version"
    echo "$resolved_version"
    return 0
}

# Export functions for use in other modules
export -f resolve_singbox_version
