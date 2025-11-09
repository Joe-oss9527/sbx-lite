#!/usr/bin/env bash
# lib/common.sh - Common utilities, global variables, and logging functions
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_COMMON_LOADED:-}" ]] && return 0
readonly _SBX_COMMON_LOADED=1

#==============================================================================
# Global Constants
#==============================================================================

declare -r SB_BIN="/usr/local/bin/sing-box"
declare -r SB_CONF_DIR="/etc/sing-box"
declare -r SB_CONF="$SB_CONF_DIR/config.json"
declare -r SB_SVC="/etc/systemd/system/sing-box.service"
declare -r CLIENT_INFO="$SB_CONF_DIR/client-info.txt"

# Default ports
declare -r REALITY_PORT_DEFAULT=443
declare -r WS_PORT_DEFAULT=8444
declare -r HY2_PORT_DEFAULT=8443

# Fallback ports
declare -r REALITY_PORT_FALLBACK=24443
declare -r WS_PORT_FALLBACK=24444
declare -r HY2_PORT_FALLBACK=24445

# Default values
declare -r SNI_DEFAULT="${SNI_DEFAULT:-www.microsoft.com}"
declare -r CERT_DIR_BASE="${CERT_DIR_BASE:-/etc/ssl/sbx}"
declare -r LOG_LEVEL="${LOG_LEVEL:-warn}"

# Operation timeouts and retry limits
declare -r NETWORK_TIMEOUT_SEC=5
declare -r SERVICE_STARTUP_MAX_WAIT_SEC=10
declare -r SERVICE_PORT_VALIDATION_MAX_RETRIES=5
declare -r PORT_ALLOCATION_MAX_RETRIES=3
declare -r PORT_ALLOCATION_RETRY_DELAY_SEC=2
declare -r CLEANUP_OLD_FILES_MIN=60
declare -r BACKUP_RETENTION_DAYS=30
declare -r CADDY_CERT_WAIT_TIMEOUT_SEC=60

# Download configuration (some constants defined in install_multi.sh early boot)
# DOWNLOAD_CONNECT_TIMEOUT_SEC, DOWNLOAD_MAX_TIMEOUT_SEC, MIN_MODULE_FILE_SIZE_BYTES
# are defined in install_multi.sh before module loading
[[ -z "${HTTP_TIMEOUT_SEC:-}" ]] && declare -r HTTP_TIMEOUT_SEC=30
[[ -z "${DEFAULT_PARALLEL_JOBS:-}" ]] && declare -r DEFAULT_PARALLEL_JOBS=5

# File permissions (octal) - defined in install_multi.sh for early use
# SECURE_DIR_PERMISSIONS and SECURE_FILE_PERMISSIONS are already readonly

# Input validation limits
[[ -z "${MAX_INPUT_LENGTH:-}" ]] && declare -r MAX_INPUT_LENGTH=256
[[ -z "${MAX_DOMAIN_LENGTH:-}" ]] && declare -r MAX_DOMAIN_LENGTH=253

# Service operation wait times
[[ -z "${SERVICE_WAIT_SHORT_SEC:-}" ]] && declare -r SERVICE_WAIT_SHORT_SEC=1
[[ -z "${SERVICE_WAIT_MEDIUM_SEC:-}" ]] && declare -r SERVICE_WAIT_MEDIUM_SEC=2

#==============================================================================
# Global Variables (from environment)
#==============================================================================

DOMAIN="${DOMAIN:-}"
CERT_MODE="${CERT_MODE:-}"
CF_Token="${CF_Token:-}"
CF_Zone_ID="${CF_Zone_ID:-}"
CF_Account_ID="${CF_Account_ID:-}"
CERT_FORCE="${CERT_FORCE:-0}"

CERT_FULLCHAIN="${CERT_FULLCHAIN:-}"
CERT_KEY="${CERT_KEY:-}"

REALITY_PORT="${REALITY_PORT:-$REALITY_PORT_DEFAULT}"
WS_PORT="${WS_PORT:-$WS_PORT_DEFAULT}"
HY2_PORT="${HY2_PORT:-$HY2_PORT_DEFAULT}"

SINGBOX_VERSION="${SINGBOX_VERSION:-}"

# Dynamic variables (generated during installation)
UUID="${UUID:-}"
PRIV="${PRIV:-}"
PUB="${PUB:-}"
SID="${SID:-}"
PUBLIC_KEY="${PUBLIC_KEY:-}"
SHORT_ID="${SHORT_ID:-}"
HY2_PASS="${HY2_PASS:-}"
SNI="${SNI:-}"
REALITY_PORT_CHOSEN="${REALITY_PORT_CHOSEN:-}"
WS_PORT_CHOSEN="${WS_PORT_CHOSEN:-}"
HY2_PORT_CHOSEN="${HY2_PORT_CHOSEN:-}"

