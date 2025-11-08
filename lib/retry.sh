#!/usr/bin/env bash
# lib/retry.sh - Retry mechanism with exponential backoff and jitter
# Part of sbx-lite modular architecture
# Based on Google SRE best practices for resilient systems

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_RETRY_LOADED:-}" ]] && return 0
readonly _SBX_RETRY_LOADED=1

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -z "${_SBX_COMMON_LOADED:-}" ]] && source "${SCRIPT_DIR}/common.sh"

#==============================================================================
# Configuration Constants
#==============================================================================

# Retry configuration (can be overridden via environment variables)
# Note: Not using 'readonly' to allow retry_with_custom_backoff to temporarily override
RETRY_MAX_ATTEMPTS="${RETRY_MAX_ATTEMPTS:-3}"
RETRY_BACKOFF_BASE="${RETRY_BACKOFF_BASE:-2}"
RETRY_BACKOFF_MAX="${RETRY_BACKOFF_MAX:-32}"
RETRY_JITTER_MAX="${RETRY_JITTER_MAX:-1000}"  # milliseconds

# Global retry budget (prevent retry amplification)
readonly GLOBAL_RETRY_BUDGET="${GLOBAL_RETRY_BUDGET:-30}"
declare -g GLOBAL_RETRY_COUNT=0

#==============================================================================
# Core Retry Functions
#==============================================================================

# Calculate exponential backoff with jitter
# Formula: min((base^attempt), max) + random(0, jitter_max)
# Reference: Google SRE - Exponential Backoff with Jitter
#
# Arguments:
#   $1 - attempt number (1-based)
#
# Returns:
#   Backoff time in milliseconds
#
# Example:
#   backoff_ms=$(calculate_backoff 2)  # Returns ~4000-5000ms
calculate_backoff() {
    local attempt="$1"
    local base="${RETRY_BACKOFF_BASE}"
    local max="${RETRY_BACKOFF_MAX}"

    # Exponential backoff: min((base^attempt), max)
    local backoff
    if command -v bc >/dev/null 2>&1; then
        # Use bc for precise calculation
        backoff=$(echo "scale=0; e=2^${attempt}; if (e > ${max}) ${max} else e" | bc)
    else
        # Fallback to bash arithmetic (may overflow for large attempts)
        backoff=$((base ** attempt))
        [[ $backoff -gt $max ]] && backoff=$max
    fi

    # Add jitter: random(0, RETRY_JITTER_MAX) milliseconds
    # Prevents thundering herd problem (retry storm)
    local jitter=$((RANDOM % RETRY_JITTER_MAX))

    # Return total backoff in milliseconds
    echo $((backoff * 1000 + jitter))
}

# Check if global retry budget is exhausted
# Google SRE: "Implement a per-request retry budget"
#
# Returns:
#   0 if budget available, 1 if exhausted
check_retry_budget() {
    if [[ $GLOBAL_RETRY_COUNT -ge $GLOBAL_RETRY_BUDGET ]]; then
        err ""
        err "Global retry budget exhausted (${GLOBAL_RETRY_BUDGET} retries)"
        err "This may indicate a systemic issue (e.g., GitHub outage)"
        err ""
        err "Suggestions:"
        err "  1. Check GitHub status: https://www.githubstatus.com"
        err "  2. Wait a few minutes and try again"
        err "  3. Use git clone installation method instead"
        err ""
        return 1
    fi
    return 0
}

# Determine if an error code is retriable
# Based on curl/wget exit codes and common network errors
#
# Arguments:
#   $1 - exit code from command
#
# Returns:
#   0 if retriable, 1 if permanent error
#
# Curl error codes reference:
#   6: Could not resolve host
#   7: Failed to connect to host
#   28: Operation timeout
#   35: SSL connect error
#   52: Empty reply from server
#   56: Connection reset by peer
#   22: HTTP error (4xx/5xx)
#   23: Write error
is_retriable_error() {
    local exit_code="$1"

    # Retriable network errors (temporary conditions)
    case "$exit_code" in
        # Curl temporary errors
        6|7|28|35|52|56)
            return 0 ;;  # Retriable

        # Wget temporary errors
        4)  # Network failure
            return 0 ;;

        # Permanent errors (don't retry)
        22)  # HTTP 4xx/5xx (likely 404, 403, etc.)
            return 1 ;;
        23)  # Write error (disk full, permissions)
            return 1 ;;

        # Wget permanent errors
        8)  # Server error response
            return 1 ;;

        # Unknown errors - retry by default (conservative approach)
        *)
            return 0 ;;
    esac
}

