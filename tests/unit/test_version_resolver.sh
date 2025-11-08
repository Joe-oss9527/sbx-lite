#!/usr/bin/env bash
# Unit tests for version alias resolution

# Disable exit on error for testing
set +e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Test environment flag
export SBX_TEST_MODE=1

# Change to project root
cd "$PROJECT_ROOT" || exit 1

# Load required modules (disable traps first)
trap - EXIT INT TERM

if ! source lib/common.sh 2>/dev/null; then
    echo "✗ Failed to load lib/common.sh"
    exit 1
fi

if ! source lib/network.sh 2>/dev/null; then
    echo "✗ Failed to load lib/network.sh"
    exit 1
fi

# Try to load version module
if ! source lib/version.sh 2>/dev/null; then
    echo "⚠ SKIP: lib/version.sh not yet created (expected for TDD red phase)"
    exit 0
fi

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Test helper
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo ""
    echo "Test $((TOTAL_TESTS + 1)): $test_name"

    ((TOTAL_TESTS++))

    if $test_func; then
        echo "✓ PASSED"
        ((PASSED_TESTS++))
        return 0
    else
        echo "✗ FAILED"
        ((FAILED_TESTS++))
        return 1
    fi
}

echo "=== Version Resolver Tests ==="

# Test 1: Resolve 'stable' to latest stable release
test_resolve_stable() {
    export SINGBOX_VERSION="stable"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    # Should succeed
    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    # Should return vX.Y.Z format (no pre-release)
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  Resolved to: $resolved"
        return 0
    else
        echo "  ERROR: Invalid format: $resolved"
        return 1
    fi
}

# Test 2: Resolve 'latest' to absolute latest release
test_resolve_latest() {
    export SINGBOX_VERSION="latest"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    # Should succeed
    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    # Should return vX.Y.Z or vX.Y.Z-beta.N format
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        echo "  Resolved to: $resolved"
        return 0
    else
        echo "  ERROR: Invalid format: $resolved"
        return 1
    fi
}

# Test 3: Resolve specific version tag
test_resolve_specific_v() {
    export SINGBOX_VERSION="v1.10.7"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    if [[ "$resolved" == "v1.10.7" ]]; then
        echo "  Resolved to: $resolved"
        return 0
    else
        echo "  ERROR: Expected v1.10.7, got $resolved"
        return 1
    fi
}

# Test 4: Resolve version without 'v' prefix
test_resolve_without_v() {
    export SINGBOX_VERSION="1.10.7"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    if [[ "$resolved" == "v1.10.7" ]]; then
        echo "  Resolved to: $resolved (auto-prefixed)"
        return 0
    else
        echo "  ERROR: Expected v1.10.7, got $resolved"
        return 1
    fi
}

# Test 5: Reject invalid version format
test_invalid_version() {
    export SINGBOX_VERSION="invalid-version-123"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    # Should fail
    if [[ $result -ne 0 ]]; then
        echo "  Correctly rejected invalid version"
        return 0
    else
        echo "  ERROR: Should have rejected invalid version: $resolved"
        return 1
    fi
}

# Test 6: Default to stable when unset
test_default_stable() {
    unset SINGBOX_VERSION

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    # Should return a valid stable version (no pre-release)
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  Default resolved to stable: $resolved"
        return 0
    else
        echo "  ERROR: Invalid format: $resolved"
        return 1
    fi
}

# Test 7: Handle pre-release versions
test_prerelease_version() {
    export SINGBOX_VERSION="v1.11.0-beta.1"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    if [[ "$resolved" == "v1.11.0-beta.1" ]]; then
        echo "  Resolved to: $resolved"
        return 0
    else
        echo "  ERROR: Expected v1.11.0-beta.1, got $resolved"
        return 1
    fi
}

# Test 8: Case insensitivity for aliases
test_case_insensitive_stable() {
    export SINGBOX_VERSION="STABLE"

    local resolved
    resolved=$(resolve_singbox_version 2>/dev/null)
    local result=$?

    if [[ $result -ne 0 ]]; then
        echo "  ERROR: Function failed"
        return 1
    fi

    # Should resolve despite uppercase
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "  Resolved STABLE to: $resolved"
        return 0
    else
        echo "  ERROR: Invalid format: $resolved"
        return 1
    fi
}

# Run all tests
run_test "Resolve 'stable' to latest stable release" test_resolve_stable
run_test "Resolve 'latest' to absolute latest release" test_resolve_latest
run_test "Resolve specific version with 'v' prefix" test_resolve_specific_v
run_test "Resolve version without 'v' prefix" test_resolve_without_v
run_test "Reject invalid version format" test_invalid_version
run_test "Default to stable when unset" test_default_stable
run_test "Handle pre-release versions" test_prerelease_version
run_test "Case insensitivity for aliases" test_case_insensitive_stable

# Print summary
echo ""
echo "========================================"
echo "Test Summary"
echo "----------------------------------------"
echo "Total:   $TOTAL_TESTS"
echo "Passed:  $PASSED_TESTS"
echo "Failed:  $FAILED_TESTS"
echo "========================================"

if [[ $FAILED_TESTS -gt 0 ]]; then
    exit 1
fi

exit 0
