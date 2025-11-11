#!/usr/bin/env bash
# lib/export.sh - Client configuration export functionality
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_EXPORT_LOADED:-}" ]] && return 0
readonly _SBX_EXPORT_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${_LIB_DIR}/common.sh"

#==============================================================================
# Configuration Loading
#==============================================================================

# Load client info from saved configuration
load_client_info() {
  [[ -f "$CLIENT_INFO" ]] || die "Client info not found. Run: sbx info"
  # shellcheck source=/dev/null
  source "$CLIENT_INFO"

  # Set defaults for missing variables to ensure valid URIs
  REALITY_PORT="${REALITY_PORT:-443}"
  SNI="${SNI:-www.microsoft.com}"
  WS_PORT="${WS_PORT:-8444}"
  HY2_PORT="${HY2_PORT:-8443}"
}

#==============================================================================
# v2rayN/v2rayNG Configuration Export
#==============================================================================

# Generate v2rayN/v2rayNG JSON configuration
export_v2rayn_json() {
  local protocol="${1:-reality}"
  load_client_info

  local config=""
  case "$protocol" in
    reality)
      config=$(cat <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 10808,
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$DOMAIN",
        "port": $REALITY_PORT,
        "users": [{
          "id": "$UUID",
          "encryption": "none",
          "flow": "xtls-rprx-vision"
        }]
      }]
    },
    "streamSettings": {
      "network": "tcp",
      "security": "reality",
      "realitySettings": {
        "serverName": "$SNI",
        "publicKey": "$PUBLIC_KEY",
        "shortId": "$SHORT_ID",
        "fingerprint": "chrome"
      }
    }
  }]
}
EOF
)
      ;;
    ws)
      [[ -n "$WS_PORT" ]] || die "WS-TLS not configured"
      config=$(cat <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [{
    "port": 10808,
    "protocol": "socks",
    "settings": { "udp": true }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "$DOMAIN",
        "port": $WS_PORT,
        "users": [{
          "id": "$UUID",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "wsSettings": {
        "path": "/ws",
        "headers": { "Host": "$DOMAIN" }
      },
      "tlsSettings": {
        "serverName": "$DOMAIN",
        "fingerprint": "chrome"
      }
    }
  }]
}
EOF
)
      ;;
    *)
      die "Invalid protocol: $protocol"
      ;;
  esac

  echo "$config"
}

#==============================================================================
# Clash/Clash Meta Configuration Export
#==============================================================================

# Generate Clash/Clash Meta YAML configuration
export_clash_yaml() {
  load_client_info

  cat <<EOF
proxies:
  - name: "sbx-reality-$DOMAIN"
    type: vless
    server: $DOMAIN
    port: $REALITY_PORT
    uuid: $UUID
    flow: xtls-rprx-vision
    network: tcp
    tls: true
    reality-opts:
      public-key: $PUBLIC_KEY
      short-id: $SHORT_ID
    client-fingerprint: chrome
    servername: $SNI
EOF

  if [[ -n "$WS_PORT" && -n "$CERT_FULLCHAIN" ]]; then
    cat <<EOF

  - name: "sbx-ws-$DOMAIN"
    type: vless
    server: $DOMAIN
    port: $WS_PORT
    uuid: $UUID
    tls: true
    network: ws
    ws-opts:
      path: /ws
      headers:
        Host: $DOMAIN
    servername: $DOMAIN
    client-fingerprint: chrome

  - name: "sbx-hysteria2-$DOMAIN"
    type: hysteria2
    server: $DOMAIN
    port: $HY2_PORT
    password: $HY2_PASS
    sni: $DOMAIN
    skip-cert-verify: false
EOF
  fi

  cat <<EOF

proxy-groups:
  - name: "sbx-lite"
    type: select
    proxies:
      - "sbx-reality-$DOMAIN"
EOF

  if [[ -n "$WS_PORT" ]]; then
    cat <<EOF
      - "sbx-ws-$DOMAIN"
      - "sbx-hysteria2-$DOMAIN"
EOF
  fi
}

#==============================================================================
# URI Export
#==============================================================================

