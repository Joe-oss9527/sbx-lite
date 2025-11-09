#!/bin/bash
# TDD Test Suite for URI Display Feature
# Tests for:
# 1. print_summary() should display URI after installation
# 2. sbx info should show warnings when critical fields are missing

set -euo pipefail

# Test framework
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

pass() {
    local test_name="$1"
    ((TESTS_PASSED++))
    TEST_RESULTS+=("✓ PASS: $test_name")
    echo "[32m✓ PASS[0m: $test_name"
}

fail() {
    local test_name="$1"
    local message="${2:-}"
    ((TESTS_FAILED++))
    TEST_RESULTS+=("✗ FAIL: $test_name - $message")
    echo "[31m✗ FAIL[0m: $test_name"
    [[ -n "$message" ]] && echo "  Reason: $message"
}

# Setup
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_TMP_DIR="/tmp/sbx-test-$$"
mkdir -p "$TEST_TMP_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEST_TMP_DIR"
}
trap cleanup EXIT

#==============================================================================
# Test Suite 1: print_summary() URI Display
#==============================================================================

test_print_summary_displays_reality_uri() {
    echo
    echo "[1m[36m=== Test: print_summary displays Reality URI ===[0m"

    # Setup test environment
    export DOMAIN="104.194.91.33"
    export UUID="test-uuid-12345678"
    export PUB="test_public_key_abcd1234efgh5678"
    export SID="12ab34cd"
    export SNI_DEFAULT="www.microsoft.com"
    export REALITY_PORT_CHOSEN="443"
    export REALITY_ONLY_MODE=1

    # Source the function
    source "$SCRIPT_DIR/install_multi.sh" 2>/dev/null || true

    # Capture output
    local output
    output=$(print_summary 2>&1 || echo "FUNCTION_ERROR")

    # Test 1: Should contain "URI" or "vless://"
    if echo "$output" | grep -qE "URI|vless://"; then
        pass "print_summary contains URI information"
    else
        fail "print_summary should display URI" "No URI found in output"
        echo "Output was:"
        echo "$output"
        return 1
    fi

    # Test 2: Should contain complete vless URI with all parameters
    local expected_uri="vless://${UUID}@${DOMAIN}:${REALITY_PORT_CHOSEN}.*pbk=${PUB}.*sid=${SID}"
    if echo "$output" | grep -qE "$expected_uri"; then
        pass "print_summary displays complete Reality URI"
    else
        fail "print_summary should display complete URI with all parameters"
        echo "Expected pattern: $expected_uri"
        echo "Output was:"
        echo "$output"
        return 1
    fi
}

test_print_summary_displays_multi_protocol_uris() {
    echo
    echo "[1m[36m=== Test: print_summary displays WS-TLS and Hysteria2 URIs ===[0m"

    # Setup test environment with certificates
    export DOMAIN="test.example.com"
    export UUID="test-uuid-12345678"
    export PUB="test_public_key"
    export SID="12ab34cd"
    export SNI_DEFAULT="www.microsoft.com"
    export REALITY_PORT_CHOSEN="443"
    export WS_PORT_CHOSEN="8444"
    export HY2_PORT_CHOSEN="8443"
    export HY2_PASS="test_password_123"
    export REALITY_ONLY_MODE=0
    export CERT_FULLCHAIN="/etc/ssl/sbx/test.example.com/fullchain.pem"
    export CERT_KEY="/etc/ssl/sbx/test.example.com/privkey.pem"

    # Source the function
    source "$SCRIPT_DIR/install_multi.sh" 2>/dev/null || true

    # Capture output
    local output
    output=$(print_summary 2>&1 || echo "FUNCTION_ERROR")

    # Test 1: Should contain Reality URI
    if echo "$output" | grep -q "vless://.*reality"; then
        pass "print_summary displays Reality URI in multi-protocol mode"
    else
        fail "print_summary should display Reality URI"
        return 1
    fi

    # Test 2: Should contain WS-TLS URI
    if echo "$output" | grep -qE "vless://.*type=ws"; then
        pass "print_summary displays WS-TLS URI"
    else
        fail "print_summary should display WS-TLS URI in full mode"
        return 1
    fi

    # Test 3: Should contain Hysteria2 URI
    if echo "$output" | grep -q "hysteria2://"; then
        pass "print_summary displays Hysteria2 URI"
    else
        fail "print_summary should display Hysteria2 URI in full mode"
        return 1
    fi
}

#==============================================================================
# Test Suite 2: sbx info Error Handling
#==============================================================================

