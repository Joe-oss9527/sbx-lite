# 修复实施计划 (Implementation Plan)

**基于**: sing-box 官方文档核对结果
**目标**: sing-box 1.12.0+ 完全合规 + 安全加固
**日期**: 2025-11-07

---

## 📋 官方文档核对结果

### ✅ 已正确实现的部分

1. **DNS 配置** (lib/config.sh:68-72)
   ```json
   {
     "dns": {
       "servers": [{"type": "local", "tag": "dns-local"}],
       "strategy": "ipv4_only"  // ✅ 正确，符合 1.12.0+ 标准
     }
   }
   ```

2. **Reality 基础配置** (lib/config.sh:148-159)
   ```json
   {
     "reality": {
       "enabled": true,
       "private_key": $priv,
       "short_id": [$sid],
       "handshake": {"server": $sni, "server_port": 443},
       "max_time_difference": "1m"  // ✅ 正确
     }
   }
   ```

3. **Route 配置** (lib/config.sh:272-287)
   ```json
   {
     "route": {
       "rules": [
         {"inbound": $inbounds, "action": "sniff"},  // ✅ 正确
         {"protocol": "dns", "action": "hijack-dns"}  // ✅ 正确
       ],
       "auto_detect_interface": true,  // ✅ 正确
       "default_domain_resolver": {"server": "dns-local"}  // ✅ 正确 (1.12.0+)
     }
   }
   ```

### ⚠️ 需要修正的误解

**原审查报告中的错误建议**（已纠正）:
- ❌ **错误**: 在 `tls.reality` 内部添加 `min_version`, `max_version`
- ✅ **正确**: 这些字段属于 `tls` 层面，不是 `reality` 特有的

**官方文档确认** (docs/configuration/shared/tls.md:19-27):
```json
{
  "tls": {
    "enabled": true,
    "server_name": "",
    "min_version": "1.2",  // ← TLS 层面的配置
    "max_version": "1.3",  // ← TLS 层面的配置
    "reality": {
      "enabled": true,
      // Reality 内部没有 min_version/max_version
      "private_key": "...",
      "short_id": ["..."]
    }
  }
}
```

---

## 🎯 修复任务清单

### 优先级 1: 安全关键修复（立即实施）

#### 1.1 修复端口分配竞态条件 ✅ 可靠方案

**文件**: `lib/network.sh` (Line 88-163)

**问题**: TOCTOU (Time-of-Check-Time-of-Use) 竞态条件

**根本原因**:
```bash
# 步骤1: 检查端口
if port_in_use "$p"; then
  return 1
fi

# ← 时间窗口：其他进程可能在这里抢占端口

# 步骤2: sing-box 尝试绑定（可能失败）
```

**解决方案**: 在服务启动层面添加重试机制（推荐方案）

**理由**:
1. 端口检查本质上无法完全避免竞态
2. 让 sing-box 实际绑定时失败，然后重试更可靠
3. 不依赖外部工具 (nc/socat)

**实施步骤**:

**步骤 A**: 修改 `lib/service.sh` 的 `setup_service()` 函数

```bash
# 在 lib/service.sh 中添加带重试的服务启动函数
start_service_with_retry() {
  local max_retries=3
  local retry_count=0
  local wait_time=2

  msg "Starting sing-box service..."

  while [[ $retry_count -lt $max_retries ]]; do
    if systemctl start sing-box 2>&1; then
      sleep 2
      if systemctl is-active sing-box >/dev/null 2>&1; then
        success "  ✓ sing-box service started successfully"
        return 0
      fi
    fi

    # 服务启动失败，检查是否是端口绑定问题
    local error_log
    error_log=$(journalctl -u sing-box -n 20 --no-pager 2>/dev/null | grep -i "bind\|address.*in use" || true)

    if [[ -n "$error_log" ]]; then
      ((retry_count++))
      if [[ $retry_count -lt $max_retries ]]; then
        warn "Port binding failed, retrying ($retry_count/$max_retries) in ${wait_time}s..."
        warn "Error: $error_log"
        systemctl stop sing-box 2>/dev/null || true
        sleep "$wait_time"
        wait_time=$((wait_time * 2))  # 指数退避
      else
        err "Failed to start sing-box after $max_retries attempts"
        err "Last error: $error_log"
        return 1
      fi
    else
      # 非端口问题，直接失败
      err "sing-box service failed to start (non-port issue)"
      journalctl -u sing-box -n 30 --no-pager >&2
      return 1
    fi
  done

  die "Failed to start sing-box service after $max_retries retries"
}
```

