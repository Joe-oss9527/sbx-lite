#!/usr/bin/env bash
# tests/coverage.sh - Bash code coverage tracker
# Part of sbx-lite test infrastructure
#
# Tracks which functions are called during test execution and generates coverage reports

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COVERAGE_DIR="${COVERAGE_DIR:-/tmp/sbx-coverage-$$}"
COVERAGE_FILE="$COVERAGE_DIR/coverage.txt"
MIN_COVERAGE_PERCENT="${MIN_COVERAGE_PERCENT:-70}"

#==============================================================================
# Coverage Tracking
#==============================================================================

# Track function calls during test execution
# Args:
#   $1 - Test script to run
#   $2 - (optional) Coverage output file
track_coverage() {
    local test_script="$1"
    local coverage_file="${2:-$COVERAGE_FILE}"

    [[ -f "$test_script" ]] || {
        echo "Error: Test script not found: $test_script" >&2
        return 1
    }

    # Create coverage directory
    mkdir -p "$(dirname "$coverage_file")"

    # Run test with debugging and capture function calls
    # Use bash -x to trace execution, then extract function names
    echo "Running: $test_script"
    bash -x "$test_script" 2>&1 | \
        grep -oE '\+ [a-z_][a-z0-9_]*' | \
        sed 's/^+ //' | \
        sort -u >> "$coverage_file" || true

    return 0
}

#==============================================================================
# Coverage Analysis
#==============================================================================

# Get all functions defined in library modules
get_all_functions() {
    local lib_dir="$PROJECT_ROOT/lib"

    # Find all function definitions in lib/*.sh files
    # Match patterns: function_name() or function function_name()
    find "$lib_dir" -name "*.sh" -type f -exec grep -h '^[a-z_][a-z0-9_]*()' {} \; 2>/dev/null | \
        sed 's/().*//' | sort -u

    # Also match "function name()" pattern
    find "$lib_dir" -name "*.sh" -type f -exec grep -h '^function [a-z_][a-z0-9_]*' {} \; 2>/dev/null | \
        sed 's/^function //' | sed 's/().*//' | sort -u
}

