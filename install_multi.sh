#!/usr/bin/env bash
# install_multi.sh
# One-click official sing-box with:
# - VLESS-REALITY (required, no cert)
# - VLESS-WS-TLS (optional, needs cert)
# - Hysteria2 (optional, needs cert)
# Optional ACME via acme.sh:
#   CERT_MODE=cf_dns  (Cloudflare DNS-01; needs CF_Token [Zone.DNS:Edit + Zone:Read])
#   CERT_MODE=le_http (HTTP-01; needs :80 reachable & DNS-only)
#
# Usage (install):
#   DOMAIN=r.example.com bash install_multi.sh
#   DOMAIN=r.example.com CERT_MODE=cf_dns CF_Token='xxx' bash install_multi.sh
#   DOMAIN=r.example.com CERT_MODE=le_http bash install_multi.sh
#   DOMAIN=r.example.com CERT_FULLCHAIN=/path/fullchain.pem CERT_KEY=/path/privkey.pem bash install_multi.sh
#
# Usage (uninstall):
#   FORCE=1 bash install_multi.sh uninstall

set -euo pipefail

# ------------------ Configurable defaults ------------------
SB_BIN="/usr/local/bin/sing-box"
SB_CONF_DIR="/etc/sing-box"
SB_CONF="$SB_CONF_DIR/config.json"
SB_SVC="/etc/systemd/system/sing-box.service"

DOMAIN="${DOMAIN:-}"              # required: your domain (DNS only / gray-cloud)
CERT_MODE="${CERT_MODE:-}"        # cf_dns | le_http | "" (no ACME)
CF_Token="${CF_Token:-}"          # for cf_dns (scoped token; not persisted)
CF_Zone_ID="${CF_Zone_ID:-}"      # optional for dns_cf
CF_Account_ID="${CF_Account_ID:-}"# optional for dns_cf

# If you already have certs, set BOTH to enable WS/Hy2 without ACME:
CERT_FULLCHAIN="${CERT_FULLCHAIN:-}"
CERT_KEY="${CERT_KEY:-}"

# Ports (can be overridden by env); will auto-fallback if occupied
REALITY_PORT="${REALITY_PORT:-443}"
WS_PORT="${WS_PORT:-8444}"
HY2_PORT="${HY2_PORT:-8443}"

# Fallback ports if default is occupied
REALITY_PORT_FALLBACK=24443
WS_PORT_FALLBACK=24444
HY2_PORT_FALLBACK=24445

# Reality handshake SNI (large site)
SNI_DEFAULT="${SNI_DEFAULT:-www.cloudflare.com}"

# Certificate install target if ACME is used
CERT_DIR_BASE="${CERT_DIR_BASE:-/etc/ssl/sbx}"

# Allow pinning a specific sing-box version by tag (e.g., v1.9.5); empty => latest
SINGBOX_VERSION="${SINGBOX_VERSION:-}"
# -----------------------------------------------------------

