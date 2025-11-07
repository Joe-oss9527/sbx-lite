# sbx-lite 一键安装改进计划
## Professional Enhancement Plan Based on Industry Best Practices

**文档版本**: 1.0
**创建日期**: 2025-11-07
**参考标准**: Google SRE, Rust Foundation (rustup), Docker, OWASP
**目标**: 将一键安装功能提升至生产级质量

---

## 执行摘要

基于对 sbx-lite 一键安装功能的全面审查（详见 `ONELINER_INSTALL_AUDIT.md`），本计划参考以下业界顶级项目的最佳实践：

- **Rustup** (`rust-lang/rustup`): 下载器抽象、分层验证、条件性重试
- **Docker Install** (`docker/docker-install`): dry-run 机制、ShellCheck 集成
- **Google SRE Book**: 指数退避 + 抖动、重试预算、错误分类
- **OWASP**: 文件完整性验证、安全传输、输入验证

本计划遵循以下软件设计原则：
- **SOLID 原则**: 单一职责、开闭原则、依赖倒置
- **DRY (Don't Repeat Yourself)**: 复用性设计
- **KISS (Keep It Simple, Stupid)**: 简单可维护
- **防御性编程**: 假设一切都会失败
- **向后兼容**: 不破坏现有用户体验

---

## 目录

1. [设计原则与架构决策](#设计原则与架构决策)
2. [Phase 1: 紧急修复](#phase-1-紧急修复-p0)
3. [Phase 2: 可靠性增强](#phase-2-可靠性增强-p1)
4. [Phase 3: 性能优化](#phase-3-性能优化-p2)
5. [Phase 4: 生产级增强](#phase-4-生产级增强-future)
6. [测试策略](#测试策略)
7. [回滚计划](#回滚计划)
8. [性能基准](#性能基准)
9. [安全审查](#安全审查)
10. [维护性评估](#维护性评估)

---

## 设计原则与架构决策

### 核心设计原则

#### 1. 单一职责原则 (SRP)
**当前问题**: `_load_modules()` 函数 74 行，混合了检测、下载、验证、清理逻辑

**改进方案**:
```bash
# 拆分为专门的函数，每个函数只负责一件事
_detect_installation_mode()  # 检测本地/远程模式
_download_module()           # 下载单个模块
_verify_module()            # 验证模块完整性
_setup_module_directory()   # 设置目录结构
_load_modules()             # 协调函数（编排上述函数）
```

**参考**: Rustup 的 `need_cmd()`, `ensure()`, `assert_nz()` 函数分离

#### 2. 开闭原则 (OCP)
**设计目标**: 对扩展开放，对修改关闭

**实现方式**:
```bash
# 通过环境变量和配置文件支持扩展
GITHUB_REPO="${GITHUB_REPO:-https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main}"
MAX_RETRIES="${MAX_RETRIES:-3}"
RETRY_BACKOFF_BASE="${RETRY_BACKOFF_BASE:-2}"
DOWNLOAD_TIMEOUT="${DOWNLOAD_TIMEOUT:-30}"

# 支持自定义下载器
DOWNLOADER="${DOWNLOADER:-auto}"  # auto, curl, wget, aria2c
```

**参考**: Rustup 的环境变量覆盖机制 (`RUSTUP_HOME`, `CARGO_HOME`)

#### 3. 依赖倒置原则 (DIP)
**设计目标**: 依赖抽象而非具体实现

**实现方式**:
```bash
# 下载器抽象层（参考 Rustup）
download_file() {
    local url="$1"
    local output="$2"

    # 自动选择最佳下载器
    if have curl; then
        _download_with_curl "$url" "$output"
    elif have wget; then
        _download_with_wget "$url" "$output"
    elif have aria2c; then
        _download_with_aria2c "$url" "$output"
    else
        die "No supported downloader found (curl, wget, aria2c)"
    fi
}

# 具体实现
_download_with_curl() {
    local url="$1"
    local output="$2"
    curl -fsSL --connect-timeout 10 --max-time "$DOWNLOAD_TIMEOUT" \
         --retry 0 "$url" -o "$output"  # 重试由上层控制
}
```

**参考**: Rustup 的 downloader abstraction

#### 4. 防御性编程
**Google SRE 原则**: "Assume everything will fail"

**实现策略**:
```bash
# 1. 严格模式
set -euo pipefail

# 2. 输入验证
validate_url() {
    local url="$1"
    [[ "$url" =~ ^https:// ]] || die "Only HTTPS URLs allowed"
    [[ "${#url}" -le 2048 ]] || die "URL too long"
}

# 3. 资源清理
cleanup() {
    local exit_code=$?
    if [[ -n "${TEMP_DIR:-}" && -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# 4. 错误分类（可重试 vs 不可重试）
is_retriable_error() {
    local exit_code="$1"
    case "$exit_code" in
        # 网络临时错误 - 可重试
        6|7|28|35|52|56)  # curl 错误代码
            return 0 ;;
        # 永久错误 - 不可重试
        22|23|404)  # HTTP 4xx 错误
            return 1 ;;
        *)
            return 0 ;;  # 默认可重试
    esac
}
```

**参考**: Google SRE - Distinguish Error Types

---

## Phase 1: 紧急修复 (P0)

**目标**: 修复影响功能的关键问题
**时间**: 30 分钟
**优先级**: CRITICAL

### 1.1 统一仓库 URL (Issue #1)

**问题**: README.md 使用 `YYvanYang/sbx-lite`，代码使用 `Joe-oss9527/sbx-lite`

**解决方案**:

#### Option A: 动态检测（推荐）
```bash
# install_multi.sh 自动检测来源
detect_github_repo() {
    # 尝试从下载 URL 提取仓库信息（如果通过 curl | bash 安装）
    # 否则使用默认值
    local detected_repo=""

    # 检查环境变量（用户可覆盖）
    if [[ -n "${GITHUB_REPO:-}" ]]; then
        echo "$GITHUB_REPO"
        return 0
    fi

    # 默认值（与代码仓库一致）
    echo "https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main"
}

readonly GITHUB_BASE_URL="$(detect_github_repo)"
```

**优点**:
- ✅ 自动适配 fork 仓库
- ✅ 支持用户覆盖
- ✅ 未来 fork 友好

**参考**: Rustup 的平台检测策略

#### Option B: 硬编码统一（简单）
```bash
# 1. 更新 README.md
sed -i 's|YYvanYang/sbx-lite|Joe-oss9527/sbx-lite|g' README.md

# 2. 在 install_multi.sh 顶部明确声明
readonly GITHUB_REPO="https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main"
```

**推荐**: 采用 Option B（短期）+ Option A（长期）

### 1.2 添加基础文件验证

**目标**: 防止下载损坏或恶意文件

**实现**:
```bash
# lib/download.sh (新建库)

# 验证下载的模块文件
verify_downloaded_module() {
    local module_file="$1"
    local module_name="$(basename "$module_file" .sh)"

    # 1. 文件存在性检查
    [[ -f "$module_file" ]] || die "Module file not found: $module_file"

    # 2. 最小文件大小检查（防止下载空文件或错误页面）
    local file_size
    file_size="$(stat -c%s "$module_file" 2>/dev/null || stat -f%z "$module_file" 2>/dev/null)"
    if [[ "$file_size" -lt 100 ]]; then
        die "Downloaded file too small: ${module_name}.sh (${file_size} bytes)"
    fi

    # 3. Bash 语法验证
    if ! bash -n "$module_file" 2>&1; then
        err "Invalid bash syntax in: ${module_name}.sh"
        err "This may indicate a corrupted download or MITM attack"
        die "Aborting for security reasons"
    fi

    # 4. 检查文件是否包含必要的模块标识
    if ! grep -q "^# lib/${module_name}.sh" "$module_file"; then
        warn "Module file missing expected header: ${module_name}.sh"
        warn "This may indicate a version mismatch"
    fi

    # 5. 检查防护变量（防止重复加载）
    local guard_var="_SBX_${module_name^^}_LOADED"
    if ! grep -q "$guard_var" "$module_file"; then
        warn "Module missing load guard: $guard_var"
    fi

    msg "✓ Module verified: ${module_name}.sh ($file_size bytes)"
}
```

**测试用例**:
```bash
# 测试 1: 正常文件 → 通过
# 测试 2: 空文件 → 失败（文件太小）
# 测试 3: HTML 404 页面 → 失败（语法错误）
# 测试 4: 不完整文件 → 失败（语法错误）
# 测试 5: 错误的模块 → 警告（缺少头部）
```

**安全考虑**:
- ✅ 防止下载 404 错误页面
- ✅ 防止下载部分文件
- ✅ 防止语法错误导致脚本中断
- ⚠️ 不能防止恶意但语法正确的代码（需要 Phase 4 的 SHA256）

**参考**:
- Rustup: File executability checks
- OWASP: Input validation

### 1.3 改进错误消息

**当前问题**: 错误消息不够具体

**改进**:
```bash
# 下载失败时提供更多上下文
download_module_with_context() {
    local module="$1"
    local module_url="${GITHUB_BASE_URL}/lib/${module}.sh"
    local module_file="${TEMP_LIB_DIR}/${module}.sh"

    msg "Downloading ${module}.sh..."

    if ! download_file "$module_url" "$module_file"; then
        err ""
        err "Failed to download module: ${module}.sh"
        err "URL: $module_url"
        err ""
        err "Possible causes:"
        err "  1. Network connectivity issues"
        err "  2. GitHub rate limiting (try again in a few minutes)"
        err "  3. Repository branch/tag does not exist"
        err "  4. Firewall blocking GitHub access"
        err ""
        err "Troubleshooting:"
        err "  • Test connectivity: curl -I https://github.com"
        err "  • Use git clone instead:"
        err "    git clone https://github.com/Joe-oss9527/sbx-lite.git"
        err "    cd sbx-lite && bash install_multi.sh"
        err ""
        return 1
    fi

    verify_downloaded_module "$module_file"
}
```

**参考**: Rustup 的分层错误消息

---

## Phase 2: 可靠性增强 (P1)

**目标**: 提升在不稳定网络下的可靠性
**时间**: 1.5 小时
**优先级**: HIGH

### 2.1 实现指数退避重试机制

**设计原则**: Google SRE - Exponential Backoff with Jitter

**实现**:
```bash
# lib/retry.sh (新建库)

# 常量配置
readonly RETRY_MAX_ATTEMPTS="${RETRY_MAX_ATTEMPTS:-3}"
readonly RETRY_BACKOFF_BASE="${RETRY_BACKOFF_BASE:-2}"
readonly RETRY_BACKOFF_MAX="${RETRY_BACKOFF_MAX:-32}"
readonly RETRY_JITTER_MAX="${RETRY_JITTER_MAX:-1000}"  # 毫秒

# 计算退避时间（含抖动）
calculate_backoff() {
    local attempt="$1"
    local base="${RETRY_BACKOFF_BASE}"
    local max="${RETRY_BACKOFF_MAX}"

    # 指数退避: min((base^attempt), max)
    local backoff=$((base ** attempt))
    [[ $backoff -gt $max ]] && backoff=$max

    # 添加抖动（0-1000ms）防止重试风暴
    # Google SRE: "Always use randomized exponential backoff"
    local jitter=$((RANDOM % RETRY_JITTER_MAX))

    echo $((backoff * 1000 + jitter))  # 返回毫秒
}

# 带重试的命令执行
retry_with_backoff() {
    local max_attempts="${1:-$RETRY_MAX_ATTEMPTS}"
    shift
    local command=("$@")

    local attempt=0
    local exit_code=0

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))

        # 执行命令
        if "${command[@]}"; then
            # 成功
            [[ $attempt -gt 1 ]] && msg "✓ Succeeded on attempt $attempt"
            return 0
        fi

        exit_code=$?

        # 检查是否可重试
        if ! is_retriable_error "$exit_code"; then
            err "✗ Non-retriable error (exit code: $exit_code)"
            return "$exit_code"
        fi

        # 最后一次尝试失败
        if [[ $attempt -ge $max_attempts ]]; then
            err "✗ Failed after $max_attempts attempts"
            return "$exit_code"
        fi

        # 计算退避时间
        local backoff_ms
        backoff_ms="$(calculate_backoff $attempt)"
        local backoff_sec=$((backoff_ms / 1000))

        warn "Attempt $attempt/$max_attempts failed, retrying in ${backoff_sec}s..."

        # 退避等待（毫秒精度）
        sleep "$(printf '%.3f' "$(echo "scale=3; $backoff_ms / 1000" | bc)")"
    done

    return "$exit_code"
}

# 可重试错误判断（参考 curl/wget 退出代码）
is_retriable_error() {
    local exit_code="$1"

    # curl 可重试错误代码
    # 6: Could not resolve host
    # 7: Failed to connect to host
    # 28: Operation timeout
    # 35: SSL connect error
    # 52: Empty reply from server
    # 56: Connection reset
    case "$exit_code" in
        6|7|28|35|52|56)
            return 0 ;;  # 可重试
        # HTTP 4xx/5xx 错误
        22)  # HTTP error (curl)
            return 1 ;;  # 不可重试（404, 403 等）
        # 其他错误默认可重试（保守策略）
        *)
            return 0 ;;
    esac
}
```

**使用示例**:
```bash
# 下载模块时使用重试
download_module() {
    local module="$1"
    local url="${GITHUB_BASE_URL}/lib/${module}.sh"
    local output="${TEMP_LIB_DIR}/${module}.sh"

    retry_with_backoff 3 download_file "$url" "$output"
}
```

**退避时间表**:
```
Attempt 1: 失败
Attempt 2: 等待 2s + (0-1s jitter) = 2-3s
Attempt 3: 等待 4s + (0-1s jitter) = 4-5s
Attempt 4: 等待 8s + (0-1s jitter) = 8-9s

最坏情况总时间: 3 + 5 + 9 = 17s (相比无重试只增加 17s)
```

**测试用例**:
```bash
# 测试 1: 命令立即成功 → 0 次重试
# 测试 2: 第 2 次成功 → 1 次重试 + 退避
# 测试 3: 全部失败 → 3 次重试后放弃
# 测试 4: 非可重试错误 → 立即失败
# 测试 5: 抖动分布 → 验证随机性
```

**参考**:
- Google SRE: Exponential Backoff with Jitter
- Cloud Storage Retry Strategy (Google Cloud)

### 2.2 重试预算实现

**目标**: 防止重试风暴消耗系统资源

**实现**:
```bash
# lib/retry.sh (扩展)

# 全局重试计数器（防止重试放大）
declare -g GLOBAL_RETRY_COUNT=0
readonly GLOBAL_RETRY_BUDGET="${GLOBAL_RETRY_BUDGET:-30}"  # 全局最大重试次数

# 检查重试预算
check_retry_budget() {
    if [[ $GLOBAL_RETRY_COUNT -ge $GLOBAL_RETRY_BUDGET ]]; then
        err ""
        err "Global retry budget exhausted ($GLOBAL_RETRY_BUDGET retries)"
        err "This may indicate a systemic issue (e.g., GitHub outage)"
        err "Please try again later or use git clone installation"
        err ""
        return 1
    fi
    return 0
}

# 扩展 retry_with_backoff
retry_with_backoff() {
    # ... (前面的代码)

    while [[ $attempt -lt $max_attempts ]]; do
        ((attempt++))

        # 检查全局预算
        if ! check_retry_budget; then
            return 1
        fi

        if "${command[@]}"; then
            return 0
        fi

        # 记录重试
        ((GLOBAL_RETRY_COUNT++))

        # ... (后续代码)
    done
}
```

**参考**: Google SRE - Retry Budget

### 2.3 下载器增强

**目标**: 参考 Rustup 实现健壮的下载器

**实现**:
```bash
# lib/download.sh (新建库)

# 检查 curl 是否支持重试
check_curl_for_retry_support() {
    local test_args="--retry 1"
    if curl $test_args -o /dev/null https://static.rust-lang.org/ >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# 增强的 curl 下载器
_download_with_curl() {
    local url="$1"
    local output="$2"

    local args=(
        -fsSL                           # fail silently, show errors, follow redirects, silent
        --proto '=https'                # only HTTPS (安全性)
        --tlsv1.2                       # TLS 1.2+ (安全性)
        --connect-timeout 10            # 连接超时
        --max-time "$DOWNLOAD_TIMEOUT"  # 总超时
    )

    # 条件性添加重试支持（Rustup 模式）
    if check_curl_for_retry_support; then
        args+=(--retry 0)  # 重试由外层控制
    fi

    # 执行下载
    if ! curl "${args[@]}" "$url" -o "$output" 2>&1; then
        return 1
    fi

    return 0
}

# 增强的 wget 下载器
_download_with_wget() {
    local url="$1"
    local output="$2"

    wget --quiet \
         --timeout="$DOWNLOAD_TIMEOUT" \
         --secure-protocol=TLSv1_2 \
         --https-only \
         "$url" \
         -O "$output" 2>&1
}

# 智能下载器选择
download_file() {
    local url="$1"
    local output="$2"

    # 验证 URL
    [[ "$url" =~ ^https:// ]] || die "Only HTTPS URLs allowed: $url"

    # 选择下载器
    if [[ "${DOWNLOADER:-auto}" == "auto" ]]; then
        if have curl; then
            _download_with_curl "$url" "$output"
        elif have wget; then
            _download_with_wget "$url" "$output"
        else
            die "No supported downloader found (curl, wget)"
        fi
    else
        # 用户指定下载器
        case "$DOWNLOADER" in
            curl)
                need_cmd curl
                _download_with_curl "$url" "$output"
                ;;
            wget)
                need_cmd wget
                _download_with_wget "$url" "$output"
                ;;
            *)
                die "Unsupported downloader: $DOWNLOADER"
                ;;
        esac
    fi
}
```

**安全增强**:
- ✅ 强制 HTTPS
- ✅ 强制 TLS 1.2+
- ✅ 超时保护
- ✅ URL 验证

**参考**: Rustup downloader abstraction

### 2.4 API 契约检查

**目标**: 验证模块版本兼容性

**实现**:
```bash
# install_multi.sh

# API 契约定义（必需的函数）
readonly REQUIRED_FUNCTIONS_COMMON=(
    msg warn err success die
    generate_uuid have need_root
)

readonly REQUIRED_FUNCTIONS_NETWORK=(
    get_public_ip allocate_port
    detect_ipv6_support safe_http_get
)

# ... 其他模块的契约

# 验证模块 API
verify_module_api() {
    local module="$1"
    shift
    local required_functions=("$@")

    for func in "${required_functions[@]}"; do
        if ! declare -F "$func" >/dev/null 2>&1; then
            err "Required function not found: $func"
            err "Module: $module"
            err "This may indicate a version mismatch"
            die "API contract violation"
        fi
    done

    msg "✓ Module API verified: $module (${#required_functions[@]} functions)"
}

# 在模块加载后验证
_load_modules() {
    # ... (加载模块)

    # 验证 API 契约
    verify_module_api "common" "${REQUIRED_FUNCTIONS_COMMON[@]}"
    verify_module_api "network" "${REQUIRED_FUNCTIONS_NETWORK[@]}"
    # ... 其他模块
}
```

**优点**:
- ✅ 早期发现版本不兼容
- ✅ 明确的错误消息
- ✅ 防止运行时错误

**参考**: Design by Contract (DbC) 原则

---

## Phase 3: 性能优化 (P2)

**目标**: 将下载时间从 30s 优化到 3s
**时间**: 2 小时
**优先级**: MEDIUM

### 3.1 并行下载实现

**设计挑战**: Bash 并行编程的复杂性

**方案 A: xargs 并行（推荐）**
```bash
# lib/download.sh (扩展)

# 单模块下载包装器（供 xargs 调用）
download_single_module_wrapper() {
    local module="$1"
    local github_base="${GITHUB_BASE_URL}"
    local temp_dir="${TEMP_LIB_DIR}"

    local url="${github_base}/lib/${module}.sh"
    local output="${temp_dir}/${module}.sh"

    # 下载
    if ! retry_with_backoff 3 download_file "$url" "$output"; then
        echo "FAILED:$module" >&2
        return 1
    fi

    # 验证
    if ! verify_downloaded_module "$output"; then
        echo "VERIFY_FAILED:$module" >&2
        return 1
    fi

    echo "SUCCESS:$module"
    return 0
}

# 导出函数供子进程使用
export -f download_single_module_wrapper
export -f download_file
export -f verify_downloaded_module
# ... 导出所有依赖函数

# 并行下载所有模块
download_all_modules_parallel() {
    local modules=("$@")
    local parallel_jobs="${PARALLEL_JOBS:-5}"

    msg "Downloading ${#modules[@]} modules (${parallel_jobs} parallel jobs)..."

    # 使用 xargs 并行执行
    local failed_modules=()
    local success_count=0

    while IFS= read -r result; do
        case "$result" in
            SUCCESS:*)
                ((success_count++))
                ;;
            FAILED:*|VERIFY_FAILED:*)
                local failed_module="${result#*:}"
                failed_modules+=("$failed_module")
                ;;
        esac
    done < <(printf '%s\n' "${modules[@]}" | \
             xargs -P "$parallel_jobs" -I {} bash -c \
             'download_single_module_wrapper "$@"' _ {})

    # 检查结果
    if [[ ${#failed_modules[@]} -gt 0 ]]; then
        err "Failed to download modules: ${failed_modules[*]}"
        return 1
    fi

    success "✓ All $success_count modules downloaded and verified"
    return 0
}
```

**方案 B: GNU Parallel（可选）**
```bash
# 如果系统有 GNU parallel
if have parallel; then
    parallel -j 5 download_single_module_wrapper ::: "${modules[@]}"
else
    # 回退到 xargs
    download_all_modules_parallel "${modules[@]}"
fi
```

**性能对比**:
```
顺序下载 (当前):
  10 modules × 3s = 30s

并行下载 (5 jobs):
  ceil(10/5) × 3s = 6s

并行下载 (10 jobs):
  max(3s) = 3s

改进: 10x 速度提升
```

**测试用例**:
```bash
# 测试 1: 所有模块成功 → 3s 完成
# 测试 2: 部分模块失败 → 正确报告失败
# 测试 3: 网络不稳定 → 重试机制工作
# 测试 4: 单 job → 与顺序下载等效
# 测试 5: 并发限制 → 不超过指定 jobs
```

**注意事项**:
- ⚠️ 导出函数可能不被所有 shell 支持（需测试）
- ⚠️ 错误收集需要额外机制
- ⚠️ 增加代码复杂度

**回退策略**:
```bash
# 如果并行下载失败，回退到顺序下载
if ! download_all_modules_parallel "${modules[@]}"; then
    warn "Parallel download failed, falling back to sequential download"
    download_all_modules_sequential "${modules[@]}"
fi
```

### 3.2 进度指示

**实现**:
```bash
# lib/ui.sh (扩展)

# 简单进度条
show_download_progress() {
    local current="$1"
    local total="$2"
    local module="$3"

    local percent=$((current * 100 / total))
    local filled=$((percent / 5))  # 20 个字符宽度
    local empty=$((20 - filled))

    printf "\r  [%-20s] %3d%% (%d/%d) %s" \
           "$(printf '=%.0s' $(seq 1 $filled))$(printf ' %.0s' $(seq 1 $empty))" \
           "$percent" "$current" "$total" "$module"

    [[ $current -eq $total ]] && echo ""
}

# 在下载时使用
download_all_modules_sequential() {
    local modules=("$@")
    local total="${#modules[@]}"
    local current=0

    for module in "${modules[@]}"; do
        ((current++))
        show_download_progress "$current" "$total" "${module}.sh"
        download_module "$module" || return 1
    done
}
```

**输出示例**:
```
Downloading 10 modules...
  [====================] 100% (10/10) export.sh
✓ All modules downloaded and verified
```

---

## Phase 4: 生产级增强 (Future)

**目标**: 达到企业级部署标准
**时间**: 4-8 小时
**优先级**: LOW (未来增强)

### 4.1 SHA256 校验和系统

**架构设计**:
```
仓库结构:
  lib/
    common.sh
    network.sh
    ...
  checksums/
    v2.1.0.sha256        # 版本化校验和
    latest.sha256 -> v2.1.0.sha256  # 符号链接
```

**生成校验和** (CI/CD 自动化):
```bash
# .github/workflows/generate-checksums.yml
name: Generate Checksums

on:
  push:
    tags:
      - 'v*'

jobs:
  checksums:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Generate SHA256 checksums
        run: |
          cd lib
          sha256sum *.sh > ../checksums/${GITHUB_REF_NAME}.sha256
          cd ../checksums
          ln -sf ${GITHUB_REF_NAME}.sha256 latest.sha256

      - name: Commit checksums
        run: |
          git config user.name "GitHub Actions"
          git config user.email "actions@github.com"
          git add checksums/
          git commit -m "chore: generate checksums for ${GITHUB_REF_NAME}"
          git push
```

**验证校验和**:
```bash
# lib/download.sh (扩展)

download_and_verify_checksums() {
    local version="${1:-latest}"
    local checksum_url="${GITHUB_BASE_URL}/checksums/${version}.sha256"
    local checksum_file="${TEMP_DIR}/checksums.sha256"

    msg "Downloading checksums..."
    download_file "$checksum_url" "$checksum_file" || return 1

    # 验证所有模块
    cd "$TEMP_LIB_DIR" || return 1
    if sha256sum -c "$checksum_file" --status; then
        success "✓ All modules verified with SHA256"
        return 0
    else
        err "✗ Checksum verification failed"
        err "This may indicate:"
        err "  - Corrupted download"
        err "  - Network tampering (MITM attack)"
        err "  - Version mismatch"
        return 1
    fi
}
```

**安全级别**:
- ✅ 防止内容篡改
- ✅ 防止损坏文件
- ✅ 防止部分下载
- ⚠️ 仍需要 HTTPS（防止校验和本身被篡改）

**更高安全级别** (可选):
```bash
# GPG 签名验证
verify_gpg_signature() {
    local checksum_file="$1"
    local signature_file="${checksum_file}.asc"

    # 下载 GPG 签名
    download_file "${checksum_url}.asc" "$signature_file"

    # 验证签名
    gpg --verify "$signature_file" "$checksum_file" 2>&1
}
```

**参考**:
- Rust Release Signing Process
- Debian Package Verification

### 4.2 版本标签系统

**实现**:
```bash
# install_multi.sh

# 从脚本读取版本
readonly SCRIPT_VERSION="2.1.0"

# 下载指定版本的模块
GITHUB_BASE_URL="https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/v${SCRIPT_VERSION}"

# 或者使用 latest tag
GITHUB_BASE_URL="https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/latest"
```

**发布流程**:
```bash
# 1. 打标签
git tag -a v2.1.0 -m "Release v2.1.0"
git push origin v2.1.0

# 2. 创建 latest 标签（自动）
git tag -f latest v2.1.0
git push -f origin latest

# 3. CI 自动生成校验和
```

### 4.3 Dry-run 模式

**参考**: Docker `--dry-run`

**实现**:
```bash
# install_multi.sh

DRY_RUN="${DRY_RUN:-0}"

dry_run_msg() {
    [[ $DRY_RUN -eq 1 ]] && echo "[DRY-RUN] $*"
}

# 在关键操作前检查
download_singbox() {
    if [[ $DRY_RUN -eq 1 ]]; then
        dry_run_msg "Would download sing-box binary"
        dry_run_msg "  URL: $SB_DOWNLOAD_URL"
        dry_run_msg "  Output: $SB_BIN"
        return 0
    fi

    # 实际下载逻辑
    # ...
}
```

**使用**:
```bash
DRY_RUN=1 bash install_multi.sh
```

**输出示例**:
```
[DRY-RUN] Would detect installation mode
[DRY-RUN] Would download 10 modules from GitHub
[DRY-RUN] Would download sing-box v1.12.0
[DRY-RUN] Would create configuration: /etc/sing-box/config.json
[DRY-RUN] Would create systemd service: sing-box.service
[DRY-RUN] Installation complete (dry-run mode)
```

### 4.4 遥测与诊断

**匿名使用统计** (可选，需用户同意):
```bash
# 发送匿名安装统计
send_telemetry() {
    [[ "${TELEMETRY_ENABLED:-0}" -eq 0 ]] && return 0

    local data=$(cat <<EOF
{
  "version": "$SCRIPT_VERSION",
  "os": "$(uname -s)",
  "arch": "$(uname -m)",
  "install_mode": "${INSTALL_MODE}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
    )

    # 异步发送，不阻塞安装
    curl -fsSL -X POST -H "Content-Type: application/json" \
         -d "$data" "https://analytics.example.com/install" \
         >/dev/null 2>&1 &
}
```

**诊断模式**:
```bash
DEBUG=1 bash install_multi.sh

# 输出详细调试信息
# - 每个函数调用
# - 环境变量
# - 网络请求详情
# - 文件操作
```

---

## 测试策略

### 单元测试

**框架**: bats-core (Bash Automated Testing System)

**安装**:
```bash
git clone https://github.com/bats-core/bats-core.git
cd bats-core
./install.sh /usr/local
```

**测试文件**: `tests/unit/retry.bats`
```bash
#!/usr/bin/env bats

setup() {
    load '../test_helper/bats-support/load'
    load '../test_helper/bats-assert/load'
    source "${BATS_TEST_DIRNAME}/../../lib/retry.sh"
}

@test "calculate_backoff: first attempt" {
    run calculate_backoff 1
    assert_success
    # 2^1 * 1000 + jitter (0-1000) = 2000-3000
    assert [ "$output" -ge 2000 ]
    assert [ "$output" -le 3000 ]
}

@test "calculate_backoff: respects maximum" {
    run calculate_backoff 10
    assert_success
    # max is 32s = 32000ms + jitter
    assert [ "$output" -le 33000 ]
}

@test "retry_with_backoff: succeeds immediately" {
    run retry_with_backoff 3 true
    assert_success
}

@test "retry_with_backoff: exhausts retries" {
    run retry_with_backoff 3 false
    assert_failure
}

@test "is_retriable_error: curl connection error" {
    run is_retriable_error 7
    assert_success  # 可重试
}

@test "is_retriable_error: HTTP 404" {
    run is_retriable_error 22
    assert_failure  # 不可重试
}
```

**运行测试**:
```bash
bats tests/unit/retry.bats
```

### 集成测试

**测试矩阵**:
```yaml
os:
  - ubuntu-20.04
  - ubuntu-22.04
  - debian-11
  - centos-8

install_mode:
  - local (git clone)
  - remote (bash <(curl))
  - environment_variables

scenarios:
  - fresh_install
  - upgrade_binary
  - reconfigure
  - uninstall
  - network_failure
  - partial_download
```

**测试脚本**: `tests/integration/install.bats`
```bash
@test "one-liner install: auto-detect mode" {
    # 模拟一键安装
    bash <(cat install_multi.sh) <<< "y"

    assert [ -f "/usr/local/bin/sing-box" ]
    assert [ -f "/etc/sing-box/config.json" ]
    assert systemctl is-active sing-box
}

@test "one-liner install: network retry" {
    # 模拟网络不稳定
    export GITHUB_BASE_URL="http://unreliable-proxy:8080/Joe-oss9527/sbx-lite/main"

    run bash install_multi.sh
    assert_success
    assert_output --partial "Retry"
}

@test "module verification: corrupted file" {
    # 创建损坏的模块文件
    echo "corrupted" > /tmp/common.sh

    run verify_downloaded_module /tmp/common.sh
    assert_failure
    assert_output --partial "Invalid bash syntax"
}
```

### 性能测试

**基准测试**: `tests/benchmark/download.sh`
```bash
#!/bin/bash

echo "=== Download Performance Benchmark ==="

# 顺序下载
echo "Sequential download (current):"
time {
    for i in {1..10}; do
        curl -fsSL -o /tmp/test_$i https://raw.githubusercontent.com/.../lib/common.sh
    done
}

# 并行下载
echo ""
echo "Parallel download (xargs -P 5):"
time {
    seq 1 10 | xargs -P 5 -I {} \
        curl -fsSL -o /tmp/test_{} https://raw.githubusercontent.com/.../lib/common.sh
}

# 清理
rm -f /tmp/test_*
```

**预期结果**:
```
Sequential download (current):
real    0m30.123s

Parallel download (xargs -P 5):
real    0m6.045s

Improvement: 5x faster
```

### 安全测试

**测试用例**:
```bash
# 1. MITM 攻击模拟
# 使用 mitmproxy 拦截 HTTP 请求

# 2. 文件篡改检测
# 修改下载的模块，验证校验和失败

# 3. 恶意代码注入
# 尝试注入 shell 元字符

# 4. 权限提升测试
# 验证不使用不必要的 root 权限
```

---

## 回滚计划

### 版本兼容性

**向后兼容性保证**:
```bash
# 旧版本脚本仍然可以工作
# 1. 保持现有函数签名不变
# 2. 新功能通过环境变量选择加入（opt-in）
# 3. 默认行为保持不变
```

**功能开关**:
```bash
# 用户可以禁用新功能
ENABLE_PARALLEL_DOWNLOAD="${ENABLE_PARALLEL_DOWNLOAD:-1}"
ENABLE_RETRY_MECHANISM="${ENABLE_RETRY_MECHANISM:-1}"
ENABLE_CHECKSUM_VERIFICATION="${ENABLE_CHECKSUM_VERIFICATION:-0}"  # 默认关闭（Phase 4）

# 回退到旧行为
LEGACY_MODE="${LEGACY_MODE:-0}"
if [[ $LEGACY_MODE -eq 1 ]]; then
    ENABLE_PARALLEL_DOWNLOAD=0
    ENABLE_RETRY_MECHANISM=0
    # ...
fi
```

### 紧急回滚

**Git 回滚**:
```bash
# 如果新版本有严重问题，回滚到上一个稳定版本
git revert <commit-hash>
git push

# 或者使用 tag
git checkout v2.0.0
```

**用户回滚**:
```bash
# 用户可以指定版本
VERSION=v2.0.0 bash <(curl -fsSL ...)
```

---

## 性能基准

### 当前性能 (v2.1.0)

```
操作                   | 时间      | 备注
--------------------- | --------- | ----
模块检测               | <0.1s     |
顺序下载 10 modules    | 30s       | 3s/module
配置生成               | 1s        |
sing-box 下载         | 10s       | 取决于网络
总计（一键安装）        | ~41s      |
```

### 优化后性能 (目标)

```
操作                   | 时间      | 改进
--------------------- | --------- | ----
模块检测               | <0.1s     | -
并行下载 10 modules    | 3s        | 10x ↑
模块验证               | 1s        | +1s
配置生成               | 1s        | -
sing-box 下载         | 10s       | -
总计（一键安装）        | ~15s      | 2.7x ↑
```

### 网络故障场景

```
场景                   | 当前      | 优化后
--------------------- | --------- | --------
单次网络抖动            | 失败      | 自动重试，成功
GitHub 限流            | 失败      | 重试 3 次，等待后成功
部分模块下载失败        | 完全失败   | 只重新下载失败的模块
完全断网               | 失败      | 清晰错误消息 + 回退方案
```

---

## 安全审查

### 威胁模型

**攻击向量**:
1. **MITM 攻击**: 拦截 HTTPS 流量
   - 缓解: 强制 TLS 1.2+, 证书验证
   - Phase 4: SHA256 校验和

2. **仓库污染**: GitHub 账号被攻击
   - 缓解: 基础文件验证（语法检查）
   - Phase 4: GPG 签名

3. **依赖混淆**: 下载错误的仓库
   - 缓解: 硬编码仓库 URL
   - Phase 4: 校验和验证

4. **重放攻击**: 使用旧版本的恶意模块
   - 缓解: 版本标签
   - Phase 4: 时间戳验证

**安全清单**:
- [x] HTTPS 强制
- [x] TLS 1.2+ 强制
- [x] 输入验证（URL, 文件大小）
- [x] 语法验证
- [x] 安全临时文件（700 权限）
- [x] 自动清理（trap）
- [ ] SHA256 校验和 (Phase 4)
- [ ] GPG 签名 (Phase 4)
- [ ] 版本锁定 (Phase 4)

**参考**:
- OWASP Secure Coding Practices
- CIS Benchmark for Shell Scripts

---

## 维护性评估

### 代码复杂度

**当前** (install_multi.sh):
```
Lines of Code: 583
Cyclomatic Complexity: ~15 (高)
Functions: 8
Max Function Length: 74 lines (_load_modules)
```

**优化后** (预期):
```
Lines of Code: ~800 (增加功能)
Cyclomatic Complexity: ~8 (降低)
Functions: 25+ (模块化)
Max Function Length: 40 lines
Libraries: 4 (common, download, retry, verify)
```

### 可维护性指标

**优点**:
- ✅ 单一职责原则
- ✅ 清晰的函数命名
- ✅ 详细的错误消息
- ✅ 统一的编码风格
- ✅ ShellCheck 验证
- ✅ 全面的测试覆盖

**改进**:
- 📝 添加函数文档注释
- 📝 创建架构决策记录 (ADR)
- 📝 更新 CLAUDE.md

### 文档更新计划

**需要更新的文档**:
1. `CLAUDE.md` - 添加新库和函数
2. `README.md` - 更新性能数据
3. `CHANGELOG.md` - 记录所有变更
4. `lib/*/README.md` - 每个库的文档

**ADR (Architecture Decision Records)**:
```
docs/adr/
  001-exponential-backoff-retry.md
  002-parallel-downloads.md
  003-sha256-checksums.md
  004-downloader-abstraction.md
```

---

## 实施时间表

### Phase 1: 紧急修复 (Week 1, Day 1)
- [x] 审查完成
- [ ] 统一仓库 URL (15 min)
- [ ] 基础文件验证 (30 min)
- [ ] 改进错误消息 (15 min)
- [ ] 测试 (30 min)
- [ ] 提交 PR

**交付物**:
- 修复的 README.md
- 增强的 install_multi.sh
- 测试报告

### Phase 2: 可靠性增强 (Week 1, Day 2-3)
- [ ] 创建 lib/retry.sh (2 hours)
- [ ] 创建 lib/download.sh (2 hours)
- [ ] 集成重试机制 (1 hour)
- [ ] API 契约检查 (1 hour)
- [ ] 单元测试 (2 hours)
- [ ] 集成测试 (2 hours)
- [ ] 文档更新 (1 hour)

**交付物**:
- 新库: retry.sh, download.sh
- 测试套件
- 更新的文档

### Phase 3: 性能优化 (Week 2, Day 1-2)
- [ ] 并行下载实现 (3 hours)
- [ ] 进度指示 (1 hour)
- [ ] 性能测试 (2 hours)
- [ ] 回退机制 (1 hour)
- [ ] 文档更新 (1 hour)

**交付物**:
- 并行下载功能
- 性能基准报告

### Phase 4: 生产级增强 (Future)
- [ ] SHA256 校验和系统 (4 hours)
- [ ] CI/CD 集成 (2 hours)
- [ ] 版本标签系统 (2 hours)
- [ ] Dry-run 模式 (2 hours)
- [ ] GPG 签名 (可选, 4 hours)

---

## 成功指标

### 功能指标
- ✅ 所有模块下载成功率: >99.9%
- ✅ 网络故障自动恢复率: >95%
- ✅ 一键安装成功率: >99%

### 性能指标
- ✅ 下载时间: <5s (从 30s)
- ✅ 总安装时间: <20s (从 41s)
- ✅ 内存使用: <100MB

### 质量指标
- ✅ ShellCheck 零警告
- ✅ 测试覆盖率: >80%
- ✅ 代码复杂度: <10

### 用户体验指标
- ✅ 错误消息清晰度: 100%
- ✅ 文档完整性: 100%
- ✅ 向后兼容性: 100%

---

## 风险与缓解

### 技术风险

**风险 1: 并行下载兼容性**
- 描述: xargs -P 可能在旧系统不可用
- 概率: 低
- 影响: 中
- 缓解: 检测支持，回退到顺序下载

**风险 2: 函数导出限制**
- 描述: export -f 在某些 shell 不支持
- 概率: 中
- 影响: 高
- 缓解: 使用脚本文件而非函数导出

**风险 3: 重试机制增加延迟**
- 描述: 重试可能显著增加安装时间
- 概率: 低
- 影响: 低
- 缓解: 合理的超时和重试次数

### 操作风险

**风险 4: 破坏现有用户**
- 描述: 新版本可能与旧环境不兼容
- 概率: 低
- 影响: 高
- 缓解: 向后兼容性测试，功能开关

**风险 5: 文档滞后**
- 描述: 文档更新不及时
- 概率: 中
- 影响: 中
- 缓解: 同步更新文档和代码

---

## 参考资料

### 官方文档
1. [Rustup Book - Installation](https://rust-lang.github.io/rustup/installation/)
2. [Docker Install Script](https://github.com/docker/docker-install)
3. [Google SRE Book - Handling Overload](https://sre.google/sre-book/handling-overload/)
4. [Google Cloud - Retry Strategy](https://cloud.google.com/storage/docs/retry-strategy)

### 最佳实践
5. [Bash Best Practices - ShellCheck](https://www.shellcheck.net/)
6. [Exponential Backoff - Google Cloud](https://cloud.google.com/memorystore/docs/redis/exponential-backoff)
7. [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)

### 技术标准
8. [Semantic Versioning 2.0.0](https://semver.org/)
9. [Conventional Commits](https://www.conventionalcommits.org/)
10. [Keep a Changelog](https://keepachangelog.com/)

### 工具和框架
11. [Bats-core - Bash Testing](https://github.com/bats-core/bats-core)
12. [ShellCheck - Shell Script Analysis](https://github.com/koalaman/shellcheck)
13. [GNU Parallel](https://www.gnu.org/software/parallel/)

---

## 附录

### A. 完整代码示例

详见独立的实现文件：
- `lib/retry.sh.new` - 重试机制
- `lib/download.sh.new` - 下载器抽象
- `lib/verify.sh.new` - 验证系统
- `install_multi.sh.patch` - 主脚本变更

### B. 测试用例清单

详见 `tests/` 目录

### C. 性能基准数据

详见 `benchmarks/` 目录

---

**文档维护者**: Claude Code
**最后更新**: 2025-11-07
**下次审查**: Phase 1 完成后
