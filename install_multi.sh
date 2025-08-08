#!/usr/bin/env bash
# install_multi.sh  —  One-click official sing-box with:
# - VLESS-REALITY (required, no cert)
# - VLESS-WS-TLS (optional, needs cert)
# - Hysteria2 (optional, needs cert)
#
# Optional ACME via acme.sh:
#   CERT_MODE=cf_dns  (Cloudflare DNS-01; needs CF_Token [Zone.DNS:Edit + Zone:Read])
#   CERT_MODE=le_http (HTTP-01; needs :80 reachable & DNS only)
#
# Usage (install):
#   DOMAIN=r.example.com bash install_multi.sh
#   DOMAIN=r.example.com CERT_MODE=cf_dns CF_Token='xxx' bash install_multi.sh
#   DOMAIN=r.example.com CERT_MODE=cf_dns CERT_FORCE=1 CF_Token='xxx' bash install_multi.sh
#   DOMAIN=r.example.com CERT_FULLCHAIN=/path/fullchain.pem CERT_KEY=/path/privkey.pem bash install_multi.sh
#
# Usage (uninstall):
#   FORCE=1 bash install_multi.sh uninstall

set -euo pipefail

# Cleanup function for temporary files and error recovery
cleanup() {
  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    err "Script execution failed with exit code $exit_code"
  fi
  
  # Clean up temporary files (avoid globbing issues)
  rm -f "${SB_CONF}.tmp" 2>/dev/null || true
  find /tmp -maxdepth 1 -name 'sb*' -type f -mmin +10 -delete 2>/dev/null || true
  find /tmp -maxdepth 1 -name 'sing-box*' -type f -mmin +10 -delete 2>/dev/null || true
  
  # Clean up any acme temp files
  [[ -d "/tmp/.acme.sh" ]] && rm -rf "/tmp/.acme.sh" 2>/dev/null || true
  
  # If we're in the middle of an upgrade/install and something fails,
  # try to restore service if it was previously running
  if [[ $exit_code -ne 0 && -f "$SB_SVC" ]]; then
    if systemctl is-enabled sing-box >/dev/null 2>&1; then
      systemctl start sing-box 2>/dev/null || true
    fi
  fi
  
  exit $exit_code
}

# Enhanced error handling with cleanup
trap cleanup EXIT INT TERM

# ASCII Art Logo
show_logo() {
  clear
  echo
  echo -e "${BLUE}███████╗${CYAN}██████╗ ${PURPLE}██╗  ██╗    ${G}██╗     ${Y}██╗${R}████████╗${G}███████╗${N}"
  echo -e "${BLUE}██╔════╝${CYAN}██╔══██╗${PURPLE}╚██╗██╔╝    ${G}██║     ${Y}██║${R}╚══██╔══╝${G}██╔════╝${N}"
  echo -e "${BLUE}███████╗${CYAN}██████╔╝${PURPLE} ╚███╔╝ ${N}███╗${G}██║     ${Y}██║${R}   ██║   ${G}█████╗  ${N}"
  echo -e "${BLUE}╚════██║${CYAN}██╔══██╗${PURPLE} ██╔██╗ ${N}╚══╝${G}██║     ${Y}██║${R}   ██║   ${G}██╔══╝  ${N}"
  echo -e "${BLUE}███████║${CYAN}██████╔╝${PURPLE}██╔╝ ██╗    ${G}███████╗${Y}██║${R}   ██║   ${G}███████╗${N}"
  echo -e "${BLUE}╚══════╝${CYAN}╚═════╝ ${PURPLE}╚═╝  ╚═╝    ${G}╚══════╝${Y}╚═╝${R}   ╚═╝   ${G}╚══════╝${N}"
  echo
  echo -e "    ${B}${CYAN}🚀 Sing-Box Official One-Click Deployment Script${N}"
  echo -e "    ${Y}📦 Multi-Protocol: REALITY + WS-TLS + Hysteria2${N}"
  echo -e "    ${G}⚡ Version: Latest | Author: YYvanYang${N}"
  echo -e "${G}================================================================${N}"
  echo
}

SB_BIN="/usr/local/bin/sing-box"
SB_CONF_DIR="/etc/sing-box"
SB_CONF="$SB_CONF_DIR/config.json"
SB_SVC="/etc/systemd/system/sing-box.service"

DOMAIN="${DOMAIN:-}"
CERT_MODE="${CERT_MODE:-}"
CF_Token="${CF_Token:-}"
CF_Zone_ID="${CF_Zone_ID:-}"
CF_Account_ID="${CF_Account_ID:-}"
CERT_FORCE="${CERT_FORCE:-0}"

CERT_FULLCHAIN="${CERT_FULLCHAIN:-}"
CERT_KEY="${CERT_KEY:-}"

REALITY_PORT="${REALITY_PORT:-443}"
WS_PORT="${WS_PORT:-8444}"
HY2_PORT="${HY2_PORT:-8443}"

REALITY_PORT_FALLBACK=24443
WS_PORT_FALLBACK=24444
HY2_PORT_FALLBACK=24445

SNI_DEFAULT="${SNI_DEFAULT:-www.microsoft.com}"
CERT_DIR_BASE="${CERT_DIR_BASE:-/etc/ssl/sbx}"
SINGBOX_VERSION="${SINGBOX_VERSION:-}"
LOG_LEVEL="${LOG_LEVEL:-warn}"

# Color definitions - safe fallback approach
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

