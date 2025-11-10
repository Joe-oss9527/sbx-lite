# sbx-lite 代码改进计划
## Multi-Phase Implementation Plan

**版本**: v1.0
**创建日期**: 2025-11-10
**目标版本**: v2.2.0
**预计总工作量**: 25-30 工作时

---

## 概述

基于全面的代码审查（评分：93/100），本计划旨在将项目质量从 A- 提升至 A+。改进重点：
- 消除技术债务
- 提升代码复用性
- 增强安全性和可靠性
- 改善可维护性

**原则**:
- ✅ 保持向后兼容性
- ✅ 每个阶段可独立交付
- ✅ 所有变更必须通过测试
- ✅ 保持文档同步更新

---

## Phase 1: 紧急修复 (高优先级)
**目标**: 修复关键安全和可靠性问题
**预计工作量**: 2-3 工作时
**目标完成时间**: Week 1
**风险等级**: 低

### 1.1 添加 strict mode 到 sbx-manager.sh
**优先级**: 🔴 CRITICAL
**问题**: bin/sbx-manager.sh 缺少 `set -euo pipefail`
**影响**: 潜在的静默失败和未捕获错误
**工作量**: 30 分钟

**实施步骤**:
```bash
# 1. 在 bin/sbx-manager.sh 第2行添加
set -euo pipefail

# 2. 修复所有可能的 unbound variable 引用
# 将 $VAR 改为 ${VAR:-default}
```

**验证方法**:
```bash
# 测试所有管理命令
sbx status
sbx info
sbx backup list
sbx export uri all

# 在未安装环境测试错误处理
bash bin/sbx-manager.sh status  # 应该优雅失败
```

**向后兼容性**: ✅ 无影响，仅增强错误处理

---

### 1.2 统一端口验证函数
**优先级**: 🔴 HIGH
**问题**: 端口验证逻辑在多处重复
**影响**: 代码重复，维护困难
**工作量**: 1 小时

**当前状态**:
```bash
# lib/network.sh:35-41
validate_port() {
    [[ "$1" =~ ^[0-9]+$ ]] || return 1
    [[ "$1" -ge 1 && "$1" -le 65535 ]] || return 1
}

# lib/config.sh:131-134 (重复实现)
if ! validate_port "$port" 2>/dev/null; then
    err "Invalid port: $port"
fi
```

**实施步骤**:
1. 在 `lib/validation.sh` 创建规范实现
2. 移除 `lib/network.sh` 中的实现
3. 更新所有调用点使用新函数
4. 添加单元测试

**文件变更**:
```bash
# lib/validation.sh (新增)
validate_port() {
    local port="$1"
    local port_name="${2:-Port}"

    # Validate numeric
    if [[ ! "$port" =~ ^[0-9]+$ ]]; then
        err "${port_name} must be numeric: $port"
        return 1
    fi

    # Validate range
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        err "${port_name} must be between 1-65535: $port"
        return 1
    fi

    return 0
}

# 导出函数
export -f validate_port
```

**验证方法**:
```bash
# 运行现有端口分配测试
bash tests/unit/test_port_allocation.sh

# 测试边界条件
validate_port 0      # 应失败
validate_port 1      # 应成功
validate_port 65535  # 应成功
validate_port 65536  # 应失败
validate_port "abc"  # 应失败
```

**向后兼容性**: ✅ 完全兼容，仅整合实现

---

### 1.3 提取文件大小工具函数
**优先级**: 🟡 MEDIUM
**问题**: 文件大小检查逻辑重复 3 次
**影响**: 代码重复
**工作量**: 45 分钟

**当前重复**:
```bash
# install_multi.sh:80, 205, 394 (3处重复)
file_size=$(stat -c%s "${file}" 2>/dev/null || stat -f%z "${file}" 2>/dev/null || echo "0")
```

**实施步骤**:
```bash
# lib/common.sh 新增函数
get_file_size() {
    local file="$1"

    # 验证文件存在
    [[ -f "$file" ]] || {
        echo "0"
        return 1
    }

    # 跨平台获取文件大小
    # Linux: stat -c%s
    # BSD/macOS: stat -f%z
    stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo "0"
}

# 导出函数
export -f get_file_size
```

**替换所有调用点**:
```bash
# install_multi.sh:80
file_size=$(get_file_size "${module_file}")

# install_multi.sh:205
file_size=$(get_file_size "${module_file}")

# install_multi.sh:394
mgr_size=$(get_file_size "${manager_file}")
```

