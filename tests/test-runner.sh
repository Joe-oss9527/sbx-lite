#!/usr/bin/env bash
# Test runner for sbx-lite bash scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test assertion helpers
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-}"

    ((TOTAL_TESTS++))
    if [[ "$expected" == "$actual" ]]; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓${NC} ${message:-Assertion passed}"
        return 0
    else
        ((FAILED_TESTS++))
        echo -e "${RED}✗${NC} ${message:-Assertion failed}"
        echo "  Expected: $expected"
        echo "  Actual:   $actual"
        return 1
    fi
}

assert_success() {
    local command="$1"
    local message="${2:-}"

    ((TOTAL_TESTS++))
    if eval "$command" >/dev/null 2>&1; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓${NC} ${message:-Command succeeded}"
        return 0
    else
        ((FAILED_TESTS++))
        echo -e "${RED}✗${NC} ${message:-Command failed}: $command"
        return 1
    fi
}

assert_failure() {
    local command="$1"
    local message="${2:-}"

    ((TOTAL_TESTS++))
    if ! eval "$command" >/dev/null 2>&1; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓${NC} ${message:-Command failed as expected}"
        return 0
    else
        ((FAILED_TESTS++))
        echo -e "${RED}✗${NC} ${message:-Command should have failed}: $command"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-}"

    ((TOTAL_TESTS++))
    if [[ -f "$file" ]]; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓${NC} ${message:-File exists}: $file"
        return 0
    else
        ((FAILED_TESTS++))
        echo -e "${RED}✗${NC} ${message:-File not found}: $file"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-}"

    ((TOTAL_TESTS++))
    if [[ "$haystack" == *"$needle"* ]]; then
        ((PASSED_TESTS++))
        echo -e "${GREEN}✓${NC} ${message:-String contains substring}"
        return 0
    else
        ((FAILED_TESTS++))
        echo -e "${RED}✗${NC} ${message:-String does not contain substring}"
        echo "  Haystack: $haystack"
        echo "  Needle:   $needle"
        return 1
    fi
}

# Export functions for test files
export -f assert_equals
export -f assert_success
export -f assert_failure
export -f assert_file_exists
export -f assert_contains

# Test discovery and execution
run_tests() {
    local test_dir="${1:-$SCRIPT_DIR}"
    local pattern="${2:-test_*.sh}"

    echo -e "${BLUE}=== Running Tests ===${NC}"
    echo "Test directory: $test_dir"
    echo "Pattern: $pattern"
    echo ""

    # Find and run test files
    local test_files
    test_files=$(find "$test_dir" -name "$pattern" -type f 2>/dev/null | sort || true)

    if [[ -z "$test_files" ]]; then
        echo -e "${YELLOW}No test files found${NC}"
        return 0
    fi

    local test_file
    local test_file_failures=0
    while IFS= read -r test_file; do
        echo -e "${BLUE}Running:${NC} $(basename "$test_file")"
        echo "----------------------------------------"

        if bash "$test_file"; then
            echo -e "${GREEN}Test file passed${NC}"
        else
            local exit_code=$?
            echo -e "${RED}Test file FAILED (exit code: $exit_code)${NC}"
            ((test_file_failures++))
        fi
        echo ""
    done <<< "$test_files"

    # Print summary
    echo "========================================"
    echo -e "${BLUE}Test Summary${NC}"
    echo "----------------------------------------"
    echo -e "Total:   ${TOTAL_TESTS}"
    echo -e "Passed:  ${GREEN}${PASSED_TESTS}${NC}"
    echo -e "Failed:  ${RED}${FAILED_TESTS}${NC}"
    if [[ $test_file_failures -gt 0 ]]; then
        echo -e "Test files failed: ${RED}${test_file_failures}${NC}"
    fi
    echo "========================================"

    if [[ $FAILED_TESTS -gt 0 ]] || [[ $test_file_failures -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Main execution
main() {
    local test_target="${1:-unit}"

    case "$test_target" in
        unit)
            run_tests "$SCRIPT_DIR/unit"
            ;;
        integration)
            run_tests "$SCRIPT_DIR/integration"
            ;;
        all)
            run_tests "$SCRIPT_DIR/unit" && run_tests "$SCRIPT_DIR/integration"
            ;;
        *)
            echo "Usage: $0 [unit|integration|all]"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