**步骤 B**: 修改 `setup_service()` 调用

```bash
# 在 lib/service.sh setup_service() 函数中
# 替换原有的 systemctl start 调用
# 旧代码:
#   systemctl start sing-box || die "Failed to start sing-box"
# 新代码:
start_service_with_retry || die "Failed to start sing-box service"
```

**优点**:
- ✅ 不依赖外部工具
- ✅ 处理实际绑定失败而非猜测
- ✅ 指数退避避免快速重试
- ✅ 区分端口问题和其他错误

---

#### 1.2 添加二进制 SHA256 校验和验证 ✅ 完整方案

**文件**: `install_multi.sh` (Line 332-401, `download_singbox()` 函数)

**风险**: 下载的二进制可能被篡改或损坏

**官方 SHA256 位置**:
- URL 模式: `https://github.com/SagerNet/sing-box/releases/download/v{VERSION}/sing-box-{VERSION}-linux-{ARCH}.tar.gz.sha256sum`
- 格式: `<sha256>  sing-box-{VERSION}-linux-{ARCH}.tar.gz`

**实施代码**:

```bash
download_singbox() {
  # ... 现有代码（获取 URL） ...

  msg "Downloading sing-box ${tag}..."
  local pkg="$tmp/sb.tgz"
  safe_http_get "$url" "$pkg" || {
    rm -rf "$tmp"
    die "Failed to download sing-box package"
  }

  # ==================== 新增：校验和验证 ====================
  msg "Verifying package integrity..."

  # 下载校验和文件
  local checksum_url="${url}.sha256sum"
  local checksum_file="$tmp/checksum.txt"

  if safe_http_get "$checksum_url" "$checksum_file" 2>/dev/null; then
    # 提取预期的 SHA256 值（第一个字段）
    local expected_sum
    expected_sum=$(awk '{print $1}' "$checksum_file" | head -1)

    if [[ -z "$expected_sum" ]]; then
      warn "  ⚠ Checksum file is empty or invalid, skipping verification"
    elif [[ ! "$expected_sum" =~ ^[0-9a-fA-F]{64}$ ]]; then
      warn "  ⚠ Invalid checksum format: $expected_sum"
      warn "  ⚠ Skipping verification"
    else
      # 计算实际的 SHA256
      local actual_sum
      if have sha256sum; then
        actual_sum=$(sha256sum "$pkg" | awk '{print $1}')
      elif have shasum; then
        actual_sum=$(shasum -a 256 "$pkg" | awk '{print $1}')
      else
        warn "  ⚠ No SHA256 tool available (sha256sum/shasum)"
        warn "  ⚠ Skipping checksum verification"
        actual_sum=""
      fi

      if [[ -n "$actual_sum" ]]; then
        # 比较校验和（不区分大小写）
        if [[ "${expected_sum,,}" == "${actual_sum,,}" ]]; then
          success "  ✓ Package integrity verified (SHA256 match)"
        else
          rm -rf "$tmp"
          err "SHA256 checksum verification FAILED!"
          err "  Expected: $expected_sum"
          err "  Actual:   $actual_sum"
          die "Package may be corrupted or tampered. Aborting for security."
        fi
      fi
    fi
  else
    warn "  ⚠ Checksum file not available from GitHub"
    warn "  ⚠ URL: $checksum_url"
    warn "  ⚠ Proceeding without verification (use at your own risk)"
  fi
  # ==================== 校验和验证结束 ====================

  msg "Extracting package..."
  # ... 现有代码继续 ...
}
```

