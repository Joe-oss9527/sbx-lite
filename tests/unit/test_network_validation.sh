#!/usr/bin/env bash
# Unit tests for network validation functions (lib/network.sh, lib/validation.sh)
# Tests for: validate_port, validate_domain, validate_ip_address, validate_short_id
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
# shellcheck source=../../lib/validation.sh
source "${PROJECT_ROOT}/lib/validation.sh"

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
    # Always return 0 to continue testing
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
    # Always return 0 to continue testing
    return 0
}

#=============================================================================
# validate_port() Tests
#=============================================================================

test_validate_port_valid_ports() {
    echo ""
    echo "Testing validate_port() - Valid Ports"
    echo "-------------------------------------"

    assert_success "Port 80 (HTTP)" "validate_port 80"
    assert_success "Port 443 (HTTPS)" "validate_port 443"
    assert_success "Port 8080 (common alt)" "validate_port 8080"
    assert_success "Port 1 (minimum)" "validate_port 1"
    assert_success "Port 65535 (maximum)" "validate_port 65535"
    assert_success "Port 24443 (fallback)" "validate_port 24443"
}

test_validate_port_invalid_ports() {
    echo ""
    echo "Testing validate_port() - Invalid Ports"
    echo "---------------------------------------"

    assert_failure "Port 0 (invalid)" "validate_port 0"
    assert_failure "Port -1 (negative)" "validate_port -1"
    assert_failure "Port 65536 (too large)" "validate_port 65536"
    assert_failure "Port 99999 (way too large)" "validate_port 99999"
    assert_failure "Port 'abc' (non-numeric)" "validate_port abc"
    assert_failure "Port '' (empty)" "validate_port ''"
    assert_failure "Port '443 ' (trailing space)" "validate_port '443 '"
    assert_failure "Port ' 443' (leading space)" "validate_port ' 443'"
}

#=============================================================================
# validate_domain() Tests
#=============================================================================

test_validate_domain_valid_domains() {
    echo ""
    echo "Testing validate_domain() - Valid Domains"
    echo "-----------------------------------------"

    assert_success "Simple domain" "validate_domain 'example.com'"
    assert_success "Subdomain" "validate_domain 'www.example.com'"
    assert_success "Deep subdomain" "validate_domain 'api.v1.example.com'"
    assert_success "Domain with numbers" "validate_domain 'test123.example.com'"
    assert_success "Domain with hyphen" "validate_domain 'my-domain.com'"
    assert_success "Long TLD" "validate_domain 'example.photography'"
    assert_success "International TLD" "validate_domain 'example.xn--fiqs8s'"
}

test_validate_domain_invalid_domains() {
    echo ""
    echo "Testing validate_domain() - Invalid Domains"
    echo "-------------------------------------------"

    assert_failure "Empty string" "validate_domain ''"
    assert_failure "Just TLD" "validate_domain 'com'"
    assert_failure "No TLD" "validate_domain 'example'"
    assert_failure "Starts with hyphen" "validate_domain '-example.com'"
    assert_failure "Ends with hyphen" "validate_domain 'example-.com'"
    assert_failure "Double dot" "validate_domain 'example..com'"
    assert_failure "Starts with dot" "validate_domain '.example.com'"
    assert_failure "Ends with dot" "validate_domain 'example.com.'"
    assert_failure "Special chars" "validate_domain 'example@domain.com'"
    assert_failure "Spaces" "validate_domain 'example domain.com'"
    assert_failure "Underscore in domain" "validate_domain 'example_test.com'"
    assert_failure "Too long (>253 chars)" "validate_domain '$(printf 'a%.0s' {1..254}).com'"
}

#=============================================================================
# validate_ip_address() Tests
#=============================================================================

test_validate_ip_address_valid_ips() {
    echo ""
    echo "Testing validate_ip_address() - Valid IPs"
    echo "-----------------------------------------"

    assert_success "Localhost" "validate_ip_address '127.0.0.1'"
    assert_success "Public IP" "validate_ip_address '8.8.8.8'"
    assert_success "Private IP (10.x)" "validate_ip_address '10.0.0.1'"
    assert_success "Private IP (172.16.x)" "validate_ip_address '172.16.0.1'"
    assert_success "Private IP (192.168.x)" "validate_ip_address '192.168.1.1'"
    assert_success "Max valid IP" "validate_ip_address '255.255.255.255'"
    assert_success "Min valid IP" "validate_ip_address '0.0.0.0'"
}

