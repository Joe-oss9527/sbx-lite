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

SNI_DEFAULT="${SNI_DEFAULT:-www.cloudflare.com}"
CERT_DIR_BASE="${CERT_DIR_BASE:-/etc/ssl/sbx}"
SINGBOX_VERSION="${SINGBOX_VERSION:-}"
LOG_LEVEL="${LOG_LEVEL:-info}"

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

port_in_use() {
  local p="$1"
  ss -lntp 2>/dev/null | grep -q ":$p " && return 0
  lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p" && return 0
  return 1
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
      msg "$name port $port in use, retrying in 2 seconds..."
    fi
    sleep 2
    ((retry_count++))
  done
  
  # Try fallback port
  if ! port_in_use "$fallback"; then
    warn "$name port $port persistently in use; switching to $fallback"
    echo "$fallback"
  else
    die "Both $name ports $port and $fallback are in use. Please free up these ports or specify different ones."
  fi
}

# Input validation functions
validate_port() {
  local port="$1"
  [[ "$port" =~ ^[1-9][0-9]{0,4}$ ]] && [ "$port" -le 65535 ]
}

validate_domain() {
  local domain="$1"
  # Simple practical validation
  [[ -n "$domain" ]] || return 1
  [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1
  [[ "$domain" != "localhost" ]] || return 1
  return 0
}

validate_cert_files() {
  local fullchain="$1" key="$2"
  # Simple file existence check
  [[ -n "$fullchain" && -n "$key" && -f "$fullchain" && -f "$key" ]]
}

get_installed_version() {
  if [[ -x "$SB_BIN" ]]; then
    "$SB_BIN" version 2>/dev/null | grep -o 'sing-box version [0-9.]*' | cut -d' ' -f3 || echo "unknown"
  else
    echo "not_installed"
  fi
}

get_latest_version() {
  local api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  if have curl; then
    curl -fsSL "$api_url" --max-time 10 --retry 2 2>/dev/null | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 | sed 's/^v//' || echo "unknown"
  elif have wget; then
    wget -qO- "$api_url" --timeout=10 --tries=2 2>/dev/null | grep -o '"tag_name": "[^"]*"' | cut -d'"' -f4 | sed 's/^v//' || echo "unknown"
  else
    echo "unknown"
  fi
}

compare_versions() {
  local current="$1" latest="$2"
  if [[ "$current" = "unknown" || "$latest" = "unknown" ]]; then
    echo "unknown"
    return
  fi
  
  # Simple version comparison (works for semantic versioning)
  printf '%s\n%s\n' "$current" "$latest" | sort -V | head -1 | grep -q "^$current$"
  if [[ $? -eq 0 && "$current" != "$latest" ]]; then
    echo "outdated"
  elif [[ "$current" = "$latest" ]]; then
    echo "current"
  else
    echo "newer"
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
  msg "Installing tools (curl/wget, tar, jq, openssl, ca-certificates, lsof)..."
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
  tmp="$(mktemp -d)"

  if [[ -n "$SINGBOX_VERSION" ]]; then
    tag="$SINGBOX_VERSION"
    api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"
  else
    api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  fi

  msg "Fetching sing-box release info for $arch ..."
  if have curl; then 
    raw="$(curl -fsSL "$api" --max-time 30 --retry 3)" || { rm -rf "$tmp"; die "Failed to query GitHub API (curl)"; }
  else 
    raw="$(wget -qO- "$api" --timeout=30 --tries=3)" || { rm -rf "$tmp"; die "Failed to query GitHub API (wget)"; }
  fi
  [[ -n "${raw:-}" ]] || { rm -rf "$tmp"; die "Failed to query GitHub API."; }

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
  if have curl; then 
    curl -fsSL "$url" -o "$pkg" --max-time 300 --retry 3 || { rm -rf "$tmp"; die "Failed to download package (curl)"; }
  else 
    wget -qO "$pkg" "$url" --timeout=300 --tries=3 || { rm -rf "$tmp"; die "Failed to download package (wget)"; }
  fi
  
  if [[ -n "$expected_sha256" ]]; then
    msg "Verifying download integrity..."
    verify_sha256 "$pkg" "$expected_sha256"
  else
    warn "SHA256 verification skipped (fallback URL used)"
  fi

  tar -xzf "$pkg" -C "$tmp"

  local bin
  bin="$(find "$tmp" -type f -name 'sing-box' | head -1)"
  [[ -n "$bin" ]] || { rm -rf "$tmp"; die "sing-box binary not found in package"; }
  install -m 0755 "$bin" "$SB_BIN"
  
  rm -rf "$tmp"
  success "Installed sing-box -> $SB_BIN"
}

acme_install() {
  [[ -x "$HOME/.acme.sh/acme.sh" ]] && return
  msg "Installing acme.sh ..."
  
  # Use a default email for ACME installation
  local email="admin@example.com"
  
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

gen_materials() {
  if [[ -z "$DOMAIN" ]]; then
    set +e  # Temporarily disable strict mode for user input
    echo "Please enter your domain name:"
    echo "- Must be set to 'DNS only' (gray cloud) in Cloudflare"
    echo "- Example: r.example.com"
    echo "- Press Enter to skip (Reality only mode)"
    
    while true; do
      read -rp "Domain: " DOMAIN
      if [[ -z "$DOMAIN" ]]; then
        warn "No domain provided. Continuing with Reality-only mode."
        break
      elif validate_domain "$DOMAIN"; then
        success "Domain '$DOMAIN' is valid"
        break
      else
        err "Invalid domain format. Please enter a valid domain (e.g., r.example.com)"
      fi
    done
    set -e  # Re-enable strict mode
  fi

  msg "Generating Reality keypair / UUID / short_id / Hy2 password ..."
  # shellcheck disable=SC2034
  read PRIV PUB < <("$SB_BIN" generate reality-keypair | awk '/PrivateKey:/{p=$2} /PublicKey:/{q=$2} END{print p" "q}')
  [[ -n "$PRIV" && -n "$PUB" ]] || die "Failed to generate Reality keypair"
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SID="$(openssl rand -hex 4)"
  # Validate short_id format (sing-box requires hex string, max 8 chars)
  [[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]] || die "Invalid short ID format: $SID"
  [[ ${#SID} -le 8 ]] || die "Short ID too long (max 8 chars): $SID"
  HY2_PASS="$(openssl rand -hex 16)"

  REALITY_PORT_CHOSEN="$(allocate_port "$REALITY_PORT" "$REALITY_PORT_FALLBACK" "Reality")"
  WS_PORT_CHOSEN="$(allocate_port "$WS_PORT" "$WS_PORT_FALLBACK" "WebSocket")"
  HY2_PORT_CHOSEN="$(allocate_port "$HY2_PORT" "$HY2_PORT_FALLBACK" "Hysteria2")"
}

write_config() {
  msg "Writing $SB_CONF ..."
  mkdir -p "$SB_CONF_DIR"
  : >"$SB_CONF"
  {
    echo '{'
    printf '  "log": { "level": "%s" },\n' "$LOG_LEVEL"
    echo '  "inbounds": ['
    local added=0
    add_comma(){ if [[ $added -eq 1 ]]; then echo ','; fi; added=1; }

    # ---- VLESS REALITY (fixed) ----
    add_comma
    cat <<EOF
      {
        "type": "vless",
        "tag": "in-reality",
        "listen": "0.0.0.0",
        "listen_port": $REALITY_PORT_CHOSEN,
        "sniff": true,
        "sniff_override_destination": true,
        "domain_strategy": "ipv4_only",
        "users": [
          { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
        ],
        "tls": {
          "enabled": true,
          "server_name": "$SNI_DEFAULT",
          "reality": {
            "enabled": true,
            "private_key": "$PRIV",
            "short_id": ["$SID"],
            "handshake": { "server": "$SNI_DEFAULT", "server_port": 443 }
          },
          "alpn": ["h2", "http/1.1"]
        }
      }
EOF

    # ---- Optional WS-TLS / Hy2 if cert is available ----
    if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
      add_comma
      cat <<EOF
      {
        "type": "vless",
        "tag": "in-ws",
        "listen": "0.0.0.0",
        "listen_port": $WS_PORT_CHOSEN,
        "users": [
          { "uuid": "$UUID" }
        ],
        "tls": {
          "enabled": true,
          "server_name": "$DOMAIN",
          "certificate_path": "$CERT_FULLCHAIN",
          "key_path": "$CERT_KEY",
          "alpn": ["http/1.1"]
        },
        "transport": { "type": "ws", "path": "/ws" }
      }
EOF

      add_comma
      cat <<EOF
      {
        "type": "hysteria2",
        "tag": "in-hy2",
        "listen": "0.0.0.0",
        "listen_port": $HY2_PORT_CHOSEN,
        "users": [
          { "password": "$HY2_PASS" }
        ],
        "up_mbps": 100,
        "down_mbps": 100,
        "tls": {
          "enabled": true,
          "certificate_path": "$CERT_FULLCHAIN",
          "key_path": "$CERT_KEY",
          "alpn": ["h3"]
        }
      }
EOF
    fi

    echo '  ],'
    echo '  "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ]'
    echo '}'
  } >>"$SB_CONF"
  
  # Set secure permissions for configuration file
  chmod 600 "$SB_CONF"
  chown root:root "$SB_CONF"
  
  "$SB_BIN" check -c "$SB_CONF" || die "Invalid sing-box configuration"
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
  systemctl enable --now sing-box
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
        echo -e "${Y}Notes${N}: Reality/Hy2 建议灰云；WS-TLS 可灰/橙云。"
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
        
    *)
        echo "Usage: $0 {status|info|restart|start|stop|log|check}"
        echo "  status   - Check service status"
        echo "  info     - Show client configuration"  
        echo "  restart  - Restart service"
        echo "  start    - Start service"
        echo "  stop     - Stop service"
        echo "  log      - View live logs"
        echo "  check    - Validate configuration"
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
  
  # Wait a moment for service to start
  sleep 2
  
  if systemctl is-active --quiet "$service_name"; then
    success "$service_name service is running"
    return 0
  else
    err "$service_name service failed to start"
    warn "Service status:"
    systemctl status "$service_name" --no-pager -l || true
    warn "Recent logs:"
    journalctl -u "$service_name" --no-pager -n 10 || true
    return 1
  fi
}

open_firewall() {
  if have ufw; then
    ufw allow "${REALITY_PORT_CHOSEN}/tcp" || true
    if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
      ufw allow "${WS_PORT_CHOSEN}/tcp" || true
      ufw allow "${HY2_PORT_CHOSEN}/udp" || true
    fi
  fi
}

print_summary() {
  echo
  printf "${B}=== sing-box Installed (official) ===${N}\n"
  echo "Domain    : ${DOMAIN}"
  echo "Binary    : $SB_BIN"
  echo "Config    : $SB_CONF"
  echo "Service   : systemctl status sing-box"
  echo
  echo "INBOUND   : VLESS-REALITY  ${REALITY_PORT_CHOSEN}/tcp"
  echo "  PublicKey = ${PUB}"
  echo "  Short ID  = ${SID}"
  echo "  UUID      = ${UUID}"
  local uri_real="vless://${UUID}@${DOMAIN}:${REALITY_PORT_CHOSEN}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI_DEFAULT}&pbk=${PUB}&sid=${SID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
  echo "  URI       = ${uri_real}"
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    echo
    echo "INBOUND   : VLESS-WS-TLS   ${WS_PORT_CHOSEN}/tcp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_ws="vless://${UUID}@${DOMAIN}:${WS_PORT_CHOSEN}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
    echo "  URI      = ${uri_ws}"
    echo
    echo "INBOUND   : Hysteria2      ${HY2_PORT_CHOSEN}/udp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_hy2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT_CHOSEN}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
    echo "  URI      = ${uri_hy2}"
  fi
  echo
  echo -e "${Y}Notes${N}: Reality/Hy2 建议灰云；WS-TLS 可灰/橙云。DNS-01 推荐；HTTP-01 需 :80 可达且未被占用。"
  echo
  echo -e "${CYAN}Management Commands:${N}"
  echo -e "  ${G}sbx info${N}          - Show configuration and URIs"
  echo -e "  ${G}sbx status${N}        - Check service status"
  echo -e "  ${G}sbx restart${N}       - Restart service"  
  echo -e "  ${G}sbx log${N}           - View live logs"
  echo -e "  ${G}sbx check${N}         - Validate configuration"
  echo ""
  echo -e "  Full command: ${G}sbx-manager${N}, short alias: ${G}sbx${N}"
  
  # Save client info for later retrieval
  cat > /etc/sing-box/client-info.txt <<EOF
DOMAIN=${DOMAIN}
REALITY_PORT=${REALITY_PORT_CHOSEN}
WS_PORT=${WS_PORT_CHOSEN}
HY2_PORT=${HY2_PORT_CHOSEN}
UUID=${UUID}
PUBLIC_KEY=${PUB}
SHORT_ID=${SID}
HY2_PASS=${HY2_PASS}
CERT_FULLCHAIN=${CERT_FULLCHAIN}
CERT_KEY=${CERT_KEY}
SNI=${SNI_DEFAULT}
EOF
  chmod 600 /etc/sing-box/client-info.txt
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
  echo ""
  echo -e "  Full command: ${G}sbx-manager${N}, short alias: ${G}sbx${N}"
  echo
  info "To reconfigure with new parameters, run the script again and choose 'Reconfigure'"
}

install_flow() {
  show_logo
  need_root
  
  # Enhanced installation detection and management
  check_existing_installation
  
  [[ -n "$DOMAIN" ]] || die "Please set DOMAIN=your.graycloud.domain"
  ensure_tools
  download_singbox
  
  # Skip configuration steps if only upgrading binary
  if [[ "${SKIP_CONFIG_GEN:-0}" != "1" ]]; then
    gen_materials
    if [[ -n "${CERT_MODE:-}" || ( -n "${CERT_FULLCHAIN:-}" && -n "${CERT_KEY:-}" ) ]]; then
      maybe_issue_cert
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
  
  msg "Cleaning firewall rules..."
  if have ufw; then
    for port in 443 8443 8444 24443 24444 24445; do
      ufw delete allow "${port}/tcp" 2>/dev/null || true
      ufw delete allow "${port}/udp" 2>/dev/null || true
    done
  fi
  
  # Clean up any temporary files that might have been created
  msg "Cleaning temporary files..."
  rm -rf /tmp/sb* 2>/dev/null || true
  rm -rf /tmp/sing-box* 2>/dev/null || true
  
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