**验证方法**:
```bash
# 单元测试
test_get_file_size() {
    # 创建测试文件
    echo "test" > /tmp/test_file_123

    # 验证大小（应该是 5 字节：test + \n）
    size=$(get_file_size /tmp/test_file_123)
    [[ "$size" == "5" ]] || return 1

    # 验证不存在文件
    size=$(get_file_size /tmp/nonexistent_file)
    [[ "$size" == "0" ]] || return 1

    rm /tmp/test_file_123
}

# 集成测试：运行完整安装流程
DEBUG=1 bash install_multi.sh
```

**向后兼容性**: ✅ 完全兼容

---

### 1.4 增强 IP 地址验证
**优先级**: 🟡 MEDIUM
**问题**: IP 地址验证缺少保留地址检查
**影响**: 可能接受无效的保留地址
**工作量**: 1 小时

**当前实现**:
```bash
# lib/validation.sh 缺少保留地址检查
```

**改进实现**:
```bash
# lib/validation.sh 增强版本
validate_ip_address() {
    local ip="$1"
    local allow_private="${2:-false}"  # 新增参数：是否允许私有地址

    # 基本格式验证
    [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1

    # 验证每个八位组范围
    local IFS='.'
    local -a octets
    read -ra octets <<< "$ip"

    for octet in "${octets[@]}"; do
        [[ "$octet" -ge 0 && "$octet" -le 255 ]] || return 1
    done

    # 检查保留地址
    # 0.0.0.0/8 - 当前网络
    [[ "${octets[0]}" == "0" ]] && return 1

    # 127.0.0.0/8 - 环回地址
    [[ "${octets[0]}" == "127" ]] && return 1

    # 224.0.0.0/4 - 组播地址
    [[ "${octets[0]}" -ge 224 && "${octets[0]}" -le 239 ]] && return 1

    # 240.0.0.0/4 - 保留地址
    [[ "${octets[0]}" -ge 240 ]] && return 1

    # 检查私有地址（如果不允许）
    if [[ "$allow_private" != "true" ]]; then
        # 10.0.0.0/8
        [[ "${octets[0]}" == "10" ]] && {
            warn "Private IP address detected: $ip"
            return 1
        }

        # 172.16.0.0/12
        [[ "${octets[0]}" == "172" && "${octets[1]}" -ge 16 && "${octets[1]}" -le 31 ]] && {
            warn "Private IP address detected: $ip"
            return 1
        }

        # 192.168.0.0/16
        [[ "${octets[0]}" == "192" && "${octets[1]}" == "168" ]] && {
            warn "Private IP address detected: $ip"
            return 1
        }
    fi

    return 0
}
```

**单元测试**:
```bash
# tests/unit/test_ip_validation.sh
test_ip_validation() {
    # 有效公网地址
    validate_ip_address "8.8.8.8" || return 1
    validate_ip_address "1.1.1.1" || return 1

    # 保留地址（应失败）
    ! validate_ip_address "0.0.0.0" || return 1
    ! validate_ip_address "127.0.0.1" || return 1
    ! validate_ip_address "224.0.0.1" || return 1

    # 私有地址（默认应失败）
    ! validate_ip_address "10.0.0.1" || return 1
    ! validate_ip_address "192.168.1.1" || return 1

    # 私有地址（允许时应成功）
    validate_ip_address "10.0.0.1" true || return 1

    echo "✓ All IP validation tests passed"
}
```

**向后兼容性**: ⚠️ 可能拒绝之前接受的私有地址
**迁移策略**: 添加 `ALLOW_PRIVATE_IP=1` 环境变量用于向后兼容

---

## Phase 2: 代码质量改进 (中优先级)
**目标**: 提升代码复用性和可维护性
**预计工作量**: 8-10 工作时
**目标完成时间**: Week 2-3
**风险等级**: 低

### 2.1 创建外部工具抽象层
**优先级**: 🟡 MEDIUM
**问题**: 外部工具依赖（jq, openssl）硬编码
**影响**: 难以替换工具实现
**工作量**: 4 小时

**创建新模块**: `lib/tools.sh`