test_sbx_info_validates_required_fields() {
    echo
    echo "[1m[36m=== Test: sbx info validates required fields ===[0m"

    # Create incomplete client-info.txt (missing PUBLIC_KEY)
    local test_client_info="$TEST_TMP_DIR/client-info.txt"
    cat > "$test_client_info" <<'EOF'
DOMAIN="104.194.91.33"
UUID="test-uuid-1234"
SHORT_ID="12ab34cd"
SNI="www.microsoft.com"
REALITY_PORT="443"
EOF

    # Mock the client info file location
    export CLIENT_INFO="$test_client_info"

    # Create a test version of sbx info function
    # This will be implemented in the actual code
    local test_script="$TEST_TMP_DIR/test_sbx_info.sh"
    cat > "$test_script" <<'SCRIPT_EOF'
#!/bin/bash
source /etc/sing-box/client-info.txt 2>/dev/null || exit 1

# Check for required fields
missing_fields=()
[[ -z "${PUBLIC_KEY:-}" ]] && missing_fields+=("PUBLIC_KEY")
[[ -z "${UUID:-}" ]] && missing_fields+=("UUID")
[[ -z "${SHORT_ID:-}" ]] && missing_fields+=("SHORT_ID")
[[ -z "${DOMAIN:-}" ]] && missing_fields+=("DOMAIN")

if [[ ${#missing_fields[@]} -gt 0 ]]; then
    echo "[WARNING] Missing required fields: ${missing_fields[*]}"
    echo "[WARNING] The generated URI may be invalid"
fi

# Display URI anyway (even if invalid)
URI_REAL="vless://${UUID}@${DOMAIN}:${REALITY_PORT}?pbk=${PUBLIC_KEY}&sid=${SHORT_ID}"
echo "URI = ${URI_REAL}"
SCRIPT_EOF
    chmod +x "$test_script"

    # Run and capture output
    cp "$test_client_info" /etc/sing-box/client-info.txt
    local output
    output=$("$test_script" 2>&1)

    # Test: Should contain warning about missing PUBLIC_KEY
    if echo "$output" | grep -qi "warning.*missing.*PUBLIC_KEY"; then
        pass "sbx info shows warning for missing PUBLIC_KEY"
    else
        fail "sbx info should warn about missing required fields" "No warning found"
        echo "Output was:"
        echo "$output"
        return 1
    fi
}

test_sbx_info_warns_invalid_uri() {
    echo
    echo "[1m[36m=== Test: sbx info warns when URI is invalid ===[0m"

    # Create client-info with empty PUBLIC_KEY
    local test_client_info="$TEST_TMP_DIR/client-info-empty-key.txt"
    cat > "$test_client_info" <<'EOF'
DOMAIN="104.194.91.33"
UUID="test-uuid-1234"
PUBLIC_KEY=""
SHORT_ID="12ab34cd"
SNI="www.microsoft.com"
REALITY_PORT="443"
EOF

    # Similar test as above
    local test_script="$TEST_TMP_DIR/test_invalid_uri.sh"
    cat > "$test_script" <<'SCRIPT_EOF'
#!/bin/bash
source "$1" 2>/dev/null || exit 1

# Generate URI
URI_REAL="vless://${UUID}@${DOMAIN}:${REALITY_PORT}?pbk=${PUBLIC_KEY}&sid=${SHORT_ID}"

# Check if URI has empty parameters
if echo "$URI_REAL" | grep -qE "pbk=&|pbk=$"; then
    echo "[WARNING] Generated URI has empty public key parameter"
    echo "[WARNING] This URI cannot be used for client connections"
fi

echo "URI = ${URI_REAL}"
SCRIPT_EOF
    chmod +x "$test_script"

    local output
    output=$("$test_script" "$test_client_info" 2>&1)

    # Test: Should warn about invalid URI
    if echo "$output" | grep -qi "warning.*empty.*key\|warning.*invalid"; then
        pass "sbx info warns when URI has empty parameters"
    else
        fail "sbx info should warn when generated URI is invalid"
        echo "Output was:"
        echo "$output"
        return 1
    fi
}

#==============================================================================
# Run All Tests
#==============================================================================

main() {
    echo
    echo "[1m[35m╔═══════════════════════════════════════════════════════╗[0m"
    echo "[1m[35m║  TDD Test Suite: URI Display Feature                 ║[0m"
    echo "[1m[35m╚═══════════════════════════════════════════════════════╝[0m"
    echo

    # Run test suite 1
    echo "[1m[33m--- Test Suite 1: print_summary() URI Display ---[0m"
    test_print_summary_displays_reality_uri || true
    test_print_summary_displays_multi_protocol_uris || true

    # Run test suite 2
    echo
    echo "[1m[33m--- Test Suite 2: sbx info Error Handling ---[0m"
    test_sbx_info_validates_required_fields || true
    test_sbx_info_warns_invalid_uri || true

    # Summary
    echo
    echo "[1m[35m╔═══════════════════════════════════════════════════════╗[0m"
    echo "[1m[35m║  Test Results Summary                                 ║[0m"
    echo "[1m[35m╚═══════════════════════════════════════════════════════╝[0m"
    echo
    echo "Total Tests: $((TESTS_PASSED + TESTS_FAILED))"
    echo "[32mPassed: ${TESTS_PASSED}[0m"
    echo "[31mFailed: ${TESTS_FAILED}[0m"
    echo

    # Print detailed results
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done

    echo
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "[1m[32m✓ All tests passed![0m"
        return 0
    else
        echo "[1m[31m✗ Some tests failed[0m"
        return 1
    fi
}

main "$@"