# Export configuration as share URIs
export_uri() {
  local protocol="${1:-all}"
  load_client_info

  case "$protocol" in
    reality)
      echo "vless://${UUID}@${DOMAIN}:${REALITY_PORT}?encryption=none&security=reality&flow=xtls-rprx-vision&sni=${SNI}&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&fp=chrome#Reality-${DOMAIN}"
      ;;
    ws)
      [[ -n "$WS_PORT" ]] || die "WS-TLS not configured"
      echo "vless://${UUID}@${DOMAIN}:${WS_PORT}?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=/ws&sni=${DOMAIN}&fp=chrome#WS-TLS-${DOMAIN}"
      ;;
    hysteria2|hy2)
      [[ -n "$HY2_PORT" ]] || die "Hysteria2 not configured"
      echo "hysteria2://${HY2_PASS}@${DOMAIN}:${HY2_PORT}/?sni=${DOMAIN}&alpn=h3&insecure=0#Hysteria2-${DOMAIN}"
      ;;
    all)
      export_uri reality
      [[ -n "$WS_PORT" ]] && export_uri ws
      [[ -n "$HY2_PORT" ]] && export_uri hy2
      ;;
    *)
      die "Invalid protocol: $protocol (use: reality, ws, hy2, all)"
      ;;
  esac
}

#==============================================================================
# QR Code Export
#==============================================================================

# Generate QR codes for configuration
export_qr_codes() {
  local output_dir="${1:-./qr-codes}"
  load_client_info

  command -v qrencode >/dev/null || die "qrencode not installed. Install with: apt install qrencode"

  mkdir -p "$output_dir"

  # Reality QR
  local reality_uri
  reality_uri=$(export_uri reality)
  qrencode -t PNG -o "$output_dir/reality-qr.png" "$reality_uri"
  qrencode -t UTF8 -o "$output_dir/reality-qr.txt" "$reality_uri"
  success "  ✓ Reality QR code: $output_dir/reality-qr.png"

  if [[ -n "$WS_PORT" ]]; then
    # WS-TLS QR
    local ws_uri
    ws_uri=$(export_uri ws)
    qrencode -t PNG -o "$output_dir/ws-qr.png" "$ws_uri"
    success "  ✓ WS-TLS QR code: $output_dir/ws-qr.png"

    # Hysteria2 QR
    local hy2_uri
    hy2_uri=$(export_uri hy2)
    qrencode -t PNG -o "$output_dir/hy2-qr.png" "$hy2_uri"
    success "  ✓ Hysteria2 QR code: $output_dir/hy2-qr.png"
  fi

  info "QR codes saved to: $output_dir"
}

#==============================================================================
# Subscription Link Export
#==============================================================================

# Generate subscription link (Base64 encoded URIs)
export_subscription() {
  local output_file="${1:-/var/www/html/sub.txt}"
  load_client_info

  local uris=""

  # Reality URI
  uris+=$(export_uri reality)

  if [[ -n "$WS_PORT" ]]; then
    uris+=$'\n'$(export_uri ws)
    uris+=$'\n'$(export_uri hy2)
  fi

  # Base64 encode
  local subscription
  subscription=$(echo -n "$uris" | base64 -w 0)

  # Save to file
  mkdir -p "$(dirname "$output_file")"
  echo "$subscription" > "$output_file"
  chmod 644 "$output_file"

  success "Subscription link generated: $output_file"

  # Display access URL if web server detected
  if systemctl is-active nginx >/dev/null 2>&1 || systemctl is-active apache2 >/dev/null 2>&1; then
    local sub_url
    sub_url="http://${DOMAIN}/$(basename "$output_file")"
    info "Subscription URL: $sub_url"
  fi
}

#==============================================================================
# Main Export Dispatcher
#==============================================================================

# Main export function
export_config() {
  local client="${1:-}"
  local protocol="${2:-reality}"
  local output_file="${3:-}"

  case "$client" in
    v2rayn|v2rayng)
      local config
      config=$(export_v2rayn_json "$protocol")
      ;;
    clash|clash-meta)
      local config
      config=$(export_clash_yaml)
      ;;
    uri)
      local config
      config=$(export_uri "$protocol")
      ;;
    subscription|sub)
      export_subscription "$output_file"
      return 0
      ;;
    qr)
      export_qr_codes "$output_file"
      return 0
      ;;
    *)
      die "Unsupported client: $client. Use: v2rayn, clash, uri, subscription, qr"
      ;;
  esac

  # Output to file or stdout
  if [[ -n "$output_file" ]]; then
    echo "$config" > "$output_file"
    success "Configuration exported to: $output_file"
  else
    echo "$config"
  fi
}

#==============================================================================
# Export Functions
#==============================================================================

export -f load_client_info export_v2rayn_json export_clash_yaml
export -f export_uri export_qr_codes export_subscription export_config