# Execute command with exponential backoff retry
# Implements Google SRE retry pattern with jitter
#
# Arguments:
#   $1 - max attempts (optional, defaults to RETRY_MAX_ATTEMPTS)
#   $@ - command to execute (remaining arguments)
#
# Returns:
#   0 on success, last command exit code on failure
#
# Example:
#   retry_with_backoff 3 curl -fsSL "$url" -o "$output"
#   retry_with_backoff download_module "common"
retry_with_backoff() {
    local max_attempts="${RETRY_MAX_ATTEMPTS}"

    # Check if first argument is a number (max attempts override)
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        max_attempts="$1"
        shift
    fi

    local command=("$@")
    local attempt=0
    local exit_code=0

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))

        # Check global retry budget before attempting
        if ! check_retry_budget; then
            return 1
        fi

        # Execute command
        "${command[@]}"
        exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            # Success
            if [[ $attempt -gt 1 ]]; then
                success "✓ Succeeded on attempt ${attempt}"
            fi
            return 0
        fi

        # Check if error is retriable
        if ! is_retriable_error "$exit_code"; then
            err "✗ Non-retriable error (exit code: ${exit_code})"
            err "This error indicates a permanent condition that won't improve with retries."
            return "$exit_code"
        fi

        # Increment global retry counter
        ((GLOBAL_RETRY_COUNT++))

        # Check if this was the last attempt
        if [[ $attempt -ge $max_attempts ]]; then
            err "✗ Failed after ${max_attempts} attempts (exit code: ${exit_code})"
            return "$exit_code"
        fi

        # Calculate backoff time
        local backoff_ms
        backoff_ms="$(calculate_backoff "$attempt")"

        # Calculate backoff in seconds for display (use bc if available)
        local backoff_sec
        if command -v bc >/dev/null 2>&1; then
            backoff_sec=$(echo "scale=1; ${backoff_ms} / 1000" | bc 2>/dev/null || echo "$((backoff_ms / 1000))")
        else
            backoff_sec=$((backoff_ms / 1000))
        fi

        warn "Attempt ${attempt}/${max_attempts} failed (exit code: ${exit_code})"
        warn "Retrying in ${backoff_sec}s..."

        # Wait with backoff (supports fractional seconds if sleep supports it)
        if sleep 0.1 2>/dev/null; then
            # sleep supports fractional seconds
            if command -v bc >/dev/null 2>&1; then
                sleep "$(echo "scale=3; ${backoff_ms} / 1000" | bc 2>/dev/null || echo "0.$((backoff_ms / 100))")"
            else
                # Fallback to bash arithmetic with millisecond precision
                local sec=$((backoff_ms / 1000))
                local ms=$((backoff_ms % 1000))
                sleep "${sec}.${ms}"
            fi
        else
            # Fallback to integer seconds
            sleep "$((backoff_ms / 1000 + 1))"
        fi
    done

    return "$exit_code"
}

# Retry with custom backoff parameters
# Provides fine-grained control over retry behavior
#
# Arguments:
#   $1 - max attempts
#   $2 - base backoff multiplier
#   $3 - max backoff seconds
#   $@ - command to execute (remaining arguments)
#
# Example:
#   retry_with_custom_backoff 5 3 60 curl "$url"
retry_with_custom_backoff() {
    local max_attempts="$1"
    local base="$2"
    local max_backoff="$3"
    shift 3

    # Temporarily override constants
    local old_max="${RETRY_MAX_ATTEMPTS}"
    local old_base="${RETRY_BACKOFF_BASE}"
    local old_backoff_max="${RETRY_BACKOFF_MAX}"

    RETRY_MAX_ATTEMPTS="$max_attempts"
    RETRY_BACKOFF_BASE="$base"
    RETRY_BACKOFF_MAX="$max_backoff"

    retry_with_backoff "$@"
    local result=$?

    # Restore constants
    RETRY_MAX_ATTEMPTS="$old_max"
    RETRY_BACKOFF_BASE="$old_base"
    RETRY_BACKOFF_MAX="$old_backoff_max"

    return "$result"
}

# Reset global retry counter
# Useful for testing or starting fresh retry budget
reset_retry_counter() {
    GLOBAL_RETRY_COUNT=0
}

# Get current retry statistics
# Useful for monitoring and debugging
get_retry_stats() {
    echo "Global retry count: ${GLOBAL_RETRY_COUNT}/${GLOBAL_RETRY_BUDGET}"
    echo "Retry budget remaining: $((GLOBAL_RETRY_BUDGET - GLOBAL_RETRY_COUNT))"
}

# Export functions for use in subshells
export -f calculate_backoff
export -f check_retry_budget
export -f is_retriable_error
export -f retry_with_backoff
export -f retry_with_custom_backoff
export -f reset_retry_counter
export -f get_retry_stats

# Module loaded successfully (silent load for cleaner output)
