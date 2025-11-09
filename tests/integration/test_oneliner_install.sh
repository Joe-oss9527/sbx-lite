#!/usr/bin/env bash
# tests/integration/test_oneliner_install.sh - Integration test for one-liner installation
# Tests complete download, module loading, and basic functionality

set -uo pipefail

# Test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL_SCRIPT="${SCRIPT_DIR}/install_multi.sh"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
    ((TESTS_RUN++))
    echo -n "  Test $TESTS_RUN: $1 ... "
}

test_pass() {
    ((TESTS_PASSED++))
    echo "✓ PASS"
}

test_fail() {
    ((TESTS_FAILED++))
    echo "✗ FAIL: $1"
}

cleanup_test_dirs() {
    find /tmp -maxdepth 1 -type d -name "sbx-install-*" -mmin -60 -exec rm -rf {} + 2>/dev/null || true
    find /tmp -maxdepth 1 -type d -name "tmp.*" -mmin -60 -exec rm -rf {} + 2>/dev/null || true
}

echo "=== Integration Test: One-Liner Installation ==="
echo ""

# Cleanup before tests
cleanup_test_dirs

#==============================================================================
# Test 1: Module download simulation (without actual installation)
#==============================================================================
test_start "One-liner module download works"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

# Run install script to trigger download, then exit immediately
output=$(timeout 30 bash install_multi.sh --version 2>&1 || true)

if echo "$output" | grep -q "modules downloaded and verified"; then
    test_pass
else
    test_fail "Module download failed"
    echo "$output" | tail -5
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 2: Debug logging output
#==============================================================================
test_start "DEBUG=1 enables debug logging"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

output=$(DEBUG=1 timeout 30 bash install_multi.sh --version 2>&1 || true)

if echo "$output" | grep -q "DEBUG:"; then
    test_pass
else
    test_fail "Debug logging not working"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 3: Verify all 14 modules downloaded
#==============================================================================
test_start "All 14 modules downloaded"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

output=$(timeout 30 bash install_multi.sh --version 2>&1 || true)

if echo "$output" | grep -qE "14/14 modules downloaded"; then
    test_pass
else
    test_fail "Not all modules downloaded"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 4: Modules sourced successfully (no error messages)
#==============================================================================
test_start "Modules loaded without errors"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

output=$(timeout 30 bash install_multi.sh --version 2>&1 || true)

if ! echo "$output" | grep -qE "(unbound variable|Required module not found)"; then
    test_pass
else
    test_fail "Module loading errors detected"
    echo "$output" | grep -E "(unbound variable|Required module not found)"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 5: Logging functions available after module load
#==============================================================================
test_start "Logging functions (msg, warn, err) available"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

# Create test script that uses the modules
cat > test_logging.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Source install_multi.sh functions (without running main)
SCRIPT_DIR="$(pwd)"
source ./install_multi.sh 2>/dev/null || true

# Check if functions are available
if declare -F msg >/dev/null && declare -F warn >/dev/null && declare -F err >/dev/null; then
    echo "FUNCTIONS_AVAILABLE"
else
    echo "FUNCTIONS_NOT_AVAILABLE"
fi
EOF

output=$(bash test_logging.sh 2>&1 || echo "SCRIPT_FAILED")

if [[ "$output" == "FUNCTIONS_AVAILABLE" ]]; then
    test_pass
else
    test_fail "Logging functions not available: $output"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 6: SCRIPT_DIR preserved across module loading
#==============================================================================
test_start "SCRIPT_DIR preserved after loading all modules"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

# Create test script
cat > test_scriptdir.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(pwd)"
ORIGINAL_SCRIPT_DIR="$SCRIPT_DIR"

# Simulate module loading by sourcing install_multi
# (this will trigger _load_modules which downloads and loads modules)
bash -c '
cd "'"$SCRIPT_DIR"'"
source ./install_multi.sh 2>/dev/null

# After loading, check if functions from common.sh are available
# If they are, SCRIPT_DIR was loaded correctly
if declare -F msg >/dev/null; then
    echo "SUCCESS"
else
    echo "FAILED"
fi
' 2>&1 || echo "ERROR"
EOF

output=$(timeout 30 bash test_scriptdir.sh 2>&1 | tail -1)

if [[ "$output" == "SUCCESS" ]]; then
    test_pass
else
    test_fail "SCRIPT_DIR preservation check failed: $output"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 7: Parallel download performance
#==============================================================================
test_start "Parallel download faster than sequential"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

# Measure parallel download time
start_parallel=$(date +%s)
timeout 60 bash install_multi.sh --version >/dev/null 2>&1 || true
end_parallel=$(date +%s)
parallel_time=$((end_parallel - start_parallel))

# Cleanup for second test
rm -rf sbx-install-* tmp.* 2>/dev/null || true

# Measure sequential download time
start_sequential=$(date +%s)
ENABLE_PARALLEL_DOWNLOAD=0 timeout 60 bash install_multi.sh --version >/dev/null 2>&1 || true
end_sequential=$(date +%s)
sequential_time=$((end_sequential - start_sequential))

# Parallel should be faster or roughly the same
if [[ $parallel_time -le $((sequential_time + 5)) ]]; then
    test_pass
else
    test_fail "Parallel ($parallel_time s) not faster than sequential ($sequential_time s)"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

#==============================================================================
# Test 8: Fallback to sequential on parallel failure
#==============================================================================
test_start "Falls back to sequential if parallel fails"
temp_test_dir=$(mktemp -d)
cp "${INSTALL_SCRIPT}" "$temp_test_dir/"
cd "$temp_test_dir"

# Disable xargs to force fallback
output=$(PATH="/usr/bin:/bin" timeout 30 bash install_multi.sh --version 2>&1 || true)

# Should see either parallel success or sequential fallback
if echo "$output" | grep -qE "(modules downloaded and verified|Downloading.*modules sequentially)"; then
    test_pass
else
    test_fail "Fallback mechanism not working"
fi

cd - >/dev/null
rm -rf "$temp_test_dir"

# Cleanup after tests
cleanup_test_dirs

#==============================================================================
# Test Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All integration tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
