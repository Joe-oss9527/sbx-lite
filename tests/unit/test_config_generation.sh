#!/usr/bin/env bash
# Unit tests for configuration generation functions (lib/config.sh)
# Tests for: create_base_config, create_reality_inbound, JSON validation
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
# shellcheck source=../../lib/config.sh
source "${PROJECT_ROOT}/lib/config.sh"

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

assert_json_valid() {
    local test_name="$1"
    local json_string="$2"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if echo "$json_string" | jq empty 2>/dev/null; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name (invalid JSON)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

assert_json_has_key() {
    local test_name="$1"
    local json_string="$2"
    local key_path="$3"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local value
    value=$(echo "$json_string" | jq -r "$key_path" 2>/dev/null)

    if [[ -n "$value" && "$value" != "null" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name (key '$key_path' not found or null)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

assert_json_value_equals() {
    local test_name="$1"
    local json_string="$2"
    local key_path="$3"
    local expected="$4"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    local actual
    actual=$(echo "$json_string" | jq -r "$key_path" 2>/dev/null)

    if [[ "$actual" == "$expected" ]]; then
        echo -e "${GREEN}✓${NC} $test_name"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} $test_name"
        echo -e "    Expected: '$expected'"
        echo -e "    Got:      '$actual'"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
    return 0
}

#=============================================================================
# create_base_config() Tests
#=============================================================================

test_create_base_config_ipv4_only() {
    echo ""
    echo "Testing create_base_config() - IPv4-only Mode"
    echo "----------------------------------------------"

    local config
    config=$(create_base_config "false" "warn" 2>/dev/null)

    assert_json_valid "Generates valid JSON" "$config"
    assert_json_has_key "Has log section" "$config" ".log"
    assert_json_has_key "Has dns section" "$config" ".dns"
    assert_json_has_key "Has inbounds array" "$config" ".inbounds"
    assert_json_has_key "Has outbounds array" "$config" ".outbounds"

    # Check IPv4-only DNS strategy
    assert_json_value_equals "DNS strategy is ipv4_only" "$config" ".dns.strategy" "ipv4_only"

    # Check log level
    assert_json_value_equals "Log level is warn" "$config" ".log.level" "warn"

    # Check outbounds
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local outbound_count
    outbound_count=$(echo "$config" | jq '.outbounds | length' 2>/dev/null)
    if [[ "$outbound_count" -ge 2 ]]; then
        echo -e "${GREEN}✓${NC} Has at least 2 outbounds (direct, block)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Missing outbounds (expected 2+, got $outbound_count)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_create_base_config_dual_stack() {
    echo ""
    echo "Testing create_base_config() - Dual-Stack Mode"
    echo "-----------------------------------------------"

    local config
    config=$(create_base_config "true" "info" 2>/dev/null)

    assert_json_valid "Generates valid JSON" "$config"

    # Check NO IPv4-only strategy for dual-stack
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local strategy
    strategy=$(echo "$config" | jq -r '.dns.strategy // "none"' 2>/dev/null)
    if [[ "$strategy" == "none" || "$strategy" == "null" ]]; then
        echo -e "${GREEN}✓${NC} DNS strategy not set (dual-stack default)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Unexpected DNS strategy: $strategy"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check log level
    assert_json_value_equals "Log level is info" "$config" ".log.level" "info"
}

test_create_base_config_log_levels() {
    echo ""
    echo "Testing create_base_config() - Log Levels"
    echo "------------------------------------------"

    local levels=("trace" "debug" "info" "warn" "error" "fatal")

    for level in "${levels[@]}"; do
        TOTAL_TESTS=$((TOTAL_TESTS + 1))
        local config
        config=$(create_base_config "false" "$level" 2>/dev/null)

        local actual_level
        actual_level=$(echo "$config" | jq -r '.log.level' 2>/dev/null)

        if [[ "$actual_level" == "$level" ]]; then
            echo -e "${GREEN}✓${NC} Accepts log level: $level"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo -e "${RED}✗${NC} Failed to set log level: $level (got: $actual_level)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    done
}

#=============================================================================
# create_reality_inbound() Tests
#=============================================================================

test_create_reality_inbound_basic() {
    echo ""
    echo "Testing create_reality_inbound() - Basic Functionality"
    echo "------------------------------------------------------"

    # Test data
    local test_uuid="123e4567-e89b-12d3-a456-426614174000"
    local test_port="443"
    local test_listen="::"
    local test_sni="www.microsoft.com"
    local test_priv="EKlZxErkrHGkRKTyR7oiQ4jF-eO8w9BNYQ_MfB8BAnk"
    local test_sid="abcdef12"

    local reality_config
    reality_config=$(create_reality_inbound "$test_uuid" "$test_port" "$test_listen" \
        "$test_sni" "$test_priv" "$test_sid" 2>/dev/null)

    assert_json_valid "Generates valid JSON" "$reality_config"
    assert_json_has_key "Has type field" "$reality_config" ".type"
    assert_json_has_key "Has tag field" "$reality_config" ".tag"
    assert_json_has_key "Has listen field" "$reality_config" ".listen"
    assert_json_has_key "Has listen_port field" "$reality_config" ".listen_port"
    assert_json_has_key "Has users array" "$reality_config" ".users"
    assert_json_has_key "Has tls section" "$reality_config" ".tls"

    # Check specific values
    assert_json_value_equals "Type is vless" "$reality_config" ".type" "vless"
    assert_json_value_equals "Listen is ::" "$reality_config" ".listen" "::"
    assert_json_value_equals "Port is $test_port" "$reality_config" ".listen_port" "$test_port"

    # Check Reality TLS section
    assert_json_has_key "Has Reality config" "$reality_config" ".tls.reality"
    assert_json_has_key "Has private_key" "$reality_config" ".tls.reality.private_key"
    assert_json_has_key "Has short_id" "$reality_config" ".tls.reality.short_id"

    # Check user configuration
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local user_uuid
    user_uuid=$(echo "$reality_config" | jq -r '.users[0].uuid' 2>/dev/null)
    if [[ "$user_uuid" == "$test_uuid" ]]; then
        echo -e "${GREEN}✓${NC} User UUID correctly set"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} User UUID mismatch (expected: $test_uuid, got: $user_uuid)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_create_reality_inbound_security() {
    echo ""
    echo "Testing create_reality_inbound() - Security Features"
    echo "-----------------------------------------------------"

    local test_uuid="123e4567-e89b-12d3-a456-426614174000"
    local test_port="443"
    local test_listen="::"
    local test_sni="www.microsoft.com"
    local test_priv="EKlZxErkrHGkRKTyR7oiQ4jF-eO8w9BNYQ_MfB8BAnk"
    local test_sid="abcdef12"

    local reality_config
    reality_config=$(create_reality_inbound "$test_uuid" "$test_port" "$test_listen" \
        "$test_sni" "$test_priv" "$test_sid" 2>/dev/null)

    # Check for XTLS flow
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local flow
    flow=$(echo "$reality_config" | jq -r '.users[0].flow // "none"' 2>/dev/null)
    if [[ "$flow" == "xtls-rprx-vision" ]]; then
        echo -e "${GREEN}✓${NC} Uses XTLS-RPRX-Vision flow"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Missing or incorrect flow (got: $flow)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check for max_time_difference (anti-replay protection)
    assert_json_has_key "Has anti-replay protection" "$reality_config" ".tls.reality.max_time_difference"

    # Check server_name (SNI)
    assert_json_value_equals "Server name is $test_sni" "$reality_config" ".tls.server_name" "$test_sni"
}

#=============================================================================
# JSON Structure Validation Tests
#=============================================================================

test_json_structure_compliance() {
    echo ""
    echo "Testing JSON Structure - sing-box 1.12.0+ Compliance"
    echo "-----------------------------------------------------"

    local base_config
    base_config=$(create_base_config "false" "warn" 2>/dev/null)

    # Check for required top-level sections
    assert_json_has_key "Has log section" "$base_config" ".log"
    assert_json_has_key "Has dns section" "$base_config" ".dns"
    assert_json_has_key "Has inbounds section" "$base_config" ".inbounds"
    assert_json_has_key "Has outbounds section" "$base_config" ".outbounds"

    # Check DNS servers format (sing-box 1.12.0+)
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local dns_server_type
    dns_server_type=$(echo "$base_config" | jq -r '.dns.servers[0].type' 2>/dev/null)
    if [[ "$dns_server_type" == "local" ]]; then
        echo -e "${GREEN}✓${NC} DNS server uses modern format (type: local)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} DNS server format incorrect (got type: $dns_server_type)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check log has timestamp
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local log_timestamp
    log_timestamp=$(echo "$base_config" | jq -r '.log.timestamp' 2>/dev/null)
    if [[ "$log_timestamp" == "true" ]]; then
        echo -e "${GREEN}✓${NC} Log timestamp enabled"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Log timestamp not enabled"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

test_deprecated_fields_not_present() {
    echo ""
    echo "Testing Deprecated Fields - Not Present"
    echo "----------------------------------------"

    local reality_config
    reality_config=$(create_reality_inbound "test-uuid" "443" "::" \
        "www.microsoft.com" "test-key" "abcdef12" 2>/dev/null)

    # Check NO deprecated inbound fields (sing-box 1.12.0+)
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local has_sniff
    has_sniff=$(echo "$reality_config" | jq 'has("sniff")' 2>/dev/null)
    if [[ "$has_sniff" == "false" ]]; then
        echo -e "${GREEN}✓${NC} No deprecated 'sniff' field in inbound"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Deprecated 'sniff' field present in inbound"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local has_sniff_override
    has_sniff_override=$(echo "$reality_config" | jq 'has("sniff_override_destination")' 2>/dev/null)
    if [[ "$has_sniff_override" == "false" ]]; then
        echo -e "${GREEN}✓${NC} No deprecated 'sniff_override_destination' field"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Deprecated 'sniff_override_destination' field present"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi

    # Check outbound doesn't have deprecated domain_strategy
    local base_config
    base_config=$(create_base_config "false" "warn" 2>/dev/null)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    local has_domain_strategy
    has_domain_strategy=$(echo "$base_config" | jq '.outbounds[0] | has("domain_strategy")' 2>/dev/null)
    if [[ "$has_domain_strategy" == "false" ]]; then
        echo -e "${GREEN}✓${NC} No deprecated 'domain_strategy' in outbounds"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} Deprecated 'domain_strategy' field present in outbound"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

#=============================================================================
# Error Handling Tests
#=============================================================================

test_error_handling() {
    echo ""
    echo "Testing Error Handling - Invalid Inputs"
    echo "----------------------------------------"

    # Test with empty UUID (should fail gracefully)
    assert_failure "Rejects empty UUID" \
        "create_reality_inbound '' '443' '::' 'www.microsoft.com' 'key' 'abcdef12' 2>/dev/null"

    # Test with invalid port (should fail gracefully)
    assert_failure "Rejects invalid port" \
        "create_reality_inbound 'uuid' '99999' '::' 'www.microsoft.com' 'key' 'abcdef12' 2>/dev/null"

    # Test with empty private key (should fail gracefully)
    assert_failure "Rejects empty private key" \
        "create_reality_inbound 'uuid' '443' '::' 'www.microsoft.com' '' 'abcdef12' 2>/dev/null"
}

#=============================================================================
# Main Test Execution
#=============================================================================

main() {
    echo "========================================="
    echo "Configuration Generation Tests"
    echo "========================================="

    # Check if functions are exported/available
    echo ""
    echo "Pre-flight Checks"
    echo "-----------------"

    local required_functions=(
        "create_base_config"
        "create_reality_inbound"
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

    # Check for jq
    if command -v jq >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} jq is available"
    else
        echo -e "${RED}✗${NC} jq is NOT available (required for config generation)"
        echo ""
        echo "ERROR: jq is required for configuration generation tests"
        exit 1
    fi

    if [[ $missing_functions -gt 0 ]]; then
        echo ""
        echo -e "${RED}ERROR:${NC} $missing_functions required function(s) not available"
        exit 1
    fi

    # Run test suites
    test_create_base_config_ipv4_only
    test_create_base_config_dual_stack
    test_create_base_config_log_levels
    test_create_reality_inbound_basic
    test_create_reality_inbound_security
    test_json_structure_compliance
    test_deprecated_fields_not_present
    test_error_handling

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