msg(){ echo "${G}[*]${N} $*"; }
warn(){ echo "${Y}[!]${N} $*" >&2; }
err(){ echo "${R}[ERR]${N} $*" >&2; }
info(){ echo "${BLUE}[INFO]${N} $*"; }
success(){ echo "${G}[✓]${N} $*"; }
die(){ err "$*"; exit 1; }
need_root(){ [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root (sudo)."; }
have(){ command -v "$1" >/dev/null 2>&1; }

# Safe temporary directory cleanup
safe_rm_temp() {
  local temp_path="$1"
  [[ -n "$temp_path" && "$temp_path" != "/" && "$temp_path" =~ ^/tmp/ ]] || return 1
  [[ -d "$temp_path" ]] && rm -rf "$temp_path" 2>/dev/null || true
}

# Auto-detect server public IP for Reality-only mode
get_public_ip() {
  local ip="" service
  local services=("https://ipv4.icanhazip.com" "https://api.ipify.org" "https://ifconfig.me/ip" "https://ipinfo.io/ip")
  
  # Try multiple IP detection services for redundancy
  for service in "${services[@]}"; do
    if have curl; then
      ip=$(timeout 5 curl -s --max-time 5 "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1)
    elif have wget; then
      ip=$(timeout 5 wget -qO- --timeout=5 "$service" 2>/dev/null | grep -E '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$' | head -1)
    else
      break
    fi
    
    # Validate the detected IP more thoroughly
    if [[ -n "$ip" ]] && validate_ip_address "$ip"; then
      echo "$ip"
      return 0
    fi
  done
  
  return 1
}

# Enhanced IP address validation
validate_ip_address() {
  local ip="$1"
  # Basic format check
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1
  
  # Check each octet is in valid range (0-255)
  local IFS='.'
  local -a octets=($ip)
  for octet in "${octets[@]}"; do
    # Remove leading zeros and check range
    octet=$((10#$octet))
    [[ $octet -le 255 ]] || return 1
  done
  
  # Check for reserved/invalid ranges (but allow private IPs for VPS environments)
  [[ ! "$ip" =~ ^0\. ]] || return 1        # 0.x.x.x
  [[ ! "$ip" =~ ^127\. ]] || return 1      # 127.x.x.x (loopback) 
  [[ ! "$ip" =~ ^169\.254\. ]] || return 1 # 169.254.x.x (link-local)
  [[ ! "$ip" =~ ^22[4-9]\. ]] || return 1  # 224.x.x.x+ (multicast)
  [[ ! "$ip" =~ ^2[4-5][0-9]\. ]] || return 1 # 240.x.x.x+ (reserved)
  
  return 0
}

port_in_use() {
  local p="$1"
  ss -lntp 2>/dev/null | grep -q ":$p " && return 0
  lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p" && return 0
  return 1
}

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
  # where y is one of [8, 9, a, b]
  local hex=$(openssl rand -hex 16)
  printf '%s-%s-4%s-%x%s-%s' \
    "${hex:0:8}" \
    "${hex:8:4}" \
    "${hex:13:3}" \
    $(( 8 + RANDOM % 4 )) \
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

# Generate ASCII QR codes for all protocol URIs
generate_all_qr_codes() {
  local domain="$1"
  local reality_port="$2"
  local ws_port="$3" 
  local hy2_port="$4"
  local uuid="$5"
  local pub_key="$6"
  local short_id="$7"
  local hy2_pass="$8"
  local cert_available="${9:-false}"
  
  # Check if qrencode is available
  if ! have qrencode; then
    info "qrencode not installed, skipping QR code generation"
    return 1
  fi
  
  info "Generating configuration QR codes..."
  
  # Always generate Reality QR code
  if [[ -n "$domain" && -n "$reality_port" && -n "$uuid" && -n "$pub_key" && -n "$short_id" ]]; then
    local reality_uri="vless://${uuid}@${domain}:${reality_port}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI_DEFAULT}&pbk=${pub_key}&sid=${short_id}&type=tcp&fp=chrome#Reality-${domain}"
    generate_qr_code "$reality_uri" "VLESS-Reality"
  fi
  
  # Generate certificate-based protocol QR codes if available
  if [[ "$cert_available" == "true" && -n "$domain" && -n "$uuid" && -n "$hy2_pass" ]]; then
    # WS-TLS QR code
    if [[ -n "$ws_port" ]]; then
      local ws_uri="vless://${uuid}@${domain}:${ws_port}?encryption=none&security=tls&type=ws&host=${domain}&path=/ws&sni=${domain}&fp=chrome#WS-TLS-${domain}"
      generate_qr_code "$ws_uri" "VLESS-WS-TLS"
    fi
    
    # Hysteria2 QR code
    if [[ -n "$hy2_port" ]]; then
      local hy2_uri="hysteria2://${hy2_pass}@${domain}:${hy2_port}/?sni=${domain}&alpn=h3&insecure=0#Hysteria2-${domain}"
      generate_qr_code "$hy2_uri" "Hysteria2"
    fi
  fi
}

# Detect IPv6 support on the server
detect_ipv6_support() {
  local ipv6_supported=false
  
  # Check 1: Kernel IPv6 support
  if [[ -f /proc/net/if_inet6 ]]; then
    # Check 2: IPv6 routing table
    if ip -6 route show 2>/dev/null | grep -q "default\|::/0"; then
      # Check 3: Actual connectivity test to a reliable IPv6 DNS server
      if timeout 3 ping6 -c 1 -W 2 2001:4860:4860::8888 >/dev/null 2>&1; then
        ipv6_supported=true
      else
        # Fallback test: check if we can create IPv6 socket
        if timeout 3 bash -c 'exec 3<>/dev/tcp/[::1]/22' 2>/dev/null; then
          exec 3<&-
          exec 3>&-
          ipv6_supported=true
        fi
      fi
    fi
  fi
  
  echo "$ipv6_supported"
}

# Choose optimal listen address based on network stack support
choose_listen_address() {
  local ipv6_supported="$1"
  
  if [[ "$ipv6_supported" == "true" ]]; then
    echo "::"  # Dual-stack mode: supports both IPv4 and IPv6
  else
    echo "0.0.0.0"  # IPv4-only mode
  fi
}

# Validate Reality destination connectivity
validate_reality_dest() {
  local sni="$1"
  local ipv6_supported="$2"
  
  msg "Testing connectivity to Reality destination: $sni"
  
  # Test IPv4 connection (always required)
  if ! timeout 5 bash -c "echo '' | openssl s_client -connect $sni:443 -servername $sni" >/dev/null 2>&1; then
    warn "IPv4 connection to $sni failed, may affect Reality handshake"
    return 1
  fi
  
  # Test IPv6 connection if supported
  if [[ "$ipv6_supported" == "true" ]]; then
    if ! timeout 5 bash -c "echo '' | openssl s_client -connect [$sni]:443 -servername $sni" >/dev/null 2>&1; then
      warn "IPv6 connection to $sni failed, but IPv4 works"
    else
      success "Both IPv4 and IPv6 connectivity to $sni verified"
      return 0
    fi
  fi
  
  success "IPv4 connectivity to Reality destination $sni verified"
  return 0
}

# Load and optionally reuse previous configuration
load_previous_config() {
  local config_file="/etc/sing-box/client-info.txt"
  
  if [[ ! -f "$config_file" ]]; then
    msg "No previous configuration found, will create new configuration"
    return 0
  fi
  
  # Validate config file is readable and not empty
  if [[ ! -r "$config_file" ]]; then
    warn "Previous configuration file exists but is not readable"
    return 1
  fi
  
  if [[ ! -s "$config_file" ]]; then
    warn "Previous configuration file is empty"
    return 1
  fi
  
  msg "Previous configuration detected"
  echo ""
  
  # Load previous config safely (avoid code injection)
  
  # Parse config file safely line by line
  local line_count=0
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    ((line_count++))
    
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    
    # Basic validation of key format
    if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      warn "Invalid key format on line $line_count: '$key'"
      continue
    fi
    
    # Sanitize value by removing dangerous characters
    value=$(echo "$value" | tr -d ';|&$`"'"'"'()[]{}*?<>' | head -c 256)
    
    # Assign to appropriate variables
    case "$key" in
      DOMAIN) DOMAIN="$value" ;;
      REALITY_PORT) [[ "$value" =~ ^[0-9]+$ ]] && REALITY_PORT="$value" ;;
      WS_PORT) [[ "$value" =~ ^[0-9]+$ ]] && WS_PORT="$value" ;;
      HY2_PORT) [[ "$value" =~ ^[0-9]+$ ]] && HY2_PORT="$value" ;;
      CERT_FULLCHAIN) CERT_FULLCHAIN="$value" ;;
      CERT_KEY) CERT_KEY="$value" ;;
      SNI) SNI="$value" ;;
      UUID) [[ "$value" =~ ^[a-fA-F0-9-]{36}$ ]] && UUID="$value" ;;
      PUB) PUB="$value" ;;
      PRIV) PRIV="$value" ;;
      SID) [[ "$value" =~ ^[a-fA-F0-9]{1,8}$ ]] && SID="$value" ;;
      HY2_PASS) HY2_PASS="$value" ;;
      *) warn "Unknown configuration key: '$key'" ;;
    esac
  done < "$config_file"
  
  # Validate that we read at least some configuration
  if [[ $line_count -eq 0 ]]; then
    warn "Configuration file appears to be empty or unreadable"
    return 1
  fi
  
  # Show previous configuration summary
  echo -e "${CYAN}Previous Configuration Summary:${N}"
  echo "  Domain/IP     : ${DOMAIN:-<not set>}"
  echo "  Reality Port  : ${REALITY_PORT:-443}"
  echo "  WebSocket Port: ${WS_PORT:-8444}"
  echo "  Hysteria2 Port: ${HY2_PORT:-8443}"
  echo "  SNI           : ${SNI:-www.microsoft.com}"
  echo "  Certificates  : $(if [[ -n "$CERT_FULLCHAIN" ]]; then echo "Yes ($CERT_FULLCHAIN)"; else echo "No (Reality-only)"; fi)"
  echo ""
  
  # Ask user preference
  echo -e "${Y}Reconfiguration Options:${N}"
  echo "1) Use previous configuration as base (modify specific settings)"
  echo "2) Start fresh configuration (ignore previous settings)"
  echo ""
  
  set +e  # Temporarily disable strict mode for user input
  while true; do
    read -rp "Choose option [1-2]: " config_choice
    case "$config_choice" in
      1)
        msg "Using previous configuration as base..."
        # Export previous values as defaults (prefixed with PREV_)
        export PREV_DOMAIN="$DOMAIN"
        export PREV_REALITY_PORT="$REALITY_PORT"
        export PREV_WS_PORT="$WS_PORT" 
        export PREV_HY2_PORT="$HY2_PORT"
        export PREV_CERT_FULLCHAIN="$CERT_FULLCHAIN"
        export PREV_CERT_KEY="$CERT_KEY"
        export PREV_SNI="$SNI"
        export USE_PREVIOUS_CONFIG=1
        break
        ;;
      2)
        msg "Starting fresh configuration..."
        export USE_PREVIOUS_CONFIG=0
        break
        ;;
      *)
        warn "Please enter 1 or 2"
        ;;
    esac
  done
  set -e  # Re-enable strict mode
  
  echo ""
}

allocate_port() {
  local port="$1" fallback="$2" name="$3"
  local retry_count=0
  local max_retries=3
  
  # First try the preferred port with retries
  while [[ $retry_count -lt $max_retries ]]; do
    if ! port_in_use "$port"; then
      echo "$port"
      return 0
    fi
    if [[ $retry_count -eq 0 ]]; then
      msg "$name port $port in use, retrying in 2 seconds..." >&2
    fi
    sleep 2
    ((retry_count++))
  done
  
  # Try fallback port
  if ! port_in_use "$fallback"; then
    warn "$name port $port persistently in use; switching to $fallback" >&2
    echo "$fallback"
  else
    die "Both $name ports $port and $fallback are in use. Please free up these ports or specify different ones."
  fi
}

# Enhanced input validation functions
validate_port() {
  local port="$1"
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$port" -le 65535 ] && [ "$port" -ge 1 ]
}