```bash
#!/usr/bin/env bash
# lib/tools.sh - External tool abstractions and wrappers
# Part of sbx-lite modular architecture

set -euo pipefail

[[ -n "${_SBX_TOOLS_LOADED:-}" ]] && return 0
readonly _SBX_TOOLS_LOADED=1

# Source dependencies
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${_LIB_DIR}/common.sh"

#==============================================================================
# JSON Operations
#==============================================================================

# Parse JSON with fallback to Python
json_parse() {
    local json_input="$1"
    shift
    local jq_filter="$@"

    if have jq; then
        echo "$json_input" | jq "$jq_filter" 2>/dev/null
    elif have python3; then
        python3 -c "
import json
import sys
data = json.loads('''$json_input''')
# 简化实现，实际需要解析 jq 语法
print(json.dumps(data))
" 2>/dev/null
    elif have python; then
        python -c "
import json
import sys
data = json.loads('''$json_input''')
print(json.dumps(data))
" 2>/dev/null
    else
        err "No JSON parser available (jq, python3, python)"
        return 1
    fi
}

# Build JSON object
json_build() {
    if have jq; then
        jq -n "$@"
    else
        err "JSON builder requires jq"
        return 1
    fi
}

#==============================================================================
# Cryptographic Operations
#==============================================================================

# Generate random bytes (hex encoded)
crypto_random_hex() {
    local length="${1:-16}"

    if have openssl; then
        openssl rand -hex "$length"
    elif [[ -f /dev/urandom ]]; then
        head -c "$length" /dev/urandom | xxd -p -c "$length"
    else
        err "No random source available"
        return 1
    fi
}

# SHA256 checksum
crypto_sha256() {
    local file="$1"

    if have sha256sum; then
        sha256sum "$file" | awk '{print $1}'
    elif have shasum; then
        shasum -a 256 "$file" | awk '{print $1}'
    elif have openssl; then
        openssl sha256 "$file" | awk '{print $2}'
    else
        err "No SHA256 tool available"
        return 1
    fi
}

#==============================================================================
# HTTP Operations
#==============================================================================

# Download file with fallback
http_download() {
    local url="$1"
    local output="$2"
    local timeout="${3:-${HTTP_TIMEOUT_SEC}}"

    if have curl; then
        curl -fsSL --connect-timeout 10 --max-time "$timeout" "$url" -o "$output"
    elif have wget; then
        wget -q --timeout="$timeout" "$url" -O "$output"
    else
        err "No HTTP client available (curl, wget)"
        return 1
    fi
}

# Export functions
export -f json_parse json_build
export -f crypto_random_hex crypto_sha256
export -f http_download
```

**更新调用点示例**:
```bash
# lib/config.sh 之前:
base_config=$(jq -n --arg log_level "$log_level" '{...}')

# lib/config.sh 之后:
source "${_LIB_DIR}/tools.sh"
base_config=$(json_build --arg log_level "$log_level" '{...}')
```

**验证方法**:
```bash
# 单元测试
test_tools_abstraction() {
    # 测试 JSON 操作
    result=$(json_build --arg name "test" '{name: $name}')
    [[ "$result" =~ "test" ]] || return 1

    # 测试随机数生成
    hex=$(crypto_random_hex 8)
    [[ ${#hex} == 16 ]] || return 1

    echo "✓ Tools abstraction tests passed"
}
```

**向后兼容性**: ✅ 完全兼容，仅添加抽象层

---

### 2.2 改进错误消息国际化准备
**优先级**: 🟢 LOW
**问题**: 错误消息硬编码
**影响**: 难以支持多语言
**工作量**: 2 小时

**创建消息模板**: `lib/messages.sh`

```bash
#!/usr/bin/env bash
# lib/messages.sh - Centralized message templates

# 错误消息模板
declare -A ERROR_MESSAGES=(
    [INVALID_PORT]="Invalid port number: %s (must be 1-65535)"
    [INVALID_DOMAIN]="Invalid domain format: %s"
    [FILE_NOT_FOUND]="File not found: %s"
    [NETWORK_ERROR]="Network error: Failed to connect to %s"
    [CHECKSUM_FAILED]="SHA256 checksum verification failed for %s"
)

# 格式化错误消息
format_error() {
    local error_key="$1"
    shift
    local template="${ERROR_MESSAGES[$error_key]:-Unknown error}"
    printf "$template" "$@"
}

# 使用示例
err_invalid_port() {
    err "$(format_error INVALID_PORT "$1")"
}
```

**向后兼容性**: ✅ 可选升级，不破坏现有代码

---

### 2.3 优化日志轮转实现
**优先级**: 🟡 MEDIUM
**问题**: 日志轮转功能存在但未自动调用
**影响**: 长期运行可能产生大日志文件
**工作量**: 2 小时

