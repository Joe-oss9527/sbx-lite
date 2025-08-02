#!/usr/bin/env bash
# sbx-lite self-test: sanity checks for services, ports, config and subscription.
set -u

RED="$(printf '\033[31m')"; GREEN="$(printf '\033[32m')"; YELLOW="$(printf '\033[33m')"; BLUE="$(printf '\033[34m')"; NC="$(printf '\033[0m')"
PASS(){ echo -e "${GREEN}PASS${NC} $*"; }
FAIL(){ echo -e "${RED}FAIL${NC} $*"; }
WARN(){ echo -e "${YELLOW}WARN${NC} $*"; }
INFO(){ echo -e "${BLUE}INFO${NC} $*"; }

OK=0; BAD=0; WARNED=0

run() { # run "desc" cmd...
  local desc="$1"; shift
  local out; out="$("$@" 2>&1)"; local rc=$?
  if [[ $rc -eq 0 ]]; then PASS "$desc"; [[ -n "$out" ]] && echo "$out"
    OK=$((OK+1))
  else FAIL "$desc"; echo "$out"
    BAD=$((BAD+1))
  fi
  echo
  return $rc
}

exists() { command -v "$1" >/dev/null 2>&1; }

# 0) Load config hints via Node (requires panel deps)
if ! exists node; then
  FAIL "node is required (installed by install.sh)"; exit 1
fi
if [[ ! -f /opt/sbx/panel/diag.js ]]; then
  FAIL "/opt/sbx/panel/diag.js missing"; exit 1
fi
eval "$(node /opt/sbx/panel/diag.js --sh)"

echo "== sbx-lite self-test =="
# FILE INTEGRITY
bad=0
for f in /opt/sbx/panel/server.js /opt/sbx/panel/gen-config.js /opt/sbx/panel/cmd.js /opt/sbx/panel/diag.js /opt/sbx/scripts/sbxctl; do
  if grep -q '\.\.\.' "$f" 2>/dev/null; then
    FAIL "File seems truncated: $f contains '...'"
    bad=$((bad+1))
  fi
done
if [[ $bad -gt 0 ]]; then
  WARN "Some files look truncated. Reinstall or restore them."; WARNED=$((WARNED+1))
fi

echo "export.host=${EXPORT_HOST} users=${USERS_COUNT} reality=${REALITY_ENABLED} ws=${WS_ENABLED} hy2=${HY2_ENABLED}"
echo

# REQUIRED FIELDS CHECK (with hints)
JSON=$(node /opt/sbx/panel/diag.js)
if [[ -z "$JSON" ]]; then
  WARN "Cannot read sbx.yml via diag.js"; WARNED=$((WARNED+1))
else
  CF_MODE=$(echo "$JSON" | jq -r '.cloudflareMode // ""')
  U_NUM=$(echo "$JSON" | jq -r '.usersCount // 0')
  if [[ "$U_NUM" -lt 1 ]]; then
    FAIL "No enabled users. Add one:  sbxctl adduser phone"; BAD=$((BAD+1))
  else
    # Per-user checks
    MISSING=0
    echo "$JSON" | jq -c '.users[]' | while read -r u; do
      name=$(echo "$u" | jq -r '.name')
      t=$(echo "$u" | jq -r '.hasToken')
      id=$(echo "$u" | jq -r '.hasUUID')
      if [[ "$t" != "true" || "$id" != "true" ]]; then
        echo -e "${YELLOW}WARN${NC} user '$name' missing token/uuid -> recreate: sbxctl rmuser '$name'; sbxctl adduser '$name'"
      fi
    done
  fi

  R_ENABLED=$(echo "$JSON" | jq -r '.inbounds.realityEnabled')
  if [[ "$R_ENABLED" == "true" ]]; then
    R_SNI=$(echo "$JSON" | jq -r '.inbounds.realityServerName // ""')
    R_PVT=$(echo "$JSON" | jq -r '.inbounds.realityPrivateKeyPresent')
    R_SID=$(echo "$JSON" | jq -r '.inbounds.realityShortIdPresent')
    if [[ -z "$R_SNI" ]]; then FAIL "reality.server_name is empty (sbx.yml)."; BAD=$((BAD+1)); fi
    if [[ "$R_PVT" != "true" || "$R_SID" != "true" ]]; then
      FAIL "reality.private_key/short_id missing -> re-run: sbxctl reality (then edit sbx.yml)"; BAD=$((BAD+1))
    fi
  fi

  WS_ENABLED=$(echo "$JSON" | jq -r '.inbounds.wsEnabled')
  if [[ "$WS_ENABLED" == "true" ]]; then
    WS_DOMAIN=$(echo "$JSON" | jq -r '.inbounds.wsDomain // ""')
    CERT=$(echo "$JSON" | jq -r '.inbounds.wsCertPath // ""')
    KEY=$(echo "$JSON" | jq -r '.inbounds.wsKeyPath // ""')
    if [[ -z "$WS_DOMAIN" ]]; then FAIL "vless_ws_tls.domain is empty (sbx.yml)."; BAD=$((BAD+1)); fi
    if [[ -z "$CERT" || -z "$KEY" || ! -f "$CERT" || ! -f "$KEY" ]]; then
      if [[ "$CF_MODE" == "proxied" ]]; then
        FAIL "Origin Cert not found -> use: cf_origin_helper.sh install <cert.pem> <key.pem>"; BAD=$((BAD+1))
      else
        FAIL "Public TLS cert not found -> place /etc/ssl/fullchain.pem + privkey.pem and set paths in sbx.yml"; BAD=$((BAD+1))
      fi
    fi
  fi

  HY2_ENABLED=$(echo "$JSON" | jq -r '.inbounds.hy2Enabled')
  HY2_CERT=$(echo "$JSON" | jq -r '.inbounds.hy2CertPath // ""')
  HY2_KEY=$(echo "$JSON" | jq -r '.inbounds.hy2KeyPath // ""')
  if [[ "$HY2_ENABLED" == "true" ]]; then
    if [[ -z "$HY2_CERT" || -z "$HY2_KEY" || ! -f "$HY2_CERT" || ! -f "$HY2_KEY" ]]; then
      FAIL "Hy2 TLS cert/key not found -> set hysteria2.tls.certificate_path/key_path in sbx.yml"; BAD=$((BAD+1))
    fi
    ANY_PASS=$(echo "$JSON" | jq -r '.hy2.anyUserHy2Pass')
    GLOBAL_PASS=$(echo "$JSON" | jq -r '.hy2.hasGlobalPassword')
    if [[ "$ANY_PASS" != "true" && "$GLOBAL_PASS" != "true" ]]; then
      FAIL "Hy2 enabled but no user hy2_pass and no global_password -> run: sbxctl adduser <name> (auto generates)"; BAD=$((BAD+1))
    fi
  fi

  # export.host check (recommended)
  HOST=$(echo "$JSON" | jq -r '.exportHost // ""')
  if [[ -z "$HOST" || "$HOST" == "YOUR_PUBLIC_HOST" ]]; then
    WARN "export.host not set -> set now: sbxctl sethost your.domain.or.ip"; WARNED=$((WARNED+1))
  fi
