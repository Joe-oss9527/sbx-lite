#!/usr/bin/env bash
# Unit tests for enhanced logging core functions (lib/common.sh)
# Tests for: debug(), timestamp support, log levels, log file output
# TDD Red Phase - These tests will fail until implementation is complete

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Load module under test
# shellcheck source=../../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"

# Test helper functions
assert_success() {
    local test_name="$1"
    local command="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

assert_failure() {
    local test_name="$1"
    local command="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if eval "$command" >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} $test_name (expected failure, got success)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    else
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    fi
    return 0
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$haystack" == *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected substring: $needle"
        echo "  Actual output: $haystack"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

assert_not_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ "$haystack" != *"$needle"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Should not contain: $needle"
        echo "  Actual output: $haystack"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

#=============================================================================
# debug() Function Tests
#=============================================================================

test_debug_function_exists() {
    echo ""
    echo "Testing debug() - Function Availability"
    echo "---------------------------------------"

    assert_success "debug function is available" "declare -f debug"
}

test_debug_respects_debug_flag() {
    echo ""
    echo "Testing debug() - DEBUG Flag Behavior"
    echo "-------------------------------------"

    # Test 1: debug() should be silent when DEBUG=0
    local output
    output=$(DEBUG=0 bash -c 'source lib/common.sh; debug "test message" 2>&1' 2>&1)
    assert_not_contains "debug silent when DEBUG=0" "$output" "test message"

    # Test 2: debug() should output when DEBUG=1
    output=$(DEBUG=1 bash -c 'source lib/common.sh; debug "test message" 2>&1' 2>&1)
    assert_contains "debug outputs when DEBUG=1" "$output" "test message"

    # Test 3: debug() should include [DEBUG] prefix
    output=$(DEBUG=1 bash -c 'source lib/common.sh; debug "test message" 2>&1' 2>&1)
    assert_contains "debug includes [DEBUG] prefix" "$output" "[DEBUG]"
}

#=============================================================================
# Timestamp Support Tests
#=============================================================================

test_timestamp_function() {
    echo ""
    echo "Testing Timestamp Support"
    echo "-------------------------"

    # Test 1: Timestamps disabled by default
    local output
    output=$(bash -c 'source lib/common.sh; msg "test" 2>&1' 2>&1)
    assert_not_contains "timestamps disabled by default" "$output" "202"

    # Test 2: Timestamps enabled with LOG_TIMESTAMPS=1
    output=$(LOG_TIMESTAMPS=1 bash -c 'source lib/common.sh; msg "test" 2>&1' 2>&1)
    assert_contains "timestamps enabled with flag" "$output" "202"

    # Test 3: Timestamp format should be ISO-like (YYYY-MM-DD HH:MM:SS)
    output=$(LOG_TIMESTAMPS=1 bash -c 'source lib/common.sh; msg "test" 2>&1' 2>&1)
    # Check for pattern like [2025-01-15 14:23:45]
    if [[ "$output" =~ \[20[0-9]{2}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}\] ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} timestamp format is ISO-like"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} timestamp format is ISO-like"
        echo "  Actual output: $output"
    fi
}

#=============================================================================
# Log Level Tests
#=============================================================================

test_log_level_filtering() {
    echo ""
    echo "Testing Log Level Filtering"
    echo "---------------------------"

    # Test 1: All levels should output when LOG_LEVEL not set (default)
    local output
    output=$(bash -c 'source lib/common.sh; debug "d"; msg "m"; warn "w"; err "e" 2>&1' 2>&1)
    # debug won't show unless DEBUG=1, but others should
    assert_contains "default level allows msg" "$output" "[*]"
    assert_contains "default level allows warn" "$output" "[!]"
    assert_contains "default level allows err" "$output" "[ERR]"

    # Test 2: LOG_LEVEL=ERROR should only show errors
    output=$(LOG_LEVEL=ERROR bash -c 'source lib/common.sh; msg "info"; warn "warning"; err "error" 2>&1' 2>&1)
    assert_not_contains "ERROR level filters msg" "$output" "info"
    assert_not_contains "ERROR level filters warn" "$output" "warning"
    assert_contains "ERROR level shows err" "$output" "error"

    # Test 3: LOG_LEVEL=WARN should show warn and error
    output=$(LOG_LEVEL=WARN bash -c 'source lib/common.sh; msg "info"; warn "warning"; err "error" 2>&1' 2>&1)
    assert_not_contains "WARN level filters msg" "$output" "info"
    assert_contains "WARN level shows warn" "$output" "warning"
    assert_contains "WARN level shows err" "$output" "error"
}

#=============================================================================
# JSON Structured Logging Tests
#=============================================================================

test_json_logging() {
    echo ""
    echo "Testing JSON Structured Logging"
    echo "--------------------------------"

    # Test 1: log_json function exists
    assert_success "log_json function is available" "declare -f log_json"

    # Test 2: JSON logging disabled by default
    local output
    output=$(bash -c 'source lib/common.sh; msg "test" 2>&1' 2>&1)
    assert_not_contains "JSON disabled by default" "$output" '"timestamp"'
    assert_not_contains "JSON disabled by default" "$output" '"level"'

    # Test 3: JSON logging enabled with LOG_FORMAT=json
    output=$(LOG_FORMAT=json bash -c 'source lib/common.sh; msg "test message" 2>&1' 2>&1)
    assert_contains "JSON format includes timestamp" "$output" '"timestamp"'
    assert_contains "JSON format includes level" "$output" '"level"'
    assert_contains "JSON format includes message" "$output" '"message"'
    assert_contains "JSON format includes test message" "$output" '"test message"'

    # Test 4: JSON output is valid
    output=$(LOG_FORMAT=json bash -c 'source lib/common.sh; msg "test" 2>&1' 2>&1)
    if echo "$output" | grep -q '{.*"timestamp".*"level".*"message".*}'; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} JSON output structure is valid"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} JSON output structure is valid"
        echo "  Output: $output"
    fi
}

#=============================================================================
# Log File Output Tests
#=============================================================================

test_log_file_output() {
    echo ""
    echo "Testing Log File Output"
    echo "-----------------------"

    local test_log_file
    test_log_file=$(mktemp)
    trap "rm -f $test_log_file" EXIT

    # Test 1: Log file can be specified
    LOG_FILE="$test_log_file" bash -c 'source lib/common.sh; msg "test log" 2>&1' >/dev/null 2>&1

    if [[ -f "$test_log_file" ]] && grep -q "test log" "$test_log_file"; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} log file is created and written"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} log file is created and written"
    fi

    # Test 2: Log file has proper permissions (600)
    LOG_FILE="$test_log_file" bash -c 'source lib/common.sh; msg "test" 2>&1' >/dev/null 2>&1
    local perms
    perms=$(stat -c %a "$test_log_file" 2>/dev/null || stat -f %A "$test_log_file" 2>/dev/null)

    if [[ "$perms" == "600" ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} log file has secure permissions (600)"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} log file has secure permissions (600)"
        echo "  Actual permissions: $perms"
    fi

    # Test 3: Logs still output to stderr when file logging enabled
    local output
    output=$(LOG_FILE="$test_log_file" bash -c 'source lib/common.sh; msg "dual output" 2>&1')
    assert_contains "dual output to stderr and file" "$output" "dual output"
}

#=============================================================================
# Log Rotation Tests
#=============================================================================

test_log_rotation() {
    echo ""
    echo "Testing Log Rotation"
    echo "--------------------"

    # Test 1: rotate_logs function exists
    assert_success "rotate_logs function is available" "declare -f rotate_logs"

    # Test 2: Log rotation with size limit
    local test_log_file
    test_log_file=$(mktemp)

    # Create a large log file (> 10MB simulation with small test)
    for i in {1..100}; do
        echo "Test log line $i with lots of content to fill space" >> "$test_log_file"
    done

    # Rotate should work without errors
    assert_success "log rotation executes without error" \
        "rotate_logs '$test_log_file' 10000"  # 10KB limit for testing

    rm -f "$test_log_file"* 2>/dev/null || true
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Enhanced Logging Core Unit Tests"
    echo "========================================="

    # Check if base functions are exported/available
    echo ""
    echo "Pre-flight Checks"
    echo "-----------------"

    local required_functions=(
        "msg"
        "warn"
        "err"
        "success"
        "die"
    )

    local missing_functions=0
    for func in "${required_functions[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $func is available"
        else
            echo -e "${RED}✗${NC} $func is NOT available"
            missing_functions=$((missing_functions + 1))
        fi
    done

    if [[ $missing_functions -gt 0 ]]; then
        echo ""
        echo -e "${RED}ERROR:${NC} $missing_functions base function(s) not available"
        exit 1
    fi

    # Run test suites
    test_debug_function_exists
    test_debug_respects_debug_flag
    test_timestamp_function
    test_log_level_filtering
    test_json_logging
    test_log_file_output
    test_log_rotation

    # Print summary
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo -e "Total:  $TOTAL_TESTS"
    echo -e "${GREEN}Passed: $PASSED_TESTS${NC}"
    echo -e "${RED}Failed: $FAILED_TESTS${NC}"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run tests
main "$@"