validate_domain() {
  local domain="$1"
  # Enhanced domain validation
  [[ -n "$domain" ]] || return 1
  # Check length (max 253 characters for FQDN)
  [[ ${#domain} -le 253 ]] || return 1
  # Check for valid domain format (letters, numbers, dots, hyphens only)
  [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  # Must not start or end with hyphen or dot
  [[ ! "$domain" =~ ^[-.]|[-.]$ ]] || return 1
  # Must not contain consecutive dots
  [[ ! "$domain" =~ \.\. ]] || return 1
  # Reserved names
  [[ "$domain" != "localhost" ]] || return 1
  [[ "$domain" != "127.0.0.1" ]] || return 1
  [[ ! "$domain" =~ ^[0-9.]+$ ]] || return 1  # Not an IP address
  return 0
}

validate_cert_files() {
  local fullchain="$1" key="$2"
  # Enhanced certificate file validation
  [[ -n "$fullchain" && -n "$key" ]] || return 1
  [[ -f "$fullchain" && -f "$key" ]] || return 1
  [[ -r "$fullchain" && -r "$key" ]] || return 1
  # Check if files are not empty
  [[ -s "$fullchain" && -s "$key" ]] || return 1
  return 0
}

# Enhanced input sanitization
sanitize_input() {
  local input="$1"
  # Remove potential dangerous characters and limit length
  input="${input//[;&|\`\$()]/}"  # Remove shell metacharacters
  input="${input:0:256}"        # Limit length
  printf '%s' "$input"
}

# Validate environment variables on startup
validate_env_vars() {
  # Validate DOMAIN if provided
  if [[ -n "$DOMAIN" ]]; then
    validate_domain "$DOMAIN" || die "Invalid DOMAIN format: $DOMAIN"
  fi
  
  # Validate ports if overridden
  if [[ -n "${REALITY_PORT:-}" ]]; then
    validate_port "$REALITY_PORT" || die "Invalid REALITY_PORT: $REALITY_PORT"
  fi
  if [[ -n "${WS_PORT:-}" ]]; then
    validate_port "$WS_PORT" || die "Invalid WS_PORT: $WS_PORT"
  fi
  if [[ -n "${HY2_PORT:-}" ]]; then
    validate_port "$HY2_PORT" || die "Invalid HY2_PORT: $HY2_PORT"
  fi
  
  # Validate certificate files if provided
  if [[ -n "$CERT_FULLCHAIN" || -n "$CERT_KEY" ]]; then
    validate_cert_files "$CERT_FULLCHAIN" "$CERT_KEY" || die "Invalid certificate files"
  fi
  
  # Validate CERT_MODE
  if [[ -n "$CERT_MODE" && ! "$CERT_MODE" =~ ^(cf_dns|le_http)$ ]]; then
    die "Invalid CERT_MODE: $CERT_MODE (must be cf_dns or le_http)"
  fi
}

get_installed_version() {
  if [[ -x "$SB_BIN" ]]; then
    "$SB_BIN" version 2>/dev/null | grep -o 'sing-box version [0-9.]*' | cut -d' ' -f3 || echo "unknown"
  else
    echo "not_installed"
  fi
}

# Enhanced network operation with better error handling
safe_http_get() {
  local url="$1" timeout="${2:-30}" max_retries="${3:-3}"
  local retry=0 output
  
  while [[ $retry -lt $max_retries ]]; do
    if have curl; then
      if output=$(curl -fsSL "$url" --max-time "$timeout" --retry 2 --connect-timeout 10 2>/dev/null); then
        printf '%s' "$output"
        return 0
      fi
    elif have wget; then
      if output=$(wget -qO- "$url" --timeout="$timeout" --tries=2 --connect-timeout=10 2>/dev/null); then
        printf '%s' "$output"
        return 0
      fi
    else
      die "Neither curl nor wget available for network operations"
    fi
    
    ((retry++))
    if [[ $retry -lt $max_retries ]]; then
      warn "Network request failed (attempt $retry/$max_retries), retrying in 2 seconds..."
      sleep 2
    fi
  done
  
  return 1
}

get_latest_version() {
  local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local result
  
  if result=$(safe_http_get "$api_url" 15 2); then
    echo "$result" | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 | sed 's/^v//' || echo "unknown"
  else
    warn "Failed to fetch latest version information"
    echo "unknown"
  fi
}

compare_versions() {
  local current="$1" latest="$2"
  if [[ "$current" = "unknown" || "$latest" = "unknown" ]]; then
    echo "unknown"
    return
  fi
  
  # Check for very old versions that might be incompatible
  if [[ "$current" =~ ^0\.|^1\.[0-9]\..*|^1\.1[01]\..*$ ]]; then
    echo "unsupported"
    return
  fi
  
  # Simple version comparison (works for semantic versioning)
  if [[ "$current" = "$latest" ]]; then
    echo "current"
  else
    local oldest
    oldest=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | head -1)
    if [[ "$oldest" = "$current" ]]; then
      echo "outdated"
    else
      echo "newer"
    fi
  fi
}

check_service_status() {
  if systemctl is-enabled sing-box >/dev/null 2>&1; then
    if systemctl is-active sing-box >/dev/null 2>&1; then
      echo "running"
    else
      echo "stopped"
    fi
  else
    echo "disabled"
  fi
}


check_existing_installation() {
  local current_version service_status latest_version version_status
  current_version="$(get_installed_version)"
  service_status="$(check_service_status)"
  
  if [[ "$current_version" != "not_installed" || -f "$SB_CONF" || -f "$SB_SVC" ]]; then
    echo
    warn "Existing sing-box installation detected:"
    info "Binary: $SB_BIN (version: $current_version)"
    [[ -f "$SB_CONF" ]] && info "Config: $SB_CONF"
    [[ -f "$SB_SVC" ]] && info "Service: $SB_SVC (status: $service_status)"
    
    # Check for updates if binary exists
    if [[ "$current_version" != "not_installed" && "$current_version" != "unknown" ]]; then
      msg "Checking for updates..."
      latest_version="$(get_latest_version)"
      version_status="$(compare_versions "$current_version" "$latest_version")"
      
      case "$version_status" in
        "current")
          success "You have the latest version ($current_version)"
          ;;
        "outdated")
          warn "Update available: $current_version → $latest_version"
          ;;
        "unsupported")
          err "Your version ($current_version) is too old and may not be compatible with this script"
          warn "Strongly recommend upgrading to the latest version ($latest_version)"
          ;;
        "newer")
          info "You have a newer version than latest release ($current_version > $latest_version)"
          ;;
        *)
          info "Version status: unknown"
          ;;
      esac
    fi
    
    echo
    echo -e "${CYAN}Available options:${N}"
    echo -e "1) ${G}Fresh install${N} (backup existing config, clean install)"
    echo -e "2) ${Y}Upgrade binary only${N} (keep existing config)"
    echo -e "3) ${Y}Reconfigure${N} (keep binary, regenerate config)"
    echo -e "4) ${R}Complete uninstall${N} (remove everything)"
    echo -e "5) ${BLUE}Show current config${N} (view and exit)"
    echo "6) Exit"
    
    set +e
    while true; do
      read -rp "Choose [1-6]: " choice
      # Validate input to prevent injection
      if [[ ! "$choice" =~ ^[1-6]$ ]]; then
        err "Invalid choice. Please select 1-6."
        continue
      fi
      case "${choice}" in
        1)
          msg "Proceeding with fresh installation..."
          # Stop service first to free up ports
          if systemctl is-active sing-box >/dev/null 2>&1; then
            msg "Stopping existing sing-box service..."
            systemctl stop sing-box
            # Wait for ports to be released
            local count=0
            while systemctl is-active sing-box >/dev/null 2>&1 && [[ $count -lt 10 ]]; do
              sleep 1
              ((count++))
            done
            if [[ $count -ge 10 ]]; then
              warn "Service took longer than expected to stop, continuing anyway..."
            else
              msg "Service stopped successfully"
            fi
          fi
          # Backup existing config
          if [[ -f "$SB_CONF" ]]; then
            local backup_file="${SB_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
            msg "Backing up existing config to: $backup_file"
            cp "$SB_CONF" "$backup_file"
          fi
          break
          ;;
        2)
          msg "Upgrading binary only, preserving configuration..."
          # Skip config generation in install flow
          export SKIP_CONFIG_GEN=1
          break
          ;;
        3)
          msg "Keeping binary, will regenerate configuration..."
          # Stop the service before regenerating config to free up ports
          if systemctl is-active sing-box >/dev/null 2>&1; then
            msg "Stopping sing-box service to free up ports..."
            systemctl stop sing-box || warn "Failed to stop service, ports may be in use"
            sleep 2  # Give service time to fully stop
          fi
          
          # Load previous configuration for reference
          load_previous_config
          
          export SKIP_BINARY_DOWNLOAD=1
          break
          ;;
        4)
          warn "This will completely remove sing-box and all configurations"
          read -rp "Are you sure? [y/N]: " confirm
          if [[ "${confirm:-N}" =~ ^[Yy]$ ]]; then
            uninstall_flow
            exit 0
          else
            warn "Uninstall cancelled"
          fi
          ;;
        5)
          if [[ -f "$SB_CONF" ]]; then
            echo
            info "Current configuration:"
            echo "----------------------------------------"
            cat "$SB_CONF"
            echo "----------------------------------------"
          else
            warn "No configuration file found"
          fi
          echo
          read -rp "Press Enter to continue with installation options..."
          ;;
        6)
          echo "Installation cancelled."
          exit 0
          ;;
      esac
    done
    set -e
    echo
  fi
}

ensure_tools() {
  msg "Installing essential tools (curl/wget, tar, jq, openssl, ca-certificates, lsof)..."
  
  # Install essential tools first
  if have apt-get; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar jq openssl ca-certificates lsof
  elif have dnf; then
    dnf install -y curl wget tar jq openssl ca-certificates lsof
  elif have yum; then
    yum install -y curl wget tar jq openssl ca-certificates lsof
  else
    warn "Unknown package manager; please ensure curl/wget, tar, jq, openssl, lsof are installed."
  fi
  
  # Try to install qrencode separately (optional for QR code generation)
  msg "Attempting to install qrencode for QR code generation (optional)..."
  local qrencode_installed=false
  
  if have apt-get; then
    if DEBIAN_FRONTEND=noninteractive apt-get install -y qrencode 2>/dev/null; then
      qrencode_installed=true
    fi
  elif have dnf; then
    if dnf install -y qrencode 2>/dev/null; then
      qrencode_installed=true
    elif dnf install -y epel-release 2>/dev/null && \
         dnf config-manager --set-enabled epel 2>/dev/null && \
         dnf install -y qrencode 2>/dev/null; then
      qrencode_installed=true
    fi
  elif have yum; then
    if yum install -y qrencode 2>/dev/null; then
      qrencode_installed=true
    elif yum install -y epel-release 2>/dev/null && \
         yum-config-manager --enable epel 2>/dev/null && \
         yum install -y qrencode 2>/dev/null; then
      qrencode_installed=true
    fi
  fi
  
  if [[ "$qrencode_installed" == "true" ]]; then
    success "qrencode installed successfully - QR code generation available"
  else
    warn "qrencode installation failed - QR code generation will be skipped"
    info "You can install qrencode later manually: dnf install epel-release && dnf config-manager --set-enabled epel && dnf install qrencode"
  fi
}

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)  echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *) die "Unsupported arch: $(uname -m)" ;;
  esac
}

build_asset_url_fallback() {
  local tag="$1" arch="$2"
  local ver="${tag#v}"
  echo "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${ver}-${arch}.tar.gz"
}

get_asset_sha256() {
  local raw="$1" arch="$2"
  printf '%s' "$raw" | jq -r --arg a "$arch" '.assets[]? | select(.name|test($a) and endswith(".tar.gz")) | .digest' | head -1 | cut -d: -f2
}

verify_sha256() {
  local file="$1" expected="$2"
  local actual
  actual="$(sha256sum "$file" | cut -d' ' -f1)"
  [[ "$actual" = "$expected" ]] || die "SHA256 verification failed: expected $expected, got $actual"
}