# Analyze coverage results
# Args:
#   $1 - Coverage file path
analyze_coverage() {
    local coverage_file="${1:-$COVERAGE_FILE}"

    [[ -f "$coverage_file" ]] || {
        echo "Error: Coverage file not found: $coverage_file" >&2
        return 1
    }

    echo ""
    echo "=============================================="
    echo "        Function Coverage Report"
    echo "=============================================="
    echo ""

    # Get all defined functions
    local all_functions
    all_functions=$(get_all_functions)

    local total=0
    local covered=0
    local -a uncovered_functions=()

    while IFS= read -r func; do
        ((total++))

        # Check if function was called (appears in coverage file)
        # Only match exact function names (not as part of other names)
        if grep -q "^${func}$" "$coverage_file" 2>/dev/null; then
            ((covered++))
            echo "✓ $func"
        else
            uncovered_functions+=("$func")
            echo "✗ $func (NOT TESTED)"
        fi
    done <<< "$all_functions"

    # Calculate coverage percentage
    local coverage_percent=0
    if [[ $total -gt 0 ]]; then
        coverage_percent=$((covered * 100 / total))
    fi

    echo ""
    echo "=============================================="
    echo "              Summary"
    echo "=============================================="
    echo "Total functions:  $total"
    echo "Tested functions: $covered"
    echo "Coverage:         ${coverage_percent}%"
    echo "=============================================="

    # Show uncovered functions
    if [[ ${#uncovered_functions[@]} -gt 0 ]]; then
        echo ""
        echo "Uncovered functions (${#uncovered_functions[@]}):"
        for func in "${uncovered_functions[@]}"; do
            echo "  - $func"
        done
    fi

    echo ""

    # Check if coverage meets minimum threshold
    if [[ $coverage_percent -lt $MIN_COVERAGE_PERCENT ]]; then
        echo "⚠️  Coverage ${coverage_percent}% is below ${MIN_COVERAGE_PERCENT}% threshold"
        return 1
    else
        echo "✓ Coverage ${coverage_percent}% meets ${MIN_COVERAGE_PERCENT}% threshold"
        return 0
    fi
}

#==============================================================================
# Coverage Report Generation
#==============================================================================

# Generate comprehensive coverage report by running all tests
generate_coverage_report() {
    echo "=============================================="
    echo "    Generating Coverage Report"
    echo "=============================================="
    echo ""

    # Clean up old coverage data
    rm -rf "$COVERAGE_DIR"
    mkdir -p "$COVERAGE_DIR"

    # Find all test files
    local test_files=()

    # Unit tests
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$PROJECT_ROOT/tests/unit" -name "test_*.sh" -type f -print0 2>/dev/null)

    # Integration tests
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$PROJECT_ROOT/tests/integration" -name "test_*.sh" -type f -print0 2>/dev/null)

    # Top-level test files
    while IFS= read -r -d '' file; do
        test_files+=("$file")
    done < <(find "$PROJECT_ROOT/tests" -maxdepth 1 -name "test_*.sh" -type f -print0 2>/dev/null)

    if [[ ${#test_files[@]} -eq 0 ]]; then
        echo "⚠️  No test files found"
        return 1
    fi

    echo "Found ${#test_files[@]} test file(s)"
    echo ""

    # Run each test and track coverage
    for test_file in "${test_files[@]}"; do
        track_coverage "$test_file" "$COVERAGE_FILE"
    done

    echo ""
    echo "Coverage tracking complete"
    echo ""

    # Analyze results
    analyze_coverage "$COVERAGE_FILE"
    local exit_code=$?

    # Save coverage report
    local report_file="$PROJECT_ROOT/coverage-report.txt"
    analyze_coverage "$COVERAGE_FILE" > "$report_file" 2>&1
    echo ""
    echo "Coverage report saved to: $report_file"

    return $exit_code
}

#==============================================================================
# HTML Report Generation (Optional)
#==============================================================================

# Generate HTML coverage report
generate_html_report() {
    local coverage_file="${1:-$COVERAGE_FILE}"
    local output_file="${2:-$PROJECT_ROOT/coverage-report.html}"

    [[ -f "$coverage_file" ]] || {
        echo "Error: Coverage file not found: $coverage_file" >&2
        return 1
    }

    # Get coverage statistics
    local all_functions
    all_functions=$(get_all_functions)
    local total=0
    local covered=0

    while IFS= read -r func; do
        ((total++))
        if grep -q ":$func$" "$coverage_file" 2>/dev/null; then
            ((covered++))
        fi
    done <<< "$all_functions"

    local coverage_percent=0
    if [[ $total -gt 0 ]]; then
        coverage_percent=$((covered * 100 / total))
    fi

    # Generate HTML
    cat > "$output_file" <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>sbx-lite Code Coverage Report</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 2px solid #4CAF50; padding-bottom: 10px; }
        .summary { display: flex; gap: 20px; margin: 20px 0; }
        .stat-box { flex: 1; padding: 20px; background: #f9f9f9; border-radius: 4px; text-align: center; }
        .stat-value { font-size: 2em; font-weight: bold; color: #4CAF50; }
        .stat-label { color: #666; margin-top: 5px; }
        .coverage-bar { height: 30px; background: #ddd; border-radius: 4px; overflow: hidden; margin: 20px 0; }
        .coverage-fill { height: 100%; background: linear-gradient(90deg, #4CAF50, #45a049); transition: width 0.3s; }
        .function-list { margin-top: 20px; }
        .function-item { padding: 10px; border-bottom: 1px solid #eee; display: flex; justify-content: space-between; align-items: center; }
        .function-item:hover { background: #f9f9f9; }
        .covered { color: #4CAF50; }
        .uncovered { color: #f44336; }
        .badge { padding: 4px 8px; border-radius: 4px; font-size: 0.8em; font-weight: bold; }
        .badge.covered { background: #4CAF50; color: white; }
        .badge.uncovered { background: #f44336; color: white; }
    </style>
</head>
<body>
    <div class="container">
        <h1>sbx-lite Code Coverage Report</h1>
        <div class="summary">
            <div class="stat-box">
                <div class="stat-value">${coverage_percent}%</div>
                <div class="stat-label">Coverage</div>
            </div>
            <div class="stat-box">
                <div class="stat-value">${covered}</div>
                <div class="stat-label">Tested Functions</div>
            </div>
            <div class="stat-box">
                <div class="stat-value">${total}</div>
                <div class="stat-label">Total Functions</div>
            </div>
            <div class="stat-box">
                <div class="stat-value">$((total - covered))</div>
                <div class="stat-label">Uncovered</div>
            </div>
        </div>
        <div class="coverage-bar">
            <div class="coverage-fill" style="width: ${coverage_percent}%"></div>
        </div>
        <div class="function-list">
            <h2>Function Details</h2>
EOF

    # Add function details
    while IFS= read -r func; do
        if grep -q ":$func$" "$coverage_file" 2>/dev/null; then
            echo "            <div class=\"function-item\"><span class=\"covered\">✓ $func</span><span class=\"badge covered\">TESTED</span></div>" >> "$output_file"
        else
            echo "            <div class=\"function-item\"><span class=\"uncovered\">✗ $func</span><span class=\"badge uncovered\">NOT TESTED</span></div>" >> "$output_file"
        fi
    done <<< "$all_functions"

    # Close HTML
    cat >> "$output_file" <<EOF
        </div>
    </div>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            console.log('Coverage report loaded: ${coverage_percent}%');
        });
    </script>
</body>
</html>
EOF

    echo "HTML coverage report saved to: $output_file"
    return 0
}

#==============================================================================
# Cleanup
#==============================================================================

cleanup_coverage() {
    [[ -d "$COVERAGE_DIR" ]] && rm -rf "$COVERAGE_DIR"
}

trap cleanup_coverage EXIT

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    case "${1:-}" in
        generate|report)
            generate_coverage_report
            ;;
        html)
            if [[ -f "$COVERAGE_FILE" ]]; then
                generate_html_report "$COVERAGE_FILE"
            else
                echo "Error: No coverage data found. Run 'coverage.sh generate' first." >&2
                return 1
            fi
            ;;
        analyze)
            if [[ -f "$COVERAGE_FILE" ]]; then
                analyze_coverage "$COVERAGE_FILE"
            else
                echo "Error: No coverage data found. Run 'coverage.sh generate' first." >&2
                return 1
            fi
            ;;
        clean)
            cleanup_coverage
            echo "Coverage data cleaned"
            ;;
        help|--help|-h)
            cat <<EOF
Usage: coverage.sh [command]

Commands:
    generate, report    Generate coverage report (default)
    html               Generate HTML coverage report
    analyze            Analyze existing coverage data
    clean              Clean coverage data
    help               Show this help message

Environment Variables:
    MIN_COVERAGE_PERCENT    Minimum coverage threshold (default: 70)
    COVERAGE_DIR            Coverage data directory (default: /tmp/sbx-coverage-PID)

Examples:
    coverage.sh                     # Generate coverage report
    coverage.sh generate            # Same as above
    coverage.sh html                # Generate HTML report
    MIN_COVERAGE_PERCENT=80 coverage.sh   # Set 80% threshold
EOF
            ;;
        *)
            generate_coverage_report
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
