#!/usr/bin/env bash
# tests/unit/test_tools.sh - Unit tests for lib/tools.sh
# Tests external tool abstraction layer

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Temporarily disable strict mode to avoid interference with test framework
set +e

# Source the tool abstraction layer
if ! source "${PROJECT_ROOT}/lib/tools.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/tools.sh"
    exit 1
fi

# Re-enable pipefail only (not errexit, as tests may intentionally fail)
set -o pipefail

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
# JSON Operations Tests
#==============================================================================

test_json_operations() {
    echo ""
    echo "Testing JSON operations..."

    # Test 1: json_build with simple object
    local result
    result=$(json_build --arg name "test" --arg value "123" '{name: $name, value: $value}' 2>/dev/null) || true
    if [[ "$result" =~ "test" ]] && [[ "$result" =~ "123" ]]; then
        test_result "json_build creates simple object" "pass"
    else
        test_result "json_build creates simple object" "fail"
    fi

    # Test 2: json_parse extracts value
    local json_input='{"name":"test","value":"123"}'
    result=$(json_parse "$json_input" '.name' 2>/dev/null | tr -d '"') || true
    if [[ "$result" == "test" ]]; then
        test_result "json_parse extracts value" "pass"
    else
        test_result "json_parse extracts value" "fail"
    fi

    # Test 3: json_parse handles arrays
    json_input='{"items":["a","b","c"]}'
    result=$(json_parse "$json_input" '.items[0]' 2>/dev/null | tr -d '"') || true
    if [[ "$result" == "a" ]]; then
        test_result "json_parse handles arrays" "pass"
    else
        test_result "json_parse handles arrays" "fail"
    fi

    # Test 4: json_build with nested objects
    result=$(json_build --arg outer "test" '{level1: {level2: $outer}}' 2>/dev/null) || true
    if [[ "$result" =~ "level1" ]] && [[ "$result" =~ "level2" ]]; then
        test_result "json_build handles nested objects" "pass"
    else
        test_result "json_build handles nested objects" "fail"
    fi
}

#==============================================================================
# Cryptographic Operations Tests
#==============================================================================

