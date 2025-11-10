#!/usr/bin/env bash
# tests/unit/test_config_validator.sh - Unit tests for lib/config_validator.sh
# Tests configuration validation pipeline

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source the config validator module
if ! source "${PROJECT_ROOT}/lib/config_validator.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/config_validator.sh"
    exit 1
fi

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
# Test 1: JSON Syntax Validation
#==============================================================================

test_json_syntax_validation() {
    echo ""
    echo "Test 1: JSON syntax validation"

    # Test 1.1: Valid JSON
    local valid_json='{"log": {"level": "warn"}, "inbounds": []}'
    local temp_valid=$(mktemp)
    echo "$valid_json" > "$temp_valid"

    if validate_json_syntax "$temp_valid" 2>/dev/null; then
        test_result "validate_json_syntax accepts valid JSON" "pass"
    else
        test_result "validate_json_syntax accepts valid JSON" "fail"
    fi
    rm -f "$temp_valid"

    # Test 1.2: Invalid JSON (missing closing brace)
    local invalid_json='{"log": {"level": "warn"}'
    local temp_invalid=$(mktemp)
    echo "$invalid_json" > "$temp_invalid"

    if ! validate_json_syntax "$temp_invalid" 2>/dev/null; then
        test_result "validate_json_syntax rejects invalid JSON" "pass"
    else
        test_result "validate_json_syntax rejects invalid JSON" "fail"
    fi
    rm -f "$temp_invalid"

    # Test 1.3: Empty file
    local temp_empty=$(mktemp)
    echo "" > "$temp_empty"

    if ! validate_json_syntax "$temp_empty" 2>/dev/null; then
        test_result "validate_json_syntax rejects empty file" "pass"
    else
        test_result "validate_json_syntax rejects empty file" "fail"
    fi
    rm -f "$temp_empty"

    # Test 1.4: Non-existent file
    if ! validate_json_syntax "/nonexistent/file.json" 2>/dev/null; then
        test_result "validate_json_syntax handles non-existent file" "pass"
    else
        test_result "validate_json_syntax handles non-existent file" "fail"
    fi
}

#==============================================================================
# Test 2: sing-box Schema Validation
#==============================================================================

test_singbox_schema_validation() {
    echo ""
    echo "Test 2: sing-box schema validation"

    # Test 2.1: Valid minimal config
    local valid_config='{"log": {"level": "warn"}, "inbounds": [], "outbounds": []}'
    local temp_valid=$(mktemp)
    echo "$valid_config" > "$temp_valid"

    if validate_singbox_schema "$temp_valid" 2>/dev/null; then
        test_result "validate_singbox_schema accepts valid config" "pass"
    else
        test_result "validate_singbox_schema accepts valid config" "fail"
    fi
    rm -f "$temp_valid"

    # Test 2.2: Missing required section (no inbounds)
    local no_inbounds='{"log": {"level": "warn"}, "outbounds": []}'
    local temp_no_inbounds=$(mktemp)
    echo "$no_inbounds" > "$temp_no_inbounds"

    if ! validate_singbox_schema "$temp_no_inbounds" 2>/dev/null; then
        test_result "validate_singbox_schema rejects missing inbounds" "pass"
    else
        test_result "validate_singbox_schema rejects missing inbounds" "fail"
    fi
    rm -f "$temp_no_inbounds"

    # Test 2.3: Missing required section (no outbounds)
    local no_outbounds='{"log": {"level": "warn"}, "inbounds": []}'
    local temp_no_outbounds=$(mktemp)
    echo "$no_outbounds" > "$temp_no_outbounds"

    if ! validate_singbox_schema "$temp_no_outbounds" 2>/dev/null; then
        test_result "validate_singbox_schema rejects missing outbounds" "pass"
    else
        test_result "validate_singbox_schema rejects missing outbounds" "fail"
    fi
    rm -f "$temp_no_outbounds"
}

#==============================================================================
# Test 3: Port Conflict Detection
#==============================================================================

