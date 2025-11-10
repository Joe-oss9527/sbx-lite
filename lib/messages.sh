#!/usr/bin/env bash
# lib/messages.sh - Centralized message templates for i18n preparation
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Provides centralized error message templates for consistency
#          and future internationalization support
# Dependencies: lib/common.sh
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_MESSAGES_LOADED:-}" ]] && return 0
readonly _SBX_MESSAGES_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Message Templates
#==============================================================================

# Error message templates
# Format: Uses printf-style placeholders (%s, %d, etc.)
# Note: All messages must be in English (no emoji, no CJK characters)
declare -gA ERROR_MESSAGES=(
    # Validation errors
    [INVALID_PORT]="Invalid port number: %s (must be 1-65535)"
    [INVALID_DOMAIN]="Invalid domain format: %s"
    [INVALID_IP]="Invalid IP address: %s"
    [INVALID_UUID]="Invalid UUID format: %s"
    [INVALID_PATH]="Invalid file path: %s"

    # File errors
    [FILE_NOT_FOUND]="File not found: %s"
    [FILE_NOT_READABLE]="File is not readable: %s"
    [FILE_WRITE_ERROR]="Failed to write to file: %s"
    [DIRECTORY_NOT_FOUND]="Directory not found: %s"

    # Network errors
    [NETWORK_ERROR]="Network error: Failed to connect to %s"
    [DOWNLOAD_FAILED]="Failed to download from: %s"
    [CONNECTION_TIMEOUT]="Connection timeout after %s seconds: %s"
    [DNS_RESOLUTION_FAILED]="DNS resolution failed for: %s"

    # Service errors
    [SERVICE_START_FAILED]="Failed to start service: %s"
    [SERVICE_STOP_FAILED]="Failed to stop service: %s"
    [SERVICE_NOT_RUNNING]="Service is not running: %s"
    [SERVICE_ALREADY_RUNNING]="Service is already running: %s"

    # Configuration errors
    [CONFIG_INVALID]="Invalid configuration in: %s"
    [CONFIG_PARSE_ERROR]="Failed to parse configuration: %s"
    [CONFIG_WRITE_FAILED]="Failed to write configuration to: %s"
    [CONFIG_VALIDATION_FAILED]="Configuration validation failed: %s"

    # Certificate errors
    [CERT_NOT_FOUND]="Certificate not found: %s"
    [CERT_EXPIRED]="Certificate has expired: %s"
    [CERT_INVALID]="Invalid certificate: %s"
    [CERT_KEY_MISMATCH]="Certificate and key do not match: %s"

    # Checksum errors
    [CHECKSUM_FAILED]="SHA256 checksum verification failed for: %s"
    [CHECKSUM_MISMATCH]="Checksum mismatch for file: %s (expected: %s, actual: %s)"
    [CHECKSUM_FILE_NOT_FOUND]="Checksum file not found: %s"

    # Permission errors
    [PERMISSION_DENIED]="Permission denied: %s"
    [ROOT_REQUIRED]="This operation requires root privileges"
    [USER_NOT_FOUND]="User not found: %s"

    # Dependency errors
    [MISSING_DEPENDENCY]="Required dependency not found: %s"
    [VERSION_MISMATCH]="Version mismatch for %s (required: %s, found: %s)"
    [TOOL_NOT_AVAILABLE]="Required tool not available: %s"

    # Port errors
    [PORT_IN_USE]="Port already in use: %s"
    [PORT_ALLOCATION_FAILED]="Failed to allocate port after %s attempts"
    [PORT_NOT_LISTENING]="Service not listening on port: %s"

    # Backup/Restore errors
    [BACKUP_FAILED]="Backup operation failed: %s"
    [RESTORE_FAILED]="Restore operation failed: %s"
    [BACKUP_NOT_FOUND]="Backup file not found: %s"
    [ENCRYPTION_FAILED]="Encryption failed: %s"
    [DECRYPTION_FAILED]="Decryption failed: %s"

    # Generic errors
    [OPERATION_FAILED]="Operation failed: %s"
    [UNEXPECTED_ERROR]="Unexpected error occurred: %s"
    [NOT_IMPLEMENTED]="Feature not implemented: %s"
    [DEPRECATED_FEATURE]="This feature is deprecated: %s"
)