**安全特性**:
- ✅ 自动下载官方 SHA256 文件
- ✅ 严格校验和比较
- ✅ 校验失败时中止安装
- ✅ 友好的降级处理（文件不可用时警告但继续）
- ✅ 支持 `sha256sum` 和 `shasum` 两种工具

---

### 优先级 2: 配置增强（重要但非关键）

#### 2.1 添加 TLS 版本控制 ⚠️ 纠正实现位置

**文件**: `lib/config.sh` (Line 113-168, `create_reality_inbound()` 函数)

**官方标准** (docs/configuration/shared/tls.md):
- `min_version` 和 `max_version` 属于 **TLS 层面**，不是 Reality 特有
- 应该放在 `tls` 对象中，与 `reality` 并列

**正确的配置结构**:

```json
{
  "tls": {
    "enabled": true,
    "server_name": "...",
    "min_version": "1.2",  // ← 这里（TLS 层）
    "max_version": "1.3",  // ← 这里（TLS 层）
    "alpn": ["h2", "http/1.1"],
    "reality": {           // ← Reality 内部没有这些字段
      "enabled": true,
      "private_key": "...",
      "short_id": ["..."],
      "handshake": {...},
      "max_time_difference": "1m"
    }
  }
}
```

**实施代码**:

```bash
# 修改 lib/config.sh create_reality_inbound() 函数
create_reality_inbound() {
  local uuid="$1"
  local port="$2"
  local listen_addr="$3"
  local sni="$4"
  local priv_key="$5"
  local short_id="$6"
  local min_tls_version="${7:-1.2}"  # 新参数：最小 TLS 版本（默认 1.2）
  local max_tls_version="${8:-1.3}"  # 新参数：最大 TLS 版本（默认 1.3）

  local reality_config

  msg "  - Creating Reality inbound configuration..."

  if ! reality_config=$(jq -n \
    --arg uuid "$uuid" \
    --arg port "$port" \
    --arg listen_addr "$listen_addr" \
    --arg sni "$sni" \
    --arg priv "$priv_key" \
    --arg sid "$short_id" \
    --arg min_tls "$min_tls_version" \
    --arg max_tls "$max_tls_version" \
    '{
      type: "vless",
      tag: "in-reality",
      listen: $listen_addr,
      listen_port: ($port | tonumber),
      users: [{ uuid: $uuid, flow: "xtls-rprx-vision" }],
      multiplex: {
        enabled: false,
        padding: false,
        brutal: {
          enabled: false,
          up_mbps: 1000,
          down_mbps: 1000
        }
      },
      tls: {
        enabled: true,
        server_name: $sni,
        min_version: $min_tls,     // ← TLS 层面的版本控制
        max_version: $max_tls,     // ← TLS 层面的版本控制
        alpn: ["h2", "http/1.1"],
        reality: {
          enabled: true,
          private_key: $priv,
          short_id: [$sid],
          handshake: { server: $sni, server_port: 443 },
          max_time_difference: "1m"
        }
      }
    }' 2>&1); then
    err "Failed to create Reality configuration. jq output:"
    err "$reality_config"
    return 1
  fi

  success "  ✓ Reality inbound configured with TLS $min_tls_version-$max_tls_version"
  echo "$reality_config"
}
```

**调用处修改** (lib/config.sh Line 379):

```bash
# 旧代码:
# reality_config=$(create_reality_inbound "$UUID" "$REALITY_PORT_CHOSEN" "$listen_addr" \
#   "$SNI_DEFAULT" "$PRIV" "$SID")

# 新代码（添加 TLS 版本参数）:
reality_config=$(create_reality_inbound "$UUID" "$REALITY_PORT_CHOSEN" "$listen_addr" \
  "$SNI_DEFAULT" "$PRIV" "$SID" "1.2" "1.3")
```

**环境变量支持** (可选):

