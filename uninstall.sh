#!/usr/bin/env bash
set -euo pipefail

# sbx-lite uninstaller
# Default: remove sbx-lite panel/scripts/config only.
# Optional: --remove-singbox to also remove sing-box binary, service and /etc/sing-box

REMOVE_SINGBOX=0
if [[ "${1:-}" == "--remove-singbox" ]]; then
  REMOVE_SINGBOX=1
fi

echo "[1/5] Stop & disable sbx-panel.service (if present)..."
if systemctl list-unit-files | grep -q '^sbx-panel.service'; then
  systemctl stop sbx-panel.service || true
  systemctl disable sbx-panel.service || true
  rm -f /etc/systemd/system/sbx-panel.service
  systemctl daemon-reload || true
fi

echo "[2/5] Remove sbx-lite files..."
rm -rf /opt/sbx/panel /opt/sbx/scripts /var/log/sbx /etc/sbx

echo "[3/5] (optional) Remove sing-box (binary, service, config) ..."
if [[ $REMOVE_SINGBOX -eq 1 ]]; then
  systemctl stop sing-box || true
  systemctl disable sing-box || true
  rm -f /etc/systemd/system/sing-box.service
  systemctl daemon-reload || true
  # Remove binary and config
  BIN="$(command -v sing-box || true)"
  if [[ -n "$BIN" ]]; then
    rm -f "$BIN"
  fi
  rm -rf /etc/sing-box
fi

echo "[4/5] Cleanup residual npm cache (optional)..."
npm cache clean --force >/dev/null 2>&1 || true

echo "[5/5] Done."
echo "sbx-lite removed. sing-box removed: $REMOVE_SINGBOX"
