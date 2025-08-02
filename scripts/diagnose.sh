#!/usr/bin/env bash
set -euo pipefail

echo "== sbx diagnose =="
node /opt/sbx/panel/diag.js | tee /tmp/sbx_diag_env.txt >/dev/null || true

set -a
source /tmp/sbx_diag_env.txt || true
set +a

err=0

if [ "${ENABLED_USERS:-0}" -eq 0 ]; then
  echo "[E] no enabled users"; err=1
fi

if [ "${REALITY_ENABLED:-false}" != "true" ]; then
  echo "[I] reality disabled"
else
  [ "${REALITY_PRIVKEY}" = "SET" ] || { echo "[E] reality missing private_key"; err=1; }
  [ "${REALITY_SHORTID}" = "SET" ] || { echo "[E] reality missing short_id"; err=1; }
  [ -n "${REALITY_SNI}" ] || { echo "[E] reality.server_name missing"; err=1; }
fi

if [ "${WS_ENABLED:-false}" = "true" ]; then
  if [ "${WS_TLS}" = "MISSING" ]; then echo "[E] ws.tls missing (cert files or acme)"; err=1; fi
fi

if [ "${HY2_ENABLED:-false}" = "true" ]; then
  if [ "${HY2_TLS}" = "MISSING" ]; then echo "[E] hy2.tls missing (cert files or acme)"; err=1; fi
fi

if ! sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
  echo "[W] sing-box check fails on current config.json (run sbxctl apply after fixing sbx.yml)"
fi

if [ $err -eq 0 ]; then echo "OK"; else echo "FAILED"; fi