```bash
# 在 lib/common.sh 中添加常量
readonly TLS_MIN_VERSION_DEFAULT="1.2"
readonly TLS_MAX_VERSION_DEFAULT="1.3"

# 在 install_multi.sh 中允许覆盖
: "${TLS_MIN_VERSION:=$TLS_MIN_VERSION_DEFAULT}"
: "${TLS_MAX_VERSION:=$TLS_MAX_VERSION_DEFAULT}"
```

**安全收益**:
- ✅ 禁用不安全的 TLS 1.0/1.1
- ✅ 强制使用 TLS 1.2+ 防止降级攻击
- ✅ 符合现代安全标准（PCI DSS 等）

---

#### 2.2 增强域名验证（要求 FQDN）

**文件**: `lib/validation.sh` (Line 34-58, `validate_domain()` 函数)

**当前问题**:
1. 允许单标签域名（如 "localhost", "example"）
2. 未验证 TLD 长度（至少 2 字符）
3. 未检查每个标签的长度限制（RFC 1035: ≤63 字符）

**RFC 1035 标准**:
- 完整域名（FQDN）至少包含一个点
- 每个标签最长 63 字符
- 总长度最长 253 字符
- TLD（顶级域名）至少 2 字符

**完整实施代码**:

```bash
# 完全替换 lib/validation.sh 中的 validate_domain() 函数
validate_domain() {
  local domain="$1"

  # === 步骤 1: 基础检查 ===
  [[ -n "$domain" ]] || return 1
  [[ ${#domain} -le 253 ]] || return 1  # RFC 1035: 最长 253 字符

  # === 步骤 2: FQDN 要求（必须包含至少一个点）===
  [[ "$domain" =~ \. ]] || return 1

  # === 步骤 3: 字符集验证 ===
  [[ "$domain" =~ ^[a-zA-Z0-9.-]+$ ]] || return 1

  # === 步骤 4: 边界条件检查 ===
  # 不能以点或连字符开头/结尾
  [[ ! "$domain" =~ ^[-.]|[-.]$ ]] || return 1

  # 不能有连续的点
  [[ ! "$domain" =~ \.\. ]] || return 1

  # === 步骤 5: 保留名称检查 ===
  [[ "$domain" != "localhost" ]] || return 1
  [[ "$domain" != "localhost.localdomain" ]] || return 1
  [[ ! "$domain" =~ ^[0-9.]+$ ]] || return 1  # 不是 IP 地址

  # === 步骤 6: TLD 验证 ===
  local tld="${domain##*.}"  # 提取最后一个点后的部分
  [[ ${#tld} -ge 2 ]] || return 1  # TLD 至少 2 字符
  [[ ! "$tld" =~ ^[0-9]+$ ]] || return 1  # TLD 不能是纯数字

  # === 步骤 7: 标签长度验证（RFC 1035）===
  local IFS='.'
  local -a labels
  read -ra labels <<< "$domain"

  for label in "${labels[@]}"; do
    # 每个标签长度检查
    [[ ${#label} -ge 1 ]] || return 1
    [[ ${#label} -le 63 ]] || return 1  # RFC 1035: 最长 63 字符

    # 标签不能以连字符开头或结尾
    [[ ! "$label" =~ ^-|-$ ]] || return 1
  done

  # === 步骤 8: 额外的保留域名检查 ===
  case "$domain" in
    *.local|*.localhost|*.test|*.invalid|*.example)
      return 1
      ;;
  esac

  return 0
}
```

**测试用例**:

```bash
# 应该通过的域名:
validate_domain "example.com"           # ✓ 标准域名
validate_domain "sub.example.com"       # ✓ 子域名
validate_domain "test-site.co.uk"       # ✓ 连字符
validate_domain "a1.b2.c3.example.com"  # ✓ 多级子域名

# 应该失败的域名:
! validate_domain "localhost"            # ✗ 保留名称
! validate_domain "example"              # ✗ 单标签（无点）
! validate_domain "example..com"         # ✗ 连续点
! validate_domain "-example.com"         # ✗ 以连字符开头
! validate_domain "example.com-"         # ✗ 以连字符结尾
! validate_domain "example.c"            # ✗ TLD 只有 1 字符
! validate_domain "192.168.1.1"          # ✗ IP 地址
! validate_domain "example.local"        # ✗ 保留 TLD
! validate_domain "example.123"          # ✗ TLD 是纯数字
! validate_domain "aaaaa...63chars...aaaaa.com"  # ✗ 标签超过 63 字符
```