download_singbox() {
  # Skip download if requested (for reconfigure option)
  if [[ "${SKIP_BINARY_DOWNLOAD:-0}" = "1" ]]; then
    if [[ -x "$SB_BIN" ]]; then
      success "Using existing sing-box binary at $SB_BIN"
      return
    else
      warn "SKIP_BINARY_DOWNLOAD set but no binary found, proceeding with download"
    fi
  fi
  
  if [[ -x "$SB_BIN" ]]; then
    success "sing-box exists at $SB_BIN (will be upgraded)"
  fi
  local arch tmp api url tag raw
  arch="$(detect_arch)"
  tmp="$(mktemp -d)" || die "Failed to create secure temporary directory"
  chmod 700 "$tmp" || { safe_rm_temp "$tmp"; die "Failed to set secure permissions on temporary directory"; }

  if [[ -n "$SINGBOX_VERSION" ]]; then
    tag="$SINGBOX_VERSION"
    api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"
  else
    api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  fi

  msg "Fetching sing-box release info for $arch ..."
  raw=$(safe_http_get "$api" 30 3) || { safe_rm_temp "$tmp"; die "Failed to query GitHub API after multiple attempts"; }
  [[ -n "${raw:-}" ]] || { safe_rm_temp "$tmp"; die "Empty response from GitHub API"; }

  if [[ -z "$SINGBOX_VERSION" ]]; then
    tag="$(printf '%s' "$raw" | jq -r .tag_name)"
  fi

  url="$(printf '%s' "$raw" | jq -r --arg a "$arch" '.assets[]? | select(.name|test($a) and endswith(".tar.gz")) | .browser_download_url' | head -1)"
  local expected_sha256
  expected_sha256="$(get_asset_sha256 "$raw" "$arch")"
  
  if [[ -z "$url" || "$url" == "null" ]]; then
    warn "Asset not found in API; falling back to guessed URL pattern."
    url="$(build_asset_url_fallback "$tag" "$arch")"
    expected_sha256=""
  fi

  msg "Downloading sing-box package (${tag:-unknown}) ..."
  local pkg="$tmp/sb.tgz"
  
  # Enhanced download with progress indication for large files
  local download_success=false
  local retry=0
  local max_download_retries=3
  
  while [[ $retry -lt $max_download_retries && "$download_success" == "false" ]]; do
    if have curl; then
      if curl -fsSL "$url" -o "$pkg" --max-time 300 --retry 2 --connect-timeout 30 --progress-bar 2>/dev/null; then
        download_success=true
      fi
    elif have wget; then
      if wget -qO "$pkg" "$url" --timeout=300 --tries=2 --connect-timeout=30 --progress=dot 2>/dev/null; then
        download_success=true
      fi
    else
      { safe_rm_temp "$tmp"; die "Neither curl nor wget available for download"; }
    fi
    
    if [[ "$download_success" == "false" ]]; then
      ((retry++))
      if [[ $retry -lt $max_download_retries ]]; then
        warn "Download failed (attempt $retry/$max_download_retries), retrying..."
        sleep 3
        rm -f "$pkg" 2>/dev/null || true
      fi
    fi
  done
  
  [[ "$download_success" == "true" ]] || { safe_rm_temp "$tmp"; die "Failed to download package after $max_download_retries attempts"; }
  
  if [[ -n "$expected_sha256" ]]; then
    msg "Verifying download integrity..."
    verify_sha256 "$pkg" "$expected_sha256"
  else
    warn "SHA256 verification skipped (fallback URL used)"
  fi

  tar -xzf "$pkg" -C "$tmp"

  local bin
  bin="$(find "$tmp" -type f -name 'sing-box' | head -1)"
  [[ -n "$bin" ]] || { safe_rm_temp "$tmp"; die "sing-box binary not found in package"; }
  install -m 0755 "$bin" "$SB_BIN"
  
  safe_rm_temp "$tmp"
  success "Installed sing-box -> $SB_BIN"
}

acme_install() {
  [[ -x "$HOME/.acme.sh/acme.sh" ]] && return
  msg "Installing acme.sh ..."
  
  # Use a default email for ACME installation
  local email="admin@yourdomain.com"
  
  if have curl; then
    curl -fsSL https://get.acme.sh | sh -s "email=${email}" >/dev/null
  else
    wget -qO- https://get.acme.sh | sh -s "email=${email}" >/dev/null
  fi
  # shellcheck disable=SC1091
  . "$HOME/.acme.sh/acme.sh.env"
}

acme_issue_cf_dns() {
  [[ -n "$CF_Token" ]] || die "CF_Token is required for CERT_MODE=cf_dns"
  export CF_Token CF_Zone_ID CF_Account_ID
  local ac="$HOME/.acme.sh/acme.sh"
  local force=()
  [[ "$CERT_FORCE" = "1" ]] && force+=(--force)

  set +e
  local out
  out="$("$ac" --issue -d "$DOMAIN" --dns dns_cf -k ec-256 --server letsencrypt "${force[@]}" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$out" | grep -qiE 'Skipping|Domains not changed|Next renewal time'; then
      warn "ACME says not due for renewal; will reuse existing order."
    else
      err "ACME issue failed"; echo "$out" >&2; die "ACME failed"
    fi
  fi

  local dir="$CERT_DIR_BASE/$DOMAIN"
  mkdir -p "$dir"
  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem"
  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"
  
  # Set secure permissions for certificate files
  chmod 600 "$CERT_FULLCHAIN" "$CERT_KEY"
  chown root:root "$CERT_FULLCHAIN" "$CERT_KEY"
  
  # Clear CF variables from environment
  unset CF_Token CF_Zone_ID CF_Account_ID
}

acme_issue_le_http() {
  port_in_use 80 && die ":80 is in use; stop it or use CERT_MODE=cf_dns"
  local ac="$HOME/.acme.sh/acme.sh"
  local force=()
  [[ "$CERT_FORCE" = "1" ]] && force+=(--force)

  set +e
  local out
  out="$("$ac" --issue -d "$DOMAIN" --standalone -k ec-256 --server letsencrypt "${force[@]}" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -ne 0 ]]; then
    if echo "$out" | grep -qiE 'Skipping|Domains not changed|Next renewal time'; then
      warn "ACME says not due for renewal; will reuse existing order."
    else
      err "ACME issue failed"; echo "$out" >&2; die "ACME failed"
    fi
  fi

  local dir="$CERT_DIR_BASE/$DOMAIN"
  mkdir -p "$dir"
  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem"
  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"
  
  # Set secure permissions for certificate files
  chmod 600 "$CERT_FULLCHAIN" "$CERT_KEY"
  chown root:root "$CERT_FULLCHAIN" "$CERT_KEY"
}

maybe_issue_cert() {
  [[ -n "$CERT_MODE" ]] || return 0
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    msg "Using provided certificate paths."
    return 0
  fi
  acme_install
  case "$CERT_MODE" in
    cf_dns)  acme_issue_cf_dns ;;
    le_http) acme_issue_le_http ;;
    *) die "Unknown CERT_MODE: $CERT_MODE (cf_dns|le_http)" ;;
  esac
  success "Certificate installed: $CERT_FULLCHAIN"
}

UUID=""
PRIV=""
PUB=""
SID=""
HY2_PASS=""
REALITY_PORT_CHOSEN=""
WS_PORT_CHOSEN=""
HY2_PORT_CHOSEN=""
REALITY_ONLY_MODE=0