# Process-specific temporary directory for secure cleanup
# Created with secure permissions and cleaned up automatically
SBX_TMP_DIR="${SBX_TMP_DIR:-}"

#==============================================================================
# Color Definitions
#==============================================================================

_init_colors() {
  if command -v tput >/dev/null 2>&1 && tput colors >/dev/null 2>&1; then
    B="$(tput bold)"
    N="$(tput sgr0)"
    R="$(tput setaf 1)"
    G="$(tput setaf 2)"
    Y="$(tput setaf 3)"
    BLUE="$(tput setaf 4)"
    PURPLE="$(tput setaf 5)"
    CYAN="$(tput setaf 6)"
  else
    # No color support
    B="" N="" R="" G="" Y="" BLUE="" PURPLE="" CYAN=""
  fi

  # Export for use in other modules
  export B N R G Y BLUE PURPLE CYAN
  readonly B N R G Y BLUE PURPLE CYAN
}

#==============================================================================
# Logging Functions
#==============================================================================

# Logging configuration from environment
LOG_TIMESTAMPS="${LOG_TIMESTAMPS:-0}"
LOG_FORMAT="${LOG_FORMAT:-text}"
LOG_FILE="${LOG_FILE:-}"
LOG_LEVEL_FILTER="${LOG_LEVEL_FILTER:-}"

# Log level values (lower number = higher priority)
declare -r -A LOG_LEVELS=( [ERROR]=0 [WARN]=1 [INFO]=2 [DEBUG]=3 )
declare -r LOG_LEVEL_CURRENT="${LOG_LEVELS[${LOG_LEVEL_FILTER:-INFO}]:-2}"

# Get timestamp prefix if enabled
_log_timestamp() {
  [[ "${LOG_TIMESTAMPS}" == "1" ]] && printf "[%s] " "$(date '+%Y-%m-%d %H:%M:%S')" || true
}

# Write to log file if configured
_log_to_file() {
  [[ -z "${LOG_FILE}" ]] && return 0

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
  local msg_level_value="${LOG_LEVELS[$msg_level]:-2}"

  [[ -z "${LOG_LEVEL_FILTER}" ]] && return 0
  [[ $msg_level_value -le $LOG_LEVEL_CURRENT ]] && return 0
  return 1
}

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

die() {
  err "$*"
  exit 1
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
# Utility Functions
#==============================================================================

# Check if running as root
need_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root (sudo)."
}

# Check if command exists
have() {
  command -v "$1" >/dev/null 2>&1
}

# Safe temporary directory cleanup
safe_rm_temp() {
  local temp_path="$1"
  [[ -n "$temp_path" && "$temp_path" != "/" && "$temp_path" =~ ^/tmp/ ]] || return 1
  [[ -d "$temp_path" ]] && rm -rf "$temp_path" 2>/dev/null || true
}

#==============================================================================
# Cleanup Handler
#==============================================================================

cleanup() {
  local exit_code=$?

  if [[ $exit_code -ne 0 ]]; then
    err "Script execution failed with exit code $exit_code"
  fi

  # Clean up process-specific temporary directory (safe)
  if [[ -n "${SBX_TMP_DIR:-}" && -d "$SBX_TMP_DIR" ]]; then
    # Verify it's a safe path before removal
    if [[ "$SBX_TMP_DIR" =~ ^/tmp/sbx-[a-zA-Z0-9._-]+$ ]]; then
      rm -rf "$SBX_TMP_DIR" 2>/dev/null || true
    fi
  fi

  # Clean up known temporary config files (specific to this process)
  rm -f "${SB_CONF}.tmp" 2>/dev/null || true

  # Clean up stale port lock files (over 60 minutes old, with safe timeout)
  # This is safe because it only removes very old locks that are likely orphaned
  if [[ -d "/var/lock" ]]; then
    find /var/lock -maxdepth 1 -name 'sbx-port-*.lock' -type f -mmin +"${CLEANUP_OLD_FILES_MIN:-60}" -delete 2>/dev/null || true
  fi

  # If we're in the middle of an upgrade/install and something fails,
  # try to restore service if it was previously running
  if [[ $exit_code -ne 0 && -f "$SB_SVC" ]]; then
    if systemctl is-enabled sing-box >/dev/null 2>&1; then
      systemctl start sing-box 2>/dev/null || true
    fi
  fi

  exit $exit_code
}

#==============================================================================
# Generation Functions
#==============================================================================

