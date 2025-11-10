#!/usr/bin/env bash
# lib/logging.sh - Centralized logging functionality
# Part of sbx-lite modular architecture v2.2.0
#
# Purpose: Provides all logging functions with configurable output formats
# Dependencies: lib/common.sh (for colors and cleanup)
# Author: sbx-lite project
# License: MIT

set -euo pipefail

# Guard against multiple sourcing
[[ -n "${_SBX_LOGGING_LOADED:-}" ]] && return 0
readonly _SBX_LOGGING_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Note: We need colors from common.sh, but common.sh will source us
# So only source common.sh if it hasn't been loaded yet
if [[ -z "${_SBX_COMMON_LOADED:-}" ]]; then
    source "${_LIB_DIR}/common.sh"
fi

#==============================================================================
# Logging Configuration
#==============================================================================

# Logging configuration from environment
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-0}"
LOG_FORMAT="${LOG_FORMAT:-text}"
LOG_FILE="${LOG_FILE:-}"
LOG_LEVEL_FILTER="${LOG_LEVEL_FILTER:-}"
LOG_MAX_SIZE_KB="${LOG_MAX_SIZE_KB:-10240}"  # Default 10MB
LOG_WRITE_COUNT=0  # Counter for periodic rotation checks

# Log level values (lower number = higher priority)
declare -r -A LOG_LEVELS=( [ERROR]=0 [WARN]=1 [INFO]=2 [DEBUG]=3 )

# Normalize and validate LOG_LEVEL_FILTER
if [[ -n "${LOG_LEVEL_FILTER}" ]]; then
  # Convert to uppercase for case-insensitive matching
  LOG_LEVEL_FILTER="${LOG_LEVEL_FILTER^^}"

  # Validate against known levels
  case "${LOG_LEVEL_FILTER}" in
    ERROR|WARN|INFO|DEBUG)
      # Valid level
      ;;
    *)
      # Invalid level - warn and use safe default
      echo "Warning: Invalid LOG_LEVEL_FILTER='${LOG_LEVEL_FILTER}'. Valid values: ERROR, WARN, INFO, DEBUG. Using INFO." >&2
      LOG_LEVEL_FILTER="INFO"
      ;;
  esac
fi

# Set current log level
case "${LOG_LEVEL_FILTER:-INFO}" in
  ERROR) declare -r LOG_LEVEL_CURRENT=0 ;;
  WARN)  declare -r LOG_LEVEL_CURRENT=1 ;;
  INFO)  declare -r LOG_LEVEL_CURRENT=2 ;;
  DEBUG) declare -r LOG_LEVEL_CURRENT=3 ;;
  *)     declare -r LOG_LEVEL_CURRENT=2 ;;  # Default to INFO
esac

#==============================================================================
# Internal Helper Functions
#==============================================================================

# Get timestamp prefix if enabled
_log_timestamp() {
  [[ "${LOG_TIMESTAMPS}" == "1" ]] && printf "[%s] " "$(date '+%Y-%m-%d %H:%M:%S')" || true
}

# Write to log file if configured
_log_to_file() {
  [[ -z "${LOG_FILE}" ]] && return 0

  # Periodic rotation check (every 100 writes to minimize overhead)
  LOG_WRITE_COUNT=$((LOG_WRITE_COUNT + 1))
  if [[ $((LOG_WRITE_COUNT % 100)) == 0 ]]; then
    rotate_logs_if_needed
  fi

  # Create log file with secure permissions on first write
  if [[ ! -f "${LOG_FILE}" ]]; then
    touch "${LOG_FILE}" && chmod 600 "${LOG_FILE}"
  fi

  echo "$*" >> "${LOG_FILE}" 2>/dev/null || true
}

# JSON structured logging helper
log_json() {
  [[ "${LOG_FORMAT}" != "json" ]] && return 0

  local level="$1"
  shift
  local message="$*"

  # Escape special characters in message for JSON
  message="${message//\\/\\\\}"
  message="${message//\"/\\\"}"
  message="${message//$'\n'/\\n}"
  message="${message//$'\r'/\\r}"
  message="${message//$'\t'/\\t}"

  local json_log
  json_log=$(printf '{"timestamp":"%s","level":"%s","message":"%s"}' \
    "$(date -Iseconds)" "$level" "$message")

  echo "$json_log" >&2
  _log_to_file "$json_log"
}