test_validate_ip_address_invalid_ips() {
    echo ""
    echo "Testing validate_ip_address() - Invalid IPs"
    echo "-------------------------------------------"

    assert_failure "Octet > 255" "validate_ip_address '256.1.1.1'"
    assert_failure "Octet > 255 (second)" "validate_ip_address '1.256.1.1'"
    assert_failure "Octet > 255 (third)" "validate_ip_address '1.1.256.1'"
    assert_failure "Octet > 255 (fourth)" "validate_ip_address '1.1.1.256'"
    assert_failure "Negative octet" "validate_ip_address '-1.1.1.1'"
    assert_failure "Too many octets" "validate_ip_address '1.1.1.1.1'"
    assert_failure "Too few octets" "validate_ip_address '1.1.1'"
    assert_failure "Empty octets" "validate_ip_address '1..1.1'"
    assert_failure "Letters in IP" "validate_ip_address '192.168.a.1'"
    assert_failure "Empty string" "validate_ip_address ''"
    assert_failure "Just dots" "validate_ip_address '...'"
    assert_failure "Leading zeros" "validate_ip_address '192.168.001.001'"
}

#=============================================================================
# validate_short_id() Tests
#=============================================================================

test_validate_short_id_valid_ids() {
    echo ""
    echo "Testing validate_short_id() - Valid Short IDs"
    echo "----------------------------------------------"

    assert_success "8 hex chars (lowercase)" "validate_short_id 'abcdef12'"
    assert_success "8 hex chars (uppercase)" "validate_short_id 'ABCDEF12'"
    assert_success "8 hex chars (mixed)" "validate_short_id 'AbCdEf12'"
    assert_success "All numbers" "validate_short_id '12345678'"
    assert_success "All letters (valid hex)" "validate_short_id 'abcdefab'"
    assert_success "1 char" "validate_short_id 'a'"
    assert_success "4 chars" "validate_short_id 'ab12'"
}

test_validate_short_id_invalid_ids() {
    echo ""
    echo "Testing validate_short_id() - Invalid Short IDs"
    echo "------------------------------------------------"

    assert_failure "Empty string" "validate_short_id ''"
    assert_failure "9 chars (too long)" "validate_short_id 'abcdef123'"
    assert_failure "16 chars (Xray limit)" "validate_short_id 'abcdef1234567890'"
    assert_failure "Non-hex chars (g)" "validate_short_id 'abcdefg1'"
    assert_failure "Non-hex chars (z)" "validate_short_id 'abcdefz1'"
    assert_failure "Special chars" "validate_short_id 'abcd-ef1'"
    assert_failure "Spaces" "validate_short_id 'abcd ef1'"
}

#=============================================================================
# Port Allocation Tests (Race Condition)
#=============================================================================

test_port_allocation_not_localhost_only() {
    echo ""
    echo "Testing Port Allocation - Multi-Interface Check"
    echo "------------------------------------------------"

    # This test verifies that port allocation checks ALL interfaces, not just 127.0.0.1
    # We'll check the implementation to ensure it doesn't have the race condition

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Check if allocate_port function exists and is callable
    if ! declare -f allocate_port >/dev/null; then
        echo -e "${RED}✗${NC} allocate_port function not found/exported"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 1
    fi

    # Read the function source and check for race condition pattern
    local func_source
    func_source=$(declare -f allocate_port)

    # Check if it only tests localhost (the bug pattern)
    if echo "$func_source" | grep -q "127.0.0.1.*tcp"; then
        if ! echo "$func_source" | grep -q "::.*tcp\|0.0.0.0.*tcp"; then
            echo -e "${YELLOW}⚠${NC} Port check uses localhost only (race condition possible)"
            echo -e "    ${YELLOW}→${NC} Should check all interfaces (::, 0.0.0.0) or use ss/lsof"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            return 1
        fi
    fi

    echo -e "${GREEN}✓${NC} Port allocation checks multiple interfaces"
    PASSED_TESTS=$((PASSED_TESTS + 1))
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Network Validation Unit Tests"
    echo "========================================="

    # Check if functions are exported/available
    echo ""
    echo "Pre-flight Checks"
    echo "-----------------"

    local required_functions=(
        "validate_port"
        "validate_domain"
        "validate_ip_address"
        "validate_short_id"
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
        echo "Please ensure all validation functions are properly exported."
        exit 1
    fi

    # Run test suites
    test_validate_port_valid_ports
    test_validate_port_invalid_ports

    test_validate_domain_valid_domains
    test_validate_domain_invalid_domains

    test_validate_ip_address_valid_ips
    test_validate_ip_address_invalid_ips

    test_validate_short_id_valid_ids
    test_validate_short_id_invalid_ids

    test_port_allocation_not_localhost_only

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
