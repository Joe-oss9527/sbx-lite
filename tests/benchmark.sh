#!/usr/bin/env bash
# tests/benchmark.sh - Performance benchmarking tool
# Part of sbx-lite test infrastructure
#
# Measures execution time and performance of critical functions

set -euo pipefail

#==============================================================================
# Configuration
#==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BENCHMARK_ITERATIONS="${BENCHMARK_ITERATIONS:-100}"
WARMUP_ITERATIONS="${WARMUP_ITERATIONS:-10}"

# Set default values for variables that modules may expect
export SB_BIN="${SB_BIN:-/usr/local/bin/sing-box}"
export SB_CONF="${SB_CONF:-/etc/sing-box/config.json}"
export NO_COLOR="${NO_COLOR:-0}"

#==============================================================================
# Timing Functions
#==============================================================================

# Get current time in nanoseconds
get_time_ns() {
    date +%s%N
}

# Get current time in milliseconds
get_time_ms() {
    echo $(($(date +%s%N) / 1000000))
}

#==============================================================================
# Benchmark Core
#==============================================================================

# Benchmark a command or function
# Args:
#   $1 - Test name
#   $2 - Number of iterations (optional, default: BENCHMARK_ITERATIONS)
#   $@ - Command to benchmark
benchmark() {
    local test_name="$1"
    local iterations="${2:-$BENCHMARK_ITERATIONS}"
    shift 2
    local command="$*"

    echo "────────────────────────────────────────────"
    echo "Benchmark: $test_name"
    echo "Command: $command"
    echo "Iterations: $iterations (+ $WARMUP_ITERATIONS warmup)"
    echo ""

    # Warmup phase
    for ((i=1; i<=WARMUP_ITERATIONS; i++)); do
        eval "$command" >/dev/null 2>&1 || true
    done

    # Benchmark phase
    local start_time
    start_time=$(get_time_ns)

    for ((i=1; i<=iterations; i++)); do
        eval "$command" >/dev/null 2>&1 || true
    done

    local end_time
    end_time=$(get_time_ns)

    # Calculate metrics
    local total_time=$((end_time - start_time))
    local total_ms=$((total_time / 1000000))
    local avg_ns=$((total_time / iterations))
    local avg_us=$((avg_ns / 1000))
    local avg_ms=$((total_time / iterations / 1000000))
    local ops_per_sec=0

    if [[ $avg_ns -gt 0 ]]; then
        ops_per_sec=$((1000000000 / avg_ns))
    fi

    # Display results
    printf "Total time:    %'d ms\n" "$total_ms"
    printf "Average time:  %'d μs (%d ms)\n" "$avg_us" "$avg_ms"
    printf "Throughput:    %'d ops/sec\n" "$ops_per_sec"
    echo ""

    # Return average time in microseconds (for comparison)
    echo "$avg_us"
}

#==============================================================================
# Benchmark Suites
#==============================================================================

# Benchmark UUID generation
benchmark_uuid_generation() {
    echo "══════════════════════════════════════════════"
    echo "  UUID Generation Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/generators.sh"

    benchmark "UUID Generation" "$BENCHMARK_ITERATIONS" "generate_uuid"
}

# Benchmark domain validation
benchmark_domain_validation() {
    echo "══════════════════════════════════════════════"
    echo "  Domain Validation Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/validation.sh"

    benchmark "Valid Domain" "$BENCHMARK_ITERATIONS" "validate_domain example.com"
    benchmark "Valid Subdomain" "$BENCHMARK_ITERATIONS" "validate_domain sub.example.com"
    benchmark "Invalid Domain" "$BENCHMARK_ITERATIONS" "validate_domain invalid..com || true"
}

# Benchmark port validation
benchmark_port_validation() {
    echo "══════════════════════════════════════════════"
    echo "  Port Validation Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/validation.sh"

    benchmark "Valid Port" "$BENCHMARK_ITERATIONS" "validate_port 443"
    benchmark "Invalid Port" "$BENCHMARK_ITERATIONS" "validate_port 99999 || true"
}

# Benchmark IP validation
benchmark_ip_validation() {
    echo "══════════════════════════════════════════════"
    echo "  IP Address Validation Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/network.sh"

    benchmark "Valid IP" "$BENCHMARK_ITERATIONS" "validate_ip_address 8.8.8.8"
    benchmark "Invalid IP" "$BENCHMARK_ITERATIONS" "validate_ip_address 999.999.999.999 || true"
    benchmark "Private IP" "$BENCHMARK_ITERATIONS" "validate_ip_address 192.168.1.1 || true"
}

# Benchmark JSON operations
benchmark_json_operations() {
    echo "══════════════════════════════════════════════"
    echo "  JSON Operations Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/tools.sh"

    local test_json='{"name": "test", "value": 123, "active": true}'

    # Only run if jq is available
    if command -v jq >/dev/null 2>&1; then
        benchmark "JSON Parse" "$BENCHMARK_ITERATIONS" "echo '$test_json' | jq -r .name"
        benchmark "JSON Build" "$BENCHMARK_ITERATIONS" "jq -n --arg name test '{name: \$name}'"
    else
        echo "⚠️  jq not available, skipping JSON benchmarks"
        echo ""
    fi
}

# Benchmark cryptographic operations
benchmark_crypto_operations() {
    echo "══════════════════════════════════════════════"
    echo "  Cryptographic Operations Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/tools.sh"

    # Test with small file
    local test_file="/tmp/bench-test-$$.txt"
    echo "test content for benchmarking" > "$test_file"

    benchmark "Random Hex (8 bytes)" "$BENCHMARK_ITERATIONS" "crypto_random_hex 8"
    benchmark "SHA256 Hash" "$BENCHMARK_ITERATIONS" "crypto_sha256 $test_file"

    rm -f "$test_file"
}

