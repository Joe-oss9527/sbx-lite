#!/usr/bin/env bash
set -euo pipefail
systemctl disable sbx-panel --now || true
systemctl disable sing-box --now || true
rm -f /etc/systemd/system/sbx-panel.service /etc/systemd/system/sing-box.service
systemctl daemon-reload
rm -rf /opt/sbx
echo "[*] sbx-lite removed."
