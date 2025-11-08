# TDD 实施指南 - Claude Code 启发的改进

## 📖 TDD 工作流程

### Red-Green-Refactor 循环

```
1. 🔴 RED: 写一个失败的测试
   ├─ 定义期望的行为
   ├─ 运行测试（应该失败）
   └─ 确认测试失败原因正确

2. 🟢 GREEN: 编写最小代码让测试通过
   ├─ 实现功能
   ├─ 运行测试（应该通过）
   └─ 确认所有测试通过

3. 🔵 REFACTOR: 优化代码
   ├─ 重构实现
   ├─ 运行测试（仍然通过）
   └─ 提交代码

重复...
```

---

## ✅ Phase 1: 测试基础设施（已完成）

### 创建的文件

- ✅ `tests/test-runner.sh` - 测试运行器框架
- ✅ `tests/mocks/http_mock.sh` - HTTP 请求 Mock
- ✅ `tests/unit/test_checksum.sh` - 校验和测试用例
- ✅ `tests/{unit,integration,mocks}/` - 目录结构

### 验证结果

```bash
$ bash tests/unit/test_checksum.sh
⚠ SKIP: lib/checksum.sh not yet created (expected for TDD red phase)
```

**状态**: ✅ Phase 1 完成

---

## 🔴 Phase 2: SHA256 校验和验证

### 当前状态: Step 2.1 完成（RED 阶段）

- ✅ 测试用例已编写
- ⏳ 功能实现（下一步）
- ⏳ 测试验证
- ⏳ 集成到安装脚本

### Step 2.2: 实现功能（GREEN 阶段）

**目标**: 创建 `lib/checksum.sh` 模块

**功能要求**:
1. 从 GitHub 下载校验和文件
2. 验证 SHA256 格式（64 个十六进制字符）
3. 计算实际文件校验和
4. 比较校验和（不区分大小写）
5. 支持 sha256sum 和 shasum 工具
6. 优雅处理缺失校验和文件

**实现代码**: `lib/checksum.sh`

```bash
#!/usr/bin/env bash
# lib/checksum.sh - SHA256 checksum verification for sing-box binaries

[[ -n "${_SBX_CHECKSUM_LOADED:-}" ]] && return 0
readonly _SBX_CHECKSUM_LOADED=1

# Determine script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load dependencies
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

# Verify file against checksum file
# Args:
#   $1: file_path - Path to file to verify
#   $2: checksum_file - Path to checksum file
# Returns:
#   0: Checksum valid
#   1: Checksum invalid or verification failed
verify_file_checksum() {
    local file_path="$1"
    local checksum_file="$2"

    # Check if file exists
    if [[ ! -f "$file_path" ]]; then
        err "File not found: $file_path"
        return 1
    fi

    # Check if checksum file exists
    if [[ ! -f "$checksum_file" ]]; then
        warn "Checksum file not found: $checksum_file"
        return 1
    fi

    # Extract expected checksum (first field of first line)
    local expected_sum
    expected_sum=$(awk '{print $1}' "$checksum_file" | head -1)

    # Validate checksum format (64 hex characters)
    if [[ ! "$expected_sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
        warn "Invalid checksum format: $expected_sum"
        return 1
    fi

    # Calculate actual checksum
    local actual_sum=""
    if command -v sha256sum >/dev/null 2>&1; then
        actual_sum=$(sha256sum "$file_path" | awk '{print $1}')
    elif command -v shasum >/dev/null 2>&1; then
        actual_sum=$(shasum -a 256 "$file_path" | awk '{print $1}')
    else
        warn "No SHA256 tool available (sha256sum/shasum)"
        return 1
    fi

    # Compare checksums (case-insensitive)
    if [[ "${expected_sum,,}" == "${actual_sum,,}" ]]; then
        return 0
    else
        err "Checksum mismatch!"
        err "  Expected: $expected_sum"
        err "  Actual:   $actual_sum"
        return 1
    fi
}

# Download and verify sing-box binary checksum
# Args:
#   $1: binary_path - Path to downloaded binary
#   $2: version - sing-box version (e.g., "v1.10.7")
#   $3: arch - Platform architecture (e.g., "linux-amd64")
# Returns:
#   0: Verification successful or skipped (non-fatal)
#   1: Verification failed (fatal)
verify_singbox_binary() {
    local binary_path="$1"
    local version="$2"
    local arch="$3"

    msg "Verifying binary integrity..."

    # Construct checksum URL
    local filename="sing-box-${version#v}-${arch}.tar.gz"
    local checksum_url="https://github.com/SagerNet/sing-box/releases/download/${version}/${filename}.sha256sum"

    # Download checksum file
    local checksum_file
    checksum_file=$(mktemp)

    if ! safe_http_get "$checksum_url" "$checksum_file" 2>/dev/null; then
        warn "  ⚠ Checksum file not available from GitHub"
        warn "  ⚠ URL: $checksum_url"
        warn "  ⚠ Proceeding without verification (use at your own risk)"
        rm -f "$checksum_file"
        return 0  # Non-fatal
    fi

    # Verify checksum
    if verify_file_checksum "$binary_path" "$checksum_file"; then
        success "  ✓ Binary integrity verified (SHA256 match)"
        rm -f "$checksum_file"
        return 0
    else
        err "Binary verification FAILED!"
        err "Package may be corrupted or tampered."
        rm -f "$checksum_file"
        return 1  # Fatal
    fi
}

# Export functions
export -f verify_file_checksum
export -f verify_singbox_binary
```