# Check if message should be logged based on level
_should_log() {
  local msg_level="$1"
  # Map log level to numeric value
  local msg_level_value
  case "$msg_level" in
    ERROR) msg_level_value=0 ;;
    WARN)  msg_level_value=1 ;;
    INFO)  msg_level_value=2 ;;
    DEBUG) msg_level_value=3 ;;
    *)     msg_level_value=2 ;;  # Default to INFO level
  esac

  [[ -z "${LOG_LEVEL_FILTER}" ]] && return 0
  [[ $msg_level_value -le $LOG_LEVEL_CURRENT ]] && return 0
  return 1
}

#==============================================================================
# Public Logging Functions
#==============================================================================

# Info message (green [*])
msg() {
  _should_log "INFO" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "INFO" "$@"
  else
    local output
    output="$(_log_timestamp)${G}[*]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Warning message (yellow [!])
warn() {
  _should_log "WARN" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "WARN" "$@"
  else
    local output
    output="$(_log_timestamp)${Y}[!]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Error message (red [ERR])
err() {
  _should_log "ERROR" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "ERROR" "$@"
  else
    local output
    output="$(_log_timestamp)${R}[ERR]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Info message (blue [INFO])
info() {
  _should_log "INFO" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "INFO" "$@"
  else
    local output
    output="$(_log_timestamp)${BLUE}[INFO]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Success message (green [✓])
success() {
  _should_log "INFO" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "INFO" "$@"
  else
    local output
    output="$(_log_timestamp)${G}[✓]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Debug message (cyan [DEBUG])
debug() {
  [[ "${DEBUG:-0}" == "1" ]] || return 0
  _should_log "DEBUG" || return 0

  if [[ "${LOG_FORMAT}" == "json" ]]; then
    log_json "DEBUG" "$@"
  else
    local output
    output="$(_log_timestamp)${CYAN}[DEBUG]${N} $*"
    echo "$output" >&2
    _log_to_file "$output"
  fi
}

# Error and exit
die() {
  err "$*"
  exit 1
}

#==============================================================================
# Log Rotation Functions
#==============================================================================

# Check if log rotation is needed and rotate if necessary
# This function is called periodically from _log_to_file to avoid
# checking file size on every log write (performance optimization)
rotate_logs_if_needed() {
  local log_file="${LOG_FILE:-}"
  local max_size_kb="${LOG_MAX_SIZE_KB:-10240}"

  [[ -z "$log_file" || ! -f "$log_file" ]] && return 0

  # Get file size in KB
  local file_size_kb
  file_size_kb=$(du -k "$log_file" 2>/dev/null | cut -f1) || return 0

  # Only rotate if file exceeds max size
  if [[ ${file_size_kb:-0} -gt $max_size_kb ]]; then
    rotate_logs "$log_file" "$max_size_kb"
  fi
}

# Log rotation helper
rotate_logs() {
  local log_file="${1:-${LOG_FILE}}"
  local max_size_kb="${2:-10240}"  # Default 10MB

  [[ -z "$log_file" ]] && return 0
  [[ ! -f "$log_file" ]] && return 0

  # Get file size in KB
  local file_size
  file_size=$(du -k "$log_file" 2>/dev/null | cut -f1)

  # Rotate if larger than max size
  if [[ $file_size -gt $max_size_kb ]]; then
    local timestamp
    timestamp=$(date '+%Y%m%d-%H%M%S')
    mv "$log_file" "${log_file}.${timestamp}" 2>/dev/null || true
    touch "$log_file" && chmod 600 "$log_file"

    # Keep only last 5 rotated logs
    find "$(dirname "$log_file")" -name "$(basename "$log_file").*" -type f \
      | sort -r | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f msg warn err info success debug die
export -f log_json rotate_logs rotate_logs_if_needed
export -f _log_timestamp _log_to_file _should_log
