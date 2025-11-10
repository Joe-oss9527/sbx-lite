#!/usr/bin/env bash
# tests/test_framework.sh - Enhanced testing framework
# Part of sbx-lite test infrastructure
#
# Provides assertion functions and test tracking for unit tests

set -euo pipefail

#==============================================================================
# Test State Tracking
#==============================================================================

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Failed test details
declare -a FAILED_TESTS=()

#==============================================================================
# Assertion Functions
#==============================================================================

# Assert two values are equal
# Usage: assert_equals "expected" "actual" ["message"]
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: '$expected'"
        echo "    Actual:   '$actual'"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert value is not empty
# Usage: assert_not_empty "value" ["message"]
assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    ((TESTS_RUN++))

    if [[ -n "$value" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: non-empty value"
        echo "    Actual:   empty string"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert value is empty
# Usage: assert_empty "value" ["message"]
assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    ((TESTS_RUN++))

    if [[ -z "$value" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: empty string"
        echo "    Actual:   '$value'"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert file exists
# Usage: assert_file_exists "/path/to/file" ["message"]
assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    ((TESTS_RUN++))

    if [[ -f "$file" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    File not found: $file"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert file does not exist
# Usage: assert_file_not_exists "/path/to/file" ["message"]
assert_file_not_exists() {
    local file="$1"
    local message="${2:-File should not exist: $file}"

    ((TESTS_RUN++))

    if [[ ! -f "$file" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    File exists: $file"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert directory exists
# Usage: assert_dir_exists "/path/to/dir" ["message"]
assert_dir_exists() {
    local dir="$1"
    local message="${2:-Directory should exist: $dir}"

    ((TESTS_RUN++))

    if [[ -d "$dir" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Directory not found: $dir"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert command succeeds (exit code 0)
# Usage: assert_success "command" ["message"]
assert_success() {
    local command="$1"
    local message="${2:-Command should succeed: $command}"

    ((TESTS_RUN++))

    if eval "$command" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        local exit_code=$?
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: exit code 0"
        echo "    Actual:   exit code $exit_code"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert command fails (non-zero exit code)
# Usage: assert_failure "command" ["message"]
assert_failure() {
    local command="$1"
    local message="${2:-Command should fail: $command}"

    ((TESTS_RUN++))

    if ! eval "$command" >/dev/null 2>&1; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: non-zero exit code"
        echo "    Actual:   exit code 0 (success)"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert string contains substring
# Usage: assert_contains "haystack" "needle" ["message"]
assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    ((TESTS_RUN++))

    if [[ "$haystack" == *"$needle"* ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    String: '$haystack'"
        echo "    Should contain: '$needle'"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert string matches regex pattern
# Usage: assert_matches "string" "pattern" ["message"]
assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"

    ((TESTS_RUN++))

    if [[ "$string" =~ $pattern ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    String: '$string'"
        echo "    Pattern: '$pattern'"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

# Assert numeric values (greater than, less than, etc.)
# Usage: assert_greater_than "5" "3" ["message"]
assert_greater_than() {
    local value1="$1"
    local value2="$2"
    local message="${3:-$value1 should be greater than $value2}"

    ((TESTS_RUN++))

    if [[ "$value1" -gt "$value2" ]] 2>/dev/null; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: $value1 > $value2"
        FAILED_TESTS+=("$message")
        return 1
    fi
}

#==============================================================================
# Test Suite Management
#==============================================================================

# Print test summary
# Usage: print_test_summary
print_test_summary() {
    echo ""
    echo "=============================================="
    echo "           Test Summary"
    echo "=============================================="
    echo "Total tests:  $TESTS_RUN"
    echo "Passed:       $TESTS_PASSED"
    echo "Failed:       $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        echo "✓ All tests passed!"
        echo "=============================================="
        return 0
    else
        echo ""
        echo "✗ Some tests failed:"
        for test in "${FAILED_TESTS[@]}"; do
            echo "  - $test"
        done
        echo "=============================================="
        return 1
    fi
}

# Reset test counters (useful for multiple test suites)
# Usage: reset_test_counters
reset_test_counters() {
    TESTS_RUN=0
    TESTS_PASSED=0
    TESTS_FAILED=0
    FAILED_TESTS=()
}

# Run a test suite with setup and teardown
# Usage: run_test_suite "suite_name" setup_function test_function teardown_function
run_test_suite() {
    local suite_name="$1"
    local setup_fn="${2:-true}"
    local test_fn="$3"
    local teardown_fn="${4:-true}"

    echo ""
    echo "=========================================="
    echo "Running test suite: $suite_name"
    echo "=========================================="

    # Run setup
    if declare -f "$setup_fn" >/dev/null 2>&1; then
        echo "Running setup..."
        if ! $setup_fn; then
            echo "✗ Setup failed, skipping test suite"
            return 1
        fi
    fi

    # Run tests
    if declare -f "$test_fn" >/dev/null 2>&1; then
        $test_fn
    else
        echo "✗ Test function not found: $test_fn"
        return 1
    fi

    # Run teardown
    if declare -f "$teardown_fn" >/dev/null 2>&1; then
        echo "Running teardown..."
        $teardown_fn || echo "⚠ Teardown had warnings (continuing)"
    fi

    return 0
}

#==============================================================================
# Helper Functions
#==============================================================================

# Create temporary test directory
# Usage: test_tmpdir=$(create_test_tmpdir)
create_test_tmpdir() {
    local tmpdir
    tmpdir=$(mktemp -d /tmp/sbx-test.XXXXXX)
    chmod 700 "$tmpdir"
    echo "$tmpdir"
}

# Clean up temporary test directory
# Usage: cleanup_test_tmpdir "$test_tmpdir"
cleanup_test_tmpdir() {
    local tmpdir="$1"
    [[ -n "$tmpdir" && -d "$tmpdir" && "$tmpdir" == /tmp/sbx-test.* ]] && rm -rf "$tmpdir"
}

#==============================================================================
# Export Functions
#==============================================================================

export -f assert_equals assert_not_empty assert_empty
export -f assert_file_exists assert_file_not_exists assert_dir_exists
export -f assert_success assert_failure
export -f assert_contains assert_matches
export -f assert_greater_than
export -f print_test_summary reset_test_counters run_test_suite
export -f create_test_tmpdir cleanup_test_tmpdir

# Note: Test counters are available when sourced, but not exported
# (arrays like FAILED_TESTS cannot be exported in bash)

#==============================================================================
# Self-Test (if run directly)
#==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Disable strict mode for self-test (assertions intentionally fail for testing)
    set +e

    echo "Running test_framework.sh self-test..."
    echo ""

    # Test assertions
    assert_equals "hello" "hello" "String equality test"
    assert_not_empty "test" "Non-empty string test"
    assert_empty "" "Empty string test"
    assert_success "true" "Success command test"
    assert_failure "false" "Failure command test"
    assert_contains "hello world" "world" "String contains test"
    assert_matches "test123" "^test[0-9]+$" "Regex match test"
    assert_greater_than 10 5 "Greater than test"

    # Test temporary directory
    tmpdir=$(create_test_tmpdir)
    assert_dir_exists "$tmpdir" "Temporary directory creation"
    cleanup_test_tmpdir "$tmpdir"
    assert_failure "[[ -d '$tmpdir' ]]" "Temporary directory cleanup"

    print_test_summary
    exit $?
fi