gen_materials() {
  # Apply previous configuration if selected
  if [[ "${USE_PREVIOUS_CONFIG:-0}" = "1" ]]; then
    msg "Applying previous configuration defaults..."
    
    # Apply previous configuration values as defaults
    REALITY_PORT="${PREV_REALITY_PORT:-$REALITY_PORT}"
    WS_PORT="${PREV_WS_PORT:-$WS_PORT}"
    HY2_PORT="${PREV_HY2_PORT:-$HY2_PORT}"
    
    # Apply certificate configuration if available
    [[ -n "${PREV_CERT_FULLCHAIN:-}" ]] && CERT_FULLCHAIN="$PREV_CERT_FULLCHAIN"
    [[ -n "${PREV_CERT_KEY:-}" ]] && CERT_KEY="$PREV_CERT_KEY"
    
    # Apply SNI configuration
    [[ -n "${PREV_SNI:-}" ]] && SNI_DEFAULT="$PREV_SNI"
    
    # Show applied configuration summary
    msg "  Previous ports: Reality=$REALITY_PORT, WebSocket=$WS_PORT, Hysteria2=$HY2_PORT"
    if [[ -n "$CERT_FULLCHAIN" ]]; then
      msg "  Previous certificates: Yes ($CERT_FULLCHAIN)"
    else
      msg "  Previous certificates: No (Reality-only mode)"
    fi
  fi
  
  if [[ -z "$DOMAIN" ]]; then
    set +e  # Temporarily disable strict mode for user input
    echo "========================================"
    echo "Server Address Configuration"
    echo "========================================"
    
    # Show previous configuration if available
    if [[ "${USE_PREVIOUS_CONFIG:-0}" = "1" && -n "$PREV_DOMAIN" ]]; then
      echo -e "${CYAN}Previous Domain/IP: $PREV_DOMAIN${N}"
      echo "Options:"
      echo "  1. Press Enter to keep previous domain/IP"
      echo "  2. Enter new domain name for full setup"
      echo "  3. Enter new IP address for Reality-only"
      echo "  4. Leave empty for auto-detect IP (Reality-only)"
    else
      echo "Options:"
      echo "  1. Press Enter for Reality-only (auto-detect IP)"
      echo "  2. Enter domain name for full setup (Reality + WS-TLS + Hysteria2)"
      echo "  3. Enter IP address manually for Reality-only"
    fi
    
    echo ""
    echo "Note: Domain must be 'DNS only' (gray cloud) in Cloudflare"
    
    local input_attempts=0
    while true; do
      if [[ "${USE_PREVIOUS_CONFIG:-0}" = "1" && -n "$PREV_DOMAIN" ]]; then
        read -rp "Domain/IP [${PREV_DOMAIN}]: " DOMAIN
        # Use previous domain if user just pressed Enter
        DOMAIN="${DOMAIN:-$PREV_DOMAIN}"
      else
        read -rp "Domain/IP (Enter for auto-detect): " DOMAIN
      fi
      
      # Sanitize input to prevent injection
      DOMAIN=$(sanitize_input "$DOMAIN")
      
      if [[ -z "$DOMAIN" ]]; then
        # Auto-detect IP for Reality-only mode
        msg "No domain provided. Auto-detecting server IP for Reality-only mode..."
        local detected_ip
        if detected_ip=$(get_public_ip); then
          DOMAIN="$detected_ip"
          success "Detected server IP: $DOMAIN"
          info "Using Reality-only mode (no certificates needed)"
          REALITY_ONLY_MODE=1
          break
        else
          err "Failed to auto-detect server IP. Please enter manually."
          continue
        fi
      elif validate_ip_address "$DOMAIN"; then
        # User entered a valid IP address
        success "Using IP address: $DOMAIN for Reality-only mode"
        REALITY_ONLY_MODE=1
        break
      elif validate_domain "$DOMAIN"; then
        success "Domain '$DOMAIN' is valid"
        info "Full setup mode available (can add WS-TLS and Hysteria2 with certificates)"
        REALITY_ONLY_MODE=0
        break
      else
        err "Invalid format. Please enter a valid domain or IP address"
        ((input_attempts++))
        if [[ $input_attempts -ge 5 ]]; then
          die "Too many invalid attempts. Please check your input and try again."
        fi
      fi
    done
    set -e  # Re-enable strict mode
  else
    # DOMAIN was provided via environment variable
    if validate_ip_address "$DOMAIN"; then
      info "Using provided IP address: $DOMAIN for Reality-only mode"
      REALITY_ONLY_MODE=1
    else
      info "Using provided domain: $DOMAIN"
      REALITY_ONLY_MODE=0
    fi
  fi

  msg "Generating security credentials..."
  
  # Step 1: Generate Reality keypair
  msg "  - Generating Reality keypair..."
  local keypair
  keypair=$(generate_reality_keypair) || die "Failed to generate Reality keypair"
  read PRIV PUB <<< "$keypair"
  success "  ✓ Reality keypair generated"
  
  # Step 2: Generate UUID
  msg "  - Generating UUID..."
  UUID="$(generate_uuid)"
  [[ -n "$UUID" ]] || die "Failed to generate UUID"
  success "  ✓ UUID: ${UUID:0:8}..."
  
  # Step 3: Generate short ID (8 hex chars for sing-box)
  msg "  - Generating short ID..."
  SID="$(generate_hex_string 4)"  # 4 bytes = 8 hex chars
  [[ -n "$SID" && ${#SID} -eq 8 ]] || die "Failed to generate valid short ID"
  success "  ✓ Short ID: $SID"
  
  # Step 4: Generate Hysteria2 password
  msg "  - Generating Hysteria2 password..."
  HY2_PASS="$(generate_hex_string 16)"
  [[ -n "$HY2_PASS" ]] || die "Failed to generate Hysteria2 password"
  success "  ✓ Hysteria2 password generated"

  msg "Allocating network ports..."
  
  # Allocate Reality port
  msg "  - Checking Reality port..."
  REALITY_PORT_CHOSEN="$(allocate_port "$REALITY_PORT" "$REALITY_PORT_FALLBACK" "Reality")"
  [[ -n "$REALITY_PORT_CHOSEN" ]] || die "Failed to allocate Reality port"
  success "  ✓ Reality port: $REALITY_PORT_CHOSEN"
  
  # Allocate WebSocket port
  msg "  - Checking WebSocket port..."
  WS_PORT_CHOSEN="$(allocate_port "$WS_PORT" "$WS_PORT_FALLBACK" "WebSocket")"
  [[ -n "$WS_PORT_CHOSEN" ]] || die "Failed to allocate WebSocket port"
  success "  ✓ WebSocket port: $WS_PORT_CHOSEN"
  
  # Allocate Hysteria2 port
  msg "  - Checking Hysteria2 port..."
  HY2_PORT_CHOSEN="$(allocate_port "$HY2_PORT" "$HY2_PORT_FALLBACK" "Hysteria2")"
  [[ -n "$HY2_PORT_CHOSEN" ]] || die "Failed to allocate Hysteria2 port"
  success "  ✓ Hysteria2 port: $HY2_PORT_CHOSEN"
  
  # Validate all ports are available after allocation
  for port_info in "Reality:$REALITY_PORT_CHOSEN" "WebSocket:$WS_PORT_CHOSEN" "Hysteria2:$HY2_PORT_CHOSEN"; do
    port_name="${port_info%%:*}"
    port_num="${port_info##*:}"
    # Skip validation if port_num is empty or invalid
    if [[ -n "$port_num" && "$port_num" =~ ^[0-9]+$ ]]; then
      if port_in_use "$port_num"; then
        die "$port_name port $port_num is still in use after allocation. Please check for conflicts."
      fi
    fi
  done
}

write_config() {
  msg "Writing $SB_CONF ..."
  mkdir -p "$SB_CONF_DIR"
  
  # Detect network stack support
  msg "Detecting network stack support..."
  local ipv6_supported
  ipv6_supported=$(detect_ipv6_support)
  
  local listen_addr
  listen_addr=$(choose_listen_address "$ipv6_supported")
  
  if [[ "$ipv6_supported" == "true" ]]; then
    success "  ✓ IPv6 support detected - using dual-stack configuration ($listen_addr)"
  else
    warn "  ⚠ IPv6 not available - using IPv4-only configuration ($listen_addr)"
  fi
  
  # Validate Reality destination connectivity
  if ! validate_reality_dest "$SNI_DEFAULT" "$ipv6_supported"; then
    warn "Reality destination connectivity issues detected, but continuing with installation"
  fi
  
  # Validate all required variables are set
  msg "Validating configuration parameters..."
  validate_config_vars() {
    local errors=0
    local var_name var_value
    
    # Check each required variable
    for var_spec in \
      "UUID:UUID" \
      "REALITY_PORT_CHOSEN:Reality port" \
      "SNI_DEFAULT:SNI domain" \
      "PRIV:Reality private key" \
      "SID:Reality short ID" \
      "LOG_LEVEL:Log level"; do
      
      IFS=':' read -r var_name var_desc <<< "$var_spec"
      var_value="${!var_name}"
      
      if [[ -z "$var_value" ]]; then
        err "  ✗ $var_desc is not set"
        ((errors++))
      else
        success "  ✓ $var_desc configured"
      fi
    done
    
    return $errors
  }
  
  validate_config_vars || die "Configuration validation failed. Please check the errors above."
  
  # Create temporary file for atomic write with secure permissions
  local temp_conf
  temp_conf=$(mktemp) || die "Failed to create secure temporary file"
  chmod 600 "$temp_conf" || die "Failed to set secure permissions on temporary file"
  
  # Enhanced certificate validation first if certificates are provided
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    [[ -r "$CERT_FULLCHAIN" ]] || die "Certificate file not readable: $CERT_FULLCHAIN"
    [[ -r "$CERT_KEY" ]] || die "Private key file not readable: $CERT_KEY"
    
    # Check certificate validity
    if ! openssl x509 -checkend 86400 -noout -in "$CERT_FULLCHAIN" >/dev/null 2>&1; then
      warn "Certificate will expire within 24 hours: $CERT_FULLCHAIN"
    fi
    
    # Verify certificate and key match
    local cert_modulus key_modulus
    if cert_modulus=$(openssl x509 -noout -modulus -in "$CERT_FULLCHAIN" 2>/dev/null | openssl md5 2>/dev/null) && \
       key_modulus=$(openssl rsa -noout -modulus -in "$CERT_KEY" 2>/dev/null | openssl md5 2>/dev/null); then
      if [[ "$cert_modulus" != "$key_modulus" ]]; then
        warn "Certificate and private key do not match"
      fi
    else
      warn "Could not verify certificate and key compatibility"
    fi
  fi
  
  # Create base configuration using jq for robust JSON generation
  local base_config reality_config
  
  if ! base_config=$(jq -n \
    --arg log_level "$LOG_LEVEL" \
    '{
      log: { level: $log_level, timestamp: true },
      inbounds: [],
      outbounds: [
        { type: "direct", tag: "direct" },
        { type: "block", tag: "block" }
      ]
    }' 2>/dev/null); then
    die "Failed to create base configuration with jq"
  fi
  
  # Add Reality inbound (always present)
  msg "  - Creating Reality inbound configuration..."
  reality_config=$(jq -n \
    --arg uuid "$UUID" \
    --arg port "$REALITY_PORT_CHOSEN" \
    --arg listen_addr "$listen_addr" \
    --arg sni "$SNI_DEFAULT" \
    --arg priv "$PRIV" \
    --arg sid "$SID" \
    '{
      type: "vless",
      tag: "in-reality",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid, flow: "xtls-rprx-vision" }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: {
        enabled: true,
        server_name: $sni,
        reality: {
          enabled: true,
          private_key: $priv,
          short_id: [$sid],
          handshake: { server: $sni, server_port: 443 },
          max_time_difference: "1m"
        },
        alpn: ["h2", "http/1.1"]
      }
    }' 2>&1) || {
    err "Failed to create Reality configuration. jq output:"
    err "$reality_config"
    die "JSON generation failed. This usually indicates a bug in the script."
  }
  success "  ✓ Reality inbound configured"
  
  # Add Reality inbound to base config
  if ! base_config=$(echo "$base_config" | jq --argjson reality "$reality_config" '.inbounds += [$reality]' 2>/dev/null); then
    die "Failed to add Reality configuration to base config"
  fi
  
  # Add WS-TLS and Hysteria2 inbounds if certificates are available
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    # Validate additional variables for certificate-based configurations
    [[ -n "$WS_PORT_CHOSEN" ]] || die "WebSocket port is not set for certificate configuration."
    [[ -n "$HY2_PORT_CHOSEN" ]] || die "Hysteria2 port is not set for certificate configuration."
    [[ -n "$DOMAIN" ]] || die "Domain is not set for certificate configuration."
    [[ -n "$HY2_PASS" ]] || die "Hysteria2 password is not set for certificate configuration."
    
    # Add WS-TLS inbound
    local ws_config hy2_config
    
    if ! ws_config=$(jq -n \
      --arg uuid "$UUID" \
      --arg port "$WS_PORT_CHOSEN" \
      --arg listen_addr "$listen_addr" \
      --arg domain "$DOMAIN" \
      --arg cert_path "$CERT_FULLCHAIN" \
      --arg key_path "$CERT_KEY" \
      '{
        type: "vless",
        tag: "in-ws",
        listen: $listen_addr,
        listen_port: ($port | tonumber),
        users: [{ uuid: $uuid }],
        multiplex: {
          enabled: false,
          padding: false,
          brutal: {
            enabled: false,
            up_mbps: 1000,
            down_mbps: 1000
          }
        },
        tls: {
          enabled: true,
          server_name: $domain,
          certificate_path: $cert_path,
          key_path: $key_path,
          alpn: ["h2", "http/1.1"]
        },
        transport: { type: "ws", path: "/ws" }
      }' 2>/dev/null); then
      die "Failed to create WS-TLS configuration with jq"
    fi
    
    # Add Hysteria2 inbound
    if ! hy2_config=$(jq -n \
      --arg password "$HY2_PASS" \
      --arg port "$HY2_PORT_CHOSEN" \
      --arg listen_addr "$listen_addr" \
      --arg cert_path "$CERT_FULLCHAIN" \
      --arg key_path "$CERT_KEY" \
      '{
        type: "hysteria2",
        tag: "in-hy2",
        listen: $listen_addr,
        listen_port: ($port | tonumber),
        users: [{ password: $password }],
        up_mbps: 100,
        down_mbps: 100,
        tls: {
          enabled: true,
          certificate_path: $cert_path,
          key_path: $key_path,
          alpn: ["h3"]
        }
      }' 2>/dev/null); then
      die "Failed to create Hysteria2 configuration with jq"
    fi
    
    # Add both WS and Hysteria2 inbounds
    if ! base_config=$(echo "$base_config" | jq --argjson ws "$ws_config" --argjson hy2 "$hy2_config" '.inbounds += [$ws, $hy2]' 2>/dev/null); then
      die "Failed to add WS-TLS and Hysteria2 configurations"
    fi
  fi
  
  # Add route configuration for sing-box 1.12.0 compatibility
  local route_inbounds='["in-reality"]'
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    route_inbounds='["in-reality", "in-ws", "in-hy2"]'
  fi
  
  if ! base_config=$(echo "$base_config" | jq --argjson inbounds "$route_inbounds" '.route = {
    "rules": [
      {
        "inbound": $inbounds,
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      }
    ],
    "auto_detect_interface": true
  }' 2>/dev/null); then
    die "Failed to add route configuration"
  fi
  
  # Optimize outbound configuration based on network stack
  if [[ "$ipv6_supported" == "false" ]]; then
    msg "  - Optimizing outbound for IPv4-only network"
    if ! base_config=$(echo "$base_config" | jq '.outbounds[0] += {
      "bind_interface": "",
      "routing_mark": 0,
      "reuse_addr": false,
      "connect_timeout": "5s",
      "tcp_fast_open": false,
      "udp_fragment": true,
      "inet4_bind_address": "0.0.0.0"
    }' 2>/dev/null); then
      warn "Failed to add IPv4-only optimization, continuing with default configuration"
    else
      success "  ✓ IPv4-only network optimization applied"
    fi
  else
    msg "  - Using default outbound configuration for dual-stack network"
  fi
  
  # Write configuration to temporary file
  echo "$base_config" > "$temp_conf" || { rm -f "$temp_conf"; die "Failed to write configuration to temporary file"; }
  
  # Validate configuration syntax before applying
  if ! /usr/local/bin/sing-box check -c "$temp_conf" >/dev/null 2>&1; then
    rm -f "$temp_conf"
    die "Generated configuration is invalid. Please check your settings."
  fi
  
  # Atomic move to final location
  if ! mv "$temp_conf" "$SB_CONF"; then
    rm -f "$temp_conf"
    die "Failed to move configuration to final location"
  fi
  
  # Set secure permissions for configuration file
  chmod 600 "$SB_CONF"
  chown root:root "$SB_CONF"
}

setup_service() {
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
  systemctl daemon-reload
  /usr/local/bin/sing-box check -c "$SB_CONF"
  
  # Enable service if not already enabled
  if ! systemctl is-enabled sing-box >/dev/null 2>&1; then
    systemctl enable sing-box
  fi
  
  # Start or restart service to apply new configuration
  if systemctl is-active sing-box >/dev/null 2>&1; then
    msg "Restarting sing-box service to apply new configuration..."
    systemctl restart sing-box
  else
    msg "Starting sing-box service..."
    systemctl start sing-box
  fi
  
  # Allow service to start up properly before verification
  sleep 3
  
  # Wait for service to fully start and verify it's working
  local retry=0
  while [[ $retry -lt 10 ]]; do    
    if systemctl is-active sing-box >/dev/null 2>&1; then
      # Additional check: verify required ports are actually listening
      sleep 2
      
      # Always check Reality port (required)
      local reality_port="${REALITY_PORT_CHOSEN:-443}"
      local reality_listening=false
      if ss -tlnp | grep -q ":${reality_port} "; then
        reality_listening=true
      fi
      
      # Check additional ports only if certificates are present
      local additional_ports_ok=true
      if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
        local ws_port="${WS_PORT_CHOSEN:-8444}"
        local hy2_port="${HY2_PORT_CHOSEN:-8443}"
        
        if ! ss -tlnp | grep -q ":${ws_port} " || \
           ! ss -ulnp | grep -q ":${hy2_port} "; then
          additional_ports_ok=false
        fi
      fi
      
      if [[ "$reality_listening" == "true" && "$additional_ports_ok" == "true" ]]; then
        success "Service started successfully and all required ports are listening"
        break
      fi
    fi
    sleep 1
    ((retry++))
  done
  
  if [[ $retry -ge 10 ]]; then
    warn "Service may not have started properly. Check logs with: journalctl -u sing-box -n 20"
    # Don't fail the installation - the service might still be working
  fi
}

create_manager_script() {
  msg "Creating management script ..."
  cat >/usr/local/bin/sbx-manager <<'EOF'
#!/bin/bash
# sbx-manager - sing-box management tool

# Color definitions
G='\033[0;32m'
Y='\033[0;33m'
R='\033[0;31m'
B='\033[1m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
N='\033[0m'

# Simple logo for management tool
show_sbx_logo() {
  echo
  echo -e "${B}${CYAN}█▀▀ █▄▄ ▀▄▀   █▀▄▀█ ▄▀█ █▄ █ ▄▀█ █▀▀ █▀▀ █▀█${N}"
  echo -e "${B}${BLUE}▄██ █▄█  █    █ ▀ █ █▀█ █ ▀█ █▀█ █▄█ ██▄ █▀▄${N}"
  echo -e "${G}================================================${N}"
  echo
}

case "$1" in
    status)
        echo -e "${B}=== Service Status ===${N}"
        echo "[sing-box]"
        systemctl is-active --quiet sing-box && echo -e "Status: ${G}Running${N}" || echo -e "Status: ${R}Stopped${N}"
        echo "PID: $(systemctl show -p MainPID --value sing-box)"
        echo
        systemctl status sing-box --no-pager | head -10
        ;;
        
    info|show)
        if [[ ! -f "/etc/sing-box/client-info.txt" ]]; then
            echo -e "${R}[ERR]${N} Client info not found."
            exit 1
        fi
        
        show_sbx_logo
        
        # Load saved info
        source /etc/sing-box/client-info.txt
        
        echo
        printf "${B}=== sing-box Configuration ===${N}\n"
        echo "Domain    : ${DOMAIN}"
        echo "Binary    : /usr/local/bin/sing-box"
        echo "Config    : /etc/sing-box/config.json"
        echo "Service   : systemctl status sing-box"
        echo
        
        # Reality
        echo "INBOUND   : VLESS-REALITY  ${REALITY_PORT}/tcp"
        echo "  PublicKey = ${PUBLIC_KEY}"
        echo "  Short ID  = ${SHORT_ID}"
        echo "  UUID      = ${UUID}"
        URI_REAL="vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
        echo "  URI       = ${URI_REAL}"
        
        # WebSocket (if cert exists)
        if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
            echo
            echo "INBOUND   : VLESS-WS-TLS   ${WS_PORT}/tcp"
            echo "  CERT     = ${CERT_FULLCHAIN}"
            URI_WS="vless://${UUID}@${DOMAIN}:${WS_PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
            echo "  URI      = ${URI_WS}"
            echo
            echo "INBOUND   : Hysteria2      ${HY2_PORT}/udp"
            echo "  CERT     = ${CERT_FULLCHAIN}"
            URI_HY2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
            echo "  URI      = ${URI_HY2}"
        fi
        echo
        echo -e "${Y}Notes${N}: Reality/Hy2 suggest gray cloud; WS-TLS can use gray/orange cloud."
        
        # Optional: Generate QR codes
        if command -v qrencode >/dev/null 2>&1; then
            echo
            echo -e "${CYAN}QR codes:${N}"
            echo -e "  ${G}sbx qr${N}            - Show QR codes for all protocols"
        fi
        ;;
        
    qr)
        if [[ ! -f "/etc/sing-box/client-info.txt" ]]; then
            echo -e "${R}[ERR]${N} Client info not found."
            exit 1
        fi
        
        if ! command -v qrencode >/dev/null 2>&1; then
            echo -e "${R}[ERR]${N} qrencode not installed. Install with: apt install qrencode"
            exit 1
        fi
        
        # Load saved info
        source /etc/sing-box/client-info.txt
        
        echo -e "${B}=== Configuration QR Codes ===${N}"
        
        # Generate Reality QR code
        if [[ -n "$UUID" && -n "$DOMAIN" && -n "$PUBLIC_KEY" && -n "$SHORT_ID" ]]; then
            URI_REAL="vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
            echo
            echo -e "${G}VLESS-REALITY:${N}"
            echo "┌─────────────────────────────────────┐"
            qrencode -t UTF8 -m 0 "$URI_REAL" 2>/dev/null || echo "QR code generation failed"
            echo "└─────────────────────────────────────┘"
        fi
        
        # Generate WS-TLS QR code if certificates exist
        if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -n "$UUID" && -n "$DOMAIN" ]]; then
            URI_WS="vless://${UUID}@${DOMAIN}:${WS_PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
            echo
            echo -e "${G}VLESS-WS-TLS:${N}"
            echo "┌─────────────────────────────────────┐"
            qrencode -t UTF8 -m 0 "$URI_WS" 2>/dev/null || echo "QR code generation failed"
            echo "└─────────────────────────────────────┘"
            
            URI_HY2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
            echo
            echo -e "${G}Hysteria2:${N}"
            echo "┌─────────────────────────────────────┐"
            qrencode -t UTF8 -m 0 "$URI_HY2" 2>/dev/null || echo "QR code generation failed"
            echo "└─────────────────────────────────────┘"
        fi
        
        echo
        echo -e "${Y}Tip${N}: Use phone to scan QR code to import proxy configuration"
        ;;
        
    restart)
        systemctl restart sing-box
        echo -e "${G}✓${N} Service restarted"
        sleep 1
        systemctl is-active --quiet sing-box && echo -e "Status: ${G}Running${N}" || echo -e "Status: ${R}Failed${N}"
        ;;
        
    start)
        systemctl start sing-box
        echo -e "${G}✓${N} Service started"
        ;;
        
    stop)
        systemctl stop sing-box
        echo -e "${Y}✓${N} Service stopped"
        ;;
        
    log|logs)
        echo -e "${CYAN}Live logs (Ctrl+C to exit):${N}"
        journalctl -u sing-box -f
        ;;
        
    check)
        echo -e "${CYAN}Checking configuration...${N}"
        /usr/local/bin/sing-box check -c /etc/sing-box/config.json && echo -e "${G}✓ Configuration valid${N}" || echo -e "${R}✗ Configuration invalid${N}"
        ;;
        
    uninstall|remove)
        # Define paths consistent with main script
        SB_BIN="/usr/local/bin/sing-box"
        SB_CONF_DIR="/etc/sing-box"
        SB_CONF="$SB_CONF_DIR/config.json"
        SB_SVC="/etc/systemd/system/sing-box.service"
        CERT_DIR_BASE="/etc/ssl/sbx"
        
        # Check if running as root
        if [[ "$(id -u)" -ne 0 ]]; then
            echo -e "${R}[ERR]${N} Please run as root (sudo sbx uninstall)"
            exit 1
        fi
        
        # Show what will be removed
        echo
        echo -e "${Y}[!]${N} The following will be completely removed:"
        [[ -x "$SB_BIN" ]] && echo "  - Binary: $SB_BIN"
        [[ -f "$SB_CONF" ]] && echo "  - Config: $SB_CONF"
        [[ -d "$SB_CONF_DIR" ]] && echo "  - Config directory: $SB_CONF_DIR"
        [[ -f "$SB_SVC" ]] && echo "  - Service: $SB_SVC"
        [[ -x "/usr/local/bin/sbx-manager" ]] && echo "  - Management commands: sbx-manager, sbx"
        [[ -d "$CERT_DIR_BASE" ]] && echo "  - Certificates: $CERT_DIR_BASE"
        echo "  - Firewall rules for common ports"
        
        echo
        read -rp "Continue with complete removal? [y/N] " confirm
        if [[ ! "${confirm:-N}" =~ ^[Yy]$ ]]; then
            echo "Uninstall cancelled."
            exit 0
        fi
        
        echo
        echo -e "${G}[*]${N} Stopping and disabling sing-box service..."
        systemctl disable --now sing-box 2>/dev/null || true
        
        # Verify service is actually stopped
        retry=0
        while systemctl is-active sing-box >/dev/null 2>&1 && [[ $retry -lt 10 ]]; do
            sleep 1
            ((retry++))
        done
        
        if [[ $retry -ge 10 ]]; then
            echo -e "${Y}[!]${N} Service may still be running. You may need to stop it manually."
        fi
        
        echo -e "${G}[*]${N} Removing service file..."
        rm -f "$SB_SVC"
        systemctl daemon-reload || true
        
        echo -e "${G}[*]${N} Removing binary..."
        rm -f "$SB_BIN"
        
        echo -e "${G}[*]${N} Removing configuration directory..."
        rm -rf "$SB_CONF_DIR"
        
        echo -e "${G}[*]${N} Removing certificate directory..."
        rm -rf "$CERT_DIR_BASE"
        
        echo -e "${G}[*]${N} Cleaning firewall rules..."
        if command -v ufw >/dev/null 2>&1; then
            for port in 443 8443 8444 24443 24444 24445; do
                ufw delete allow "${port}/tcp" 2>/dev/null || true
                ufw delete allow "${port}/udp" 2>/dev/null || true
            done
        fi
        
        echo -e "${G}[*]${N} Cleaning acme.sh installation..."
        if [[ -d "$HOME/.acme.sh" ]]; then
            "$HOME/.acme.sh/acme.sh" --uninstall 2>/dev/null || true
            rm -rf "$HOME/.acme.sh" 2>/dev/null || true
        fi
        
        echo -e "${G}[*]${N} Cleaning temporary files..."
        find /tmp -maxdepth 1 -name 'sb*' -type f -mmin +10 -delete 2>/dev/null || true
        find /tmp -maxdepth 1 -name 'sing-box*' -type f -mmin +10 -delete 2>/dev/null || true
        
        echo -e "${G}[*]${N} Removing management scripts..."
        rm -f /usr/local/bin/sbx-manager
        rm -f /usr/local/bin/sbx
        
        # Verify removal
        remaining_items=()
        [[ -x "$SB_BIN" ]] && remaining_items+=("$SB_BIN")
        [[ -f "$SB_CONF" ]] && remaining_items+=("$SB_CONF")
        [[ -f "$SB_SVC" ]] && remaining_items+=("$SB_SVC")
        
        if [[ ${#remaining_items[@]} -eq 0 ]]; then
            echo
            echo -e "${G}[✓]${N} Uninstall completed successfully!"
            echo
            echo -e "${BLUE}[INFO]${N} All sing-box files and configurations have been removed."
            echo -e "${BLUE}[INFO]${N} You can safely run the installation script again for a fresh setup."
        else
            echo
            echo -e "${Y}[!]${N} Some items could not be removed:"
            printf '  %s\n' "${remaining_items[@]}"
            echo -e "${Y}[!]${N} You may need to remove them manually."
        fi
        ;;
        
    *)
        echo "Usage: $0 {status|info|qr|restart|start|stop|log|check|uninstall}"
        echo "  status    - Check service status"
        echo "  info      - Show client configuration"
        echo "  qr        - Show QR codes for easy client import"
        echo "  restart   - Restart service"
        echo "  start     - Start service"
        echo "  stop      - Stop service"
        echo "  log       - View live logs"
        echo "  check     - Validate configuration"
        echo "  uninstall - Completely remove sing-box (requires root)"
        ;;
esac
EOF
  chmod +x /usr/local/bin/sbx-manager
  
  # Create short alias
  ln -sf /usr/local/bin/sbx-manager /usr/local/bin/sbx
  
  success "Management commands installed: sbx-manager (or sbx)"
}

validate_service() {
  local service_name="$1"
  msg "Checking $service_name service status..."
  
  # Quick check first - many services start immediately
  if systemctl is-active --quiet "$service_name"; then
    success "$service_name service is running"
    return 0
  fi
  
  # Wait for service to start with retry logic
  local max_retries=15
  local wait_time=2
  local total_wait_time=$((max_retries * wait_time))
  
  msg "Service starting, waiting up to ${total_wait_time}s..."
  local retry=0
  
  while [[ $retry -lt $max_retries ]]; do
    sleep $wait_time
    retry=$((retry + 1))
    
    if systemctl is-active --quiet "$service_name"; then
      success "$service_name service is running (started in $((retry * wait_time))s)"
      return 0
    fi
    
    # Progress feedback every 5 attempts (10 seconds)
    if [[ $((retry % 5)) -eq 0 ]]; then
      msg "Still waiting for service startup... ($((retry * wait_time))/${total_wait_time}s)"
    fi
  done
  
  # If we get here, service failed to start
  err "$service_name service failed to start after ${max_retries} attempts (${total_wait_time}s total)"
  warn "Final service state: $(systemctl is-active "$service_name" 2>/dev/null || echo "unknown")"
  warn "Service status:"
  systemctl status "$service_name" --no-pager -l || true
  warn "Recent logs:"
  journalctl -u "$service_name" --no-pager -n 15 --since "30 seconds ago" || true
  return 1
}

open_firewall() {
  if have ufw; then
    # Use chosen ports if available, otherwise fall back to defaults
    local reality_port="${REALITY_PORT_CHOSEN:-$REALITY_PORT}"
    local ws_port="${WS_PORT_CHOSEN:-$WS_PORT}" 
    local hy2_port="${HY2_PORT_CHOSEN:-$HY2_PORT}"
    
    [[ -n "$reality_port" ]] && ufw allow "${reality_port}/tcp" || true
    if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
      [[ -n "$ws_port" ]] && ufw allow "${ws_port}/tcp" || true
      [[ -n "$hy2_port" ]] && ufw allow "${hy2_port}/udp" || true
    fi
  fi
}

print_summary() {
  echo
  printf "${B}=== sing-box Installed (official) ===${N}\n"
  if [[ "${REALITY_ONLY_MODE:-0}" == "1" ]]; then
    echo "Server    : ${DOMAIN:-N/A} (IP address - Reality-only mode)"
  else
    echo "Domain    : ${DOMAIN:-N/A}"
  fi
  echo "Binary    : $SB_BIN"
  echo "Config    : $SB_CONF"
  echo "Service   : systemctl status sing-box"
  echo
  
  # Use chosen ports if available, otherwise fall back to defaults
  local reality_port="${REALITY_PORT_CHOSEN:-$REALITY_PORT}"
  local ws_port="${WS_PORT_CHOSEN:-$WS_PORT}"
  local hy2_port="${HY2_PORT_CHOSEN:-$HY2_PORT}"
  
  echo "INBOUND   : VLESS-REALITY  ${reality_port}/tcp"
  echo "  PublicKey = ${PUB:-N/A}"
  echo "  Short ID  = ${SID:-N/A}"
  echo "  UUID      = ${UUID:-N/A}"
  
  if [[ -n "${UUID:-}" && -n "${DOMAIN:-}" && -n "${PUB:-}" && -n "${SID:-}" ]]; then
    local uri_real="vless://${UUID}@${DOMAIN}:${reality_port}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI_DEFAULT}&pbk=${PUB}&sid=${SID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
    echo "  URI       = ${uri_real}"
  else
    echo "  URI       = [Configuration incomplete - check /etc/sing-box/client-info.txt]"
  fi
  
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    echo
    echo "INBOUND   : VLESS-WS-TLS   ${ws_port}/tcp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    if [[ -n "${UUID:-}" && -n "${DOMAIN:-}" ]]; then
      local uri_ws="vless://${UUID}@${DOMAIN}:${ws_port}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
      echo "  URI      = ${uri_ws}"
    else
      echo "  URI      = [Configuration incomplete]"
    fi
    echo
    echo "INBOUND   : Hysteria2      ${hy2_port}/udp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    if [[ -n "${HY2_PASS:-}" && -n "${DOMAIN:-}" ]]; then
      local uri_hy2="hysteria2://${HY2_PASS}@${DOMAIN}:${hy2_port}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
      echo "  URI      = ${uri_hy2}"
    else
      echo "  URI      = [Configuration incomplete]"
    fi
  fi
  echo
  echo -e "${Y}Notes${N}: Reality/Hy2 suggest gray cloud; WS-TLS can use gray/orange cloud. DNS-01 recommended; HTTP-01 requires port :80 accessible and unused."
  echo
  echo -e "${CYAN}Management Commands:${N}"
  echo -e "  ${G}sbx info${N}          - Show configuration and URIs"
  echo -e "  ${G}sbx status${N}        - Check service status"
  echo -e "  ${G}sbx restart${N}       - Restart service"  
  echo -e "  ${G}sbx log${N}           - View live logs"
  echo -e "  ${G}sbx check${N}         - Validate configuration"
  echo -e "  ${G}sudo sbx uninstall${N} - Completely remove sing-box"
  echo ""
  echo -e "  Full command: ${G}sbx-manager${N}, short alias: ${G}sbx${N}"
  
  # Save client info for later retrieval with safe variable handling
  cat > /etc/sing-box/client-info.txt <<EOF
DOMAIN=${DOMAIN:-}
REALITY_PORT=${REALITY_PORT_CHOSEN:-$REALITY_PORT}
WS_PORT=${WS_PORT_CHOSEN:-$WS_PORT}
HY2_PORT=${HY2_PORT_CHOSEN:-$HY2_PORT}
UUID=${UUID:-}
PUBLIC_KEY=${PUB:-}
SHORT_ID=${SID:-}
HY2_PASS=${HY2_PASS:-}
CERT_FULLCHAIN=${CERT_FULLCHAIN:-}
CERT_KEY=${CERT_KEY:-}
SNI=${SNI_DEFAULT:-www.microsoft.com}
EOF
  chmod 600 /etc/sing-box/client-info.txt
  
  # Generate QR codes for easy import
  local cert_available="false"
  [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]] && cert_available="true"
  
  generate_all_qr_codes \
    "${DOMAIN:-}" \
    "${REALITY_PORT_CHOSEN:-$REALITY_PORT}" \
    "${WS_PORT_CHOSEN:-$WS_PORT}" \
    "${HY2_PORT_CHOSEN:-$HY2_PORT}" \
    "${UUID:-}" \
    "${PUB:-}" \
    "${SID:-}" \
    "${HY2_PASS:-}" \
    "$cert_available"
}

