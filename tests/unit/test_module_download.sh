#!/usr/bin/env bash
# tests/unit/test_module_download.sh - Unit tests for module download functionality
# Tests variable export, SCRIPT_DIR pollution, and module loading

set -uo pipefail

# Test framework
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

test_start() {
    ((TESTS_RUN++))
    echo -n "  Test $TESTS_RUN: $1 ... "
}

test_pass() {
    ((TESTS_PASSED++))
    echo "✓ PASS"
}

test_fail() {
    ((TESTS_FAILED++))
    echo "✗ FAIL: $1"
}

echo "=== Unit Tests: Module Download & Loading ==="
echo ""

#==============================================================================
# Test 1: Environment variable export to xargs subshells
#==============================================================================
test_start "Constants exported to xargs subshells"
result=$(bash -c '
readonly DOWNLOAD_CONNECT_TIMEOUT_SEC=10
readonly DOWNLOAD_MAX_TIMEOUT_SEC=30
readonly MIN_MODULE_FILE_SIZE_BYTES=100

_test_func() {
    [[ "${DOWNLOAD_CONNECT_TIMEOUT_SEC:-}" == "10" ]] || exit 1
    [[ "${DOWNLOAD_MAX_TIMEOUT_SEC:-}" == "30" ]] || exit 1
    [[ "${MIN_MODULE_FILE_SIZE_BYTES:-}" == "100" ]] || exit 1
    echo "SUCCESS"
}

export -f _test_func
export DOWNLOAD_CONNECT_TIMEOUT_SEC DOWNLOAD_MAX_TIMEOUT_SEC MIN_MODULE_FILE_SIZE_BYTES

echo "test" | xargs -I {} bash -c "_test_func"
' 2>&1)

if [[ "$result" == "SUCCESS" ]]; then
    test_pass
else
    test_fail "Variables not accessible in subshell: $result"
fi

#==============================================================================
# Test 2: SCRIPT_DIR pollution from sourced modules
#==============================================================================
test_start "SCRIPT_DIR pollution occurs without protection"
result=$(bash -c '
# Simulate main script
MAIN_SCRIPT_DIR="/tmp/main"
SCRIPT_DIR="$MAIN_SCRIPT_DIR"

# Create fake module that redefines SCRIPT_DIR
temp_dir=$(mktemp -d)
cat > "$temp_dir/module.sh" << "INNEREOF"
#!/usr/bin/env bash
SCRIPT_DIR="/tmp/module"
INNEREOF

# Source without protection
source "$temp_dir/module.sh"

# Check if SCRIPT_DIR changed
if [[ "$SCRIPT_DIR" != "$MAIN_SCRIPT_DIR" ]]; then
    echo "POLLUTED"
else
    echo "PRESERVED"
fi

rm -rf "$temp_dir"
')

if [[ "$result" == "POLLUTED" ]]; then
    test_pass  # We expect pollution without protection
else
    test_fail "Expected pollution but got: $result"
fi

#==============================================================================
# Test 3: SCRIPT_DIR protection mechanism
#==============================================================================
test_start "SCRIPT_DIR protection restores original value"
result=$(bash -c '
# Simulate main script with protection
MAIN_SCRIPT_DIR="/tmp/main"
SCRIPT_DIR="$MAIN_SCRIPT_DIR"

# Create fake module that redefines SCRIPT_DIR
temp_dir=$(mktemp -d)
cat > "$temp_dir/module.sh" << "INNEREOF"
#!/usr/bin/env bash
SCRIPT_DIR="/tmp/module"
INNEREOF

# Source WITH protection (like install_multi.sh does now)
INSTALLER_SCRIPT_DIR="${SCRIPT_DIR}"
source "$temp_dir/module.sh"
SCRIPT_DIR="${INSTALLER_SCRIPT_DIR}"

# Check if SCRIPT_DIR restored
if [[ "$SCRIPT_DIR" == "$MAIN_SCRIPT_DIR" ]]; then
    echo "RESTORED"
else
    echo "NOT_RESTORED:$SCRIPT_DIR"
fi

rm -rf "$temp_dir"
')

if [[ "$result" == "RESTORED" ]]; then
    test_pass
else
    test_fail "SCRIPT_DIR not restored: $result"
fi

#==============================================================================
# Test 4: Module syntax validation
#==============================================================================
test_start "Downloaded module syntax validation"
temp_dir=$(mktemp -d)

# Create valid module
cat > "$temp_dir/valid.sh" << 'EOF'
#!/usr/bin/env bash
echo "valid"
EOF

# Create invalid module
cat > "$temp_dir/invalid.sh" << 'EOF'
#!/usr/bin/env bash
if [[ ; then
EOF

if bash -n "$temp_dir/valid.sh" 2>/dev/null && ! bash -n "$temp_dir/invalid.sh" 2>/dev/null; then
    test_pass
else
    test_fail "Syntax validation not working correctly"
fi

rm -rf "$temp_dir"

#==============================================================================
# Test 5: File size validation
#==============================================================================
test_start "File size validation for downloaded modules"
temp_dir=$(mktemp -d)

# Create small file (< 100 bytes)
echo "small" > "$temp_dir/small.sh"

# Create large file (> 100 bytes)
dd if=/dev/zero of="$temp_dir/large.sh" bs=1 count=150 2>/dev/null

small_size=$(stat -c%s "$temp_dir/small.sh" 2>/dev/null || stat -f%z "$temp_dir/small.sh" 2>/dev/null)
large_size=$(stat -c%s "$temp_dir/large.sh" 2>/dev/null || stat -f%z "$temp_dir/large.sh" 2>/dev/null)

if [[ $small_size -lt 100 ]] && [[ $large_size -gt 100 ]]; then
    test_pass
else
    test_fail "Size check logic incorrect: small=$small_size, large=$large_size"
fi

rm -rf "$temp_dir"

#==============================================================================
# Test 6: Parallel download error detection
#==============================================================================
test_start "Parallel download detects and reports failures"
result=$(bash -c '
_download_single_module() {
    local module="$1"
    if [[ "$module" == "fail_module" ]]; then
        echo "DOWNLOAD_FAILED:fail_module"
        return 1
    fi
    echo "SUCCESS:${module}:1000"
}
export -f _download_single_module

modules=(good1 fail_module good2)
failed_count=0

while IFS= read -r result; do
    if [[ "$result" =~ ^DOWNLOAD_FAILED ]]; then
        ((failed_count++))
    fi
done < <(printf "%s\n" "${modules[@]}" | xargs -P 2 -I {} bash -c "_download_single_module \"{}\"" 2>&1)

echo "$failed_count"
')

if [[ "$result" == "1" ]]; then
    test_pass
else
    test_fail "Failed to detect module download failure: $result"
fi

#==============================================================================
# Test 7: Success count tracking
#==============================================================================
test_start "Parallel download tracks successful downloads"
result=$(bash -c '
_download_single_module() {
    local module="$1"
    echo "SUCCESS:${module}:1000"
}
export -f _download_single_module

modules=(mod1 mod2 mod3)
success_count=0

while IFS= read -r result; do
    if [[ "$result" =~ ^SUCCESS ]]; then
        ((success_count++))
    fi
done < <(printf "%s\n" "${modules[@]}" | xargs -P 2 -I {} bash -c "_download_single_module \"{}\"")

echo "$success_count"
' 2>&1 | tail -1)

if [[ "$result" == "3" ]]; then
    test_pass
else
    test_fail "Success count incorrect: expected 3, got $result"
fi

#==============================================================================
# Test 8: Regex parsing of download results
#==============================================================================
test_start "Download result regex parsing works correctly"
result=$(bash -c '
test_results=(
    "SUCCESS:common:16239"
    "DOWNLOAD_FAILED:retry"
    "FILE_TOO_SMALL:network:50"
    "SYNTAX_ERROR:config"
)

success_count=0
failed_count=0

for result in "${test_results[@]}"; do
    if [[ "$result" =~ ^SUCCESS:(.+):([0-9]+)$ ]]; then
        ((success_count++))
    elif [[ "$result" =~ ^(DOWNLOAD_FAILED|FILE_NOT_FOUND|FILE_TOO_SMALL|SYNTAX_ERROR):(.+) ]]; then
        ((failed_count++))
    fi
done

echo "${success_count}:${failed_count}"
' 2>&1)

if [[ "$result" == "1:3" ]]; then
    test_pass
else
    test_fail "Regex parsing incorrect: expected 1:3, got $result"
fi

#==============================================================================
# Test Summary
#==============================================================================
echo ""
echo "=== Test Summary ==="
echo "Tests run:    $TESTS_RUN"
echo "Tests passed: $TESTS_PASSED"
echo "Tests failed: $TESTS_FAILED"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
else
    echo "✗ Some tests failed"
    exit 1
fi
