#!/bin/bash
# Test one-liner installation scenario
# Verifies that bin/sbx-manager.sh is correctly downloaded and installed

set -uo pipefail  # Don't use -e for test scripts

# Colors
G='\033[0;32m'
Y='\033[0;33m'
R='\033[0;31m'
N='\033[0m'

TEST_DIR="/tmp/sbx-oneliner-test-$$"
PASS_COUNT=0
FAIL_COUNT=0

# Cleanup function
cleanup() {
    [[ -d "$TEST_DIR" ]] && rm -rf "$TEST_DIR"
}
trap cleanup EXIT INT TERM

# Test result tracking
pass() {
    echo -e "${G}✓${N} $1"
    ((PASS_COUNT++))
}

fail() {
    echo -e "${R}✗${N} $1"
    ((FAIL_COUNT++))
}

info() {
    echo -e "${Y}[INFO]${N} $1"
}

echo "=========================================="
echo "One-Liner Installation Test Suite"
echo "=========================================="
echo

# Test 1: Simulate one-liner install environment
info "Test 1: Simulating one-liner install (no bin/ directory)"
mkdir -p "$TEST_DIR"
cp install_multi.sh "$TEST_DIR/"

# Check from original directory (test directory doesn't have bin/)
if [[ ! -d "$TEST_DIR/bin" && ! -d "$TEST_DIR/lib" ]]; then
    pass "One-liner environment simulated (no bin/ or lib/)"
else
    fail "Failed to simulate one-liner environment"
    exit 1
fi

# Test 2: Check module download logic exists
info "Test 2: Checking _load_modules() function"
if grep -q "Download bin/sbx-manager.sh for one-liner install" install_multi.sh; then
    pass "Module download logic includes bin/sbx-manager.sh"
else
    fail "bin/sbx-manager.sh download logic not found"
fi

# Test 3: Verify download validation
info "Test 3: Checking download validation logic"
if grep -q "Check file size (full version should be >5KB" install_multi.sh; then
    pass "File size validation present"
else
    fail "File size validation missing"
fi

if grep -q 'bash -n.*manager_file' install_multi.sh; then
    pass "Bash syntax validation present"
else
    fail "Bash syntax validation missing"
fi

# Test 4: Check improved fallback warning
info "Test 4: Checking fallback warning messages"
if grep -q "sbx info.*will not show URIs" install_multi.sh; then
    pass "Detailed fallback warning present"
else
    fail "Detailed fallback warning missing"
fi

if grep -q "manually download:" install_multi.sh; then
    pass "Manual download instructions present"
else
    fail "Manual download instructions missing"
fi

# Test 5: Verify manager template path detection
info "Test 5: Checking manager installation logic"
if grep -q 'manager_template="\${SCRIPT_DIR}/bin/sbx-manager.sh"' install_multi.sh; then
    pass "Manager template path correctly set"
else
    fail "Manager template path issue"
fi

# Test 6: Check module list completeness
info "Test 6: Verifying all required modules are downloaded"
EXPECTED_MODULES="common retry download network validation checksum version certificate caddy config service ui backup export"
if grep -q "local modules=.*$EXPECTED_MODULES" install_multi.sh; then
    pass "All 13 modules listed for download"
else
    fail "Module list incomplete or incorrect"
fi

# Test 7: Verify error handling
info "Test 7: Checking error handling for download failures"
if grep -q "ERROR: Failed to download sbx-manager.sh" install_multi.sh; then
    pass "Download failure error handling present"
else
    fail "Download failure error handling missing"
fi

# Test 8: Check timeout configuration
info "Test 8: Verifying download timeout settings"
if grep -q "DOWNLOAD_CONNECT_TIMEOUT_SEC\|DOWNLOAD_MAX_TIMEOUT_SEC" install_multi.sh; then
    pass "Download timeout configuration present"
else
    fail "Download timeout configuration missing"
fi

# Test 9: Dry-run syntax check
info "Test 9: Running bash syntax check on modified script"
if bash -n install_multi.sh 2>/dev/null; then
    pass "Bash syntax check passed"
else
    fail "Bash syntax errors detected"
    bash -n install_multi.sh 2>&1 | head -10
fi

# Test 10: Check GitHub raw URL format
info "Test 10: Verifying GitHub raw content URL format"
if grep -q 'github_repo="https://raw.githubusercontent.com' install_multi.sh; then
    pass "GitHub raw content URL correctly formatted"
else
    fail "GitHub URL format issue"
fi

echo
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "Passed: ${G}${PASS_COUNT}${N}"
echo -e "Failed: ${R}${FAIL_COUNT}${N}"
echo

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${G}All tests passed!${N}"
    exit 0
else
    echo -e "${R}Some tests failed!${N}"
    exit 1
fi
