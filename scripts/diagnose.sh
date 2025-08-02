#!/usr/bin/env bash
set -euo pipefail

echo "== sbx diagnose =="

node /opt/sbx/panel/diag.js | tee /tmp/sbx_diag_env.txt >/dev/null || true

# Export variables
set -a
source /tmp/sbx_diag_env.txt || true
set +a

err=0

# Users
if [ "${ENABLED_USERS:-0}" -eq 0 ]; then
  echo "[E] no enabled users"
  err=1
fi

# Reality
if [ "${REALITY_ENABLED:-false}" != "true" ]; then
  echo "[I] reality disabled"
else
  if [ "${REALITY_PRIVKEY}" != "SET" ] || [ "${REALITY_SHORTID}" != "SET" ]; then
    echo "[E] reality missing key/short_id"
    err=1
  fi
  if [ -z "${REALITY_SNI}" ]; then
    echo "[E] reality.server_name missing"
    err=1
  fi
fi

# WS
if [ "${WS_ENABLED:-false}" = "true" ]; then
  if [ "${WS_TLS}" = "MISSING" ]; then
    echo "[E] ws.tls missing (cert files or acme)"
    err=1
  fi
fi

# HY2
if [ "${HY2_ENABLED:-false}" = "true" ]; then
  if [ "${HY2_TLS}" = "MISSING" ]; then
    echo "[E] hy2.tls missing (cert files or acme)"
    err=1
  fi
fi

# sing-box check quick
if ! sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
  echo "[W] sing-box check fails on current config.json (run sbxctl apply after fixing sbx.yml)"
fi

if [ $err -eq 0 ]; then
  echo "OK"
else
  echo "FAILED"
fi