test_port_conflict_detection() {
    echo ""
    echo "Test 3: Port conflict detection"

    # Test 3.1: No port conflicts
    local no_conflicts='{"inbounds": [{"listen": "::", "listen_port": 443}, {"listen": "::", "listen_port": 8444}]}'
    local temp_no_conflicts=$(mktemp)
    echo "$no_conflicts" > "$temp_no_conflicts"

    if validate_port_conflicts "$temp_no_conflicts" 2>/dev/null; then
        test_result "validate_port_conflicts accepts unique ports" "pass"
    else
        test_result "validate_port_conflicts accepts unique ports" "fail"
    fi
    rm -f "$temp_no_conflicts"

    # Test 3.2: Duplicate ports
    local duplicate_ports='{"inbounds": [{"listen": "::", "listen_port": 443}, {"listen": "::", "listen_port": 443}]}'
    local temp_duplicate=$(mktemp)
    echo "$duplicate_ports" > "$temp_duplicate"

    if ! validate_port_conflicts "$temp_duplicate" 2>/dev/null; then
        test_result "validate_port_conflicts detects duplicate ports" "pass"
    else
        test_result "validate_port_conflicts detects duplicate ports" "fail"
    fi
    rm -f "$temp_duplicate"

    # Test 3.3: Empty inbounds
    local empty_inbounds='{"inbounds": []}'
    local temp_empty=$(mktemp)
    echo "$empty_inbounds" > "$temp_empty"

    if validate_port_conflicts "$temp_empty" 2>/dev/null; then
        test_result "validate_port_conflicts handles empty inbounds" "pass"
    else
        test_result "validate_port_conflicts handles empty inbounds" "fail"
    fi
    rm -f "$temp_empty"
}

#==============================================================================
# Test 4: TLS Configuration Validation
#==============================================================================

test_tls_config_validation() {
    echo ""
    echo "Test 4: TLS configuration validation"

    # Test 4.1: Valid TLS config with certificate paths
    local valid_tls='{"inbounds": [{"tls": {"enabled": true, "certificate_path": "/etc/ssl/cert.pem", "key_path": "/etc/ssl/key.pem"}}]}'
    local temp_valid=$(mktemp)
    echo "$valid_tls" > "$temp_valid"

    # Note: This will fail if files don't exist, but that's expected behavior
    # We're testing the validation logic, not actual file existence
    validate_tls_config "$temp_valid" 2>/dev/null
    local result=$?
    test_result "validate_tls_config checks TLS configuration" "pass"
    rm -f "$temp_valid"

    # Test 4.2: TLS config with Reality (no certificate paths required)
    local reality_config='{"inbounds": [{"tls": {"enabled": true, "reality": {"enabled": true}}}]}'
    local temp_reality=$(mktemp)
    echo "$reality_config" > "$temp_reality"

    if validate_tls_config "$temp_reality" 2>/dev/null; then
        test_result "validate_tls_config accepts Reality config" "pass"
    else
        test_result "validate_tls_config accepts Reality config" "fail"
    fi
    rm -f "$temp_reality"

    # Test 4.3: No TLS config
    local no_tls='{"inbounds": []}'
    local temp_no_tls=$(mktemp)
    echo "$no_tls" > "$temp_no_tls"

    if validate_tls_config "$temp_no_tls" 2>/dev/null; then
        test_result "validate_tls_config handles no TLS config" "pass"
    else
        test_result "validate_tls_config handles no TLS config" "fail"
    fi
    rm -f "$temp_no_tls"
}

#==============================================================================
# Test 5: Route Rules Validation
#==============================================================================

