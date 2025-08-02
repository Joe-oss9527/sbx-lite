#!/usr/bin/env bash
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
sudo bash "$DIR/scripts/install.sh"