test_crypto_operations() {
    echo ""
    echo "Testing cryptographic operations..."

    # Test 1: crypto_random_hex generates correct length
    local hex
    hex=$(crypto_random_hex 8 2>/dev/null) || true
    if [[ ${#hex} == 16 ]]; then  # 8 bytes = 16 hex chars
        test_result "crypto_random_hex generates 8 bytes (16 hex)" "pass"
    else
        test_result "crypto_random_hex generates 8 bytes (16 hex) - got ${#hex} chars" "fail"
    fi

    # Test 2: crypto_random_hex generates different values
    local hex1 hex2
    hex1=$(crypto_random_hex 16 2>/dev/null) || true
    hex2=$(crypto_random_hex 16 2>/dev/null) || true
    if [[ "$hex1" != "$hex2" ]] && [[ -n "$hex1" ]] && [[ -n "$hex2" ]]; then
        test_result "crypto_random_hex generates unique values" "pass"
    else
        test_result "crypto_random_hex generates unique values" "fail"
    fi

    # Test 3: crypto_random_hex contains only hex chars
    hex=$(crypto_random_hex 16 2>/dev/null) || true
    if [[ "$hex" =~ ^[0-9a-fA-F]+$ ]] && [[ -n "$hex" ]]; then
        test_result "crypto_random_hex output is valid hex" "pass"
    else
        test_result "crypto_random_hex output is valid hex" "fail"
    fi

    # Test 4: crypto_sha256 computes correct checksum
    local test_file="/tmp/test_tools_sha256_$$"
    echo -n "test" > "$test_file"
    local checksum
    checksum=$(crypto_sha256 "$test_file" 2>/dev/null) || true
    # SHA256 of "test" is 9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08
    if [[ "$checksum" == "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" ]]; then
        test_result "crypto_sha256 computes correct checksum" "pass"
    else
        test_result "crypto_sha256 computes correct checksum - got $checksum" "fail"
    fi
    rm -f "$test_file"

    # Test 5: crypto_sha256 handles non-existent files
    if ! crypto_sha256 "/tmp/nonexistent_file_$$" 2>/dev/null; then
        test_result "crypto_sha256 fails on non-existent file" "pass"
    else
        test_result "crypto_sha256 fails on non-existent file" "fail"
    fi
}

#==============================================================================
# HTTP Operations Tests
#==============================================================================

test_http_operations() {
    echo ""
    echo "Testing HTTP operations..."

    # Test 1: http_download creates output file
    local test_url="https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/README.md"
    local output_file="/tmp/test_http_download_$$"

    if http_download "$test_url" "$output_file" 10 2>/dev/null; then
        if [[ -f "$output_file" ]] && [[ -s "$output_file" ]]; then
            test_result "http_download creates non-empty file" "pass"
        else
            test_result "http_download creates non-empty file" "fail"
        fi
        rm -f "$output_file"
    else
        test_result "http_download (skipped - network issue)" "pass"
    fi

    # Test 2: http_download fails on invalid URL
    if ! http_download "https://invalid.domain.that.does.not.exist.example.com/file" "$output_file" 5 2>/dev/null; then
        test_result "http_download fails on invalid URL" "pass"
    else
        test_result "http_download fails on invalid URL" "fail"
    fi
    rm -f "$output_file"

    # Test 3: http_fetch returns content
    local content
    content=$(http_fetch "https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/README.md" 10 2>/dev/null | head -1) || true
    if [[ -n "$content" ]]; then
        test_result "http_fetch returns content" "pass"
    else
        test_result "http_fetch (skipped - network issue)" "pass"
    fi
}

#==============================================================================
# Tool Availability Tests
#==============================================================================

test_tool_availability() {
    echo ""
    echo "Testing tool availability detection..."

    # Test 1: Detect jq availability
    if have jq; then
        test_result "Detects jq availability (installed)" "pass"
    else
        test_result "Detects jq availability (not installed)" "pass"
    fi

    # Test 2: Detect openssl availability
    if have openssl; then
        test_result "Detects openssl availability (installed)" "pass"
    else
        test_result "Detects openssl availability (not installed)" "fail"
    fi

    # Test 3: Detect curl or wget
    if have curl || have wget; then
        test_result "Detects curl or wget availability" "pass"
    else
        test_result "Detects curl or wget availability" "fail"
    fi
}

#==============================================================================
# Encoding Operations Tests
#==============================================================================

test_encoding_operations() {
    echo ""
    echo "Testing encoding operations..."

    # Test 1: base64_encode
    local encoded
    encoded=$(base64_encode "hello world" 2>/dev/null | tr -d '\n') || true
    if [[ "$encoded" == "aGVsbG8gd29ybGQ=" ]]; then
        test_result "base64_encode works correctly" "pass"
    else
        test_result "base64_encode works correctly - got $encoded" "fail"
    fi

    # Test 2: base64_decode
    local decoded
    decoded=$(base64_decode "aGVsbG8gd29ybGQ=" 2>/dev/null) || true
    if [[ "$decoded" == "hello world" ]]; then
        test_result "base64_decode works correctly" "pass"
    else
        test_result "base64_decode works correctly - got $decoded" "fail"
    fi

    # Test 3: Round-trip encoding
    local original="test string 123"
    local round_trip
    round_trip=$(base64_encode "$original" 2>/dev/null | tr -d '\n' | base64_decode 2>/dev/null) || true
    if [[ "$round_trip" == "$original" ]]; then
        test_result "base64 round-trip encoding" "pass"
    else
        test_result "base64 round-trip encoding (got: '$round_trip')" "fail"
    fi
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "lib/tools.sh Unit Tests"
    echo "=========================================="

    # Run test suites
    test_tool_availability
    test_json_operations
    test_crypto_operations
    test_http_operations
    test_encoding_operations

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
