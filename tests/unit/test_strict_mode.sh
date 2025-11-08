#!/usr/bin/env bash
# Unit tests for strict mode compliance in library modules
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Test: Check if module has strict mode
test_library_has_strict_mode() {
    local module="$1"
    local module_path="${PROJECT_ROOT}/lib/${module}.sh"

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    if [[ ! -f "$module_path" ]]; then
        echo -e "${RED}✗${NC} [$module] Module file not found"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        return 0  # Don't exit script
    fi

    if head -20 "$module_path" | grep -qE '^set -[euo]{3,5}$|^set -euo pipefail$'; then
        echo -e "${GREEN}✓${NC} [$module] Has strict mode directive"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo -e "${RED}✗${NC} [$module] Missing strict mode directive"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
}

# Main test execution
main() {
    local modules=(
        common network validation checksum certificate caddy
        config service ui backup export retry download version
    )

    echo "========================================="
    echo "Strict Mode Compliance Tests"
    echo "========================================="
    echo ""

    for module in "${modules[@]}"; do
        test_library_has_strict_mode "$module"
    done

    # Print summary
    echo ""
    echo "========================================="
    echo "Test Summary"
    echo "========================================="
    echo "Total:  $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo ""

    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}✓ All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        exit 1
    fi
}

# Run tests
main
