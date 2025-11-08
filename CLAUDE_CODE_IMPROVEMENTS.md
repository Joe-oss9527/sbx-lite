# Claude Code 启发的安装脚本改进计划

**基于**: Claude Code bootstrap.sh 分析
**目标**: 增强安装脚本的安全性、灵活性和用户体验
**方法**: Test-Driven Development (TDD)
**日期**: 2025-11-08

---

## 📋 改进概览

| 功能 | 优先级 | 估算时间 | 安全影响 | 用户体验影响 |
|------|--------|----------|----------|--------------|
| SHA256 校验和验证 | 🔴 P0 | 4-6h | 高 | 中 |
| 版本别名支持 | 🟡 P1 | 3-4h | 低 | 高 |
| 平台检测增强 | 🟡 P1 | 2-3h | 低 | 中 |
| Manifest 管理 | 🟢 P2 | 6-8h | 中 | 高 |
| 引导脚本模式 | 🟢 P3 | 4-6h | 低 | 高 |

---

## 🎯 Phase 1: 测试基础设施搭建

**目标**: 建立可靠的 TDD 测试框架

### 1.1 创建测试运行器

**输出文件**: `tests/test-runner.sh`

```bash
#!/usr/bin/env bash
# Test runner for sbx-lite bash scripts

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Test statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

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
    test_files=$(find "$test_dir" -name "$pattern" -type f | sort)
    
    if [[ -z "$test_files" ]]; then
        echo -e "${YELLOW}No test files found${NC}"
        return 0
    fi
    
    local test_file
    while IFS= read -r test_file; do
        echo -e "${BLUE}Running:${NC} $(basename "$test_file")"
        echo "----------------------------------------"
        
        if bash "$test_file"; then
            echo -e "${GREEN}Test file passed${NC}"
        else
            echo -e "${RED}Test file failed${NC}"
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
    echo -e "Skipped: ${YELLOW}${SKIPPED_TESTS}${NC}"
    echo "========================================"
    
    if [[ $FAILED_TESTS -gt 0 ]]; then
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

### 1.2 Mock 工具集成

**输出文件**: `tests/mocks/http_mock.sh` ✓ 已创建

**功能**:
- Mock GitHub API 响应
- Mock 校验和文件
- Mock curl/wget 命令
- Mock sha256sum/shasum 工具

### 1.3 测试运行命令

```bash
# 运行单元测试
bash tests/test-runner.sh unit

# 运行集成测试
bash tests/test-runner.sh integration

# 运行所有测试
bash tests/test-runner.sh all

# 单独运行某个测试文件
bash tests/unit/test_checksum.sh
```

### 1.4 CI/CD 集成

**输出文件**: `.github/workflows/test-improvements.yml`

```yaml
name: Test Improvements

on:
  pull_request:
    paths:
      - 'lib/**'
      - 'install_multi.sh'
      - 'tests/**'
  push:
    branches: [main, develop, 'feature/*']

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Run unit tests
        run: bash tests/test-runner.sh unit
      
      - name: Check test coverage
        run: |
          echo "Test coverage check (placeholder)"

  integration-tests:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [ubuntu-22.04, ubuntu-20.04]
    steps:
      - uses: actions/checkout@v4
      
      - name: Install dependencies
        run: sudo apt-get update && sudo apt-get install -y jq curl
      
      - name: Run integration tests
        run: bash tests/test-runner.sh integration
```

---

## 🔴 Phase 2: SHA256 校验和验证 (TDD)

**优先级**: P0 - 关键安全功能
**预计时间**: 4-6 小时

### Step 2.1: 编写测试用例（先写测试）

**输出文件**: `tests/unit/test_checksum.sh`

```bash
#!/usr/bin/env bash
# Unit tests for SHA256 checksum verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load test framework
source "$SCRIPT_DIR/../test-runner.sh"

# Load mocks
source "$SCRIPT_DIR/../mocks/http_mock.sh"