**实施步骤**:
```bash
# lib/common.sh 增强日志轮转
rotate_logs_if_needed() {
    local log_file="${LOG_FILE:-}"
    local max_size_kb="${LOG_MAX_SIZE_KB:-10240}"  # 默认 10MB

    [[ -z "$log_file" || ! -f "$log_file" ]] && return 0

    # 获取文件大小（KB）
    local file_size_kb
    file_size_kb=$(du -k "$log_file" 2>/dev/null | cut -f1)

    # 仅在超过大小时轮转
    if [[ ${file_size_kb:-0} -gt $max_size_kb ]]; then
        rotate_logs "$log_file" "$max_size_kb"
    fi
}

# 在每次日志写入前检查（性能优化：每100次调用检查一次）
_log_to_file() {
    [[ -z "${LOG_FILE}" ]] && return 0

    # 计数器：每100次日志写入检查一次文件大小
    LOG_WRITE_COUNT=$((${LOG_WRITE_COUNT:-0} + 1))
    if [[ $((LOG_WRITE_COUNT % 100)) == 0 ]]; then
        rotate_logs_if_needed
    fi

    # 创建日志文件（如果不存在）
    if [[ ! -f "${LOG_FILE}" ]]; then
        touch "${LOG_FILE}" && chmod 600 "${LOG_FILE}"
    fi

    echo "$*" >> "${LOG_FILE}" 2>/dev/null || true
}
```

**配置示例**:
```bash
# 用户可配置
export LOG_FILE="/var/log/sbx-install.log"
export LOG_MAX_SIZE_KB=5120  # 5MB
```

**验证方法**:
```bash
# 压力测试
for i in {1..10000}; do
    msg "Test log message $i with some padding text to increase size"
done

# 检查是否创建了轮转文件
ls -lh /var/log/sbx-install.log*
```

**向后兼容性**: ✅ 完全兼容

---

## Phase 3: 架构优化 (低优先级)
**目标**: 改善模块结构和职责划分
**预计工作量**: 10-12 工作时
**目标完成时间**: Week 4-5
**风险等级**: 中

### 3.1 拆分 lib/common.sh 模块
**优先级**: 🟢 LOW
**问题**: common.sh 包含多种职责（563行）
**影响**: 违反单一职责原则
**工作量**: 6 小时

**拆分方案**:

```
lib/common.sh (563 lines) 拆分为:
├── lib/common.sh        (150 lines) - 核心常量和工具
├── lib/logging.sh       (200 lines) - 所有日志功能
└── lib/generators.sh    (213 lines) - UUID/QR/密钥生成
```

**实施步骤**:

**步骤 1: 创建 lib/logging.sh**
```bash
#!/usr/bin/env bash
# lib/logging.sh - Centralized logging functionality

set -euo pipefail

[[ -n "${_SBX_LOGGING_LOADED:-}" ]] && return 0
readonly _SBX_LOGGING_LOADED=1

# 移动以下内容从 common.sh:
# - 第 104-331 行：所有日志函数
# - LOG_* 配置变量
# - 颜色初始化（从 common.sh 导入）

# 保留在 common.sh 的：
# - 常量定义
# - have(), need_root() 等基础工具
# - cleanup() 函数
```

**步骤 2: 创建 lib/generators.sh**
```bash
#!/usr/bin/env bash
# lib/generators.sh - Random data and key generation

set -euo pipefail

[[ -n "${_SBX_GENERATORS_LOADED:-}" ]] && return 0
readonly _SBX_GENERATORS_LOADED=1

# 移动以下内容从 common.sh:
# - 第 409-547 行：生成函数
# - generate_uuid()
# - generate_reality_keypair()
# - generate_hex_string()
# - generate_qr_code()
# - generate_all_qr_codes()
```

**步骤 3: 更新依赖**
```bash
# 所有使用日志的模块更新为:
source "${_LIB_DIR}/logging.sh"

# 所有使用生成功能的模块更新为:
source "${_LIB_DIR}/generators.sh"

# install_multi.sh 模块列表更新:
local modules=(common logging generators retry download network ...)
```

**向后兼容性**: ⚠️ 需要更新所有模块的 source 语句
**迁移策略**:
1. 先创建新模块
2. common.sh 保留所有函数但标记为 deprecated
3. 下一个版本移除 deprecated 函数

**验证方法**:
```bash
# 运行完整测试套件
bash tests/test-runner.sh

# 测试所有模块加载
for module in lib/*.sh; do
    bash -n "$module" || echo "Syntax error in $module"
done

# 集成测试
DEBUG=1 bash install_multi.sh
```

---

### 3.2 实现配置文件验证管道
**优先级**: 🟢 LOW
**问题**: 配置生成后验证不够系统化
**影响**: 潜在的配置错误难以早期发现
**工作量**: 4 小时

**创建验证管道**: `lib/config_validator.sh`

