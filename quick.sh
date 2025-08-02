#!/usr/bin/env bash
# quick.sh - sbx-lite bootstrap installer
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/quick.sh)
#   # or
#   bash <(wget -qO- https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/quick.sh)
#
# Environment:
#   SBX_VERSION=main     # default. Or set to a tag like v20
#   SKIP_SMOKE=1         # optional, skip end-of-install smoke tests

set -euo pipefail

REPO="YYvanYang/sbx-lite"
VER="${SBX_VERSION:-main}"   # default to main
TMP="$(mktemp -d -t sbx-lite.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
dl() {
  local url="$1" out="$2"
  if have curl; then
    curl -fsSL "$url" -o "$out"
  elif have wget; then
    wget -qO "$out" "$url"
  else
    echo "[!] Need curl or wget to download $url" >&2
    return 1
  fi
}

# Compose tarball URL
if [[ "$VER" == "main" ]]; then
  URL="https://codeload.github.com/${REPO}/tar.gz/refs/heads/main"
else
  URL="https://codeload.github.com/${REPO}/tar.gz/refs/tags/${VER}"
fi

echo "[*] Downloading: $URL"
cd "$TMP"
dl "$URL" "sbx.tgz"

# Extract top-level dir name and unpack
TOPDIR="$(tar -tzf sbx.tgz | head -1 | cut -f1 -d/ || true)"
if [[ -z "$TOPDIR" ]]; then
  echo "[!] Failed to read tarball contents." >&2
  exit 1
fi

tar -xzf sbx.tgz
cd "$TOPDIR"

if [[ ! -x "./install.sh" ]]; then
  echo "[!] install.sh not found in tarball. Please check repository layout." >&2
  exit 1
fi

echo "[*] Running installer (install.sh) ..."
# Allow skipping smoke tests when certificates are not yet ready
if have sudo && [[ "${EUID:-1000}" -ne 0 ]]; then
  sudo env SKIP_SMOKE="${SKIP_SMOKE:-0}" ./install.sh
else
  env SKIP_SMOKE="${SKIP_SMOKE:-0}" ./install.sh
fi

cat <<'EOF'

[*] Install complete.

Next steps (typical):
  sudo /opt/sbx/scripts/sbxctl sethost          # (optional) no arg -> auto-detect public IPv4
  sudo /opt/sbx/scripts/sbxctl cf proxied       # or 'direct' for no CDN
  sudo /opt/sbx/scripts/sbxctl setdomain your.domain
  sudo /opt/sbx/scripts/sbxctl enable reality
  sudo /opt/sbx/scripts/sbxctl apply
  sudo /opt/sbx/scripts/diagnose.sh

Panel (local only, via SSH tunnel):
  ssh -N -L 7789:127.0.0.1:7789 root@server
  open http://127.0.0.1:7789

EOF
