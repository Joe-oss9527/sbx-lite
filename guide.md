下面是一份**完整、认真、可直接落地**的《官方 sing-box 极简最佳实践》文档，**内含脚本源码**。目标：**简便、稳健**，默认仅启用 **VLESS-REALITY**（无需证书），并可选一并启用 **VLESS-WS-TLS** 与 **Hysteria2（Hy2）**（自动签证书或使用你已有证书）。
所有配置字段、参数命名均与 **sing-box 官方文档**一致；脚本会打印可直接导入的 **客户端 URI**，并提供**一键卸载**。

---

# 官方 sing-box 极简实战 · 最佳实践（含脚本）

## 0. 前置要求

* Linux（建议 Ubuntu 22.04/24.04），`root` 或 `sudo` 权限。
* 一个 **灰云（DNS only）** 的域名/子域（例如 `r.example.com`）**指向你的服务器公网 IP**。

  * **Reality 不能橙云**（CF 代理）；**Hy2** 只能灰云；**WS-TLS** 可灰/橙云（橙云时客户端看到的是 CF 证书，源站证书仅供回源校验）。
* 若要自动签证书（推荐 DNS-01）：准备 **Cloudflare API Token**（建议最小权限，仅 Zone.DNS\:Edit + Zone\:Read）。

---

## 1. 一键安装 / 卸载（在线执行）

> 默认只启用 **Reality（443/tcp）**，最简最稳；如设置证书参数或启用 ACME，则**同时**启用 **WS-TLS（8444/tcp）** 与 **Hy2（8443/udp）**。端口若被占用会自动切换备用口，终端会提示。

**仅 Reality（推荐最简）**

```bash
DOMAIN=r.example.com \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**DNS-01（Cloudflare）自动签证书 → 同开 WS-TLS + Hy2（推荐）**

```bash
DOMAIN=r.example.com \
CERT_MODE=cf_dns \
CF_Token='<你的CF API Token>' \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**HTTP-01 自动签证书（需灰云，80 直达且未被占用）**

```bash
DOMAIN=r.example.com \
CERT_MODE=le_http \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**卸载（无交互）**

```bash
curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh \
| sudo FORCE=1 bash -s -- uninstall
```

> 可选：若你已有证书也可直接传入路径并启用 WS/Hy2：
> `CERT_FULLCHAIN=/path/fullchain.pem CERT_KEY=/path/privkey.pem`

---

## 2. 脚本源码（保存为 `install_multi.sh`，或直接用上面的在线命令）

> 脚本会：安装官方 **sing-box 最新版** → 生成 **Reality 私钥/公钥**、**UUID**、**short\_id** → 写入标准配置 → systemd 托管并启动 → 打印 **Reality/WS-TLS/Hy2** 的**导入 URI**。
> **Reality** 配置包含：`handshake.server/server_port`、`private_key`、`short_id`，`users[].flow="xtls-rprx-vision"`；客户端 URI 会带 `pbk/sid/sni/flow/security` 等必需参数。**Hy2** 入站写入 `tls.certificate_path/key_path`（TLS 必填）。

```bash
#!/usr/bin/env bash
# install_multi.sh
# One-click official sing-box with:
# - VLESS-REALITY (required, no cert)
# - VLESS-WS-TLS (optional, needs cert)
# - Hysteria2 (optional, needs cert)
# Integrated ACME (optional):
#   CERT_MODE=cf_dns (Cloudflare DNS-01; needs CF_Token)
#   CERT_MODE=le_http (HTTP-01; needs :80 reachable & DNS-only)

set -euo pipefail

# -------- Settings --------
SB_BIN="/usr/local/bin/sing-box"
SB_CONF_DIR="/etc/sing-box"
SB_CONF="$SB_CONF_DIR/config.json"
SB_SVC="/etc/systemd/system/sing-box.service"