```bash
#!/usr/bin/env bash
# lib/config_validator.sh - Configuration validation pipeline

set -euo pipefail

#==============================================================================
# Validation Pipeline
#==============================================================================

# 验证管道：多阶段验证配置文件
validate_config_pipeline() {
    local config_file="${1:-$SB_CONF}"
    local validators=(
        validate_json_syntax
        validate_singbox_schema
        validate_port_conflicts
        validate_tls_config
        validate_route_rules
    )

    msg "Running configuration validation pipeline..."

    for validator in "${validators[@]}"; do
        if ! $validator "$config_file"; then
            err "Validation failed at stage: $validator"
            return 1
        fi
        success "  ✓ $validator passed"
    done

    success "All validation stages passed"
    return 0
}

# Stage 1: JSON 语法验证
validate_json_syntax() {
    local config="$1"
    jq empty < "$config" 2>/dev/null || {
        err "Invalid JSON syntax"
        return 1
    }
}

# Stage 2: sing-box schema 验证
validate_singbox_schema() {
    local config="$1"
    "$SB_BIN" check -c "$config" 2>&1 || {
        err "sing-box schema validation failed"
        return 1
    }
}

# Stage 3: 端口冲突检查
validate_port_conflicts() {
    local config="$1"

    # 提取所有监听端口
    local ports
    ports=$(jq -r '.inbounds[].listen_port // empty' "$config" 2>/dev/null)

    # 检查重复
    if [[ -n "$ports" ]]; then
        local unique_ports
        unique_ports=$(echo "$ports" | sort -u)

        if [[ $(echo "$ports" | wc -l) != $(echo "$unique_ports" | wc -l) ]]; then
            err "Port conflict detected in configuration"
            return 1
        fi
    fi

    return 0
}

# Stage 4: TLS 配置验证
validate_tls_config() {
    local config="$1"

    # 检查 TLS 入站是否有有效证书配置
    local tls_inbounds
    tls_inbounds=$(jq -r '.inbounds[] | select(.tls != null) | .tag' "$config" 2>/dev/null)

    for inbound in $tls_inbounds; do
        local cert_path
        cert_path=$(jq -r ".inbounds[] | select(.tag == \"$inbound\") | .tls.certificate_path // empty" "$config")

        if [[ -n "$cert_path" && ! -f "$cert_path" ]]; then
            err "TLS certificate not found for inbound $inbound: $cert_path"
            return 1
        fi
    done

    return 0
}

# Stage 5: 路由规则验证
validate_route_rules() {
    local config="$1"

    # 验证路由规则引用的 tag 都存在
    local referenced_tags
    referenced_tags=$(jq -r '.route.rules[]?.outbound // empty' "$config" 2>/dev/null)

    local available_tags
    available_tags=$(jq -r '.outbounds[].tag' "$config" 2>/dev/null)

    for tag in $referenced_tags; do
        if ! echo "$available_tags" | grep -q "^$tag$"; then
            err "Route rule references non-existent outbound: $tag"
            return 1
        fi
    done

    return 0
}

export -f validate_config_pipeline
```

**集成到安装流程**:
```bash
# lib/config.sh:write_config() 末尾添加
if ! validate_config_pipeline "$temp_config"; then
    err "Generated configuration failed validation"
    rm -f "$temp_config"
    return 1
fi
```

**向后兼容性**: ✅ 仅增强验证，不改变行为

---

### 3.3 实现依赖注入模式
**优先级**: 🟢 LOW
**问题**: 模块间硬编码依赖
**影响**: 难以单元测试和 mock
**工作量**: 6 小时

**示例重构**: `lib/network.sh`

**当前实现**（硬编码依赖）:
```bash
get_public_ip() {
    # 硬编码服务列表
    local services=(
        "https://api.ipify.org"
        "https://icanhazip.com"
        "https://ifconfig.me/ip"
    )
    # ...
}
```

**改进实现**（可注入依赖）:
```bash
# 允许通过环境变量注入自定义服务
get_public_ip() {
    local services=()

    # 优先使用自定义服务（用于测试/企业环境）
    if [[ -n "${CUSTOM_IP_SERVICES:-}" ]]; then
        IFS=',' read -ra services <<< "$CUSTOM_IP_SERVICES"
    else
        # 默认服务列表
        services=(
            "https://api.ipify.org"
            "https://icanhazip.com"
            "https://ifconfig.me/ip"
            "https://ipinfo.io/ip"
        )
    fi

    # ... 其余逻辑不变
}
```

**单元测试示例**:
```bash
# tests/unit/test_network_injection.sh
test_ip_detection_with_mock() {
    # 使用本地 mock 服务
    export CUSTOM_IP_SERVICES="http://localhost:8888/ip"

    # 启动 mock HTTP 服务器
    echo "1.2.3.4" > /tmp/mock_ip.txt
    python3 -m http.server 8888 --directory /tmp &
    local server_pid=$!

    # 测试
    local detected_ip
    detected_ip=$(get_public_ip)

    # 清理
    kill $server_pid

    # 验证
    [[ "$detected_ip" == "1.2.3.4" ]] || return 1
}
```