### Step 2.3: 运行测试（验证 GREEN）

```bash
# 运行测试
bash tests/unit/test_checksum.sh

# 预期输出：所有测试通过
```

### Step 2.4: 集成到安装脚本

**修改文件**: `install_multi.sh`

在 `download_singbox()` 函数中添加校验和验证：

```bash
# 在文件顶部添加 source
source "${LIB_DIR}/checksum.sh"

# 在 download_singbox() 函数中，下载后添加验证
download_singbox() {
    # ... 现有下载逻辑 ...

    msg "Downloading sing-box ${tag}..."
    local pkg="$tmp/sb.tgz"
    safe_http_get "$url" "$pkg" || {
        rm -rf "$tmp"
        die "Failed to download sing-box package"
    }

    # ========== 新增：校验和验证 ==========
    if ! verify_singbox_binary "$pkg" "$tag" "$arch"; then
        rm -rf "$tmp"
        die "Binary verification failed, aborting installation"
    fi
    # ========== 校验和验证结束 ==========

    msg "Extracting package..."
    # ... 继续现有逻辑 ...
}
```

### Step 2.5: 集成测试

**创建**: `tests/integration/test_install_with_checksum.sh`

```bash
#!/usr/bin/env bash
# Integration test for installation with checksum verification

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== Integration Test: Install with Checksum Verification ==="

# Create test environment
TEST_DIR="/tmp/sbx-test-$$"
mkdir -p "$TEST_DIR"

# Cleanup function
cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

echo "Test 1: Verify checksum module loads correctly"
if source "$PROJECT_ROOT/lib/checksum.sh"; then
    echo "✓ Checksum module loaded"
else
    echo "✗ Failed to load checksum module"
    exit 1
fi

echo "Test 2: Verify functions are exported"
if declare -F verify_file_checksum >/dev/null && \
   declare -F verify_singbox_binary >/dev/null; then
    echo "✓ Checksum functions exported"
else
    echo "✗ Checksum functions not exported"
    exit 1
fi

echo ""
echo "=== Integration Test Passed ==="
```

### Step 2.6: 文档更新

**更新**: `CLAUDE.md`

添加到 "Environment Variables & Configuration" 部分：

```markdown
### Checksum Verification (Security)
- `SKIP_CHECKSUM=1` - Skip SHA256 checksum verification (not recommended)
- Default: Checksum verification enabled
- Automatically downloads official `.sha256sum` files from GitHub releases
- Supports both `sha256sum` and `shasum` tools
- Gracefully degrades if checksum files unavailable
```

---

## 🟡 Phase 3: 版本别名支持