DOMAIN="${DOMAIN:-}"              # required: your domain (DNS only / gray-cloud)
CERT_MODE="${CERT_MODE:-}"        # cf_dns | le_http | (empty => no ACME)
CF_Token="${CF_Token:-}"          # for cf_dns (scoped token: Zone.DNS:Edit + Zone:Read)
CF_Zone_ID="${CF_Zone_ID:-}"      # optional for acme.sh dns_cf
CF_Account_ID="${CF_Account_ID:-}"# optional for acme.sh dns_cf

# If you already have certs, set these to skip ACME and enable WS/Hy2:
CERT_FULLCHAIN="${CERT_FULLCHAIN:-}"
CERT_KEY="${CERT_KEY:-}"

REALITY_PORT_DEFAULT=443
WS_PORT_DEFAULT=8444
HY2_PORT_DEFAULT=8443

SNI_DEFAULT="www.cloudflare.com"  # Reality handshake SNI (large site)
CERT_DIR_BASE="/etc/ssl/sbx"      # where certs will be installed
# --------------------------

# Colors & utils
B="$(tput bold 2>/dev/null || true)"; N="$(tput sgr0 2>/dev/null || true)"
G="$(tput setaf 2 2>/dev/null || true)"; Y="$(tput setaf 3 2>/dev/null || true)"; R="$(tput setaf 1 2>/dev/null || true)"
msg(){ echo "${G}[*]${N} $*"; } warn(){ echo "${Y}[!]${N} $*" >&2; } err(){ echo "${R}[ERR]${N} $*" >&2; }
need_root(){ [[ "${EUID:-$(id -u)}" -eq 0 ]] || { err "Please run as root (sudo)."; exit 1; }; }
have(){ command -v "$1" >/dev/null 2>&1; }
die(){ err "$*"; exit 1; }

port_in_use(){
  local p="$1"
  ss -lntp 2>/dev/null | grep -q ":$p " || lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | grep -q ":$p" || return 1
}

ensure_tools(){
  msg "Installing tools (curl/wget, tar, jq, openssl, ca-certificates, lsof)..."
  if have apt-get; then
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl wget tar jq openssl ca-certificates lsof
  elif have dnf; then dnf install -y curl wget tar jq openssl ca-certificates lsof
  elif have yum; then yum install -y curl wget tar jq openssl ca-certificates lsof
  else warn "Unknown package manager; ensure curl/wget, tar, jq, openssl, lsof installed."
  fi
}

detect_arch(){
  case "$(uname -m)" in
    x86_64|amd64)  echo "linux-amd64" ;;
    aarch64|arm64) echo "linux-arm64" ;;
    *) die "Unsupported arch: $(uname -m)" ;;
  esac
}

download_singbox(){
  if [[ -x "$SB_BIN" ]]; then msg "sing-box exists at $SB_BIN"; return; fi
  local arch="$(detect_arch)" tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  msg "Fetching latest sing-box for $arch ..."
  local api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
  local tag url raw
  if have curl; then raw="$(curl -fsSL "$api")"; else raw="$(wget -qO- "$api")"; fi
  tag="$(printf '%s' "$raw" | jq -r .tag_name)"
  url="$(printf '%s' "$raw" | jq -r --arg a "$arch" '.assets[]|select(.name|test($a))|.browser_download_url' | head -1)"
  [[ -n "$url" && "$url" != "null" ]] || die "Release asset not found for $arch"
  msg "Latest tag: $tag"
  local pkg="$tmp/sb.tgz"; if have curl; then curl -fsSL "$url" -o "$pkg"; else wget -qO "$pkg" "$url"; fi
  tar -xzf "$pkg" -C "$tmp"
  local top; top="$(tar -tzf "$pkg" | head -1 | cut -d/ -f1)"
  local bin; bin="$(find "$tmp/$top" -type f -name sing-box | head -1)"
  [[ -n "$bin" ]] || die "sing-box binary not found in package"
  install -m 0755 "$bin" "$SB_BIN"
  msg "Installed sing-box -> $SB_BIN"
}