# Generate UUID with multiple fallback methods
generate_uuid() {
  # Method 1: Linux kernel UUID (most reliable on Linux)
  if [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
    return 0
  fi

  # Method 2: uuidgen command (available on most Unix systems)
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
    return 0
  fi

  # Method 3: Python (widely available)
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid; print(str(uuid.uuid4()))'
    return 0
  elif command -v python >/dev/null 2>&1; then
    python -c 'import uuid; print(str(uuid.uuid4()))'
    return 0
  fi

  # Method 4: OpenSSL with proper UUID v4 format
  # UUID v4 format: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  # where y is one of [8, 9, a, b] (variant bits: 10xx in binary)
  local hex variant_byte variant_value
  hex=$(openssl rand -hex 16) || return 1

  # Use cryptographically secure random for variant bits
  # Use bitwise AND to get last 2 bits (0-3), then add to 8 to get 8-11
  variant_byte=$(openssl rand -hex 1)
  # Extract lower 2 bits using bitwise AND, ensuring uniform distribution
  variant_value=$(( 8 + (0x${variant_byte} & 0x3) ))

  printf '%s-%s-4%s-%x%s-%s' \
    "${hex:0:8}" \
    "${hex:8:4}" \
    "${hex:13:3}" \
    "$variant_value" \
    "${hex:17:3}" \
    "${hex:20:12}"
}

# Generate Reality keypair with proper error handling
generate_reality_keypair() {
  local output
  output=$("$SB_BIN" generate reality-keypair 2>&1) || {
    err "Failed to generate Reality keypair: $output"
    return 1
  }

  # Extract and validate keys
  local priv pub
  priv=$(echo "$output" | grep "PrivateKey:" | awk '{print $2}')
  pub=$(echo "$output" | grep "PublicKey:" | awk '{print $2}')

  if [[ -z "$priv" || -z "$pub" ]]; then
    err "Failed to extract keys from Reality keypair output"
    return 1
  fi

  echo "$priv $pub"
  return 0
}

# Generate secure random hex string
generate_hex_string() {
  local length="${1:-16}"
  openssl rand -hex "$length"
}

# Generate ASCII QR code for URI (terminal display only)
generate_qr_code() {
  local uri="$1"
  local name="${2:-Config}"

  # Validate input
  if [[ -z "$uri" ]]; then
    return 1
  fi

  # Check if qrencode is available
  if ! have qrencode; then
    return 1
  fi

  # Check URI length (QR code capacity limitation)
  local uri_length=${#uri}
  if [[ $uri_length -gt 1500 ]]; then
    warn "URI is long ($uri_length chars), QR code may be dense"
  fi

  echo
  success "$name configuration QR code:"
  echo "┌─────────────────────────────────────┐"
  # Generate ASCII QR code for terminal display
  if qrencode -t UTF8 -m 0 "$uri" 2>/dev/null; then
    echo "└─────────────────────────────────────┘"
    info "Scan QR code to import config to client"
  else
    warn "QR code generation failed"
    return 1
  fi
  echo

  return 0
}

# Generate all QR codes for configured protocols
generate_all_qr_codes() {
  local uuid="$1"
  local domain="$2"
  local reality_port="$3"
  local public_key="$4"
  local short_id="$5"
  local sni="${6:-$SNI_DEFAULT}"

  # Optional parameters for WS-TLS and Hysteria2
  local ws_port="${7:-}"
  local hy2_port="${8:-}"
  local hy2_pass="${9:-}"

  # Reality QR code (always generated)
  local reality_uri="vless://${uuid}@${domain}:${reality_port}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${sni}&pbk=${public_key}&sid=${short_id}&type=tcp&fp=chrome#Reality-${domain}"
  generate_qr_code "$reality_uri" "Reality"

  # WS-TLS QR code (if configured)
  if [[ -n "$ws_port" ]]; then
    local ws_uri="vless://${uuid}@${domain}:${ws_port}?encryption=none&security=tls&type=ws&host=${domain}&path=/ws&sni=${domain}&fp=chrome#WS-TLS-${domain}"
    generate_qr_code "$ws_uri" "WS-TLS"
  fi

  # Hysteria2 QR code (if configured)
  if [[ -n "$hy2_port" && -n "$hy2_pass" ]]; then
    local hy2_uri="hysteria2://${hy2_pass}@${domain}:${hy2_port}/?sni=${domain}&alpn=h3&insecure=0#Hysteria2-${domain}"
    generate_qr_code "$hy2_uri" "Hysteria2"
  fi
}

#==============================================================================
# Module Initialization
#==============================================================================

# Initialize colors
_init_colors

# Setup cleanup trap (can be overridden by main script)
trap cleanup EXIT INT TERM

# Export functions for use in other modules
export -f msg warn err info success debug die need_root have safe_rm_temp
export -f log_json rotate_logs _log_timestamp _log_to_file _should_log
export -f generate_uuid generate_reality_keypair generate_hex_string
export -f generate_qr_code generate_all_qr_codes
