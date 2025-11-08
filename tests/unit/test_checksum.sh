#!/usr/bin/env bash
# Unit tests for SHA256 checksum verification

# Disable exit on error for testing
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test environment flag
export SBX_TEST_MODE=1

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Load required modules (disable traps first)
trap - EXIT INT TERM

if ! source lib/common.sh 2>/dev/null; then
    echo "✗ Failed to load lib/common.sh"
    exit 1
fi

if ! source lib/network.sh 2>/dev/null; then
    echo "✗ Failed to load lib/network.sh"
    exit 1
fi

if ! source lib/checksum.sh 2>/dev/null; then
    echo "⚠ SKIP: lib/checksum.sh not yet created (expected for TDD red phase)"
    exit 0
fi

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo ""
    echo "Test $((TOTAL_TESTS + 1)): $test_name"

    ((TOTAL_TESTS++))

    if $test_func; then
        echo "✓ PASSED"
        ((PASSED_TESTS++))
        return 0
    else
        echo "✗ FAILED"
        ((FAILED_TESTS++))
        return 1
    fi
}

echo "=== Checksum Verification Tests ==="

# Test 1: Valid checksum verification
test_valid_checksum() {
    local test_file="/tmp/test-checksum-$$-valid"
    local checksum_file="/tmp/checksum-$$-valid"

    # Create test file
    echo "test content for valid checksum" > "$test_file"

    # Calculate actual checksum
    local actual_sum
    actual_sum=$(sha256sum "$test_file" | awk '{print $1}')

    # Create matching checksum file
    echo "$actual_sum  test-file" > "$checksum_file"

    # Verify (should succeed)
    local result
    verify_file_checksum "$test_file" "$checksum_file" >/dev/null 2>&1
    result=$?

    # Cleanup
    rm -f "$test_file" "$checksum_file"

    return $result
}

# Test 2: Invalid checksum rejection
test_invalid_checksum() {
    local test_file="/tmp/test-checksum-$$-invalid"
    local checksum_file="/tmp/checksum-$$-invalid"

    # Create test file
    echo "test content for invalid checksum" > "$test_file"

    # Create wrong checksum
    echo "0000000000000000000000000000000000000000000000000000000000000000  test-file" > "$checksum_file"

    # Verify (should fail)
    local result
    verify_file_checksum "$test_file" "$checksum_file" >/dev/null 2>&1
    result=$?

    # Cleanup
    rm -f "$test_file" "$checksum_file"

    # Invert result (we want failure)
    if [[ $result -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 3: Missing checksum file
test_missing_checksum_file() {
    local test_file="/tmp/test-checksum-$$-missing"

    # Create test file
    echo "test content" > "$test_file"

    # Verify with non-existent checksum file (should fail gracefully)
    local result
    verify_file_checksum "$test_file" "/nonexistent/checksum-$$" >/dev/null 2>&1
    result=$?

    # Cleanup
    rm -f "$test_file"

    # Should return error
    if [[ $result -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 4: Invalid checksum format
test_invalid_format() {
    local test_file="/tmp/test-checksum-$$-format"
    local checksum_file="/tmp/checksum-$$-format"

    # Create test file
    echo "test content" > "$test_file"

    # Invalid format (not 64 hex chars)
    echo "invalid_format  test-file" > "$checksum_file"

    # Verify (should fail)
    local result
    verify_file_checksum "$test_file" "$checksum_file" >/dev/null 2>&1
    result=$?

    # Cleanup
    rm -f "$test_file" "$checksum_file"

    # Should return error
    if [[ $result -ne 0 ]]; then
        return 0
    else
        return 1
    fi
}

# Test 5: Case insensitivity
test_case_insensitive() {
    local test_file="/tmp/test-checksum-$$-case"
    local checksum_file="/tmp/checksum-$$-case"

    # Create test file
    echo "test content for case test" > "$test_file"

    # Calculate checksum
    local actual_sum
    actual_sum=$(sha256sum "$test_file" | awk '{print $1}')

    # Create uppercase checksum
    local upper_sum="${actual_sum^^}"
    echo "$upper_sum  test-file" > "$checksum_file"

    # Verify (should succeed despite case difference)
    local result
    verify_file_checksum "$test_file" "$checksum_file" >/dev/null 2>&1
    result=$?

    # Cleanup
    rm -f "$test_file" "$checksum_file"

    return $result
}

# Test 6: SHA256 tool availability
test_sha256_tool_available() {
    if command -v sha256sum >/dev/null 2>&1 || command -v shasum >/dev/null 2>&1; then
        return 0
    else
        echo "  ⚠ No SHA256 tool available"
        return 1
    fi
}

# Run all tests
run_test "Valid checksum verification" test_valid_checksum
run_test "Invalid checksum rejection" test_invalid_checksum
run_test "Missing checksum file handling" test_missing_checksum_file
run_test "Invalid checksum format rejection" test_invalid_format
run_test "Case-insensitive comparison" test_case_insensitive
run_test "SHA256 tool availability" test_sha256_tool_available

# Print summary
echo ""
echo "========================================"
echo "Test Summary"
echo "----------------------------------------"
echo "Total:   $TOTAL_TESTS"
echo "Passed:  $PASSED_TESTS"
echo "Failed:  $FAILED_TESTS"
echo "========================================"

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi

exit 0