# Warning message templates
declare -gA WARNING_MESSAGES=(
    [DEPRECATED_FUNCTION]="Function '%s' is deprecated and will be removed in version %s"
    [EXPERIMENTAL_FEATURE]="Feature '%s' is experimental and may change in future versions"
    [FALLBACK_IN_USE]="Using fallback method for: %s"
    [RESOURCE_LOW]="Low system resources detected: %s"
    [INSECURE_OPERATION]="Potentially insecure operation: %s"
)

# Info message templates
declare -gA INFO_MESSAGES=(
    [OPERATION_SUCCESS]="Operation completed successfully: %s"
    [SERVICE_STARTED]="Service started: %s"
    [SERVICE_STOPPED]="Service stopped: %s"
    [BACKUP_CREATED]="Backup created: %s"
    [CONFIG_UPDATED]="Configuration updated: %s"
)

#==============================================================================
# Message Formatting Functions
#==============================================================================

# Format error message
#
# Usage: format_error <error_key> [arguments...]
# Example: format_error "INVALID_PORT" "99999"
#
# Returns: Formatted error message
# Exit code: 0 on success, 1 if key not found
format_error() {
    local error_key="$1"
    shift

    local template="${ERROR_MESSAGES[$error_key]:-}"

    if [[ -z "$template" ]]; then
        # Fallback for unknown error keys
        echo "Error: $error_key - $*"
        return 1
    fi

    # Use printf for safe formatting
    # shellcheck disable=SC2059
    printf "$template" "$@"
    return 0
}

# Format warning message
#
# Usage: format_warning <warning_key> [arguments...]
# Example: format_warning "DEPRECATED_FUNCTION" "old_func" "v3.0"
#
# Returns: Formatted warning message
format_warning() {
    local warning_key="$1"
    shift

    local template="${WARNING_MESSAGES[$warning_key]:-}"

    if [[ -z "$template" ]]; then
        echo "Warning: $warning_key - $*"
        return 1
    fi

    # shellcheck disable=SC2059
    printf "$template" "$@"
    return 0
}

# Format info message
#
# Usage: format_info <info_key> [arguments...]
# Example: format_info "SERVICE_STARTED" "sing-box"
#
# Returns: Formatted info message
format_info() {
    local info_key="$1"
    shift

    local template="${INFO_MESSAGES[$info_key]:-}"

    if [[ -z "$template" ]]; then
        echo "Info: $info_key - $*"
        return 1
    fi

    # shellcheck disable=SC2059
    printf "$template" "$@"
    return 0
}

#==============================================================================
# Convenience Helper Functions (Optional)
#==============================================================================

# These helpers make common error reporting easier
# They combine message formatting with error logging

# Report invalid port error
err_invalid_port() {
    err "$(format_error "INVALID_PORT" "$1")"
}

# Report invalid domain error
err_invalid_domain() {
    err "$(format_error "INVALID_DOMAIN" "$1")"
}

# Report file not found error
err_file_not_found() {
    err "$(format_error "FILE_NOT_FOUND" "$1")"
}

# Report network error
err_network() {
    err "$(format_error "NETWORK_ERROR" "$1")"
}

# Report checksum failure
err_checksum_failed() {
    err "$(format_error "CHECKSUM_FAILED" "$1")"
}

# Report missing dependency
err_missing_dependency() {
    err "$(format_error "MISSING_DEPENDENCY" "$1")"
}

# Report service error
err_service() {
    err "$(format_error "SERVICE_START_FAILED" "$1")"
}

# Report configuration error
err_config() {
    err "$(format_error "CONFIG_INVALID" "$1")"
}

#==============================================================================
# Export Functions
#==============================================================================

export -f format_error format_warning format_info
export -f err_invalid_port err_invalid_domain err_file_not_found
export -f err_network err_checksum_failed err_missing_dependency
export -f err_service err_config

# Export message arrays
export ERROR_MESSAGES WARNING_MESSAGES INFO_MESSAGES