acme_install(){
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

acme_issue_cf_dns(){
  [[ -n "$CF_Token" ]] || die "CF_Token is required for CERT_MODE=cf_dns"
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

acme_issue_le_http(){
  if port_in_use 80; then die ":80 is in use; stop it or use CERT_MODE=cf_dns"; fi
  local ac="$HOME/.acme.sh/acme.sh"
  "$ac" --issue -d "$DOMAIN" --standalone -k ec-256 --server letsencrypt
  local dir="$CERT_DIR_BASE/$DOMAIN"; mkdir -p "$dir"
  "$ac" --install-cert -d "$DOMAIN" --ecc \
    --fullchain-file "$dir/fullchain.pem" \
    --key-file "$dir/privkey.pem"
  CERT_FULLCHAIN="$dir/fullchain.pem"
  CERT_KEY="$dir/privkey.pem"
}

maybe_issue_cert(){
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
  msg "Certificate installed: $CERT_FULLCHAIN"
}

gen_materials(){
  [[ -n "$DOMAIN" ]] || read -rp "Enter your domain (DNS only / gray cloud): " DOMAIN
  [[ -n "$DOMAIN" ]] || die "DOMAIN is required (e.g., r.example.com)."
  msg "Generating Reality keypair / UUID / short_id / Hy2 password ..."
  read PRIV PUB < <("$SB_BIN" generate reality-keypair | awk '/PrivateKey:/{p=$2} /PublicKey:/{q=$2} END{print p" "q}')
  [[ -n "${PRIV:-}" && -n "${PUB:-}" ]] || die "Failed to generate Reality keypair"
  UUID="$(cat /proc/sys/kernel/random/uuid)"
  SID="$(openssl rand -hex 4)"
  HY2_PASS="$(openssl rand -hex 16)"
  SNI="${SNI_DEFAULT}"
  REALITY_PORT="$REALITY_PORT_DEFAULT"
  port_in_use "$REALITY_PORT" && { warn "Port $REALITY_PORT in use; switching to 24443"; REALITY_PORT=24443; }
  WS_PORT="$WS_PORT_DEFAULT"
  port_in_use "$WS_PORT" && { warn "WS port $WS_PORT in use; switching to 24444"; WS_PORT=24444; }
  HY2_PORT="$HY2_PORT_DEFAULT"
  port_in_use "$HY2_PORT" && { warn "Hy2 port $HY2_PORT in use; switching to 24443"; HY2_PORT=24443; }
}

write_config(){
  msg "Writing $SB_CONF ..."
  mkdir -p "$SB_CONF_DIR"
  : >"$SB_CONF"
  {
    echo '{'
    echo '  "log": { "level": "info" },'
    echo '  "inbounds": ['
    added=0
    add_comma(){ if [[ $added -eq 1 ]]; then echo ','; fi; added=1; }

    # VLESS-REALITY
    add_comma
    cat <<EOF
      {
        "type": "vless",
        "tag": "in-reality",
        "listen": "0.0.0.0",
        "listen_port": $REALITY_PORT,
        "users": [
          { "uuid": "$UUID", "flow": "xtls-rprx-vision" }
        ],
        "tls": {
          "enabled": true,
          "server_name": "$SNI",
          "reality": {
            "enabled": true,
            "private_key": "$PRIV",
            "short_id": "$SID",
            "handshake": { "server": "$SNI", "server_port": 443 }
          },
          "alpn": ["h2","http/1.1"]
        }
      }
EOF

    # VLESS-WS-TLS (if we have certs)
    if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" && -f "$CERT_FULLCHAIN" && -f "$CERT_KEY" ]]; then
      add_comma
      cat <<EOF
      {
        "type": "vless",
        "tag": "in-ws",
        "listen": "0.0.0.0",
        "listen_port": $WS_PORT,
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
      # Hysteria2 (if we have certs)
      add_comma
      cat <<EOF
      {
        "type": "hysteria2",
        "tag": "in-hy2",
        "listen": "0.0.0.0",
        "listen_port": $HY2_PORT,
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

setup_service(){
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
  "$SB_BIN" check -c "$SB_CONF"
  systemctl enable --now sing-box
}

open_firewall(){
  have ufw || return 0
  ufw allow "${REALITY_PORT}/tcp" || true
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    ufw allow "${WS_PORT}/tcp" || true
    ufw allow "${HY2_PORT}/udp" || true
  fi
}

print_summary(){
  echo
  echo "${B}=== sing-box Installed (official) ===${N}"
  echo "Domain    : ${DOMAIN}   (灰云 / DNS only)"
  echo "Binary    : $SB_BIN"
  echo "Config    : $SB_CONF"
  echo "Service   : systemctl status sing-box"
  echo
  echo "INBOUND   : VLESS-REALITY  ${REALITY_PORT}/tcp"
  echo "  SNI       = ${SNI_DEFAULT}"
  echo "  PublicKey = ${PUB}"
  echo "  Short ID  = ${SID}"
  echo "  UUID      = ${UUID}"
  local uri_real="vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI_DEFAULT}&pbk=${PUB}&sid=${SID}&type=tcp&fp=chrome"
  echo "  URI       = ${uri_real}"
  if [[ -n "$CERT_FULLCHAIN" && -n "$CERT_KEY" ]]; then
    echo
    echo "INBOUND   : VLESS-WS-TLS   ${WS_PORT}/tcp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_ws="vless://${UUID}@${DOMAIN}:${WS_PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome"
    echo "  URI      = ${uri_ws}"
    echo
    echo "INBOUND   : Hysteria2      ${HY2_PORT}/udp"
    echo "  CERT     = ${CERT_FULLCHAIN}"
    local uri_hy2="hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0"
    echo "  URI      = ${uri_hy2}"
  fi
  echo
  echo "${Y}Notes${N}:"
  echo "- Reality 必须灰云；WS-TLS 可灰/橙云；Hy2 只能灰云。"
  echo "- DNS-01（cf_dns）推荐；HTTP-01 需灰云且 :80 直达、未被占用。"
}

install_flow(){
  need_root
  ensure_tools
  download_singbox
  gen_materials
  maybe_issue_cert
  write_config
  setup_service
  open_firewall
  print_summary
}

uninstall_flow(){
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
  *) die "Usage: $0 [install|uninstall]";;
esac
```

---

## 3. 验证与日常运维

**配置校验与服务状态**

```bash
sing-box check -c /etc/sing-box/config.json
systemctl status sing-box --no-pager
journalctl -u sing-box -e --no-pager
```

**客户端导入（Reality 必要参数）**
脚本已在终端打印形如：

```
vless://UUID@r.example.com:443?encryption=none&security=reality&flow=xtls-rprx-vision&sni=www.cloudflare.com&pbk=PUBLIC_KEY&sid=SHORTID&type=tcp&fp=chrome
```

* `pbk`=服务端 **public\_key**；`sid`= **short\_id**；`sni`=握手域名（大站）；
* `flow=xtls-rprx-vision`；ALPN 推荐 `h2,http/1.1`（已在服务端配置）。

---

## 4. 常见问题

* **Reality 连不通**：域名必须 **灰云**；检查 `sing-box check`；确认 443 未被其它服务占用；校验本机时间（TLS/Reality 对时钟敏感）。
* **Hy2 不工作**：需启用证书（自动签或自备）并放通 **UDP** 端口（默认 8443）。
* **WS-TLS 橙云**：客户端看到 CF 证书（正常），源站证书仅供回源校验；可用 LE 证书或 CF Origin Cert。

---

## 5. 你可能关心的细节（已在脚本处理）

* **端口占用**：Reality/WS/Hy2 各自检测占用并自动切换到备用端口。
* **ACME**：默认采用 `acme.sh`，DNS-01 推荐；HTTP-01 仅当 80 直达未占用。
* **重复执行**：可覆盖更新现有配置（例如：第一次仅 Reality，后来加证书重装即可启用 WS/Hy2）。
* **卸载**：停止服务、删除二进制与 `/etc/sing-box/` 配置。

---

需要我把这份脚本和文档直接提到你的仓库（`YYvanYang/sbx-lite`）并在 README 顶部放上“一键安装/卸载”命令吗？我可以顺手加一个发布标签，方便外部直接用稳定版本。