# Benchmark message formatting
benchmark_message_formatting() {
    echo "══════════════════════════════════════════════"
    echo "  Message Formatting Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/messages.sh"

    benchmark "Format Error Message" "$BENCHMARK_ITERATIONS" "format_error INVALID_PORT 99999"
    benchmark "Format Warning Message" "$BENCHMARK_ITERATIONS" "format_warning CERT_EXPIRY example.com 30"
}

# Benchmark logging operations
benchmark_logging_operations() {
    echo "══════════════════════════════════════════════"
    echo "  Logging Operations Benchmarks"
    echo "══════════════════════════════════════════════"
    echo ""

    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/logging.sh"

    # Disable color for benchmarking
    NO_COLOR=1

    benchmark "Log Message (msg)" "$BENCHMARK_ITERATIONS" "msg 'Test message'"
    benchmark "Log Warning (warn)" "$BENCHMARK_ITERATIONS" "warn 'Test warning'"
    benchmark "Log Success (success)" "$BENCHMARK_ITERATIONS" "success 'Test success'"
}

#==============================================================================
# Comparison Suite
#==============================================================================

# Run all benchmarks and generate comparison report
run_all_benchmarks() {
    echo "══════════════════════════════════════════════"
    echo "  sbx-lite Performance Benchmark Suite"
    echo "══════════════════════════════════════════════"
    echo ""
    echo "Configuration:"
    echo "  Iterations: $BENCHMARK_ITERATIONS"
    echo "  Warmup: $WARMUP_ITERATIONS"
    echo "  Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""

    benchmark_uuid_generation
    benchmark_domain_validation
    benchmark_port_validation
    benchmark_ip_validation
    benchmark_json_operations
    benchmark_crypto_operations
    benchmark_message_formatting
    benchmark_logging_operations

    echo "══════════════════════════════════════════════"
    echo "  Benchmark Suite Complete"
    echo "══════════════════════════════════════════════"
}

#==============================================================================
# Performance Regression Detection
#==============================================================================

# Compare current performance with baseline
# Args:
#   $1 - Baseline file
compare_with_baseline() {
    local baseline_file="$1"

    if [[ ! -f "$baseline_file" ]]; then
        echo "⚠️  Baseline file not found: $baseline_file"
        echo "Run with 'baseline' command to create one"
        return 1
    fi

    echo "Comparing with baseline: $baseline_file"
    echo ""

    # Run benchmarks and save to temp file
    local current_file="/tmp/bench-current-$$.txt"
    run_all_benchmarks > "$current_file" 2>&1

    # Compare results (placeholder - would need more sophisticated comparison)
    echo "Current results saved to: $current_file"
    echo "Baseline: $baseline_file"
    echo ""
    echo "Note: Detailed comparison not implemented yet"
    echo "Manually compare the two files for now"

    rm -f "$current_file"
}

# Create performance baseline
create_baseline() {
    local baseline_file="${1:-$PROJECT_ROOT/benchmark-baseline.txt}"

    echo "Creating performance baseline..."
    run_all_benchmarks > "$baseline_file" 2>&1

    echo ""
    echo "✓ Baseline created: $baseline_file"
}

#==============================================================================
# Quick Benchmarks
#==============================================================================

# Run quick benchmarks (fewer iterations)
run_quick_benchmarks() {
    BENCHMARK_ITERATIONS=10
    WARMUP_ITERATIONS=2

    echo "Running quick benchmarks (10 iterations)..."
    echo ""

    run_all_benchmarks
}

#==============================================================================
# Main Entry Point
#==============================================================================

main() {
    case "${1:-all}" in
        all)
            run_all_benchmarks
            ;;
        quick)
            run_quick_benchmarks
            ;;
        baseline)
            create_baseline "${2:-}"
            ;;
        compare)
            if [[ -z "${2:-}" ]]; then
                echo "Error: Baseline file required"
                echo "Usage: benchmark.sh compare <baseline-file>"
                return 1
            fi
            compare_with_baseline "$2"
            ;;
        uuid)
            benchmark_uuid_generation
            ;;
        domain)
            benchmark_domain_validation
            ;;
        port)
            benchmark_port_validation
            ;;
        ip)
            benchmark_ip_validation
            ;;
        json)
            benchmark_json_operations
            ;;
        crypto)
            benchmark_crypto_operations
            ;;
        message)
            benchmark_message_formatting
            ;;
        logging)
            benchmark_logging_operations
            ;;
        help|--help|-h)
            cat <<EOF
Usage: benchmark.sh [command] [options]

Commands:
    all              Run all benchmarks (default)
    quick            Run quick benchmarks (10 iterations)
    baseline [file]  Create performance baseline
    compare <file>   Compare with baseline

Specific benchmarks:
    uuid             UUID generation
    domain           Domain validation
    port             Port validation
    ip               IP address validation
    json             JSON operations
    crypto           Cryptographic operations
    message          Message formatting
    logging          Logging operations

Environment Variables:
    BENCHMARK_ITERATIONS    Number of iterations (default: 100)
    WARMUP_ITERATIONS       Warmup iterations (default: 10)

Examples:
    benchmark.sh                    # Run all benchmarks
    benchmark.sh quick              # Quick benchmarks
    benchmark.sh uuid               # Only UUID benchmarks
    benchmark.sh baseline           # Create baseline
    BENCHMARK_ITERATIONS=1000 benchmark.sh  # 1000 iterations
EOF
            ;;
        *)
            echo "Error: Unknown command: $1"
            echo "Run 'benchmark.sh help' for usage information"
            return 1
            ;;
    esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi
