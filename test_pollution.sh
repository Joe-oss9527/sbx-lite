#!/usr/bin/env bash
set -euo pipefail

# Main script SCRIPT_DIR
SCRIPT_DIR="/tmp/main"
echo "1. Main script SCRIPT_DIR: $SCRIPT_DIR"

# Create a module that redefines SCRIPT_DIR (without local)
cat > module.sh << EOF2
#!/usr/bin/env bash
SCRIPT_DIR="/tmp/module"  # No local! This pollutes parent scope
echo "2. Inside module SCRIPT_DIR: \$SCRIPT_DIR"
EOF2

# Source the module
source ./module.sh

# Check SCRIPT_DIR after sourcing
echo "3. Main script SCRIPT_DIR after sourcing: $SCRIPT_DIR"
echo "   ^^^ POLLUTED! Should be /tmp/main but is /tmp/module"

rm -f module.sh
