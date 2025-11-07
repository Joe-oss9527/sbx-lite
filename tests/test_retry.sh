#!/usr/bin/env bash
# tests/test_retry.sh - Unit tests for lib/retry.sh
# Tests retry mechanism, exponential backoff, and error classification

set -uo pipefail  # Don't use -e as we test failure cases

# Setup test environment
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/lib/retry.sh" 2>/dev/null || true

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

assert_eq() {
    if [[ "$1" == "$2" ]]; then
        return 0
    else
        echo "Expected: $2, Got: $1"
        return 1
    fi
}

assert_range() {
    local value=$1
    local min=$2
    local max=$3
    if [[ $value -ge $min && $value -le $max ]]; then
        return 0
    else
        echo "Value $value not in range [$min, $max]"
        return 1
    fi
}

# Start testing
echo "=== Testing lib/retry.sh ==="
echo ""

# Test 1: calculate_backoff function
test_start "calculate_backoff returns correct range for attempt 1"
backoff=$(calculate_backoff 1)
if assert_range "$backoff" 2000 3000; then
    test_pass
else
    test_fail "Backoff out of range"
fi

# Test 2: calculate_backoff for attempt 2
test_start "calculate_backoff returns correct range for attempt 2"
backoff=$(calculate_backoff 2)
if assert_range "$backoff" 4000 5000; then
    test_pass
else
    test_fail "Backoff out of range"
fi

# Test 3: calculate_backoff respects maximum
test_start "calculate_backoff respects maximum backoff"
backoff=$(calculate_backoff 10)
max_expected=$((RETRY_BACKOFF_MAX * 1000 + RETRY_JITTER_MAX))
if [[ $backoff -le $max_expected ]]; then
    test_pass
else
    test_fail "Exceeded maximum backoff"
fi

# Test 4: is_retriable_error - retriable errors
test_start "is_retriable_error identifies retriable errors (curl 7)"
if is_retriable_error 7; then  # curl: failed to connect
    test_pass
else
    test_fail "Should be retriable"
fi

# Test 5: is_retriable_error - non-retriable errors
test_start "is_retriable_error identifies non-retriable errors (curl 22)"
if ! is_retriable_error 22; then  # curl: HTTP error
    test_pass
else
    test_fail "Should not be retriable"
fi

# Test 6: retry_with_backoff succeeds immediately
test_start "retry_with_backoff succeeds on first attempt"
reset_retry_counter
if retry_with_backoff 3 true >/dev/null 2>&1; then
    test_pass
else
    test_fail "Should succeed immediately"
fi

# Test 7: retry_with_backoff fails after max attempts
test_start "retry_with_backoff exhausts retries"
reset_retry_counter
retry_with_backoff 3 /bin/false 2>/dev/null
exit_code=$?
if [[ $exit_code -ne 0 ]]; then
    test_pass
else
    test_fail "Should fail after max attempts (got exit code: $exit_code)"
fi

# Test 8: Global retry budget check
test_start "check_retry_budget enforces budget"
GLOBAL_RETRY_COUNT=$((GLOBAL_RETRY_BUDGET + 1))
if ! check_retry_budget >/dev/null 2>&1; then
    test_pass
else
    test_fail "Should reject when budget exhausted"
fi

# Test 9: reset_retry_counter
test_start "reset_retry_counter resets global counter"
reset_retry_counter
if [[ $GLOBAL_RETRY_COUNT -eq 0 ]]; then
    test_pass
else
    test_fail "Counter not reset"
fi

# Test 10: retry_with_backoff with successful command after retries
test_start "retry_with_backoff succeeds on second attempt"
reset_retry_counter
attempt_count=0
test_command() {
    ((attempt_count++))
    if [[ $attempt_count -ge 2 ]]; then
        return 0
    else
        return 1
    fi
}
if retry_with_backoff 3 test_command >/dev/null 2>&1; then
    if [[ $attempt_count -eq 2 ]]; then
        test_pass
    else
        test_fail "Wrong number of attempts: $attempt_count"
    fi
else
    test_fail "Should succeed on second attempt"
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