---

#### 2.3 增强 IP 地址验证（更多保留地址段）

**文件**: `lib/network.sh` (Line 49-73, `validate_ip_address()` 函数)

**新增保留地址段** (基于 IANA 规范):

```bash
validate_ip_address() {
  local ip="$1"

  # === 现有检查保持不变 ===
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] || return 1

  local IFS='.'
  local -a octets
  read -ra octets <<< "$ip"
  for octet in "${octets[@]}"; do
    octet=$((10#$octet))
    [[ $octet -le 255 ]] || return 1
  done

  # === 现有保留地址检查 ===
  [[ ! "$ip" =~ ^0\. ]] || return 1          # 0.0.0.0/8
  [[ ! "$ip" =~ ^127\. ]] || return 1        # 127.0.0.0/8 (loopback)
  [[ ! "$ip" =~ ^169\.254\. ]] || return 1   # 169.254.0.0/16 (link-local)
  [[ ! "$ip" =~ ^22[4-9]\. ]] || return 1    # 224.0.0.0/4 (multicast)
  [[ ! "$ip" =~ ^2[4-5][0-9]\. ]] || return 1 # 240.0.0.0/4 (reserved)

  # === 新增：额外的保留地址段检查 ===

  # 100.64.0.0/10 - Shared Address Space (CGNAT, RFC 6598)
  [[ ! "$ip" =~ ^100\.6[4-9]\. ]] || return 1      # 100.64.0.0 - 100.79.255.255
  [[ ! "$ip" =~ ^100\.[7-9][0-9]\. ]] || return 1
  [[ ! "$ip" =~ ^100\.1[0-1][0-9]\. ]] || return 1
  [[ ! "$ip" =~ ^100\.12[0-7]\. ]] || return 1

  # 192.0.0.0/24 - IETF Protocol Assignments (RFC 6890)
  [[ ! "$ip" =~ ^192\.0\.0\. ]] || return 1

  # 192.0.2.0/24 - TEST-NET-1 (RFC 5737)
  [[ ! "$ip" =~ ^192\.0\.2\. ]] || return 1

  # 198.51.100.0/24 - TEST-NET-2 (RFC 5737)
  [[ ! "$ip" =~ ^198\.51\.100\. ]] || return 1

  # 203.0.113.0/24 - TEST-NET-3 (RFC 5737)
  [[ ! "$ip" =~ ^203\.0\.113\. ]] || return 1

  # 198.18.0.0/15 - Benchmarking (RFC 2544)
  [[ ! "$ip" =~ ^198\.1[89]\. ]] || return 1

  # 192.88.99.0/24 - IPv6 to IPv4 relay (6to4, deprecated but blocked)
  [[ ! "$ip" =~ ^192\.88\.99\. ]] || return 1

  # 255.255.255.255 - Broadcast address
  [[ "$ip" != "255.255.255.255" ]] || return 1

  return 0
}
```

**新增保护的地址段说明**:

| 地址段 | 用途 | RFC |
|--------|------|-----|
| 100.64.0.0/10 | Shared Address Space (CGNAT) | RFC 6598 |
| 192.0.0.0/24 | IETF Protocol Assignments | RFC 6890 |
| 192.0.2.0/24 | TEST-NET-1 (文档示例) | RFC 5737 |
| 198.51.100.0/24 | TEST-NET-2 (文档示例) | RFC 5737 |
| 203.0.113.0/24 | TEST-NET-3 (文档示例) | RFC 5737 |
| 198.18.0.0/15 | Network Benchmark Testing | RFC 2544 |
| 192.88.99.0/24 | 6to4 Relay Anycast (已废弃) | RFC 3068 |
| 255.255.255.255 | Limited Broadcast | RFC 919 |

