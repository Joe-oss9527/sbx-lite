#!/usr/bin/env bash
set -euo pipefail

ROOT=/opt/sbx
mkdir -p $ROOT
cp -r panel scripts systemd config $ROOT/

# prerequisites
if ! command -v sing-box >/dev/null 2>&1; then
  echo "[*] installing sing-box from apt (you may replace with your source)"
  apt-get update && apt-get install -y sing-box || true
fi

if ! command -v node >/dev/null 2>&1; then
  echo "[*] installing nodejs"
  apt-get update && apt-get install -y nodejs npm
fi

# config
mkdir -p /etc/sbx /etc/sing-box
if [ ! -f /etc/sbx/sbx.yml ]; then
  cp config/sbx.yml /etc/sbx/sbx.yml
fi

# panel deps
cd $ROOT/panel
npm install --omit=dev

# systemd
cp $ROOT/systemd/sbx-panel.service /etc/systemd/system/sbx-panel.service
cp $ROOT/systemd/sing-box.service /etc/systemd/system/sing-box.service
systemctl daemon-reload
systemctl enable sbx-panel --now
systemctl enable sing-box --now || true

# cli
install -m 0755 $ROOT/scripts/sbxctl /usr/local/bin/sbxctl
install -m 0755 $ROOT/scripts/diagnose.sh /usr/local/bin/sbx-diagnose

echo "[*] Installation finished."
echo "Panel password is shown on: curl http://127.0.0.1:7789 (via SSH tunnel)"