fi


# 1) sing-box binary & version
exists sing-box && run "sing-box version" sing-box version || { FAIL "sing-box not found"; exit 1; }

# 2) systemd services
run "sing-box.service is active" bash -lc "systemctl is-active --quiet sing-box"
run "sbx-panel.service is active" bash -lc "systemctl is-active --quiet sbx-panel"

# 3) config validation
if [[ -f /etc/sing-box/config.json ]]; then
  run "sing-box check -c /etc/sing-box/config.json" bash -lc "sing-box check -c /etc/sing-box/config.json"
else
  WARN "/etc/sing-box/config.json not found; run: sudo /opt/sbx/scripts/sbxctl apply"; WARNED=$((WARNED+1))
fi

# 4) ports listening
if [[ "${REALITY_ENABLED}" -eq 1 ]]; then
  run "REALITY port ${REALITY_PORT}/tcp listening" bash -lc "ss -plnt | grep -E ':%s ' >/dev/null" "$(printf '%s' ${REALITY_PORT})"
fi
if [[ "${WS_ENABLED}" -eq 1 ]]; then
  run "WS-TLS port ${WS_PORT}/tcp listening" bash -lc "ss -plnt | grep -E ':%s ' >/dev/null" "$(printf '%s' ${WS_PORT})"
fi
if [[ "${HY2_ENABLED}" -eq 1 ]]; then
  run "Hy2 port ${HY2_PORT}/udp listening" bash -lc "ss -plun | grep -E ':%s ' >/dev/null" "$(printf '%s' ${HY2_PORT})"
fi

# 5) subscription endpoint (public, token-protected)
if [[ -n "${U_TOKEN}" ]]; then
  run "Subscription endpoint returns URIs" bash -lc "curl -fsS http://127.0.0.1:7789/sub/${U_TOKEN}?format=shadowrocket | grep -E '^(vless|hy2)://' -q"
else
  WARN "No enabled user/token found; add one via /api/user/new"; WARNED=$((WARNED+1))
fi

# 6) WS-TLS quick probe (if domain set)
if [[ "${WS_ENABLED}" -eq 1 && -n "${WS_DOMAIN}" ]]; then
  # Expect success TLS handshake and HTTP 400/404/200 or upgrade
  run "WS-TLS HTTPS probe https://${WS_DOMAIN}${WS_PATH}" bash -lc "curl -skI https://${WS_DOMAIN}${WS_PATH} --connect-timeout 8 >/dev/null"
fi

# Summary
# panel.env permission check
if [[ -f /etc/sbx/panel.env ]]; then
  perm=$(stat -c "%a" /etc/sbx/panel.env 2>/dev/null || echo "")
  if [[ "$perm" != "600" ]]; then
    WARN "/etc/sbx/panel.env perm=$perm (expected 600)"; WARNED=$((WARNED+1))
  fi
fi

# certificate existence check when WS enabled
if [[ "${WS_ENABLED}" -eq 1 ]]; then
  CERT="${WS_CERTPATH:-}"; KEY="${WS_KEYPATH:-}"
  # try to obtain from diag.js JSON mode for exact paths
  JSON=$(node /opt/sbx/panel/diag.js)
  CERT=$(echo "$JSON" | sed -n 's/.*"wsCertPath": *"\([^"]*\)".*/\1/p' | head -n1)
  KEY=$(echo "$JSON" | sed -n 's/.*"wsKeyPath": *"\([^"]*\)".*/\1/p' | head -n1)
  if [[ -z "$CERT" || -z "$KEY" || ! -f "$CERT" || ! -f "$KEY" ]]; then
    WARN "WS-TLS cert/key not found (cert_path/key_path). Check /etc/sbx/sbx.yml."
    WARNED=$((WARNED+1))
  else
    if command -v openssl >/dev/null 2>&1; then
      INFO "CERT EXPIRY"
      openssl x509 -noout -subject -issuer -enddate -in "$CERT" || true
    fi
  fi
fi

echo "== Summary ==
echo -e "OK=${GREEN}${OK}${NC}  WARN=${YELLOW}${WARNED}${NC}  FAIL=${RED}${BAD}${NC}"
if [[ $BAD -gt 0 ]]; then
  echo -e "${RED}Some checks failed. Review logs above and 'journalctl -u sing-box -f'.${NC}"
  exit 1
fi
exit 0