---

### 优先级 3: 配置优化（可选）

#### 3.1 路由规则优化

**文件**: `lib/config.sh` (Line 262-293, `add_route_config()` 函数)

**建议添加**:

```bash
add_route_config() {
  local config="$1"
  local has_certs="${2:-false}"

  local route_inbounds='["in-reality"]'
  if [[ "$has_certs" == "true" ]]; then
    route_inbounds='["in-reality", "in-ws", "in-hy2"]'
  fi

  local updated_config
  if ! updated_config=$(echo "$config" | jq --argjson inbounds "$route_inbounds" '.route = {
    "rules": [
      {
        "inbound": $inbounds,
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      # 新增：私有地址直连（防止泄漏）
      {
        "ip_cidr": [
          "10.0.0.0/8",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "fc00::/7"
        ],
        "action": "direct"
      }
    ],
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-local"
    },
    "final": "direct"  # 新增：明确默认出站
  }' 2>/dev/null); then
    err "Failed to add route configuration"
    return 1
  fi

  echo "$updated_config"
}
```

**收益**:
- 私有地址不会被代理（防止内网泄漏）
- 明确的 `final` 规则提高可读性

---

## 🧪 测试计划

### 阶段 1: 单元测试

**创建**: `tests/unit/test_validation.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

source lib/common.sh
source lib/validation.sh
source lib/network.sh

test_domain_validation() {
  echo "Testing domain validation..."
  local passed=0
  local failed=0

  # 应该通过
  for domain in "example.com" "sub.example.com" "test-site.co.uk"; do
    if validate_domain "$domain"; then
      ((passed++))
    else
      echo "  ✗ FAIL: $domain should be valid"
      ((failed++))
    fi
  done

  # 应该失败
  for domain in "localhost" "example" "example..com" "-example.com" "example.c"; do
    if ! validate_domain "$domain"; then
      ((passed++))
    else
      echo "  ✗ FAIL: $domain should be invalid"
      ((failed++))
    fi
  done

  echo "Domain validation: $passed passed, $failed failed"
  return $failed
}

test_ip_validation() {
  echo "Testing IP validation..."
  local passed=0
  local failed=0

  # 应该通过
  for ip in "8.8.8.8" "1.1.1.1" "192.168.1.1"; do
    if validate_ip_address "$ip"; then
      ((passed++))
    else
      echo "  ✗ FAIL: $ip should be valid"
      ((failed++))
    fi
  done

  # 应该失败（保留地址）
  for ip in "127.0.0.1" "0.0.0.0" "192.0.2.1" "100.64.0.1" "255.255.255.255"; do
    if ! validate_ip_address "$ip"; then
      ((passed++))
    else
      echo "  ✗ FAIL: $ip should be invalid (reserved)"
      ((failed++))
    fi
  done

  echo "IP validation: $passed passed, $failed failed"
  return $failed
}

# 运行测试
echo "=== Running Validation Tests ==="
test_domain_validation
test_ip_validation
echo "=== All Tests Complete ==="
```

### 阶段 2: 集成测试

**创建**: `tests/integration/test_config_generation.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

# 加载所有模块
source lib/common.sh
source lib/validation.sh
source lib/config.sh
source lib/network.sh

# 模拟配置生成
export UUID="test-uuid-12345678-1234-1234-1234-123456789012"
export PRIV="test-private-key"
export SID="12345678"
export REALITY_PORT_CHOSEN="443"
export SNI_DEFAULT="www.microsoft.com"

echo "=== Testing Configuration Generation ==="

# 生成配置
base_config=$(create_base_config "false" "warn")
echo "✓ Base config generated"

reality_config=$(create_reality_inbound "$UUID" "443" "::" "$SNI_DEFAULT" "$PRIV" "$SID" "1.2" "1.3")
echo "✓ Reality inbound generated"

# 验证 TLS 版本字段存在
if echo "$reality_config" | jq -e '.tls.min_version == "1.2"' >/dev/null; then
  echo "✓ TLS min_version correctly set to 1.2"
else
  echo "✗ FAIL: TLS min_version not found or incorrect"
  exit 1
fi

if echo "$reality_config" | jq -e '.tls.max_version == "1.3"' >/dev/null; then
  echo "✓ TLS max_version correctly set to 1.3"
else
  echo "✗ FAIL: TLS max_version not found or incorrect"
  exit 1
fi

echo "=== All Configuration Tests Passed ==="
```