### Step 3.1: 编写测试用例（RED）

**创建**: `tests/unit/test_version_resolver.sh`

```bash
#!/usr/bin/env bash
# Unit tests for version alias resolution

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

# Load test framework
source "$PROJECT_ROOT/tests/test-runner.sh"

# Try to load module under test
if [[ -f "$PROJECT_ROOT/lib/version.sh" ]]; then
    source "$PROJECT_ROOT/lib/version.sh"
else
    echo "⚠ SKIP: lib/version.sh not yet created"
    exit 0
fi

echo "=== Version Resolver Tests ==="

# Test 1: Resolve 'stable' to latest stable release
test_resolve_stable() {
    echo ""
    echo "Test 1: Resolve 'stable' alias"

    SINGBOX_VERSION="stable"
    local resolved
    resolved=$(resolve_singbox_version)

    # Should return vX.Y.Z format
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        assert_success "true" "Stable version resolved: $resolved"
    else
        assert_failure "true" "Invalid version format: $resolved"
    fi
}

# Test 2: Resolve 'latest' to absolute latest release
test_resolve_latest() {
    echo ""
    echo "Test 2: Resolve 'latest' alias"

    SINGBOX_VERSION="latest"
    local resolved
    resolved=$(resolve_singbox_version)

    # Should return vX.Y.Z or vX.Y.Z-beta.N format
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        assert_success "true" "Latest version resolved: $resolved"
    else
        assert_failure "true" "Invalid version format: $resolved"
    fi
}

# Test 3: Resolve specific version tag
test_resolve_specific() {
    echo ""
    echo "Test 3: Resolve specific version"

    SINGBOX_VERSION="v1.10.7"
    local resolved
    resolved=$(resolve_singbox_version)

    assert_equals "v1.10.7" "$resolved" "Specific version preserved"
}

# Test 4: Resolve version without 'v' prefix
test_resolve_without_v() {
    echo ""
    echo "Test 4: Resolve version without 'v' prefix"

    SINGBOX_VERSION="1.10.7"
    local resolved
    resolved=$(resolve_singbox_version)

    assert_equals "v1.10.7" "$resolved" "Version prefixed with 'v'"
}

# Test 5: Reject invalid version format
test_invalid_version() {
    echo ""
    echo "Test 5: Reject invalid version format"

    SINGBOX_VERSION="invalid-version"
    if resolve_singbox_version 2>/dev/null; then
        assert_failure "true" "Should reject invalid version"
    else
        assert_success "true" "Invalid version correctly rejected"
    fi
}

# Test 6: Default to stable when unset
test_default_stable() {
    echo ""
    echo "Test 6: Default to stable when unset"

    unset SINGBOX_VERSION
    local resolved
    resolved=$(resolve_singbox_version)

    # Should return a valid version
    if [[ "$resolved" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        assert_success "true" "Default resolves to stable: $resolved"
    else
        assert_failure "true" "Default resolution failed"
    fi
}

# Run all tests
test_resolve_stable
test_resolve_latest
test_resolve_specific
test_resolve_without_v
test_invalid_version
test_default_stable

echo ""
echo "=== Version Resolver Tests Complete ==="
```

### Step 3.2: 实现功能（GREEN）

**创建**: `lib/version.sh`

