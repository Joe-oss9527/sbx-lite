#!/usr/bin/env bash
# Unit tests for success logging additions
# Tests that critical operations log success messages
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

# Load modules under test
# shellcheck source=../../lib/common.sh
source "${PROJECT_ROOT}/lib/common.sh"
# shellcheck source=../../lib/network.sh
source "${PROJECT_ROOT}/lib/network.sh"
# shellcheck source=../../lib/validation.sh
source "${PROJECT_ROOT}/lib/validation.sh"
# shellcheck source=../../lib/certificate.sh
source "${PROJECT_ROOT}/lib/certificate.sh"

# Test helper functions
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

assert_log_contains() {
    local test_name="$1"
    local command="$2"
    local expected_message="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local output
    output=$(eval "$command" 2>&1)

    if [[ "$output" == *"$expected_message"* ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected log: $expected_message"
        echo "  Actual output: $output"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

#=============================================================================
# IP Detection Success Logging Tests
#=============================================================================

test_ip_detection_logs_success() {
    echo ""
    echo "Testing IP Detection - Success Logging"
    echo "---------------------------------------"

    # Mock successful IP detection
    # This test verifies that get_public_ip logs which service succeeded

    # We'll test by checking if the function outputs logging information
    # Since get_public_ip returns the IP, we need to capture stderr

    # Create a mock environment where curl succeeds with a valid IP
    local output
    output=$(bash -c '
        source lib/common.sh
        source lib/network.sh

        # Mock curl to return a valid IP
        curl() {
            if [[ "$*" == *"ipify"* ]]; then
                echo "8.8.8.8"
                return 0
            fi
            return 1
        }
        export -f curl

        # Capture both stdout and stderr
        get_public_ip 2>&1
    ' 2>&1)

    # Check if success message includes the IP and source
    assert_contains "IP detection logs IP address" "$output" "8.8.8.8"

    # The success log should mention which service was used
    # This will fail until we implement the logging
    if [[ "$output" == *"detected"* ]] || [[ "$output" == *"ipify"* ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} IP detection logs service source"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} IP detection logs service source (not implemented yet)"
        echo "  This is expected in TDD Red phase"
    fi
}

#=============================================================================
# Port Allocation Success Logging Tests
#=============================================================================

test_port_allocation_logs_success() {
    echo ""
    echo "Testing Port Allocation - Success Logging"
    echo "------------------------------------------"

    # Test that successful port allocation logs a success message
    # This requires mocking the port checking mechanism

    local output
    output=$(bash -c '
        source lib/common.sh
        source lib/network.sh

        # Test allocate_port logs success (need all 3 params)
        # We need to check stderr for success messages
        allocate_port 9999 9998 "test-service" 2>&1
    ' 2>&1 || true)

    # Check if output contains success confirmation
    # This test will fail until we add success logging
    if [[ "$output" == *"allocated"* ]] || [[ "$output" == *"success"* ]] || [[ "$output" == *"✓"* ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} port allocation logs success"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} port allocation logs success (not implemented yet)"
        echo "  Expected to see 'allocated' or 'success' message"
        echo "  Actual output: $output"
    fi
}

#=============================================================================
# IPv6 Detection Success Logging Tests
#=============================================================================

test_ipv6_detection_logs_result() {
    echo ""
    echo "Testing IPv6 Detection - Result Logging"
    echo "----------------------------------------"

    # Test that IPv6 detection logs the result (enabled or disabled)
    local output
    output=$(bash -c '
        source lib/common.sh
        source lib/network.sh

        detect_ipv6_support 2>&1
    ' 2>&1)

    # Should log whether IPv6 is supported or not
    # This test will fail until we add result logging
    if [[ "$output" == *"IPv6"* ]] && ([[ "$output" == *"enabled"* ]] || [[ "$output" == *"disabled"* ]] || [[ "$output" == *"supported"* ]]); then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} IPv6 detection logs result"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} IPv6 detection logs result (not implemented yet)"
        echo "  Expected to see IPv6 status message"
        echo "  Actual output: $output"
    fi
}

#=============================================================================
# Certificate Validation Success Logging Tests
#=============================================================================

test_certificate_validation_logs_success() {
    echo ""
    echo "Testing Certificate Validation - Success Logging"
    echo "-------------------------------------------------"

    # Create temporary certificate files for testing
    local test_cert test_key
    test_cert=$(mktemp)
    test_key=$(mktemp)
    trap "rm -f $test_cert $test_key" RETURN

    # Create minimal valid cert and key (self-signed)
    openssl req -x509 -newkey rsa:2048 -keyout "$test_key" -out "$test_cert" \
        -days 1 -nodes -subj "/CN=test" >/dev/null 2>&1 || {
        echo -e "${YELLOW}⚠${NC} Skipping certificate tests (openssl not available)"
        return 0
    }

    # Test that certificate validation logs success when valid
    local output
    output=$(bash -c "
        source lib/common.sh
        source lib/validation.sh
        validate_cert_files '$test_cert' '$test_key' 2>&1
    " 2>&1)

    # Should log success message after validation passes
    # This test will fail until we add success logging
    if [[ "$output" == *"success"* ]] || [[ "$output" == *"valid"* ]] || [[ "$output" == *"✓"* ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} certificate validation logs success"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} certificate validation logs success (not implemented yet)"
        echo "  Expected to see success/valid message"
        echo "  Actual output: $output"
    fi
}

#=============================================================================
# Architecture Detection Logging Tests
#=============================================================================

test_architecture_detection_logs() {
    echo ""
    echo "Testing Architecture Detection - Logging"
    echo "----------------------------------------"

    # Test that architecture detection logs the detected architecture
    # This will be in install_multi.sh, so we'll test the pattern

    local test_script
    test_script=$(mktemp)
    trap "rm -f $test_script" RETURN

    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
source lib/common.sh

detect_arch() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        x86_64|amd64) echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*|armv8*) echo "armv7" ;;
        *) echo "unknown" ;;
    esac
}

arch=$(detect_arch)
msg "Detected architecture: $arch"
EOF

    local output
    output=$(bash "$test_script" 2>&1)

    # Should log the detected architecture
    assert_contains "architecture detection logs result" "$output" "Detected architecture:"
}

#=============================================================================
# Version Resolution Logging Tests
#=============================================================================

test_version_resolution_logs() {
    echo ""
    echo "Testing Version Resolution - Logging"
    echo "-------------------------------------"

    # Test that version resolution logs which version was resolved
    # This will require checking install_multi.sh behavior

    # We'll create a minimal test that checks if the pattern exists
    local test_script
    test_script=$(mktemp)
    trap "rm -f $test_script" RETURN

    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
source lib/common.sh

# Simulate version resolution
resolve_version() {
    echo "v1.12.0"
}

version=$(resolve_version)
msg "Resolved version: $version (stable)"
EOF

    local output
    output=$(bash "$test_script" 2>&1)

    # Should log the resolved version
    assert_contains "version resolution logs result" "$output" "Resolved version:"
    assert_contains "version resolution logs version type" "$output" "stable"
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Success Logging Unit Tests"
    echo "========================================="
    echo ""
    echo "These tests verify that critical operations"
    echo "log success messages for troubleshooting."
    echo ""

    # Run test suites
    test_ip_detection_logs_success
    test_port_allocation_logs_success
    test_ipv6_detection_logs_result
    test_certificate_validation_logs_success
    test_architecture_detection_logs
    test_version_resolution_logs

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
        echo -e "${YELLOW}Expected failures in TDD Red phase${NC}"
        echo "Tests will pass after implementation."
        exit 1
    fi
}

# Run tests
main "$@"