### 阶段 3: 实际部署测试

```bash
# Docker 环境测试
docker run --rm -it --privileged ubuntu:22.04 bash -c "
  apt-get update && apt-get install -y curl sudo

  # 测试自动安装模式
  curl -fsSL https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/install_multi.sh | \
    AUTO_INSTALL=1 bash

  # 验证安装
  test -x /usr/local/bin/sing-box || exit 1
  test -f /etc/sing-box/config.json || exit 1

  # 验证配置合法性
  /usr/local/bin/sing-box check -c /etc/sing-box/config.json || exit 1

  # 验证 TLS 版本字段
  jq -e '.inbounds[0].tls.min_version == \"1.2\"' /etc/sing-box/config.json || exit 1
  jq -e '.inbounds[0].tls.max_version == \"1.3\"' /etc/sing-box/config.json || exit 1

  # 验证服务启动
  systemctl is-active sing-box || exit 1

  echo '✓ All deployment tests passed'
"
```

---

## 📊 实施优先级总结

| 任务 | 优先级 | 风险 | 工作量 | 建议时间 |
|------|--------|------|--------|----------|
| 1.1 端口竞态修复 | P0-Critical | 高 | 中 | 立即 |
| 1.2 SHA256 校验 | P0-Critical | 高 | 中 | 立即 |
| 2.1 TLS 版本控制 | P1-High | 中 | 低 | 1-2天 |
| 2.2 域名验证增强 | P1-High | 低 | 低 | 1-2天 |
| 2.3 IP 验证增强 | P2-Medium | 低 | 低 | 1-2天 |
| 3.1 路由规则优化 | P3-Low | 无 | 低 | 可选 |

**建议实施顺序**:
1. 立即修复：1.1 + 1.2 (安全关键)
2. 第二批：2.1 + 2.2 + 2.3 (配置增强)
3. 可选：3.1 (优化项)

---

## ✅ 验收标准

### 功能验收

- [ ] 所有配置通过 `sing-box check` 验证
- [ ] 服务能够成功启动并监听端口
- [ ] 二进制校验和验证正常工作
- [ ] 域名验证拒绝无效输入
- [ ] IP 验证拒绝所有保留地址

### 性能验收

- [ ] 端口分配成功率 > 99%
- [ ] 服务启动时间 < 10 秒
- [ ] 配置生成时间 < 5 秒

### 安全验收

- [ ] TLS 1.0/1.1 被禁用
- [ ] 下载的二进制经过完整性验证
- [ ] 无保留/内网 IP 被接受为服务器地址

---

## 📝 注意事项

1. **向后兼容性**:
   - 所有修改保持环境变量覆盖能力
   - TLS 版本使用合理默认值（1.2-1.3）
   - 校验和失败时提供清晰错误信息

2. **错误处理**:
   - 所有新增代码包含完整错误检查
   - 使用 `|| die` 模式确保失败时退出
   - 提供可操作的错误消息

3. **文档更新**:
   - 更新 CLAUDE.md 文档
   - 添加新环境变量说明
   - 更新配置示例

4. **测试覆盖**:
   - 每个修改都有对应的测试用例
   - 集成测试覆盖完整安装流程
   - Docker 测试确保跨平台兼容性

---

**下一步**: 依次实施上述修复，每个任务完成后更新待办列表并验证功能。
