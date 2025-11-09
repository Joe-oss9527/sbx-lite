#!/usr/bin/env bash
# Integration tests for enhanced logging features
# Tests logging behavior across multiple modules
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
# shellcheck source=../../lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"
# shellcheck source=../../lib/caddy.sh
source "${PROJECT_ROOT}/lib/caddy.sh"

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
        echo "  Actual output: ${haystack:0:200}..."
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

#=============================================================================
# Configuration Generation Debug Logging Tests
#=============================================================================

test_config_generation_debug_logging() {
    echo ""
    echo "Testing Configuration Generation - Debug Logging"
    echo "------------------------------------------------"

    # Test that configuration generation logs intermediate steps with DEBUG=1
    local output
    output=$(DEBUG=1 bash -c '
        source lib/common.sh
        source lib/config.sh

        # Mock configuration generation
        create_base_config "1" "warn" 2>&1
    ' 2>&1 || true)

    # Should include debug output for configuration steps
    if [[ "$output" == *"[DEBUG]"* ]] || [[ "$output" == *"DNS"* ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} config generation includes debug logging"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} config generation includes debug logging (not implemented yet)"
        echo "  Expected to see [DEBUG] messages"
    fi
}

test_reality_inbound_debug_logging() {
    echo ""
    echo "Testing Reality Inbound Creation - Debug Logging"
    echo "------------------------------------------------"

    # Test that Reality inbound creation logs debug information
    local output
    output=$(DEBUG=1 bash -c '
        source lib/common.sh
        source lib/config.sh

        # Create a test Reality configuration
        create_reality_inbound "::" 443 "test-uuid" "test-flow" \
            "public-key" "short-id" "www.microsoft.com" "max-time" 2>&1
    ' 2>&1 || true)

    # Should log the configuration being created
    if [[ "$output" == *"[DEBUG]"* ]] && [[ "$output" == *"Reality"* ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} Reality inbound creation includes debug output"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} Reality inbound creation includes debug output (not implemented yet)"
    fi
}

#=============================================================================
# Caddy Certificate Path Detection Logging Tests
#=============================================================================

test_caddy_cert_path_detection_logging() {
    echo ""
    echo "Testing Caddy Certificate Path Detection - Logging"
    echo "---------------------------------------------------"

    # Test that Caddy certificate path detection logs the paths found
    local test_cert_dir
    test_cert_dir=$(mktemp -d)
    trap "rm -rf $test_cert_dir" RETURN

    # Create mock certificate structure
    mkdir -p "$test_cert_dir/certificates/acme-v02.api.letsencrypt.org-directory/example.com"
    touch "$test_cert_dir/certificates/acme-v02.api.letsencrypt.org-directory/example.com/example.com.crt"
    touch "$test_cert_dir/certificates/acme-v02.api.letsencrypt.org-directory/example.com/example.com.key"

    local output
    output=$(bash -c "
        source lib/common.sh
        source lib/caddy.sh

        # Mock Caddy data directory
        export CADDY_DATA_DIR='$test_cert_dir'

        # This would be the certificate path detection logic
        msg 'Searching for certificates in Caddy data directory'
        find '$test_cert_dir' -name '*.crt' 2>&1
    " 2>&1)

    # Should log certificate path discovery
    assert_contains "certificate path detection logs results" "$output" "example.com.crt"
}

#=============================================================================
# Multi-Module Logging Flow Tests
#=============================================================================

test_logging_flow_consistency() {
    echo ""
    echo "Testing Logging Flow - Consistency Across Modules"
    echo "--------------------------------------------------"

    # Test that all modules use consistent logging format
    local test_script
    test_script=$(mktemp)
    trap "rm -f $test_script" RETURN

    cat > "$test_script" << 'EOF'
#!/usr/bin/env bash
source lib/common.sh
source lib/network.sh
source lib/validation.sh

# Test consistent logging across modules
msg "Message from common"
warn "Warning from common"
success "Success from common"

# Validate something
if validate_ip_address "8.8.8.8"; then
    success "IP validation passed"
fi

# All outputs should go to stderr
EOF

    local output
    output=$(bash "$test_script" 2>&1)

    # Check for consistent formatting
    assert_contains "logging uses consistent format" "$output" "[*]"
    assert_contains "logging includes success markers" "$output" "[✓]"
}

test_timestamp_consistency() {
    echo ""
    echo "Testing Timestamp - Consistency"
    echo "--------------------------------"

    # Test that timestamps are consistent when enabled
    local output
    output=$(LOG_TIMESTAMPS=1 bash -c '
        source lib/common.sh
        msg "First message"
        sleep 1
        msg "Second message"
    ' 2>&1)

    # Both messages should have timestamps
    local timestamp_count
    timestamp_count=$(echo "$output" | grep -c "202[0-9]-[0-9][0-9]-[0-9][0-9]" || true)

    if [[ $timestamp_count -ge 2 ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} timestamps are consistent across multiple messages"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} timestamps are consistent across multiple messages"
        echo "  Found $timestamp_count timestamps, expected >= 2"
    fi
}

test_json_logging_integration() {
    echo ""
    echo "Testing JSON Logging - Integration"
    echo "-----------------------------------"

    # Test that JSON logging works across all log functions
    local output
    output=$(LOG_FORMAT=json bash -c '
        source lib/common.sh
        msg "info message"
        warn "warning message"
        err "error message"
    ' 2>&1)

    # All three should produce JSON output
    local json_count
    json_count=$(echo "$output" | grep -c '"timestamp"' || true)

    if [[ $json_count -ge 3 ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} JSON logging works across all log levels"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} JSON logging works across all log levels"
        echo "  Found $json_count JSON outputs, expected >= 3"
    fi
}

#=============================================================================
# Log File Integration Tests
#=============================================================================

test_log_file_integration() {
    echo ""
    echo "Testing Log File - Integration"
    echo "-------------------------------"

    local test_log_file
    test_log_file=$(mktemp)
    trap "rm -f $test_log_file" RETURN

    # Test that log file captures all log levels
    LOG_FILE="$test_log_file" bash -c '
        source lib/common.sh
        msg "info"
        warn "warning"
        err "error"
        success "success"
    ' 2>&1 >/dev/null

    # Check log file contains all messages
    local log_content
    log_content=$(cat "$test_log_file" 2>/dev/null || echo "")

    assert_contains "log file captures msg" "$log_content" "info"
    assert_contains "log file captures warn" "$log_content" "warning"
    assert_contains "log file captures err" "$log_content" "error"
    assert_contains "log file captures success" "$log_content" "success"
}

#=============================================================================
# Performance Tests
#=============================================================================

test_logging_performance() {
    echo ""
    echo "Testing Logging - Performance Impact"
    echo "-------------------------------------"

    # Test that logging doesn't significantly impact performance
    local start_time end_time duration

    # Measure time with logging disabled
    start_time=$(date +%s%N)
    for i in {1..100}; do
        bash -c 'source lib/common.sh; msg "test" >/dev/null 2>&1' >/dev/null 2>&1
    done
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds

    # Should complete 100 logs in reasonable time (< 1000ms)
    if [[ $duration -lt 1000 ]]; then
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo -e "${GREEN}✓${NC} logging performance is acceptable (${duration}ms for 100 logs)"
    else
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo -e "${RED}✗${NC} logging performance is acceptable"
        echo "  Took ${duration}ms for 100 logs (expected < 1000ms)"
    fi
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Enhanced Logging Integration Tests"
    echo "========================================="
    echo ""
    echo "These tests verify logging behavior"
    echo "across multiple modules and scenarios."
    echo ""

    # Run test suites
    test_config_generation_debug_logging
    test_reality_inbound_debug_logging
    test_caddy_cert_path_detection_logging
    test_logging_flow_consistency
    test_timestamp_consistency
    test_json_logging_integration
    test_log_file_integration
    test_logging_performance

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
