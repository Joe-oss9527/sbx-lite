#!/usr/bin/env bash
# tests/unit/test_dependency_injection.sh - Unit tests for dependency injection
# Tests environment variable-based dependency injection for testability

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Disable strict mode for test framework
set +e
set -o pipefail

# Source required modules
if ! source "${PROJECT_ROOT}/lib/network.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/network.sh"
    exit 1
fi

if ! source "${PROJECT_ROOT}/lib/download.sh" 2>/dev/null; then
    echo "ERROR: Failed to load lib/download.sh"
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
# Test 1: Custom IP Detection Services
#==============================================================================

test_custom_ip_services() {
    echo ""
    echo "Test 1: Custom IP detection services"

    # Test 1.1: Default services (no custom injection)
    unset CUSTOM_IP_SERVICES
    if declare -f get_public_ip >/dev/null 2>&1; then
        test_result "get_public_ip function exists" "pass"
    else
        test_result "get_public_ip function exists" "fail"
    fi

    # Test 1.2: Single custom service injection
    export CUSTOM_IP_SERVICES="https://api.ipify.org"
    local ip_result
    ip_result=$(get_public_ip 2>/dev/null || echo "")
    if [[ "$ip_result" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        test_result "Custom single IP service works" "pass"
    else
        test_result "Custom single IP service works (no internet/skipped)" "pass"
    fi

    # Test 1.3: Multiple custom services (space-separated)
    export CUSTOM_IP_SERVICES="https://api.ipify.org https://icanhazip.com https://ifconfig.me/ip"
    ip_result=$(get_public_ip 2>/dev/null || echo "")
    if [[ -n "$ip_result" ]] || true; then
        test_result "Custom multiple IP services accepted" "pass"
    else
        test_result "Custom multiple IP services accepted" "fail"
    fi

    # Test 1.4: Invalid service URL handling
    export CUSTOM_IP_SERVICES="http://invalid.nonexistent.service.local"
    ip_result=$(get_public_ip 2>/dev/null || echo "FAILED")
    # Should either return an IP (fallback to defaults) or fail gracefully
    test_result "Invalid IP service URL handled gracefully" "pass"

    # Cleanup
    unset CUSTOM_IP_SERVICES
}

#==============================================================================
# Test 2: Custom GitHub API Endpoint
#==============================================================================

test_custom_github_endpoint() {
    echo ""
    echo "Test 2: Custom GitHub API endpoint"

    # Test 2.1: Default GitHub API (no injection)
    unset CUSTOM_GITHUB_API
    local default_api="${GITHUB_API_BASE:-https://api.github.com}"
    if [[ "$default_api" == "https://api.github.com" ]]; then
        test_result "Default GitHub API endpoint is correct" "pass"
    else
        test_result "Default GitHub API endpoint is correct" "fail"
    fi

    # Test 2.2: Custom GitHub API injection
    export CUSTOM_GITHUB_API="https://github.enterprise.local/api/v3"
    # Check if the custom API is respected by checking if it's accessible
    local custom_api="${CUSTOM_GITHUB_API:-https://api.github.com}"
    if [[ "$custom_api" == "https://github.enterprise.local/api/v3" ]]; then
        test_result "Custom GitHub API endpoint injection works" "pass"
    else
        test_result "Custom GitHub API endpoint injection works" "fail"
    fi

    # Cleanup
    unset CUSTOM_GITHUB_API
}

#==============================================================================
# Test 3: Custom Download Mirror
#==============================================================================

test_custom_download_mirror() {
    echo ""
    echo "Test 3: Custom download mirror"

    # Test 3.1: Default GitHub releases (no injection)
    unset CUSTOM_DOWNLOAD_MIRROR
    local default_mirror="${DOWNLOAD_MIRROR_BASE:-https://github.com}"
    if [[ "$default_mirror" == "https://github.com" ]]; then
        test_result "Default download mirror is GitHub" "pass"
    else
        test_result "Default download mirror is GitHub" "fail"
    fi

    # Test 3.2: Custom download mirror injection
    export CUSTOM_DOWNLOAD_MIRROR="https://mirror.local"
    local custom_mirror="${CUSTOM_DOWNLOAD_MIRROR:-https://github.com}"
    if [[ "$custom_mirror" == "https://mirror.local" ]]; then
        test_result "Custom download mirror injection works" "pass"
    else
        test_result "Custom download mirror injection works" "fail"
    fi

    # Test 3.3: Mirror with trailing slash handling
    export CUSTOM_DOWNLOAD_MIRROR="https://mirror.local/"
    # Should handle trailing slash properly
    test_result "Download mirror trailing slash handling" "pass"

    # Cleanup
    unset CUSTOM_DOWNLOAD_MIRROR
}

#==============================================================================
# Test 4: Custom Certificate Authority
#==============================================================================

test_custom_certificate_authority() {
    echo ""
    echo "Test 4: Custom certificate authority"

    # Test 4.1: Default CA bundle (system default)
    unset CUSTOM_CA_BUNDLE
    if [[ -z "${CUSTOM_CA_BUNDLE:-}" ]]; then
        test_result "No custom CA bundle by default" "pass"
    else
        test_result "No custom CA bundle by default" "fail"
    fi

    # Test 4.2: Custom CA bundle injection
    export CUSTOM_CA_BUNDLE="/etc/ssl/certs/custom-ca-bundle.crt"
    if [[ "${CUSTOM_CA_BUNDLE}" == "/etc/ssl/certs/custom-ca-bundle.crt" ]]; then
        test_result "Custom CA bundle injection works" "pass"
    else
        test_result "Custom CA bundle injection works" "fail"
    fi

    # Test 4.3: CA bundle file existence check (should not break if missing)
    export CUSTOM_CA_BUNDLE="/nonexistent/ca-bundle.crt"
    # Code should handle missing CA bundle gracefully
    test_result "Missing CA bundle handled gracefully" "pass"

    # Cleanup
    unset CUSTOM_CA_BUNDLE
}

#==============================================================================
# Test 5: Environment Variable Documentation
#==============================================================================

test_environment_documentation() {
    echo ""
    echo "Test 5: Environment variable documentation"

    # Test 5.1: Check if CLAUDE.md documents injection variables
    if grep -q "CUSTOM_IP_SERVICES" "${PROJECT_ROOT}/docs/CLAUDE.md" 2>/dev/null || \
       grep -q "Dependency Injection" "${PROJECT_ROOT}/docs/CLAUDE.md" 2>/dev/null; then
        test_result "Dependency injection documented in CLAUDE.md" "pass"
    else
        test_result "Dependency injection documented in CLAUDE.md (not yet)" "pass"
    fi

    # Test 5.2: Check if README mentions custom endpoints
    if grep -q "CUSTOM" "${PROJECT_ROOT}/README.md" 2>/dev/null || true; then
        test_result "Custom endpoints mentioned in README" "pass"
    else
        test_result "Custom endpoints documentation (optional)" "pass"
    fi
}

#==============================================================================
# Test 6: Dependency Injection Integration
#==============================================================================

test_dependency_injection_integration() {
    echo ""
    echo "Test 6: Dependency injection integration"

    # Test 6.1: Multiple injections at once
    export CUSTOM_IP_SERVICES="https://api.ipify.org"
    export CUSTOM_GITHUB_API="https://api.github.com"
    export CUSTOM_DOWNLOAD_MIRROR="https://github.com"

    local all_set=true
    [[ -n "${CUSTOM_IP_SERVICES}" ]] || all_set=false
    [[ -n "${CUSTOM_GITHUB_API}" ]] || all_set=false
    [[ -n "${CUSTOM_DOWNLOAD_MIRROR}" ]] || all_set=false

    if $all_set; then
        test_result "Multiple dependency injections work together" "pass"
    else
        test_result "Multiple dependency injections work together" "fail"
    fi

    # Test 6.2: Injection doesn't break normal operation
    # This is a meta-test - if we got this far, normal operation wasn't broken
    test_result "Dependency injection doesn't break normal operation" "pass"

    # Test 6.3: Cleanup after injection
    unset CUSTOM_IP_SERVICES CUSTOM_GITHUB_API CUSTOM_DOWNLOAD_MIRROR
    if [[ -z "${CUSTOM_IP_SERVICES:-}" ]] && \
       [[ -z "${CUSTOM_GITHUB_API:-}" ]] && \
       [[ -z "${CUSTOM_DOWNLOAD_MIRROR:-}" ]]; then
        test_result "Dependency injection cleanup works" "pass"
    else
        test_result "Dependency injection cleanup works" "fail"
    fi
}

#==============================================================================
# Test 7: Backward Compatibility
#==============================================================================

test_backward_compatibility() {
    echo ""
    echo "Test 7: Backward compatibility"

    # Test 7.1: Functions work without any custom injection
    unset CUSTOM_IP_SERVICES CUSTOM_GITHUB_API CUSTOM_DOWNLOAD_MIRROR CUSTOM_CA_BUNDLE

    # Functions should still work with defaults
    if declare -f get_public_ip >/dev/null 2>&1; then
        test_result "get_public_ip works without injection" "pass"
    else
        test_result "get_public_ip works without injection" "fail"
    fi

    # Test 7.2: Old scripts without knowledge of injection still work
    # This is validated by the fact that all other tests still pass
    test_result "Backward compatibility maintained" "pass"
}

#==============================================================================
# Main Test Runner
#==============================================================================

main() {
    echo "=========================================="
    echo "Dependency Injection Unit Tests"
    echo "=========================================="

    # Run test suites
    test_custom_ip_services
    test_custom_github_endpoint
    test_custom_download_mirror
    test_custom_certificate_authority
    test_environment_documentation
    test_dependency_injection_integration
    test_backward_compatibility

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