**向后兼容性**: ✅ 完全兼容，默认行为不变

---

## Phase 4: 测试和文档增强
**目标**: 提升测试覆盖率和文档质量
**预计工作量**: 6-8 工作时
**目标完成时间**: Week 6
**风险等级**: 低

### 4.1 实现代码覆盖率跟踪
**优先级**: 🟡 MEDIUM
**工作量**: 4 小时

**创建覆盖率工具**: `tests/coverage.sh`

```bash
#!/usr/bin/env bash
# tests/coverage.sh - Bash code coverage tracker

set -euo pipefail

# 函数覆盖率跟踪
track_coverage() {
    local test_script="$1"
    local coverage_file="/tmp/sbx-coverage-$$.txt"

    # 启用 bash 调试模式跟踪函数调用
    export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'

    # 运行测试并记录调用
    bash -x "$test_script" 2>&1 | grep -E '^\+\(' > "$coverage_file"

    # 分析覆盖率
    echo "=== Function Coverage Report ==="
    echo ""

    # 提取所有定义的函数
    local all_functions
    all_functions=$(grep -rh '^[a-z_][a-z0-9_]*()' lib/*.sh | sed 's/().*//' | sort -u)

    local total=0
    local covered=0

    while IFS= read -r func; do
        ((total++))
        if grep -q "${func}()" "$coverage_file"; then
            ((covered++))
            echo "✓ $func"
        else
            echo "✗ $func (NOT TESTED)"
        fi
    done <<< "$all_functions"

    local coverage_percent=$((covered * 100 / total))

    echo ""
    echo "=== Summary ==="
    echo "Total functions: $total"
    echo "Tested functions: $covered"
    echo "Coverage: ${coverage_percent}%"

    rm -f "$coverage_file"

    # 设置最低覆盖率阈值
    if [[ $coverage_percent -lt 70 ]]; then
        echo "⚠️  Coverage below 70% threshold"
        return 1
    fi
}

# 运行所有测试并生成覆盖率报告
generate_coverage_report() {
    echo "Generating coverage report..."

    local test_files=(
        tests/unit/*.sh
        tests/integration/*.sh
    )

    for test_file in "${test_files[@]}"; do
        [[ -f "$test_file" ]] || continue
        echo "Running: $test_file"
        track_coverage "$test_file"
    done
}

# 主入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_coverage_report
fi
```

**集成到 Makefile**:
```makefile
# Makefile
coverage:
	@echo "→ Running coverage analysis..."
	@bash tests/coverage.sh
	@echo "✓ Coverage report generated"

# 更新 check 目标
check: lint syntax security coverage
	@echo "✓ All checks passed!"
```

**向后兼容性**: ✅ 新功能，不影响现有代码

---

### 4.2 增强单元测试
**优先级**: 🟡 MEDIUM
**工作量**: 4 小时

**创建测试框架增强**: `tests/test_framework.sh`

```bash
#!/usr/bin/env bash
# tests/test_framework.sh - Enhanced testing framework

# 测试计数器
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# 测试断言函数
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Assertion failed}"

    ((TESTS_RUN++))

    if [[ "$expected" == "$actual" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        echo "    Expected: $expected"
        echo "    Actual:   $actual"
        return 1
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    ((TESTS_RUN++))

    if [[ -n "$value" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        return 1
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist: $file}"

    ((TESTS_RUN++))

    if [[ -f "$file" ]]; then
        ((TESTS_PASSED++))
        echo "  ✓ $message"
        return 0
    else
        ((TESTS_FAILED++))
        echo "  ✗ $message"
        return 1
    fi
}

# 测试套件报告
print_test_summary() {
    echo ""
    echo "=== Test Summary ==="
    echo "Total:  $TESTS_RUN"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"

    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo "✓ All tests passed!"
        return 0
    else
        echo "✗ Some tests failed"
        return 1
    fi
}

# 导出函数
export -f assert_equals assert_not_empty assert_file_exists print_test_summary
```

**示例测试用法**:
```bash
#!/usr/bin/env bash
# tests/unit/test_validation_enhanced.sh

source tests/test_framework.sh
source lib/validation.sh

test_domain_validation() {
    echo "Testing domain validation..."

    # 有效域名
    assert_equals "0" "$?" "Valid domain should pass"
    validate_domain "example.com"

    # 无效域名
    ! validate_domain "invalid..com"
    assert_equals "0" "$?" "Invalid domain should fail"

    # 边界情况
    ! validate_domain ""
    assert_equals "0" "$?" "Empty domain should fail"
}

test_port_validation() {
    echo "Testing port validation..."

    validate_port 443
    assert_equals "0" "$?" "Valid port 443 should pass"

    ! validate_port 0
    assert_equals "0" "$?" "Port 0 should fail"

    ! validate_port 65536
    assert_equals "0" "$?" "Port 65536 should fail"
}

# 运行测试
test_domain_validation
test_port_validation

print_test_summary
```