# --------------- Styling & small helpers -------------------
B="$(tput bold 2>/dev/null || true)"; N="$(tput sgr0 2>/dev/null || true)"
G="$(tput setaf 2 2>/dev/null || true)"; Y="$(tput setaf 3 2>/dev/null || true)"; R="$(tput setaf 1 2>/dev/null || true)"
msg(){ echo "${G}[*]${N} $*"; }
warn(){ echo "${Y}[!]${N} $*" >&2; }
err(){ echo "${R}[ERR]${N} $*" >&2; }
die(){ err "$*"; exit 1; }
need_root(){ [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Please run as root (sudo)."; }
have(){ command -v "$1" >/dev/null 2>&1; }

port_in_use() {
  local p="$1"
  ss -lntp 2>/dev/null | grep -q ":$p\\b" && return 0
  lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p\\b" && return 0
  return 1
}
# -----------------------------------------------------------

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

# Build a fallback asset URL if the API asset lookup fails.
build_asset_url_fallback() {
  local tag="$1" arch="$2"
  local ver="${tag#v}"
  echo "https://github.com/SagerNet/sing-box/releases/download/${tag}/sing-box-${ver}-${arch}.tar.gz"
}

download_singbox() {
  if [[ -x "$SB_BIN" ]]; then msg "sing-box exists at $SB_BIN"; return; fi
  local arch; arch="$(detect_arch)"
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local api url tag raw
  if [[ -n "$SINGBOX_VERSION" ]]; then
    tag="$SINGBOX_VERSION"
    api="https://api.github.com/repos/SagerNet/sing-box/releases/tags/${tag}"
  else
    api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  fi

  msg "Fetching sing-box release info for $arch ..."
  if have curl; then raw="$(curl -fsSL "$api")"; else raw="$(wget -qO- "$api")"; fi
  [[ -n "${raw:-}" ]] || die "Failed to query GitHub API."

  if [[ -z "$SINGBOX_VERSION" ]]; then
    tag="$(printf '%s' "$raw" | jq -r .tag_name)"
  fi

  url="$(printf '%s' "$raw" | jq -r --arg a "$arch" '.assets[]? | select(.name|test($a) and endswith(".tar.gz")) | .browser_download_url' | head -1)"
  if [[ -z "$url" || "$url" == "null" ]]; then
    warn "Asset not found in API; falling back to guessed URL pattern."
    url="$(build_asset_url_fallback "$tag" "$arch")"
  fi

  msg "Downloading sing-box package (${tag:-unknown}) ..."
  local pkg="$tmp/sb.tgz"
  if have curl; then curl -fsSL "$url" -o "$pkg"; else wget -qO "$pkg" "$url"; fi

  tar -xzf "$pkg" -C "$tmp"

  local bin
  bin="$(find "$tmp" -type f -name 'sing-box' | head -1)"
  [[ -n "$bin" ]] || die "sing-box binary not found in package"
  install -m 0755 "$bin" "$SB_BIN"
  msg "Installed sing-box -> $SB_BIN"
}

# -------------------- ACME via acme.sh ---------------------
acme_install() {
  [[ -x "$HOME/.acme.sh/acme.sh" ]] && return
  msg "Installing acme.sh ..."
  if have curl; then
    curl -fsSL https://get.acme.sh | sh -s email=admin@"${DOMAIN#*.}" >/dev/null
  else
    wget -qO- https://get.acme.sh | sh -s email=admin@"${DOMAIN#*.}" >/dev/null
  fi
  # shellcheck disable=SC1090
  . "$HOME/.acme.sh/acme.sh.env"
}

acme_issue_cf_dns() {
  [[ -n "${CF_Token:-}" ]] || die "CF_Token is required for CERT_MODE=cf_dns"
  export CF_Token CF_Zone_ID CF_Account_ID
  local ac="$HOME/.acme.sh/acme.sh"
  "$ac" --issue -d "$DOMAIN" --dns dns_cf -k ec-256 --server letsencrypt
  local dir="$CERT_DIR_BASE/$DOMAIN"; mkdir -p "$dir"
  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem"
  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"
}

acme_issue_le_http() {
  port_in_use 80 && die ":80 is in use; stop it or use CERT_MODE=cf_dns"
  local ac="$HOME/.acme.sh/acme.sh"
  "$ac" --issue -d "$DOMAIN" --standalone -k ec-256 --server letsencrypt
  local dir="$CERT_DIR_BASE/$DOMAIN"; mkdir -p "$dir"
  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem"
  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"
}

maybe_issue_cert() {
  # FIX: 先识别“已提供证书”，即使 CERT_MODE 为空也启用
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
    msg "Using provided certificate paths."
    return 0
  fi

  # 需要 ACME 时再执行
  [[ -n "$CERT_MODE" ]] || return 0
  acme_install
  case "$CERT_MODE" in
    cf_dns)  acme_issue_cf_dns ;;
    le_http) acme_issue_le_http ;;
    *) die "Unknown CERT_MODE: $CERT_MODE (cf_dns|le_http)" ;;
  esac
  msg "Certificate installed: $CERT_FULLCHAIN"
}
# -----------------------------------------------------------

# ---------------- Materials & config -----------------------
UUID=""; PRIV=""; PUB=""; SID=""; HY2_PASS=""
REALITY_PORT_CHOSEN=""; WS_PORT_CHOSEN=""; HY2_PORT_CHOSEN=""

gen_materials() {
  [[ -n "$DOMAIN" ]] || read -rp "Enter your domain (DNS only / gray cloud): " DOMAIN
  [[ -n "$DOMAIN" ]] || die "DOMAIN is required (e.g., r.example.com)."

  msg "Generating Reality keypair / UUID / short_id / Hy2 password ..."
  read PRIV PUB < <("$SB_BIN" generate reality-keypair | awk '/PrivateKey:/{p=$2} /PublicKey:/{q=$2} END{print p" "q}')
  [[ -n "$PRIV" && -n "$PUB" ]] || die "Failed to generate Reality keypair"
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SID="$(openssl rand -hex 4)"
  HY2_PASS="$(openssl rand -hex 16)"

  REALITY_PORT_CHOSEN="$REALITY_PORT"
  if port_in_use "$REALITY_PORT_CHOSEN"; then
    warn "Port $REALITY_PORT_CHOSEN in use; switching to $REALITY_PORT_FALLBACK"
    REALITY_PORT_CHOSEN="$REALITY_PORT_FALLBACK"
  fi

  WS_PORT_CHOSEN="$WS_PORT"
  if port_in_use "$WS_PORT_CHOSEN"; then
    warn "WS port $WS_PORT_CHOSEN in use; switching to $WS_PORT_FALLBACK"
    WS_PORT_CHOSEN="$WS_PORT_FALLBACK"
  fi

  HY2_PORT_CHOSEN="$HY2_PORT"
  if port_in_use "$HY2_PORT_CHOSEN"; then
    warn "Hy2 port $HY2_PORT_CHOSEN in use; switching to $HY2_PORT_FALLBACK"
    HY2_PORT_CHOSEN="$HY2_PORT_FALLBACK"
  fi
}

