#!/usr/bin/env bash
# hy2_wizard.sh - One-click Hy2 TLS check & path setup
set -euo pipefail

SBX_YAML="/etc/sbx/sbx.yml"

info(){ echo -e "[INFO] $*"; }
warn(){ echo -e "[WARN] $*" >&2; }
fail(){ echo -e "[FAIL] $*" >&2; exit 1; }

if [[ ! -f "$SBX_YAML" ]]; then
  fail "Config not found: $SBX_YAML"
fi

CERT="${1:-/etc/ssl/fullchain.pem}"
KEY="${2:-/etc/ssl/privkey.pem}"

info "Checking Hy2 TLS: cert=$CERT key=$KEY"
[[ -f "$CERT" ]] || fail "Cert not found: $CERT"
[[ -f "$KEY" ]] || fail "Key not found: $KEY"

if command -v openssl >/dev/null 2>&1; then
  echo "----- CERT INFO -----"
  openssl x509 -noout -subject -issuer -enddate -in "$CERT" || true
fi

# patch sbx.yml
node - <<'JS' "$SBX_YAML" "$CERT" "$KEY"
const fs = require('fs');
const yaml = require('js-yaml');
const SBX = process.argv[2], CERT = process.argv[3], KEY = process.argv[4];
const doc = yaml.load(fs.readFileSync(SBX, 'utf8'));
doc.inbounds = doc.inbounds || {};
doc.inbounds.hysteria2 = doc.inbounds.hysteria2 || {};
doc.inbounds.hysteria2.tls = doc.inbounds.hysteria2.tls || {};
doc.inbounds.hysteria2.tls.certificate_path = CERT;
doc.inbounds.hysteria2.tls.key_path = KEY;
fs.writeFileSync(SBX, yaml.dump(doc), 'utf8');
console.log("Updated", SBX, "with Hy2 TLS paths.");
JS

echo "[OK] Hy2 TLS paths written. Next:"
echo "  sudo /opt/sbx/scripts/sbxctl apply"
echo "  sudo /opt/sbx/scripts/diagnose.sh"
