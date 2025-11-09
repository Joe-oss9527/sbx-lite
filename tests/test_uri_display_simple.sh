#!/bin/bash
# Simplified TDD Test Suite for URI Display Feature
set -euo pipefail

# Colors
G='\033[0;32m'
R='\033[0;31m'
Y='\033[0;33m'
B='\033[1m'
N='\033[0m'

# Test counters
PASS=0
FAIL=0

pass() { echo -e "${G}✓ PASS${N}: $1"; ((PASS++)); }
fail() { echo -e "${R}✗ FAIL${N}: $1${2:+ - $2}"; ((FAIL++)); }

echo
echo -e "${B}${Y}=== TDD Test Suite: URI Display (RED Phase) ===${N}"
echo

#==============================================================================
# Test 1: Current print_summary() does NOT display URI
#==============================================================================

echo -e "${B}Test 1: Verify current print_summary() lacks URI display${N}"

# Extract current print_summary function
CURRENT_OUTPUT=$(sed -n '/^print_summary() {/,/^}/p' install_multi.sh)

if echo "$CURRENT_OUTPUT" | grep -qE 'vless://|URI.*=.*vless'; then
    fail "print_summary should NOT currently display URI" "Found URI in current implementation"
else
    pass "Confirmed: current print_summary() does not display URI"
fi

#==============================================================================
# Test 2: Current sbx-manager does NOT validate missing fields
#==============================================================================

echo
echo -e "${B}Test 2: Verify sbx info lacks field validation${N}"

# Check if sbx-manager validates missing fields
SBX_INFO_CODE=$(sed -n '/info|show)/,/;;/p' bin/sbx-manager.sh)

if echo "$SBX_INFO_CODE" | grep -qiE 'warning.*missing|validate.*field|check.*empty.*PUBLIC_KEY'; then
    fail "sbx info should NOT currently validate fields" "Found validation in current code"
else
    pass "Confirmed: sbx info does not validate missing fields"
fi

#==============================================================================
# Test 3: Simulate missing PUBLIC_KEY in sbx info
#==============================================================================

echo
echo -e "${B}Test 3: Test sbx info behavior with missing PUBLIC_KEY${N}"

# Create backup
if [[ -f /etc/sing-box/client-info.txt ]]; then
    cp /etc/sing-box/client-info.txt /tmp/client-info-backup.$$.txt
    BACKUP_EXISTS=1
else
    BACKUP_EXISTS=0
fi

# Create incomplete client-info
cat > /etc/sing-box/client-info.txt <<'CLIENT_EOF'
DOMAIN="104.194.91.33"
UUID="test-uuid-1234"
SHORT_ID="12ab34cd"
SNI="www.microsoft.com"
REALITY_PORT="443"
CLIENT_EOF

# Run sbx info and capture output
SBX_OUTPUT=$(sbx info 2>&1 || true)

# Restore original
if [[ $BACKUP_EXISTS -eq 1 ]]; then
    cat /tmp/client-info-backup.$$.txt > /etc/sing-box/client-info.txt
    rm -f /tmp/client-info-backup.$$.txt
fi

# Check if warning exists
if echo "$SBX_OUTPUT" | grep -qiE 'warning.*missing|error.*PUBLIC_KEY'; then
    fail "sbx info should NOT currently show warnings" "Expected no validation"
else
    pass "Confirmed: sbx info shows no warning for missing PUBLIC_KEY"
fi

# Check if empty pbk= parameter exists in URI
if echo "$SBX_OUTPUT" | grep -qE 'pbk=&|pbk=[[:space:]]|pbk=$'; then
    pass "Confirmed: Invalid URI generated with empty pbk parameter"
else
    fail "Expected invalid URI with empty pbk" "URI validation may have changed"
fi

#==============================================================================
# Summary
#==============================================================================

echo
echo -e "${B}${Y}╔═══════════════════════════════════════════════════╗${N}"
echo -e "${B}${Y}║  RED Phase Test Results (Expect All PASS)        ║${N}"
echo -e "${B}${Y}╚═══════════════════════════════════════════════════╝${N}"
echo
echo "Total Tests: $((PASS + FAIL))"
echo -e "${G}Passed: $PASS${N}"
echo -e "${R}Failed: $FAIL${N}"
echo

if [[ $FAIL -eq 0 ]]; then
    echo -e "${G}${B}✓ RED Phase Complete: Ready for implementation${N}"
    echo "These tests confirm the features are NOT yet implemented."
    exit 0
else
    echo -e "${R}${B}✗ RED Phase Incomplete: $FAIL test(s) failed${N}"
    exit 1
fi