print_upgrade_summary() {
  local current_version="$(get_installed_version)"
  local service_status="$(check_service_status)"
  
  echo
  echo -e "${B}=== sing-box Binary Upgraded ===${N}"
  echo "Version   : ${current_version}"
  echo "Binary    : $SB_BIN"
  echo "Config    : $SB_CONF (preserved)"
  echo "Service   : $service_status"
  echo
  success "Binary upgrade completed successfully!"
  echo
  echo -e "${CYAN}Management Commands:${N}"
  echo -e "  ${G}sbx info${N}          - Show configuration and URIs"
  echo -e "  ${G}sbx status${N}        - Check service status"
  echo -e "  ${G}sbx restart${N}       - Restart service"  
  echo -e "  ${G}sbx log${N}           - View live logs"
  echo -e "  ${G}sbx check${N}         - Validate configuration"
  echo -e "  ${G}sudo sbx uninstall${N} - Completely remove sing-box"
  echo ""
  echo -e "  Full command: ${G}sbx-manager${N}, short alias: ${G}sbx${N}"
  echo
  info "To reconfigure with new parameters, run the script again and choose 'Reconfigure'"
}

install_flow() {
  show_logo
  need_root
  
  # Validate environment variables first (if provided)
  if [[ -n "$DOMAIN" ]]; then
    validate_env_vars
  fi
  
  # Enhanced installation detection and management
  check_existing_installation
  
  # DOMAIN is no longer required - will be handled in gen_materials
  ensure_tools
  download_singbox
  
  # Skip configuration steps if only upgrading binary
  if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
    gen_materials  # This will handle DOMAIN/IP detection
    
    # Only attempt certificate operations if we have a real domain (not IP)
    if [[ "${REALITY_ONLY_MODE:-0}" != "1" ]]; then
      if [[ -n "${CERT_MODE:-}" || ( -n "${CERT_FULLCHAIN:-}" && -n "${CERT_KEY:-}" ) ]]; then
        maybe_issue_cert
      fi
    else
      info "Reality-only mode: Skipping certificate operations"
    fi
    write_config
    setup_service
    create_manager_script
  else
    success "Binary upgrade completed, preserving existing configuration"
    # Just restart the service with existing config
    if systemctl is-active sing-box >/dev/null 2>&1; then
      msg "Restarting sing-box service with existing configuration..."
      systemctl restart sing-box
    else
      msg "Starting sing-box service..."
      systemctl start sing-box
    fi
  fi
  
  validate_service "sing-box"
  open_firewall
  
  # Show appropriate summary based on operation type
  if [[ "${SKIP_CONFIG_GEN:-0}" = "1" ]]; then
    print_upgrade_summary
  else
    print_summary
  fi
}

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
  [[ -d "/etc/ssl/sbx" ]] && echo "  - Certificates: /etc/ssl/sbx"
  echo "  - Firewall rules for common ports"
  
  if [[ "${FORCE:-0}" != "1" ]]; then
    echo
    read -rp "Continue with complete removal? [y/N] " confirm
    [[ "${confirm:-N}" =~ ^[Yy]$ ]] || { echo "Uninstall cancelled."; exit 0; }
  fi
  
  echo
  msg "Stopping and disabling sing-box service..."
  systemctl disable --now sing-box 2>/dev/null || true
  
  # Verify service is actually stopped
  local retry=0
  while systemctl is-active sing-box >/dev/null 2>&1 && [[ $retry -lt 10 ]]; do
    sleep 1
    ((retry++))
  done
  
  if [[ $retry -ge 10 ]]; then
    warn "Service may still be running. You may need to stop it manually."
  fi
  
  msg "Removing service file..."
  rm -f "$SB_SVC"
  systemctl daemon-reload || true
  
  msg "Removing binary..."
  rm -f "$SB_BIN"
  
  msg "Removing management scripts..."
  rm -f /usr/local/bin/sbx-manager
  rm -f /usr/local/bin/sbx
  
  msg "Removing configuration directory..."
  rm -rf "$SB_CONF_DIR"
  
  msg "Removing certificate directory..."
  rm -rf "/etc/ssl/sbx"
  
  msg "Cleaning acme.sh installation..."
  if [[ -d "$HOME/.acme.sh" ]]; then
    "$HOME/.acme.sh/acme.sh" --uninstall 2>/dev/null || true
    rm -rf "$HOME/.acme.sh" 2>/dev/null || true
  fi
  
  msg "Cleaning firewall rules..."
  if have ufw; then
    for port in 443 8443 8444 24443 24444 24445; do
      ufw delete allow "${port}/tcp" 2>/dev/null || true
      ufw delete allow "${port}/udp" 2>/dev/null || true
    done
  fi
  
  # Clean up any temporary files that might have been created
  msg "Cleaning temporary files..."
  find /tmp -maxdepth 1 -name 'sb*' -type f -mmin +10 -delete 2>/dev/null || true
  find /tmp -maxdepth 1 -name 'sing-box*' -type f -mmin +10 -delete 2>/dev/null || true
  
  # Verify removal
  local remaining_items=()
  [[ -x "$SB_BIN" ]] && remaining_items+=("$SB_BIN")
  [[ -f "$SB_CONF" ]] && remaining_items+=("$SB_CONF")
  [[ -f "$SB_SVC" ]] && remaining_items+=("$SB_SVC")
  
  if [[ ${#remaining_items[@]} -eq 0 ]]; then
    echo
    success "Uninstall completed successfully!"
    echo
    info "All sing-box files and configurations have been removed."
    info "You can safely run the installation script again for a fresh setup."
  else
    echo
    warn "Some items could not be removed:"
    printf '  %s\n' "${remaining_items[@]}"
    warn "You may need to remove them manually."
  fi
}

case "${1:-install}" in
  install)   install_flow ;;
  uninstall) uninstall_flow ;;
  *) die "Usage: $0 [install|uninstall]" ;;
esac