**向后兼容性**: ✅ 新增框架，不影响现有测试

---

### 4.3 创建性能基准测试
**优先级**: 🟢 LOW
**工作量**: 3 小时

**创建基准测试**: `tests/benchmark.sh`

```bash
#!/usr/bin/env bash
# tests/benchmark.sh - Performance benchmarking

set -euo pipefail

# 基准测试函数
benchmark() {
    local test_name="$1"
    local iterations="${2:-1000}"
    shift 2
    local command="$@"

    echo "Benchmarking: $test_name ($iterations iterations)"

    local start_time
    start_time=$(date +%s%N)

    for ((i=1; i<=iterations; i++)); do
        eval "$command" >/dev/null 2>&1
    done

    local end_time
    end_time=$(date +%s%N)

    local total_time=$((end_time - start_time))
    local avg_time=$((total_time / iterations))
    local ops_per_sec=$((1000000000 * iterations / total_time))

    printf "  Total: %d ms\n" $((total_time / 1000000))
    printf "  Average: %d μs\n" $((avg_time / 1000))
    printf "  Ops/sec: %d\n" "$ops_per_sec"
    echo ""
}

# 运行基准测试
main() {
    echo "=== sbx-lite Performance Benchmarks ==="
    echo ""

    # 测试 UUID 生成
    source lib/common.sh
    benchmark "UUID Generation" 100 "generate_uuid"

    # 测试域名验证
    source lib/validation.sh
    benchmark "Domain Validation" 1000 "validate_domain example.com"

    # 测试端口验证
    benchmark "Port Validation" 1000 "validate_port 443"

    # 测试 JSON 解析
    echo '{"test": "value"}' > /tmp/bench.json
    benchmark "JSON Parsing" 500 "jq -r .test /tmp/bench.json"
    rm /tmp/bench.json

    echo "=== Benchmarks Complete ==="
}

main
```

**集成到 Makefile**:
```makefile
benchmark:
	@echo "→ Running performance benchmarks..."
	@bash tests/benchmark.sh
```

---

### 4.4 更新文档
**优先级**: 🟡 MEDIUM
**工作量**: 2 小时

**更新 CLAUDE.md**:
```markdown
## Recent Updates

### v2.2.0 (2025-11-XX) - Code Quality Improvements
**Focus**: Addressing code review findings and technical debt

**Key Improvements**:
- ✅ Added strict mode to sbx-manager.sh
- ✅ Unified port validation across all modules
- ✅ Created external tool abstraction layer (lib/tools.sh)
- ✅ Enhanced IP address validation with reserved address checks
- ✅ Improved code coverage tracking
- ✅ Split common.sh into focused modules (logging, generators)

**New Modules**:
- `lib/tools.sh` - External tool abstractions
- `lib/logging.sh` - Centralized logging functionality
- `lib/generators.sh` - Random data and key generation
- `lib/config_validator.sh` - Configuration validation pipeline

**Testing Enhancements**:
- Added code coverage tracking (tests/coverage.sh)
- Enhanced test framework with assertion helpers
- Added performance benchmarking (tests/benchmark.sh)
```

**创建升级指南**: `docs/UPGRADE_v2.2.md`

```markdown
# Upgrading to v2.2.0

## Breaking Changes
None - v2.2.0 is fully backward compatible

## New Features
- Enhanced validation pipeline
- Tool abstraction layer for better testability
- Improved logging with automatic rotation
- Code coverage reporting

## Migration Guide

### For Developers
If you've been using sbx-lite modules in custom scripts:

**Old import pattern:**
```bash
source /usr/local/lib/sbx/common.sh  # Contains everything
```

**New recommended pattern:**
```bash
source /usr/local/lib/sbx/common.sh    # Core utilities
source /usr/local/lib/sbx/logging.sh   # Logging functions
source /usr/local/lib/sbx/generators.sh # UUID/key generation
```

**Deprecated (still works but will be removed in v3.0):**
- Calling logging functions from common.sh (use logging.sh instead)
- Calling generators from common.sh (use generators.sh instead)

### For End Users
No changes required - all functionality remains the same.
Simply update your installation:

```bash
cd /path/to/sbx-lite
git pull origin main
bash install_multi.sh
```
```