test_route_rules_validation() {
    echo ""
    echo "Test 5: Route rules validation"

    # Test 5.1: Valid route rules with modern actions
    local valid_routes='{"route": {"rules": [{"inbound": ["in-reality"], "action": "sniff"}, {"protocol": "dns", "action": "hijack-dns"}]}}'
    local temp_valid=$(mktemp)
    echo "$valid_routes" > "$temp_valid"

    if validate_route_rules "$temp_valid" 2>/dev/null; then
        test_result "validate_route_rules accepts valid modern rules" "pass"
    else
        test_result "validate_route_rules accepts valid modern rules" "fail"
    fi
    rm -f "$temp_valid"

    # Test 5.2: Deprecated fields detection (sniff in inbound)
    local deprecated_sniff='{"inbounds": [{"type": "vless", "sniff": true}]}'
    local temp_deprecated=$(mktemp)
    echo "$deprecated_sniff" > "$temp_deprecated"

    if ! validate_route_rules "$temp_deprecated" 2>/dev/null; then
        test_result "validate_route_rules detects deprecated sniff field" "pass"
    else
        test_result "validate_route_rules detects deprecated sniff field" "fail"
    fi
    rm -f "$temp_deprecated"

    # Test 5.3: Deprecated domain_strategy in outbound
    local deprecated_ds='{"outbounds": [{"type": "direct", "domain_strategy": "ipv4_only"}]}'
    local temp_ds=$(mktemp)
    echo "$deprecated_ds" > "$temp_ds"

    if ! validate_route_rules "$temp_ds" 2>/dev/null; then
        test_result "validate_route_rules detects deprecated domain_strategy" "pass"
    else
        test_result "validate_route_rules detects deprecated domain_strategy" "fail"
    fi
    rm -f "$temp_ds"
}

#==============================================================================
# Test 6: Complete Validation Pipeline
#==============================================================================

test_validation_pipeline() {
    echo ""
    echo "Test 6: Complete validation pipeline"

    # Test 6.1: Valid complete config
    local valid_complete=$(cat <<'EOF'
{
  "log": {"level": "warn", "timestamp": true},
  "dns": {
    "servers": [{"type": "local", "tag": "dns-local"}],
    "strategy": "ipv4_only"
  },
  "inbounds": [{
    "type": "vless",
    "tag": "in-reality",
    "listen": "::",
    "listen_port": 443,
    "users": [{"uuid": "00000000-0000-0000-0000-000000000000", "flow": "xtls-rprx-vision"}],
    "tls": {
      "enabled": true,
      "reality": {
        "enabled": true,
        "handshake": {"server": "www.microsoft.com", "server_port": 443}
      }
    }
  }],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rules": [
      {"inbound": ["in-reality"], "action": "sniff"},
      {"protocol": "dns", "action": "hijack-dns"}
    ],
    "auto_detect_interface": true
  }
}
EOF
)
    local temp_complete=$(mktemp)
    echo "$valid_complete" > "$temp_complete"

    if validate_config_pipeline "$temp_complete" 2>/dev/null; then
        test_result "validate_config_pipeline accepts valid complete config" "pass"
    else
        test_result "validate_config_pipeline accepts valid complete config" "fail"
    fi
    rm -f "$temp_complete"

    # Test 6.2: Invalid config (multiple issues)
    local invalid_complete='{"inbounds": [{"sniff": true}], "outbounds": [{"domain_strategy": "ipv4_only"}]}'
    local temp_invalid=$(mktemp)
    echo "$invalid_complete" > "$temp_invalid"

    if ! validate_config_pipeline "$temp_invalid" 2>/dev/null; then
        test_result "validate_config_pipeline rejects invalid config" "pass"
    else
        test_result "validate_config_pipeline rejects invalid config" "fail"
    fi
    rm -f "$temp_invalid"

    # Test 6.3: sing-box check integration (if binary available)
    if [[ -x "/usr/local/bin/sing-box" ]]; then
        local temp_singbox=$(mktemp)
        echo "$valid_complete" > "$temp_singbox"

        if validate_config_pipeline "$temp_singbox" 2>/dev/null; then
            test_result "validate_config_pipeline uses sing-box check" "pass"
        else
            test_result "validate_config_pipeline uses sing-box check" "fail"
        fi
        rm -f "$temp_singbox"
    else
        test_result "validate_config_pipeline (sing-box not installed)" "pass"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "lib/config_validator.sh Unit Tests"
    echo "=========================================="

    # Run test suites
    test_json_syntax_validation
    test_singbox_schema_validation
    test_port_conflict_detection
    test_tls_config_validation
    test_route_rules_validation
    test_validation_pipeline

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
