#!/usr/bin/env bash
# tests/unit/test_validation_enhanced.sh - Enhanced validation tests using test framework
# Part of sbx-lite unit test suite

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source test framework
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../test_framework.sh"

# Source modules to test
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/common.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/logging.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/validation.sh"
# shellcheck source=/dev/null
source "$PROJECT_ROOT/lib/network.sh"

#==============================================================================
# Test Setup and Teardown
#==============================================================================

setup() {
    echo "Setting up validation tests..."
    return 0
}

teardown() {
    echo "Cleaning up validation tests..."
    return 0
}

#==============================================================================
# Domain Validation Tests
#==============================================================================

test_domain_validation() {
    echo ""
    echo "Testing domain validation..."

    # Valid domains
    validate_domain "example.com" 2>/dev/null
    assert_equals "0" "$?" "Valid domain 'example.com' should pass"

    validate_domain "sub.example.com" 2>/dev/null
    assert_equals "0" "$?" "Valid subdomain 'sub.example.com' should pass"

    validate_domain "my-site.example.co.uk" 2>/dev/null
    assert_equals "0" "$?" "Valid domain with hyphens should pass"

    # Invalid domains
    ! validate_domain "invalid..com" 2>/dev/null
    assert_equals "0" "$?" "Domain with double dots should fail"

    ! validate_domain "" 2>/dev/null
    assert_equals "0" "$?" "Empty domain should fail"

    ! validate_domain "-example.com" 2>/dev/null
    assert_equals "0" "$?" "Domain starting with hyphen should fail"

    ! validate_domain "example-.com" 2>/dev/null
    assert_equals "0" "$?" "Domain ending with hyphen should fail"

    # Length validation
    local long_domain
    long_domain=$(printf 'a%.0s' {1..260})
    ! validate_domain "$long_domain" 2>/dev/null
    assert_equals "0" "$?" "Domain exceeding 253 chars should fail"
}

#==============================================================================
# Port Validation Tests
#==============================================================================

test_port_validation() {
    echo ""
    echo "Testing port validation..."

    # Valid ports
    validate_port 443 2>/dev/null
    assert_equals "0" "$?" "Valid port 443 should pass"

    validate_port 1 2>/dev/null
    assert_equals "0" "$?" "Minimum port 1 should pass"

    validate_port 65535 2>/dev/null
    assert_equals "0" "$?" "Maximum port 65535 should pass"

    validate_port 8080 2>/dev/null
    assert_equals "0" "$?" "Common port 8080 should pass"

    # Invalid ports
    ! validate_port 0 2>/dev/null
    assert_equals "0" "$?" "Port 0 should fail"

    ! validate_port 65536 2>/dev/null
    assert_equals "0" "$?" "Port 65536 should fail"

    ! validate_port -1 2>/dev/null
    assert_equals "0" "$?" "Negative port should fail"

    ! validate_port "abc" 2>/dev/null
    assert_equals "0" "$?" "Non-numeric port should fail"

    ! validate_port "" 2>/dev/null
    assert_equals "0" "$?" "Empty port should fail"
}

#==============================================================================
# IP Address Validation Tests
#==============================================================================

