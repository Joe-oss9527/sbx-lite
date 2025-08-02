#!/usr/bin/env bash
# sbx-lite one-liner installer (strict: requires scripts/install.sh in repo)
# curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/quick.sh | bash
set -euo pipefail

# escalate to root
if [ "${EUID:-$(id -u)}" -ne 0 ]; then exec sudo -E bash "$0" "$@"; fi

REPO="${SBX_REPO:-YYvanYang/sbx-lite}"
BRANCH="${SBX_BRANCH:-main}"

log(){ echo -e "\033[1;32m[*]\033[0m $*"; }
err(){ echo -e "\033[1;31m[×]\033[0m $*"; exit 1; }

# deps
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
  if command -v apt-get >/dev/null 2>&1; then apt-get update && apt-get install -y curl
  elif command -v dnf >/dev/null 2>&1; then dnf install -y curl
  elif command -v yum >/dev/null 2>&1; then yum install -y curl
  else err "no curl/wget and no known package manager"; fi
fi

fetch(){ if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"; else wget -qO "$2" "$1"; fi; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

if command -v git >/dev/null 2>&1; then
  log "cloning https://github.com/${REPO}.git (${BRANCH})"
  git clone --depth=1 -b "$BRANCH" "https://github.com/${REPO}.git" "$TMP/src" >/dev/null 2>&1 || err "git clone failed"
else
  TARBALL="https://codeload.github.com/${REPO}/tar.gz/${BRANCH}"
  log "downloading tarball $TARBALL"
  fetch "$TARBALL" "$TMP/src.tgz"
  mkdir -p "$TMP/src"
  tar -xzf "$TMP/src.tgz" -C "$TMP/src" --strip-components=1
fi

INSTALLER="$TMP/src/scripts/install.sh"
[ -f "$INSTALLER" ] || err "installer not found: scripts/install.sh (please ensure it exists in the repo)"

cd "$TMP/src"
log "running installer: $INSTALLER"
bash "$INSTALLER"
log "done."
log "SSH tunnel: ssh -N -L 7789:127.0.0.1:7789 root@<你的服务器IP或域名>"