write_config() {
  msg "Writing $SB_CONF ..."
  mkdir -p "$SB_CONF_DIR"
  : >"$SB_CONF"
  {
    echo '{'
    echo '  "log": { "level": "info" },'
    echo '  "inbounds": ['
    local added=0
    add_comma(){ if [[ $added -eq 1 ]]; then echo ','; fi; added=1; }

    # VLESS-REALITY (no cert required)
    add_comma
    cat <<EOF
      {
        "type": "vless",
        "tag": "in-reality",
        "listen": "0.0.0.0",
        "listen_port": $REALITY_PORT_CHOSEN,
        "users": [
          { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
        ],
        "tls": {
          "enabled": true,
          "server_name": "$SNI_DEFAULT",
          "reality": {
            "enabled": true,
            "private_key": "$PRIV",
            "short_id": "$SID",
            "handshake": { "server": "$SNI_DEFAULT", "server_port": 443 }
          },
          "alpn": ["h2","http/1.1"]
        }
      }
EOF

    # VLESS-WS-TLS (enable when cert exists)
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
          "key_path": "$CERT_KEY"
        },
        "transport": { "type": "ws", "path": "/ws" }
      }
EOF

      # Hysteria2 (enable when cert exists)
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
          "key_path": "$CERT_KEY"
        }
      }
EOF
    fi

    echo '  ],'
    echo '  "outbounds": [ { "type": "direct", "tag": "direct" }, { "type": "block", "tag": "block" } ]'
    echo '}'
  } >>"$SB_CONF"
}

setup_service() {
  msg "Creating systemd service ..."
  cat >"$SB_SVC" <<'EOF'
[Unit]
Description=sing-box
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
User=root
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json
  systemctl enable --now sing-box
}

open_firewall() {
  have ufw || return 0
  ufw allow "${REALITY_PORT_CHOSEN}/tcp" || true
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    ufw allow "${WS_PORT_CHOSEN}/tcp" || true
    ufw allow "${HY2_PORT_CHOSEN}/udp" || true
  fi
}

print_summary() {
  echo
  echo "${B}=== sing-box Installed (official) ===${N}"
  echo "Domain    : ${DOMAIN}   (DNS only / 灰云)"
  echo "Binary    : $SB_BIN"
  echo "Config    : $SB_CONF"
  echo "Service   : systemctl status sing-box"
  echo
  echo "INBOUND   : VLESS-REALITY  ${REALITY_PORT_CHOSEN}/tcp"
  echo "  PublicKey = ${PUB}"
  echo "  Short ID  = ${SID}"
  echo "  UUID      = ${UUID}"
  local uri_real="vless://${UUID}@${DOMAIN}:${REALITY_PORT_CHOSEN}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI_DEFAULT}&pbk=${PUB}&sid=${SID}&type=tcp&fp=chrome"
  echo "  URI       = ${uri_real}"
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    echo
    echo "INBOUND   : VLESS-WS-TLS   ${WS_PORT_CHOSEN}/tcp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_ws="vless://${UUID}@${DOMAIN}:${WS_PORT_CHOSEN}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome"
    echo "  URI      = ${uri_ws}"
    echo
    echo "INBOUND   : Hysteria2      ${HY2_PORT_CHOSEN}/udp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_hy2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT_CHOSEN}/?sni=${DOMAIN}&alpn=h3&insecure=0"
    echo "  URI      = ${uri_hy2}"
  fi
  echo
  echo "${Y}Notes${N}: Reality/Hy2 需灰云；WS-TLS 可灰/橙云。DNS-01 推荐；HTTP-01 需 :80 可达且未被占用。"
}

install_flow() {
  need_root
  [[ -n "$DOMAIN" ]] || die "Please set DOMAIN=your.graycloud.domain"
  ensure_tools
  download_singbox
  gen_materials
  # 如提供证书或指定 ACME，处理证书
  if [[ -n "$CERT_MODE" || ( -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ) ]]; then
    maybe_issue_cert
  fi
  write_config
  setup_service
  open_firewall
  print_summary
}

uninstall_flow() {
  need_root
  if [[ "${FORCE:-0}" != "1" ]]; then
    read -rp "This will stop service and remove sing-box + config. Continue? [y/N] " a
    [[ "${a:-N}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  fi
  systemctl disable --now sing-box 2>/dev/null || true
  rm -f "$SB_SVC"; systemctl daemon-reload || true
  rm -f "$SB_BIN"
  rm -rf "$SB_CONF_DIR"
  msg "Uninstalled."
}

case "${1:-install}" in
  install)   install_flow ;;
  uninstall) uninstall_flow ;;
  *) die "Usage: $0 [install|uninstall]" ;;
esac
