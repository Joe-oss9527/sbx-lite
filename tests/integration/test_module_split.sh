#!/usr/bin/env bash
# tests/integration/test_module_split.sh - Integration test for module split
# Verifies that splitting common.sh doesn't break functionality

set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    local test_name="$1"
    local result="$2"

    TESTS_RUN=$((TESTS_RUN + 1))

    if [[ "$result" == "pass" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo "  ✓ $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo "  ✗ $test_name"
    fi
}

echo "=========================================="
echo "Module Split Integration Test"
echo "=========================================="

#==============================================================================
# Test 1: Logging module loads correctly
#==============================================================================

echo ""
echo "Test 1: Logging functions work after split"

# Source the new logging module
if source "${PROJECT_ROOT}/lib/logging.sh" 2>/dev/null; then
    test_result "lib/logging.sh loads successfully" "pass"
else
    test_result "lib/logging.sh loads successfully" "fail"
    echo "ERROR: Failed to load lib/logging.sh"
    exit 1
fi

# Test logging functions exist
if declare -f msg >/dev/null 2>&1 && \
   declare -f warn >/dev/null 2>&1 && \
   declare -f err >/dev/null 2>&1 && \
   declare -f info >/dev/null 2>&1 && \
   declare -f success >/dev/null 2>&1 && \
   declare -f debug >/dev/null 2>&1; then
    test_result "All logging functions defined" "pass"
else
    test_result "All logging functions defined" "fail"
fi

# Test logging functions work
TEST_LOG="/tmp/test_log_$$"
export LOG_FILE="$TEST_LOG"
msg "Test message" 2>/dev/null
if [[ -f "$TEST_LOG" ]] && grep -q "Test message" "$TEST_LOG"; then
    test_result "Logging functions write to file" "pass"
else
    test_result "Logging functions write to file" "fail"
fi
rm -f "$TEST_LOG"

#==============================================================================
# Test 2: Generators module loads correctly
#==============================================================================

echo ""
echo "Test 2: Generator functions work after split"

# Source the generators module
if source "${PROJECT_ROOT}/lib/generators.sh" 2>/dev/null; then
    test_result "lib/generators.sh loads successfully" "pass"
else
    test_result "lib/generators.sh loads successfully" "fail"
fi

# Test generator functions exist
if declare -f generate_uuid >/dev/null 2>&1 && \
   declare -f generate_hex_string >/dev/null 2>&1; then
    test_result "All generator functions defined" "pass"
else
    test_result "All generator functions defined" "fail"
fi

# Test UUID generation works
UUID=$(generate_uuid 2>/dev/null || echo "")
if [[ "$UUID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
    test_result "generate_uuid produces valid UUID" "pass"
else
    test_result "generate_uuid produces valid UUID" "fail"
fi

# Test hex string generation works
HEX=$(generate_hex_string 16 2>/dev/null || echo "")
if [[ "$HEX" =~ ^[0-9a-f]{32}$ ]]; then
    test_result "generate_hex_string produces valid hex" "pass"
else
    test_result "generate_hex_string produces valid hex" "fail"
fi

#==============================================================================
# Test 3: Common module still works
#==============================================================================

echo ""
echo "Test 3: Core utility functions remain in common.sh"

# Re-source common.sh (should load logging and generators automatically)
if source "${PROJECT_ROOT}/lib/common.sh" 2>/dev/null; then
    test_result "lib/common.sh loads successfully" "pass"
else
    test_result "lib/common.sh loads successfully" "fail"
fi

# Test utility functions exist
if declare -f have >/dev/null 2>&1 && \
   declare -f need_root >/dev/null 2>&1 && \
   declare -f get_file_size >/dev/null 2>&1; then
    test_result "Core utility functions defined" "pass"
else
    test_result "Core utility functions defined" "fail"
fi

# Test have() function works
if have bash; then
    test_result "have() function works" "pass"
else
    test_result "have() function works" "fail"
fi

# Test get_file_size() function works
echo "test" > /tmp/test_size_$$
SIZE=$(get_file_size /tmp/test_size_$$ 2>/dev/null || echo "0")
rm -f /tmp/test_size_$$
if [[ "$SIZE" -gt 0 ]]; then
    test_result "get_file_size() function works" "pass"
else
    test_result "get_file_size() function works" "fail"
fi

#==============================================================================
# Test 4: All modules can be sourced together
#==============================================================================

echo ""
echo "Test 4: Modules work together without conflicts"

# Fresh shell environment test
bash -c "
    source '${PROJECT_ROOT}/lib/common.sh' || exit 1
    source '${PROJECT_ROOT}/lib/logging.sh' || exit 1
    source '${PROJECT_ROOT}/lib/generators.sh' || exit 1

    # Test that functions still work
    have bash || exit 1
    msg 'Test' 2>/dev/null || exit 1
    generate_uuid >/dev/null 2>&1 || exit 1

    exit 0
" 2>/dev/null

if [[ $? -eq 0 ]]; then
    test_result "Modules load together without conflicts" "pass"
else
    test_result "Modules load together without conflicts" "fail"
fi

#==============================================================================
# Test 5: Backward compatibility with existing scripts
#==============================================================================

echo ""
echo "Test 5: Backward compatibility maintained"

# Test that old code still works (sourcing only common.sh should work)
bash -c "
    source '${PROJECT_ROOT}/lib/common.sh' || exit 1

    # All functions should be available
    msg 'Test message' 2>/dev/null || exit 1
    have bash || exit 1
    UUID=\$(generate_uuid 2>/dev/null) || exit 1
    [[ -n \"\$UUID\" ]] || exit 1

    exit 0
" 2>/dev/null

if [[ $? -eq 0 ]]; then
    test_result "Backward compatibility maintained" "pass"
else
    test_result "Backward compatibility maintained" "fail"
fi

#==============================================================================
# Summary
#==============================================================================

echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Total:  $TESTS_RUN"
echo "Passed: $TESTS_PASSED"
echo "Failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All module split tests passed!"
    exit 0
else
    echo "✗ $TESTS_FAILED test(s) failed"
    exit 1
fi
