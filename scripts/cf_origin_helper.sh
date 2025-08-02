#!/usr/bin/env bash
# cf_origin_helper.sh - Manage Cloudflare Origin Cert placement for sbx-lite
set -euo pipefail

CERT_DIR="/etc/ssl/cf"
CERT_PATH="${CERT_DIR}/origin.pem"
KEY_PATH="${CERT_DIR}/origin.key"

usage() {
  cat <<EOF
Usage: $0 <command> [args]

Commands:
  check                 Check presence, permissions, and expiry of origin cert and key.
  install <cert> <key>  Copy existing PEM files to ${CERT_PATH} and ${KEY_PATH} with safe perms.
  stdin                 Read cert and key from stdin (interactive), write to paths above.
  print-paths           Print the expected paths for sbx-lite.

Notes:
- Use this helper AFTER you generated a Cloudflare Origin Cert from the dashboard.
- Ensure vless_ws_tls.enabled=true and cloudflare_mode=proxied in /etc/sbx/sbx.yml, then:
    cert_path: ${CERT_PATH}
    key_path:  ${KEY_PATH}
EOF
}

ensure_dirs() {
  install -d -m 0755 "${CERT_DIR}"
}

cmd="${1:-}"
case "$cmd" in
  check)
    ensure_dirs
    ok=0
    warn=0

    if [[ -f "${CERT_PATH}" ]]; then
      echo "[OK] cert: ${CERT_PATH}"
      if command -v openssl >/dev/null 2>&1; then
        echo "----- CERT INFO -----"
        openssl x509 -noout -subject -issuer -enddate -in "${CERT_PATH}" || true
      fi
    else
      echo "[WARN] missing cert: ${CERT_PATH}"; warn=$((warn+1))
    fi
    if [[ -f "${KEY_PATH}" ]]; then
      echo "[OK] key: ${KEY_PATH}"
      perm=$(stat -c "%a" "${KEY_PATH}" 2>/dev/null || echo "")
      if [[ "$perm" != "600" ]]; then
        echo "[WARN] key perm=$perm (expected 600)"; warn=$((warn+1))
      fi
    else
      echo "[WARN] missing key: ${KEY_PATH}"; warn=$((warn+1))
    fi
    if [[ $warn -gt 0 ]]; then exit 1; fi
    ;;
  install)
    ensure_dirs
    src_c="${2:-}"; src_k="${3:-}"
    if [[ -z "$src_c" || -z "$src_k" ]]; then usage; exit 1; fi
    cp -f "$src_c" "${CERT_PATH}"
    cp -f "$src_k" "${KEY_PATH}"
    chmod 644 "${CERT_PATH}"
    chmod 600 "${KEY_PATH}"
    echo "[OK] Installed to ${CERT_PATH} and ${KEY_PATH}"
    ;;
  stdin)
    ensure_dirs
    echo "Paste CERT (PEM), end with EOF (Ctrl-D):"
    cat > "${CERT_PATH}"
    echo "Paste KEY  (PEM), end with EOF (Ctrl-D):"
    cat > "${KEY_PATH}"
    chmod 644 "${CERT_PATH}"
    chmod 600 "${KEY_PATH}"
    echo "[OK] Written ${CERT_PATH} and ${KEY_PATH}"
    ;;
  print-paths)
    echo "${CERT_PATH}"
    echo "${KEY_PATH}"
    ;;
  *)
    usage; exit 1;;
esac
