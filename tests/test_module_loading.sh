#!/usr/bin/env bash
# tests/test_module_loading.sh - Test parallel/sequential module downloading
# Tests the smart module loading functionality in install_multi.sh

set -uo pipefail

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
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

# Start testing
echo "=== Testing Module Loading (install_multi.sh) ==="
echo ""

# Test 1: Verify bash syntax
test_start "install_multi.sh has valid bash syntax"
if bash -n "../install_multi.sh" 2>/dev/null; then
    test_pass
else
    test_fail "Syntax validation failed"
fi

# Test 2: Check for required functions
test_start "_download_single_module function exists"
if grep -q "^_download_single_module()" "../install_multi.sh"; then
    test_pass
else
    test_fail "Function not found"
fi

# Test 3: Check for parallel download function
test_start "_download_modules_parallel function exists"
if grep -q "^_download_modules_parallel()" "../install_multi.sh"; then
    test_pass
else
    test_fail "Function not found"
fi

# Test 4: Check for sequential download function
test_start "_download_modules_sequential function exists"
if grep -q "^_download_modules_sequential()" "../install_multi.sh"; then
    test_pass
else
    test_fail "Function not found"
fi

# Test 5: Verify progress indicator in parallel download
test_start "Parallel download has progress indicator"
if grep -q 'printf "\\r  \[%3d%%\]' "../install_multi.sh"; then
    test_pass
else
    test_fail "Progress indicator not found"
fi

# Test 6: Verify progress indicator in sequential download
test_start "Sequential download has progress indicator"
if grep -q 'printf "  \[%d/%d\]' "../install_multi.sh"; then
    test_pass
else
    test_fail "Progress indicator not found"
fi

# Test 7: Check for xargs parallel execution
test_start "Parallel download uses xargs -P"
if grep -q 'xargs -P' "../install_multi.sh"; then
    test_pass
else
    test_fail "xargs -P not found"
fi

# Test 8: Verify fallback mechanism
test_start "Fallback mechanism exists"
if grep -q "Falling back to sequential download" "../install_multi.sh"; then
    test_pass
else
    test_fail "Fallback message not found"
fi

# Test 9: Check error handling in parallel download
test_start "Parallel download handles failed modules"
if grep -q 'failed_modules=' "../install_multi.sh"; then
    test_pass
else
    test_fail "Error tracking not found"
fi

# Test 10: Verify result parsing in parallel download
test_start "Result parsing uses regex matching"
if grep -q 'if \[\[ "\$result" =~ \^SUCCESS:' "../install_multi.sh"; then
    test_pass
else
    test_fail "Result parsing not found"
fi

# Test 11: Check for module verification (file size check)
test_start "Module verification includes size check"
if grep -q '\[\[ "${file_size}" -lt 100 \]\]' "../install_multi.sh"; then
    test_pass
else
    test_fail "Size check not found"
fi

# Test 12: Check for bash syntax validation
test_start "Module verification includes syntax check"
if grep -q 'bash -n "${module_file}"' "../install_multi.sh"; then
    test_pass
else
    test_fail "Syntax check not found"
fi

# Test Summary
echo ""
echo "=== Test Summary ==="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
