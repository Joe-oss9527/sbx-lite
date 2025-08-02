#!/usr/bin/env bash
set -euo pipefail
umask 027

on_err() {
  echo "[ERROR] Install failed at step: ${STEP:-unknown}" >&2
  echo "See logs above. Fix the issue and re-run." >&2
}
trap on_err ERR

# OS check: Ubuntu 22.04/24.04 only
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
fi
if [[ "${ID:-}" != "ubuntu" || ! "${VERSION_ID:-}" =~ ^(22\.04|24\.04)$ ]]; then
  echo "Supported OS: Ubuntu 22.04/24.04. Detected: ${ID:-?} ${VERSION_ID:-?}" >&2
  exit 1
fi


# sbx-lite installer: Ubuntu 22.04/24.04 assumed
# - Installs official sing-box
# - Installs Node.js (from apt) + panel
# - Sets up /etc/sbx/sbx.yml and generates keys
# - Creates systemd service: sbx-panel
# - Leaves panel bound to 127.0.0.1:7789 (use SSH tunnel or reverse proxy if needed)

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root." >&2
  exit 1
fi

STEP="apt deps"
echo "[1/9] Updating packages..."
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y curl ca-certificates jq ufw nodejs npm

echo "[2/9] Installing sing-box (official)..."
curl -fsSL https://sing-box.app/install.sh | bash

STEP="dirs"
echo "[3/9] Creating directories..."
install -d -m 0750 /etc/sbx
install -d -m 0755 /opt/sbx/panel
install -d -m 0755 /var/log/sbx
install -d -m 0755 /etc/ssl/cf

# Copy project files if running from a checked-out workspace
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$SRC_DIR/panel" ]]; then
  cp -a "$SRC_DIR/panel/." /opt/sbx/panel/
fi
if [[ -d "$SRC_DIR/scripts" ]]; then
  install -d -m 0755 /opt/sbx/scripts
  cp -a "$SRC_DIR/scripts/." /opt/sbx/scripts/
fi
if [[ -d "$SRC_DIR/systemd" ]]; then
  cp -a "$SRC_DIR/systemd/." /etc/systemd/system/
fi
if [[ -d "$SRC_DIR/config" ]]; then
  cp -a "$SRC_DIR/config/." /etc/sbx/
fi

STEP="npm install"
echo "[4/9] Installing panel dependencies..."
cd /opt/sbx/panel
if ! npm install --omit=dev; then echo "npm install failed." >&2; exit 1; fi

# Ensure default config exists
if [[ ! -f /etc/sbx/sbx.yml ]]; then
  cp /opt/sbx/panel/default.sbx.yml /etc/sbx/sbx.yml
fi

echo "[5/9] Generating credentials and defaults..."
UUID=$(sing-box generate uuid | tr -d '\r\n')
REALITY_KEYS=$(sing-box generate reality-keypair)
PRIVATE_KEY=$(echo "$REALITY_KEYS" | awk '/PrivateKey/{print $2}')
PUBLIC_KEY=$(echo "$REALITY_KEYS" | awk '/PublicKey/{print $2}')
SHORT_ID=$(sing-box generate rand 8 --hex | tr -d '\r\n')

# Random admin password
ADMIN_PASS=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)

# Patch sbx.yml placeholders if present
sed -i "s#uuid: \"GENERATE\"#uuid: \"$UUID\"#g" /etc/sbx/sbx.yml
sed -i "s#private_key: \"GENERATE\"#private_key: \"$PRIVATE_KEY\"#g" /etc/sbx/sbx.yml
sed -i "s#public_key: \"\"#public_key: \"$PUBLIC_KEY\"#g" /etc/sbx/sbx.yml
sed -i "s#short_id: \"GENERATE8\"#short_id: \"$SHORT_ID\"#g" /etc/sbx/sbx.yml
# --- Default two users
USER1_UUID=$(sing-box generate uuid | tr -d '\r\n')
USER2_UUID=$(sing-box generate uuid | tr -d '\r\n')
USER1_TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
USER2_TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
USER1_HY2=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
USER2_HY2=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
sed -i "s#vless_uuid: \\"GENERATE_UUID1\\"#vless_uuid: \\"$USER1_UUID\\"#g" /etc/sbx/sbx.yml
sed -i "s#token: \\"GENERATE_TOKEN1\\"#token: \\"$USER1_TOKEN\\"#g" /etc/sbx/sbx.yml
sed -i "s#hy2_pass: \\"GENERATE_PASS1\\"#hy2_pass: \\"$USER1_HY2\\"#g" /etc/sbx/sbx.yml
sed -i "s#vless_uuid: \\"GENERATE_UUID2\\"#vless_uuid: \\"$USER2_UUID\\"#g" /etc/sbx/sbx.yml
sed -i "s#token: \\"GENERATE_TOKEN2\\"#token: \\"$USER2_TOKEN\\"#g" /etc/sbx/sbx.yml
sed -i "s#hy2_pass: \\"GENERATE_PASS2\\"#hy2_pass: \\"$USER2_HY2\\"#g" /etc/sbx/sbx.yml