---

## 实施时间表

```
Week 1: Phase 1 (Critical Fixes)
├── Day 1-2: 任务 1.1-1.2 (strict mode, port validation)
├── Day 3:   任务 1.3 (file size utility)
└── Day 4-5: 任务 1.4 (IP validation), Testing

Week 2-3: Phase 2 (Code Quality)
├── Day 1-3: 任务 2.1 (tool abstraction layer)
├── Day 4:   任务 2.2 (message templates)
└── Day 5:   任务 2.3 (log rotation), Testing

Week 4-5: Phase 3 (Architecture)
├── Day 1-3: 任务 3.1 (module splitting)
├── Day 4:   任务 3.2 (validation pipeline)
└── Day 5:   任务 3.3 (dependency injection), Testing

Week 6: Phase 4 (Testing & Docs)
├── Day 1-2: 任务 4.1-4.2 (coverage, unit tests)
├── Day 3:   任务 4.3 (benchmarks)
└── Day 4-5: 任务 4.4 (documentation), Final Testing
```

---

## 验证检查清单

### Phase 1 验证
```bash
# ✅ strict mode 验证
bash -n bin/sbx-manager.sh
shellcheck bin/sbx-manager.sh

# ✅ 端口验证统一
grep -r "validate_port" lib/*.sh | wc -l  # 应该只有一处定义

# ✅ 文件大小工具
grep -r "stat -c%s" install_multi.sh | wc -l  # 应该为 0（已替换）

# ✅ IP 验证增强
validate_ip_address "127.0.0.1"  # 应该失败
validate_ip_address "8.8.8.8"    # 应该成功
```

### Phase 2 验证
```bash
# ✅ 工具抽象层
bash -n lib/tools.sh
source lib/tools.sh && crypto_random_hex 16

# ✅ 日志轮转
LOG_FILE=/tmp/test.log LOG_MAX_SIZE_KB=1 bash tests/log_rotation_test.sh
```

### Phase 3 验证
```bash
# ✅ 模块拆分
bash -n lib/logging.sh lib/generators.sh
bash tests/test-runner.sh  # 所有测试应通过

# ✅ 验证管道
validate_config_pipeline /etc/sing-box/config.json
```

### Phase 4 验证
```bash
# ✅ 代码覆盖率
make coverage  # 应该 ≥70%

# ✅ 基准测试
make benchmark  # 记录基线性能
```

---

## 回滚计划

如果任何阶段出现问题：

### Phase 1-2: 快速回滚
```bash
git revert <commit-hash>
git push origin claude/best-practices-design-principles-011CUyqtsAAwZsUxYkBX1qo4
```

### Phase 3: 模块拆分回滚
```bash
# 恢复旧版 common.sh
git checkout <previous-commit> -- lib/common.sh
# 移除新模块
rm lib/logging.sh lib/generators.sh
```

### Phase 4: 无风险
仅添加测试和文档，无需回滚。

---

## 成功指标

### 代码质量指标
- [ ] ShellCheck 无警告
- [ ] 代码覆盖率 ≥ 70%
- [ ] 代码重复率 < 2%
- [ ] 平均函数复杂度 < 10
- [ ] 最大函数行数 < 100

### 功能指标
- [ ] 所有现有测试通过
- [ ] 新增 ≥20 个单元测试
- [ ] 集成测试通过率 100%
- [ ] 性能无退化（benchmark验证）

### 文档指标
- [ ] CLAUDE.md 更新
- [ ] UPGRADE.md 创建
- [ ] API 文档完整
- [ ] 所有新函数有注释

---

## 风险评估

| 风险 | 可能性 | 影响 | 缓解措施 |
|------|--------|------|----------|
| 模块拆分破坏现有功能 | 中 | 高 | 全面测试 + 渐进式迁移 |
| 性能退化 | 低 | 中 | 基准测试 + 性能监控 |
| 向后兼容性问题 | 低 | 高 | 保留 deprecated 函数 |
| 测试覆盖不足 | 中 | 中 | 代码覆盖率强制要求 |

---

## 下一步行动

1. **获取批准**: 审查本计划并获得确认
2. **创建分支**: `git checkout -b feature/code-quality-improvements`
3. **开始 Phase 1**: 按照计划执行高优先级任务
4. **持续集成**: 每个任务完成后提交并测试
5. **代码审查**: 每个阶段完成后进行审查
6. **合并主线**: 所有阶段完成并验证后合并

---

*计划创建时间*: 2025-11-10
*预计完成时间*: 2025-12-15 (6周)
*计划审核人*: [待定]
*计划批准人*: [待定]