test_ip_validation() {
    echo ""
    echo "Testing IP address validation..."

    # Valid public IPs
    validate_ip_address "8.8.8.8" 2>/dev/null
    assert_equals "0" "$?" "Google DNS IP should pass"

    validate_ip_address "1.1.1.1" 2>/dev/null
    assert_equals "0" "$?" "Cloudflare DNS IP should pass"

    validate_ip_address "203.0.113.1" 2>/dev/null
    assert_equals "0" "$?" "Valid public IP should pass"

    # Invalid reserved addresses
    ! validate_ip_address "0.0.0.0" 2>/dev/null
    assert_equals "0" "$?" "Reserved address 0.0.0.0 should fail"

    ! validate_ip_address "127.0.0.1" 2>/dev/null
    assert_equals "0" "$?" "Loopback address 127.0.0.1 should fail"

    ! validate_ip_address "224.0.0.1" 2>/dev/null
    assert_equals "0" "$?" "Multicast address should fail"

    ! validate_ip_address "255.255.255.255" 2>/dev/null
    assert_equals "0" "$?" "Broadcast address should fail"

    # Invalid format
    ! validate_ip_address "256.1.1.1" 2>/dev/null
    assert_equals "0" "$?" "IP with octet > 255 should fail"

    ! validate_ip_address "1.1.1" 2>/dev/null
    assert_equals "0" "$?" "IP with missing octet should fail"

    ! validate_ip_address "a.b.c.d" 2>/dev/null
    assert_equals "0" "$?" "Non-numeric IP should fail"

    # Private IPs (default: should fail)
    ! validate_ip_address "10.0.0.1" 2>/dev/null
    assert_equals "0" "$?" "Private IP 10.0.0.1 should fail (default)"

    ! validate_ip_address "192.168.1.1" 2>/dev/null
    assert_equals "0" "$?" "Private IP 192.168.1.1 should fail (default)"

    ! validate_ip_address "172.16.0.1" 2>/dev/null
    assert_equals "0" "$?" "Private IP 172.16.0.1 should fail (default)"
}

#==============================================================================
# Environment Variable Validation Tests
#==============================================================================

test_env_var_validation() {
    echo ""
    echo "Testing environment variable validation..."

    # Test with valid domain
    export DOMAIN="example.com"
    export REALITY_PORT=443
    validate_env_vars >/dev/null 2>&1
    assert_equals "0" "$?" "Valid domain environment variables should pass"

    # Test with valid IP address
    export DOMAIN="8.8.8.8"
    validate_env_vars >/dev/null 2>&1
    assert_equals "0" "$?" "Valid IP address in DOMAIN should pass"

    # Note: Cannot test invalid cases as validate_env_vars calls die() on failure
    # which would terminate the test script

    # Clean up
    unset DOMAIN REALITY_PORT
}

#==============================================================================
# Yes/No Validation Tests
#==============================================================================

test_yes_no_validation() {
    echo ""
    echo "Testing yes/no validation..."

    # Valid single-character inputs
    validate_yes_no "y" 2>/dev/null
    assert_equals "0" "$?" "Input 'y' should be valid"

    validate_yes_no "Y" 2>/dev/null
    assert_equals "0" "$?" "Input 'Y' should be valid"

    validate_yes_no "n" 2>/dev/null
    assert_equals "0" "$?" "Input 'n' should be valid"

    validate_yes_no "N" 2>/dev/null
    assert_equals "0" "$?" "Input 'N' should be valid"

    # Invalid inputs (function only accepts single chars Y/y/N/n)
    ! validate_yes_no "yes" 2>/dev/null
    assert_equals "0" "$?" "Full word 'yes' should fail (only Y/y accepted)"

    ! validate_yes_no "no" 2>/dev/null
    assert_equals "0" "$?" "Full word 'no' should fail (only N/n accepted)"

    ! validate_yes_no "maybe" 2>/dev/null
    assert_equals "0" "$?" "Invalid input 'maybe' should fail"

    ! validate_yes_no "123" 2>/dev/null
    assert_equals "0" "$?" "Invalid input '123' should fail"

    ! validate_yes_no "" 2>/dev/null
    assert_equals "0" "$?" "Empty input should fail"
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    # Disable strict mode for tests (assertions return non-zero on purpose)
    set +e

    echo "=========================================="
    echo "Enhanced Validation Unit Tests"
    echo "=========================================="

    run_test_suite "Validation Tests" setup run_all_tests teardown

    print_test_summary
    return $?
}

run_all_tests() {
    test_domain_validation
    test_port_validation
    test_ip_validation
    test_env_var_validation
    test_yes_no_validation
}

# Run tests if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
    exit $?
fi