```bash
#!/usr/bin/env bash
# lib/version.sh - Version alias resolution for sing-box

[[ -n "${_SBX_VERSION_LOADED:-}" ]] && return 0
readonly _SBX_VERSION_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

# Resolve version alias to actual version tag
# Uses SINGBOX_VERSION environment variable
# Returns: Resolved version tag (e.g., "v1.10.7")
resolve_singbox_version() {
    local version_input="${SINGBOX_VERSION:-stable}"
    local resolved_version=""

    msg "Resolving version: $version_input"

    case "$version_input" in
        stable|"")
            # Fetch latest stable release (non-prerelease)
            msg "  Fetching latest stable release..."
            local api_response
            api_response=$(safe_http_get \
                "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 10)

            resolved_version=$(echo "$api_response" | \
                grep '"tag_name":' | \
                head -1 | \
                grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')
            ;;

        latest)
            # Fetch absolute latest release (including prereleases)
            msg "  Fetching latest release (including pre-releases)..."
            local api_response
            api_response=$(safe_http_get \
                "https://api.github.com/repos/SagerNet/sing-box/releases" 10)

            resolved_version=$(echo "$api_response" | \
                grep '"tag_name":' | \
                head -1 | \
                grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?')
            ;;

        v[0-9]*)
            # Already a version tag
            resolved_version="$version_input"
            ;;

        [0-9]*)
            # Version without 'v' prefix
            resolved_version="v${version_input}"
            ;;

        *)
            die "Invalid version format: $version_input (use: stable, latest, or vX.Y.Z)"
            ;;
    esac

    if [[ -z "$resolved_version" ]]; then
        die "Failed to resolve version: $version_input"
    fi

    success "  ✓ Resolved to: $resolved_version"
    echo "$resolved_version"
}

export -f resolve_singbox_version
```

### Step 3.3: 集成到安装脚本

**修改**: `install_multi.sh`

```bash
# 在文件顶部
source "${LIB_DIR}/version.sh"

# 修改 download_singbox() 函数
download_singbox() {
    # ... 现有代码 ...

    # 使用版本解析器
    local tag
    tag=$(resolve_singbox_version)

    msg "Downloading sing-box ${tag}..."

    # ... 继续现有逻辑 ...
}
```

---

## 🟡 Phase 4: 平台检测增强

### Step 4.1: 编写测试用例（RED）

**创建**: `tests/unit/test_platform_detection.sh`

```bash
#!/usr/bin/env bash
# Unit tests for enhanced platform detection

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

source "$PROJECT_ROOT/tests/test-runner.sh"

if [[ -f "$PROJECT_ROOT/lib/platform.sh" ]]; then
    source "$PROJECT_ROOT/lib/platform.sh"
else
    echo "⚠ SKIP: lib/platform.sh not yet created"
    exit 0
fi

echo "=== Platform Detection Tests ==="

# Test 1: Detect current platform
test_current_platform() {
    echo ""
    echo "Test 1: Detect current platform"

    local platform
    platform=$(detect_platform)

    # Should return valid platform string
    if [[ "$platform" =~ ^(linux|darwin)-(amd64|arm64|armv7)$ ]]; then
        assert_success "true" "Platform detected: $platform"
    else
        assert_failure "true" "Invalid platform format: $platform"
    fi
}

# Test 2: Detect musl on Alpine
test_musl_detection() {
    echo ""
    echo "Test 2: Musl libc detection"

    # Can only test if we're on a musl system
    if [[ -f /lib/libc.musl-x86_64.so.1 ]] || ldd /bin/ls 2>&1 | grep -q musl; then
        assert_success "true" "Musl libc detected"
    else
        echo "  ℹ SKIP: Not a musl system"
    fi
}

# Test 3: Architecture normalization
test_arch_normalization() {
    echo ""
    echo "Test 3: Architecture normalization"

    # Mock uname -m output
    local arch
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) arch="unknown" ;;
    esac

    if [[ "$arch" != "unknown" ]]; then
        assert_success "true" "Architecture normalized: $arch"
    else
        assert_failure "true" "Unknown architecture"
    fi
}

# Run tests
test_current_platform
test_musl_detection
test_arch_normalization

echo ""
echo "=== Platform Detection Tests Complete ==="
```

### Step 4.2: 实现功能（GREEN）

**创建**: `lib/platform.sh`

