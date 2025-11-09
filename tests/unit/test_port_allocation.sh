#!/usr/bin/env bash
# Unit tests for port allocation and race condition prevention
# Tests for: allocate_port, port_in_use, multi-interface handling
# Note: Don't use set -e here, we want to run all tests even if some fail
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

# Load modules under test
# shellcheck source=../../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=../../lib/network.sh
source "${PROJECT_ROOT}/lib/network.sh"

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

    if echo "$haystack" | grep -q "$needle"; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "    Expected to find: $needle"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

#=============================================================================
# port_in_use() Tests
#=============================================================================

test_port_in_use_basic() {
    echo ""
    echo "Testing port_in_use() - Basic Functionality"
    echo "-------------------------------------------"

    # Test with a port that's definitely in use (sshd if available)
    if ss -lntp 2>/dev/null | grep -q ":22 "; then
        assert_success "Detects port 22 (SSH) in use" "port_in_use 22"
    else
        echo -e "${YELLOW}⊘${NC} Skipping SSH test (port 22 not in use)"
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
    fi

    # Test with a port that's unlikely to be in use
    assert_failure "Reports port 54321 as free" "port_in_use 54321"
    assert_failure "Reports port 54322 as free" "port_in_use 54322"
}

#=============================================================================
# Multi-Interface Port Check Tests
#=============================================================================

test_port_check_all_interfaces() {
    echo ""
    echo "Testing Port Check - Multi-Interface Coverage"
    echo "----------------------------------------------"

    # This test verifies that port checking considers all interfaces,
    # not just localhost (127.0.0.1)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Check if the implementation properly handles multiple interfaces
    # We'll inspect the port_in_use and allocate_port functions

    # Test 1: port_in_use should use ss/lsof which check all interfaces
    local port_in_use_impl
    port_in_use_impl=$(declare -f port_in_use)

    # Verify port_in_use uses ss or lsof (both check all interfaces)
    if echo "$port_in_use_impl" | grep -qE "ss |lsof "; then
        echo -e "${GREEN}✓${NC} port_in_use() uses ss/lsof (checks all interfaces)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} port_in_use() doesn't use ss/lsof"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Test 2: Check allocate_port for the localhost-only bug
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local allocate_impl
    allocate_impl=$(declare -f allocate_port)

    # Look for the problematic pattern: /dev/tcp/127.0.0.1
    if echo "$allocate_impl" | grep -q "127.0.0.1"; then
        # Check if there's also a check for :: or 0.0.0.0
        if echo "$allocate_impl" | grep -qE "::|0\.0\.0\.0"; then
            echo -e "${GREEN}✓${NC} allocate_port() checks multiple interfaces"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${YELLOW}⚠${NC} allocate_port() only checks localhost (127.0.0.1)"
            echo -e "    ${YELLOW}→${NC} Should also check :: (IPv6) and 0.0.0.0 (all IPv4)"
            echo -e "    ${YELLOW}→${NC} This can cause race conditions on multi-interface systems"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        # Doesn't use /dev/tcp at all - check what it does use
        if echo "$allocate_impl" | grep -qE "ss |lsof |port_in_use"; then
            echo -e "${GREEN}✓${NC} allocate_port() relies on port_in_use (checks all interfaces)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗${NC} allocate_port() has unclear interface checking"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    fi
}

#=============================================================================
# Port Allocation Tests
#=============================================================================

test_allocate_port_basic() {
    echo ""
    echo "Testing allocate_port() - Basic Functionality"
    echo "---------------------------------------------"

    # Test allocation of a high port that should be free
    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Use a high port number unlikely to be in use
    local test_port=54321
    local fallback_port=54322

    # Try to allocate the port
    local result
    result=$(allocate_port "$test_port" "$fallback_port" "Test" 2>/dev/null)

    if [[ -n "$result" && ("$result" == "$test_port" || "$result" == "$fallback_port") ]]; then
        echo -e "${GREEN}✓${NC} Successfully allocates free port"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Failed to allocate free port"
        echo -e "    Expected: $test_port or $fallback_port"
        echo -e "    Got: '$result'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_allocate_port_fallback() {
    echo ""
    echo "Testing allocate_port() - Fallback Behavior"
    echo "-------------------------------------------"

    # This test would require actually blocking a port
    # For now, we'll verify the fallback logic exists

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local allocate_impl
    allocate_impl=$(declare -f allocate_port)

    # Check for retry logic
    if echo "$allocate_impl" | grep -q "max_retries"; then
        echo -e "${GREEN}✓${NC} Has retry logic implemented"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Missing retry logic"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check for fallback handling
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if echo "$allocate_impl" | grep -q "fallback"; then
        echo -e "${GREEN}✓${NC} Has fallback port handling"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Missing fallback port handling"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

#=============================================================================
# Race Condition Tests
#=============================================================================

test_port_allocation_race_condition() {
    echo ""
    echo "Testing Port Allocation - Race Condition Prevention"
    echo "---------------------------------------------------"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local allocate_impl
    allocate_impl=$(declare -f allocate_port)

    # Check for flock usage (atomic locking)
    if echo "$allocate_impl" | grep -q "flock"; then
        echo -e "${GREEN}✓${NC} Uses flock for atomic port allocation"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${YELLOW}⚠${NC} No flock usage detected (race condition possible)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check for lock file cleanup
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if echo "$allocate_impl" | grep -q "lock"; then
        echo -e "${GREEN}✓${NC} Implements locking mechanism"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} No locking mechanism found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

#=============================================================================
# Detailed Interface Check Test
#=============================================================================

test_interface_check_details() {
    echo ""
    echo "Testing Port Check - Detailed Interface Analysis"
    echo "------------------------------------------------"

    # Test what interfaces port_in_use actually checks
    echo "  Analyzing port_in_use implementation:"

    local impl
    impl=$(declare -f port_in_use)

    # Show the actual implementation (for debugging)
    echo "  ---"
    echo "$impl" | grep -v "^{" | grep -v "^}$" | sed 's/^/  /'
    echo "  ---"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # ss -lntp shows all listening TCP ports (all interfaces)
    # lsof also shows all interfaces
    if echo "$impl" | grep -qE "ss.*-l.*tcp|lsof.*TCP.*LISTEN"; then
        echo -e "${GREEN}✓${NC} port_in_use correctly checks all interfaces"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} port_in_use may not check all interfaces properly"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Port Allocation & Race Condition Tests"
    echo "========================================="

    # Check if functions are exported/available
    echo ""
    echo "Pre-flight Checks"
    echo "-----------------"

    local required_functions=(
        "port_in_use"
        "allocate_port"
    )

    local missing_functions=0
    for func in "${required_functions[@]}"; do
        if declare -f "$func" >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} $func is available"
        else
            echo -e "${RED}✗${NC} $func is NOT available (not exported?)"
            missing_functions=$((missing_functions + 1))
        fi
    done

    if [[ $missing_functions -gt 0 ]]; then
        echo ""
        echo -e "${RED}ERROR:${NC} $missing_functions required function(s) not available"
        echo "This likely means the functions are not exported from their modules."
        exit 1
    fi

    # Run test suites
    test_port_in_use_basic
    test_port_check_all_interfaces
    test_allocate_port_basic
    test_allocate_port_fallback
    test_port_allocation_race_condition
    test_interface_check_details

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