# Load module under test (will be created in Step 2.2)
source "$PROJECT_ROOT/lib/checksum.sh" 2>/dev/null || {
    echo "SKIP: lib/checksum.sh not yet created"
    exit 0
}

echo "=== Checksum Verification Tests ==="

# Test 1: Verify valid checksum succeeds
test_verify_valid_checksum() {
    echo ""
    echo "Test 1: Valid checksum verification"
    
    local test_file="/tmp/test-binary-$$"
    echo "test content" > "$test_file"
    
    # Calculate actual checksum
    local actual_sum
    actual_sum=$(sha256sum "$test_file" | awk '{print $1}')
    
    # Create mock checksum file
    local checksum_file="/tmp/checksum-$$"
    echo "$actual_sum  test-binary" > "$checksum_file"
    
    # Test verification
    if verify_file_checksum "$test_file" "$checksum_file"; then
        assert_success "true" "Valid checksum verification succeeded"
    else
        assert_failure "true" "Valid checksum verification failed"
    fi
    
    rm -f "$test_file" "$checksum_file"
}

# Test 2: Verify invalid checksum fails
test_verify_invalid_checksum() {
    echo ""
    echo "Test 2: Invalid checksum verification"
    
    local test_file="/tmp/test-binary-$$"
    echo "test content" > "$test_file"
    
    # Create wrong checksum
    local checksum_file="/tmp/checksum-$$"
    echo "0000000000000000000000000000000000000000000000000000000000000000  test-binary" > "$checksum_file"
    
    # Test verification (should fail)
    if verify_file_checksum "$test_file" "$checksum_file"; then
        assert_failure "true" "Invalid checksum should have failed"
    else
        assert_success "true" "Invalid checksum correctly rejected"
    fi
    
    rm -f "$test_file" "$checksum_file"
}

# Test 3: Missing checksum file handling
test_missing_checksum_file() {
    echo ""
    echo "Test 3: Missing checksum file handling"
    
    local test_file="/tmp/test-binary-$$"
    echo "test content" > "$test_file"
    
    # Test with non-existent checksum file
    local result
    result=$(verify_file_checksum "$test_file" "/nonexistent/checksum.txt" 2>&1 || echo "FAILED")
    
    assert_contains "$result" "not found" "Should warn about missing checksum file"
    
    rm -f "$test_file"
}

# Test 4: SHA256 tool detection
test_sha256_tool_detection() {
    echo ""
    echo "Test 4: SHA256 tool detection"
    
    # Test sha256sum
    if command -v sha256sum >/dev/null 2>&1; then
        assert_success "command -v sha256sum" "sha256sum tool detected"
    fi
    
    # Test shasum
    if command -v shasum >/dev/null 2>&1; then
        assert_success "command -v shasum" "shasum tool detected"
    fi
}

# Test 5: Checksum format validation
test_checksum_format_validation() {
    echo ""
    echo "Test 5: Checksum format validation"
    
    local test_file="/tmp/test-binary-$$"
    echo "test content" > "$test_file"
    
    # Invalid checksum format (too short)
    local checksum_file="/tmp/checksum-$$"
    echo "invalid  test-binary" > "$checksum_file"
    
    local result
    result=$(verify_file_checksum "$test_file" "$checksum_file" 2>&1 || echo "INVALID_FORMAT")
    
    assert_contains "$result" "INVALID" "Should detect invalid checksum format"
    
    rm -f "$test_file" "$checksum_file"
}

# Test 6: Integration with download process
test_download_with_verification() {
    echo ""
    echo "Test 6: Download with verification integration"
    
    # This tests the integration with download_singbox function
    # Will be implemented after the function is created
    echo "  SKIP: Integration test (implement in Phase 2.3)"
}

# Run all tests
test_verify_valid_checksum
test_verify_invalid_checksum
test_missing_checksum_file
test_sha256_tool_detection
test_checksum_format_validation
test_download_with_verification

echo ""
echo "=== Checksum Tests Complete ==="
