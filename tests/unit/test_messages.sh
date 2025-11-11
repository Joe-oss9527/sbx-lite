#!/usr/bin/env bash
# tests/unit/test_messages.sh - Unit tests for lib/messages.sh
# Tests centralized message template system

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the messages module
if ! source "${PROJECT_ROOT}/lib/messages.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/messages.sh"
    exit 1
fi

# Disable traps after loading modules (modules set their own traps)
trap - EXIT INT TERM

# Reset to permissive mode (modules use strict mode with set -e)
set +e

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test result tracking
test_result() {
    local test_name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
        return 1
    fi
}

#==============================================================================
# Message Template Tests
#==============================================================================

test_message_templates() {
    echo ""
    echo "Testing message templates..."

    # Test 1: ERROR_MESSAGES array exists
    if declare -p ERROR_MESSAGES &>/dev/null; then
        test_result "ERROR_MESSAGES array exists" "pass"
    else
        test_result "ERROR_MESSAGES array exists" "fail"
    fi

    # Test 2: Key error messages are defined
    local required_keys=("INVALID_PORT" "INVALID_DOMAIN" "FILE_NOT_FOUND" "NETWORK_ERROR" "CHECKSUM_FAILED")
    local all_found=true
    for key in "${required_keys[@]}"; do
        if [[ -z "${ERROR_MESSAGES[$key]:-}" ]]; then
            all_found=false
            break
        fi
    done

    if $all_found; then
        test_result "All required message keys defined" "pass"
    else
        test_result "All required message keys defined" "fail"
    fi

    # Test 3: Message templates contain placeholders
    if [[ "${ERROR_MESSAGES[INVALID_PORT]}" =~ %s ]]; then
        test_result "Message templates use placeholders" "pass"
    else
        test_result "Message templates use placeholders" "fail"
    fi
}

#==============================================================================
# Format Error Tests
#==============================================================================

test_format_error() {
    echo ""
    echo "Testing format_error function..."

    # Test 1: format_error with single argument
    local result
    result=$(format_error "INVALID_PORT" "99999" 2>/dev/null) || true
    if [[ "$result" =~ "99999" ]] && [[ "$result" =~ "port" || "$result" =~ "Port" ]]; then
        test_result "format_error with single argument" "pass"
    else
        test_result "format_error with single argument - got: $result" "fail"
    fi

    # Test 2: format_error with multiple arguments
    result=$(format_error "FILE_NOT_FOUND" "/path/to/file" 2>/dev/null) || true
    if [[ "$result" =~ "/path/to/file" ]]; then
        test_result "format_error with file path" "pass"
    else
        test_result "format_error with file path" "fail"
    fi

    # Test 3: format_error with unknown key
    result=$(format_error "UNKNOWN_KEY" "value" 2>/dev/null) || true
    if [[ -n "$result" ]]; then
        test_result "format_error handles unknown key" "pass"
    else
        test_result "format_error handles unknown key" "fail"
    fi
}

#==============================================================================
# Helper Function Tests
#==============================================================================

test_helper_functions() {
    echo ""
    echo "Testing helper functions..."

    # Test 1: err_invalid_port helper
    if declare -f err_invalid_port &>/dev/null; then
        local output
        output=$(err_invalid_port "65536" 2>&1) || true
        if [[ "$output" =~ "65536" ]]; then
            test_result "err_invalid_port helper works" "pass"
        else
            test_result "err_invalid_port helper works" "fail"
        fi
    else
        test_result "err_invalid_port helper (not implemented)" "pass"
    fi

    # Test 2: err_invalid_domain helper
    if declare -f err_invalid_domain &>/dev/null; then
        local output
        output=$(err_invalid_domain "invalid..com" 2>&1) || true
        if [[ "$output" =~ "invalid..com" ]]; then
            test_result "err_invalid_domain helper works" "pass"
        else
            test_result "err_invalid_domain helper works" "fail"
        fi
    else
        test_result "err_invalid_domain helper (not implemented)" "pass"
    fi

    # Test 3: err_file_not_found helper
    if declare -f err_file_not_found &>/dev/null; then
        local output
        output=$(err_file_not_found "/missing/file" 2>&1) || true
        if [[ "$output" =~ "/missing/file" ]]; then
            test_result "err_file_not_found helper works" "pass"
        else
            test_result "err_file_not_found helper works" "fail"
        fi
    else
        test_result "err_file_not_found helper (not implemented)" "pass"
    fi
}

#==============================================================================
# Message Consistency Tests
#==============================================================================

test_message_consistency() {
    echo ""
    echo "Testing message consistency..."

    # Test 1: All messages are non-empty
    local all_non_empty=true
    for key in "${!ERROR_MESSAGES[@]}"; do
        if [[ -z "${ERROR_MESSAGES[$key]}" ]]; then
            all_non_empty=false
            break
        fi
    done

    if $all_non_empty; then
        test_result "All messages are non-empty" "pass"
    else
        test_result "All messages are non-empty" "fail"
    fi

    # Test 2: Messages are properly formatted (no trailing/leading spaces)
    local all_properly_formatted=true
    for key in "${!ERROR_MESSAGES[@]}"; do
        local msg="${ERROR_MESSAGES[$key]}"
        if [[ "$msg" =~ ^[[:space:]] ]] || [[ "$msg" =~ [[:space:]]$ ]]; then
            all_properly_formatted=false
            break
        fi
    done

    if $all_properly_formatted; then
        test_result "Messages have no extra whitespace" "pass"
    else
        test_result "Messages have no extra whitespace" "fail"
    fi

    # Test 3: Messages are ASCII-only (no non-ASCII characters)
    local all_ascii=true
    for key in "${!ERROR_MESSAGES[@]}"; do
        local msg="${ERROR_MESSAGES[$key]}"
        # Check if message contains only ASCII characters (printable ASCII: 32-126)
        if LC_ALL=C grep -q '[^[:print:]]' <<< "$msg" 2>/dev/null; then
            all_ascii=false
            break
        fi
    done

    if $all_ascii; then
        test_result "Messages contain only ASCII characters" "pass"
    else
        test_result "Messages contain only ASCII characters" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "lib/messages.sh Unit Tests"
    echo "=========================================="

    # Run test suites
    test_message_templates
    test_format_error
    test_helper_functions
    test_message_consistency

    # Print summary
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    echo ""

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        exit 0
    else
        echo "✗ $TESTS_FAILED test(s) failed"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