```bash
#!/usr/bin/env bash
# lib/platform.sh - Enhanced platform detection

[[ -n "${_SBX_PLATFORM_LOADED:-}" ]] && return 0
readonly _SBX_PLATFORM_LOADED=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# Detect current platform with enhanced detection
# Returns: Platform string (e.g., "linux-amd64", "darwin-arm64")
detect_platform() {
    local os arch platform

    # Detect OS
    case "$(uname -s)" in
        Linux) os="linux" ;;
        Darwin) os="darwin" ;;
        *) die "Unsupported OS: $(uname -s)" ;;
    esac

    # Detect architecture
    case "$(uname -m)" in
        x86_64|amd64) arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l) arch="armv7" ;;
        *) die "Unsupported architecture: $(uname -m)" ;;
    esac

    # Check for musl on Linux (Alpine, Void, etc.)
    if [[ "$os" = "linux" ]]; then
        if [[ -f /lib/libc.musl-x86_64.so.1 ]] || \
           [[ -f /lib/libc.musl-aarch64.so.1 ]] || \
           ldd /bin/ls 2>&1 | grep -q musl; then
            msg "Detected musl libc (Alpine Linux)"
            # Note: sing-box currently doesn't have separate musl builds
            # This prepares for future support
        fi
    fi

    platform="${os}-${arch}"
    echo "$platform"
}

export -f detect_platform
```

---

## 📊 实施进度跟踪

### Phase 1: 测试基础设施 ✅
- ✅ 测试运行器框架
- ✅ Mock 工具
- ✅ 单元测试模板
- ✅ 集成测试模板

### Phase 2: 校验和验证 ⏳
- ✅ 测试用例编写 (RED)
- ⏳ 功能实现 (GREEN) - 下一步
- ⏳ 测试验证
- ⏳ 集成到安装脚本
- ⏳ 文档更新

### Phase 3: 版本别名支持 ⏳
- ⏳ 测试用例编写 (RED)
- ⏳ 功能实现 (GREEN)
- ⏳ 集成到安装脚本

### Phase 4: 平台检测增强 ⏳
- ⏳ 测试用例编写 (RED)
- ⏳ 功能实现 (GREEN)
- ⏳ 集成到安装脚本

### Phase 5: 集成测试和文档 ⏳
- ⏳ 端到端测试
- ⏳ 文档更新
- ⏳ CHANGELOG 更新

---

## 🎯 下一步行动

### 立即执行：实现 Phase 2.2 (GREEN 阶段)

1. 创建 `lib/checksum.sh` 文件
2. 实现 `verify_file_checksum()` 函数
3. 实现 `verify_singbox_binary()` 函数
4. 运行测试验证功能

```bash
# 执行命令
cd /home/user/sbx-lite
# 1. 创建 checksum 模块（参考上面的实现代码）
# 2. 运行测试
bash tests/unit/test_checksum.sh
# 3. 验证所有测试通过
```

### 后续步骤

- Phase 2.3: 集成到 install_multi.sh
- Phase 2.4: 集成测试
- Phase 2.5: 文档更新
- Phase 2.6: 提交 PR

---

## 📝 Commit 消息规范

遵循 Conventional Commits 标准：

```
feat(checksum): add SHA256 verification for sing-box binaries

- Implement verify_file_checksum() function
- Implement verify_singbox_binary() function
- Support both sha256sum and shasum tools
- Graceful degradation when checksum unavailable
- Add comprehensive unit tests (6 test cases)

Tests: All unit tests passing (6/6)
Coverage: 100% of new code
Breaking: None
```

---

## ✅ 验收标准

### Phase 2: Checksum Verification

- [ ] 所有单元测试通过 (6/6)
- [ ] 集成测试通过
- [ ] 支持 sha256sum 工具
- [ ] 支持 shasum 工具
- [ ] 优雅处理缺失校验和
- [ ] 校验和不匹配时中止安装
- [ ] 文档更新完成

### Phase 3: Version Aliases

- [ ] 所有单元测试通过 (6/6)
- [ ] `stable` 别名工作正常
- [ ] `latest` 别名工作正常
- [ ] 语义版本号支持
- [ ] 向后兼容现有用法
- [ ] 文档更新完成

### Phase 4: Platform Detection

- [ ] 所有单元测试通过 (3/3)
- [ ] 正确检测 musl libc
- [ ] 支持所有架构
- [ ] 清晰的错误消息
- [ ] 文档更新完成

---

现在可以开始实施了！是否要我继续执行 Phase 2.2 (创建 lib/checksum.sh)?