# --- Public IP auto-detect (fill export.host only if still placeholder)
PUBIP=$(curl -4 -fsS ifconfig.co || curl -4 -fsS api.ipify.org || true)
if [[ -n "${PUBIP}" ]]; then
  if grep -q 'host: \"YOUR_PUBLIC_HOST\"' /etc/sbx/sbx.yml; then
    sed -i "s#host: \\"YOUR_PUBLIC_HOST\\"#host: \\"${PUBIP}\\"#g" /etc/sbx/sbx.yml
  fi
fi

# Default user credentials
USER_UUID=$(sing-box generate uuid | tr -d '\r\n')
USER_TOKEN=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 24)
USER_HY2=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 20)
# Fill default user1
sed -i "s#vless_uuid: \"GENERATE_UUID\"#vless_uuid: \"$USER_UUID\"#g" /etc/sbx/sbx.yml
sed -i "s#token: \"GENERATE_TOKEN\"#token: \"$USER_TOKEN\"#g" /etc/sbx/sbx.yml
sed -i "s#hy2_pass: \"GENERATE_PASS\"#hy2_pass: \"$USER_HY2\"#g" /etc/sbx/sbx.yml


echo "ADMIN_PASS=$ADMIN_PASS" > /etc/sbx/panel.env
chmod 600 /etc/sbx/panel.env

echo "[6/9] Creating systemd service for panel..."
cat >/etc/systemd/system/sbx-panel.service <<'UNIT'
[Unit]
Description=sbx-lite panel
After=network.target

[Service]
Type=simple
EnvironmentFile=-/etc/sbx/panel.env
ExecStart=/usr/bin/node /opt/sbx/panel/server.js
WorkingDirectory=/opt/sbx/panel
Restart=on-failure
# Bind to localhost only by default
Environment=SBX_BIND=127.0.0.1
Environment=SBX_PORT=7789

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload

echo "[7/9] Generating initial sing-box config.json from sbx.yml..."
node /opt/sbx/panel/gen-config.js || true

echo "[8/9] Enabling services..."
systemctl enable --now sing-box || true
systemctl enable --now sbx-panel

echo "[9/9] Firewall (optional): allowing 443/tcp and 8443/udp if ufw is active..."
if ufw status | grep -q "Status: active"; then
  ufw allow 443/tcp || true
  ufw allow 8443/udp || true
fi

echo "== Done =="
echo "Panel: http://127.0.0.1:7789 (local only)."
echo "Admin password is stored at /etc/sbx/panel.env"
echo "Recommended: use SSH port forwarding from your laptop:"
echo "  ssh -N -L 7789:127.0.0.1:7789 root@YOUR_SERVER"


echo "[9/9] Post-install smoke tests..."
# Node syntax check
node -e "new Function(require('fs').readFileSync('/opt/sbx/panel/server.js','utf8'))" || { echo "server.js syntax error"; exit 1; }
node -e "new Function(require('fs').readFileSync('/opt/sbx/panel/gen-config.js','utf8'))" || { echo "gen-config syntax error"; exit 1; }
# Generate config & check
node /opt/sbx/panel/gen-config.js || { echo "gen-config failed"; exit 1; }
sing-box check -c /etc/sing-box/config.json || { echo "sing-box check failed"; exit 1; }

echo "Install complete."
