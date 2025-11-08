# sing-box 官方文档审查报告

**日期**: 2025-11-08
**目的**: 在继续实施 Phase 3 之前，审查官方文档确保合规性和最佳实践

---

## 📚 审查来源

### 官方文档位置
- **Git Submodule**: `docs/sing-box-official/` (commit: 43fef1d)
- **官方仓库**: https://github.com/SagerNet/sing-box
- **官方网站**: https://sing-box.sagernet.org/

### 审查的文档
1. ✅ `docs/installation/package-manager.md` - 官方安装方式
2. ✅ `docs/migration.md` - 版本迁移指南
3. ✅ `docs/deprecated.md` - 废弃功能列表
4. ✅ `docs/changelog.md` - 最新版本变化
5. ✅ 官方安装脚本分析

---

## 🔍 关键发现

### 1. 官方安装脚本分析

**官方脚本位置**: `https://sing-box.app/install.sh`
- 重定向到: `https://sing-box.sagernet.org/installation/tools/install.sh`

**版本选择机制**:
```bash
# 默认（stable）
curl -fsSL https://sing-box.app/install.sh | sh

# Beta 版本
curl -fsSL https://sing-box.app/install.sh | sh -s -- --beta

# 特定版本
curl -fsSL https://sing-box.app/install.sh | sh -s -- --version <version>
```

**实现方式**:
- GitHub API: 获取 release 信息
- 版本提取: `grep tag_name | awk -F: '{print $2}' | sed 's/[", v]//g'`
- 包管理器优先级: pacman > dpkg > dnf > rpm > opkg

**⚠️ 关键缺陷**:
- ❌ **没有校验和验证**
- ❌ 没有 GPG 签名检查
- ❌ 没有证书固定
- ❌ 没有下载完整性验证

**我们的优势**:
- ✅ **实施了 SHA256 校验和验证**（Phase 2 完成）
- ✅ 从 GitHub releases 下载官方校验和文件
- ✅ 失败时中止安装，防止安装损坏的二进制文件

---

### 2. 版本兼容性检查

#### 1.12.0 重大变更 ✅

**DNS 服务器格式重构** (我们已合规):
```json
// ❌ 旧格式（将在 1.14.0 移除）
{
  "dns": {
    "servers": [{"address": "local"}]
  }
}

// ✅ 新格式（我们在用）
{
  "dns": {
    "servers": [{"type": "local"}]
  }
}
```

**验证**: `lib/config.sh:68-72` ✅
```bash
"dns": {
  "servers": [{"type": "local", "tag": "dns-local"}],
  "strategy": "ipv4_only"
}
```

#### 1.11.0 废弃字段 ✅

**传统 Inbound 字段** (我们已遵循):
- ❌ 废弃: `inbound.sniff`, `inbound.domain_strategy`
- ✅ 新方式: Route rule actions
- 移除时间: sing-box 1.13.0

**验证**: `lib/config.sh:272-287` ✅
```bash
# 我们使用 route rules 而不是 inbound fields
"route": {
  "rules": [
    {"inbound": [...], "action": "sniff"},  # ✅ 正确
    {"protocol": "dns", "action": "hijack-dns"}  # ✅ 正确
  ]
}
```

#### 其他废弃功能 ✅

| 功能 | 状态 | 移除版本 | sbx-lite 影响 |
|------|------|----------|---------------|
| Legacy DNS formats | 废弃 | 1.14.0 | ✅ 已使用新格式 |
| `outbound` DNS rule | 废弃 | - | ✅ 使用 `domain_resolver` |
| Legacy inbound fields | 废弃 | 1.13.0 | ✅ 使用 route actions |
| GeoIP/Geosite | 废弃 | 已移除 | ✅ 不使用 |

---

### 3. 配置标准合规性验证

#### ✅ 完全合规的配置项

1. **DNS 配置** (`lib/config.sh:68-72`)
   ```json
   {
     "dns": {
       "servers": [{"type": "local", "tag": "dns-local"}],
       "strategy": "ipv4_only"
     }
   }
   ```
   - ✅ 使用新格式 `type: "local"`
   - ✅ 全局 DNS 策略 `strategy: "ipv4_only"`
   - ✅ 符合 1.12.0+ 标准

2. **Route 配置** (`lib/config.sh:272-287`)
   ```json
   {
     "route": {
       "rules": [
         {"inbound": [...], "action": "sniff"},
         {"protocol": "dns", "action": "hijack-dns"}
       ],
       "auto_detect_interface": true,
       "default_domain_resolver": {"server": "dns-local"}
     }
   }
   ```
   - ✅ 使用 rule actions 而不是废弃的 inbound fields
   - ✅ 配置 `default_domain_resolver` (1.12.0 推荐)
   - ✅ 启用 `auto_detect_interface` (防止路由环路)

3. **Inbound 配置** (`lib/config.sh:113-168`)
   ```json
   {
     "inbounds": [{
       "type": "vless",
       "listen": "::",  // ✅ 双栈支持
       "tls": {
         "reality": {
           "max_time_difference": "1m"  // ✅ 防重放
         }
       }
     }]
   }
   ```
   - ✅ 使用 `listen: "::"` 而不是 `"0.0.0.0"`
   - ✅ 没有废弃的 `sniff`/`domain_strategy` 字段
   - ✅ Reality 配置符合最新标准

4. **Outbound 配置** (`lib/config.sh:294-310`)
   ```json
   {
     "outbounds": [{
       "type": "direct",
       "tcp_fast_open": true  // ✅ 性能优化
     }]
   }
   ```
   - ✅ 没有废弃的 `domain_strategy` 字段
   - ✅ 使用全局 DNS 策略
   - ✅ 启用 TCP Fast Open

---

### 4. 版本管理最佳实践

#### 官方推荐的版本管理方式

**Package Manager 方式** (官方推荐):
```bash
# Debian/Ubuntu
apt install sing-box        # stable
apt install sing-box-beta   # beta

# Arch Linux
pacman -S sing-box
```

**Manual Installation** (我们的方式):
```bash
# 官方脚本
curl -fsSL https://sing-box.app/install.sh | sh                      # stable
curl -fsSL https://sing-box.app/install.sh | sh -s -- --beta        # beta
curl -fsSL https://sing-box.app/install.sh | sh -s -- --version 1.10.7  # specific
```

**我们的实现对比**:
| 功能 | 官方脚本 | sbx-lite (当前) | Phase 3 计划 |
|------|----------|-----------------|--------------|
| stable 版本 | ✅ 默认 | ✅ 默认 | ✅ 环境变量 |
| beta 版本 | ✅ --beta | ❌ 不支持 | ✅ `SINGBOX_VERSION=latest` |
| 特定版本 | ✅ --version | ✅ `SINGBOX_VERSION=vX.Y.Z` | ✅ 保持 |
| 校验和验证 | ❌ 无 | ✅ SHA256 | ✅ 保持 |
| 包管理器 | ✅ 自动检测 | ❌ 通用二进制 | ❌ 不需要 |

---

## 📋 Phase 3 实施建议

### 基于官方文档的改进计划

#### 1. 版本别名支持 (参考官方)

**环境变量设计**:
```bash
# Stable (默认)
bash install_multi.sh
# 或
SINGBOX_VERSION=stable bash install_multi.sh

# Latest (包括 pre-release)
SINGBOX_VERSION=latest bash install_multi.sh

# Specific version
SINGBOX_VERSION=v1.10.7 bash install_multi.sh
SINGBOX_VERSION=1.10.7 bash install_multi.sh  # 自动添加 'v' 前缀
```

**实现要点**:
1. ✅ 使用 GitHub API 获取版本信息
2. ✅ stable: `/repos/SagerNet/sing-box/releases/latest`
3. ✅ latest: `/repos/SagerNet/sing-box/releases` (第一个)
4. ✅ 版本验证和规范化
5. ✅ 保持 SHA256 校验和验证

#### 2. 不采用官方的部分

**Package Manager 检测**:
- ❌ 不实施：我们专注于通用二进制安装
- ✅ 优势：跨发行版兼容，无依赖

**Managed Installation**:
- ❌ 不实施：复杂度高，收益低
- ✅ 保持简单：一键脚本即可

---

## ✅ 合规性检查清单

### 配置格式合规

- [x] DNS 服务器使用新格式 (`type: "local"`)
- [x] 没有使用废弃的 inbound 字段
- [x] 使用 route rule actions
- [x] 配置 `default_domain_resolver`
- [x] 使用全局 DNS 策略
- [x] 启用 `auto_detect_interface`
- [x] Reality 配置符合标准
- [x] 没有使用废弃的 GeoIP/Geosite

### 版本兼容性

- [x] 支持 sing-box 1.12.0+
- [x] 向前兼容 1.13.0/1.14.0
- [x] 没有使用将被移除的功能
- [x] 遵循官方迁移指南

### 安全性

- [x] ✅ SHA256 校验和验证（官方没有）
- [x] ✅ 下载完整性检查
- [x] ✅ 失败时安全中止
- [x] 配置文件权限 600
- [x] 临时文件安全处理

---

## 🎯 Phase 3 实施要点

### 必须遵循的官方标准

1. **版本号格式**:
   - 官方格式: `vX.Y.Z` (例如: v1.10.7)
   - 支持无 `v` 前缀: `X.Y.Z` (自动规范化)
   - Pre-release: `vX.Y.Z-beta.N`, `vX.Y.Z-rc.N`

2. **GitHub API 使用**:
   - Stable: `https://api.github.com/repos/SagerNet/sing-box/releases/latest`
   - Latest: `https://api.github.com/repos/SagerNet/sing-box/releases`
   - Specific: `https://api.github.com/repos/SagerNet/sing-box/releases/tags/{tag}`
   - 支持 `GITHUB_TOKEN` 环境变量（提高 API 限额）

3. **下载 URL 格式**:
   ```
   https://github.com/SagerNet/sing-box/releases/download/{tag}/sing-box-{version}-{platform}.tar.gz
   ```

4. **校验和 URL** (我们的增强):
   ```
   https://github.com/SagerNet/sing-box/releases/download/{tag}/sing-box-{version}-{platform}.tar.gz.sha256sum
   ```

### 不需要实施的功能

1. ❌ 包管理器检测（pacman/dpkg/dnf/rpm/opkg）
2. ❌ 平台特定包格式（.deb/.rpm/.pkg.tar.zst）
3. ❌ OpenWRT 特殊处理
4. ❌ Repository 安装（apt/dnf/pacman）

### 保持的优势

1. ✅ SHA256 校验和验证（官方缺失）
2. ✅ 通用二进制安装（跨平台）
3. ✅ 完整的配置生成（Reality/WS-TLS/Hysteria2）
4. ✅ 管理工具集成（sbx 命令）
5. ✅ 测试驱动开发（TDD）

---

## 📊 对比总结

| 特性 | 官方脚本 | sbx-lite | 评估 |
|------|----------|----------|------|
| **版本管理** | ✅ stable/beta/specific | ⚠️ 仅 specific | 📋 Phase 3 改进 |
| **校验和验证** | ❌ 无 | ✅ SHA256 | ⭐ 我们更安全 |
| **包管理器** | ✅ 自动检测 | ❌ 通用二进制 | ✅ 简化方案 |
| **配置生成** | ❌ 无 | ✅ 完整生成 | ⭐ 核心功能 |
| **管理工具** | ❌ 无 | ✅ sbx 命令 | ⭐ 用户友好 |
| **测试覆盖** | ❌ 无 | ✅ TDD | ⭐ 高质量 |

---

## ✅ 结论

### sbx-lite 的现状

1. **✅ 配置格式**: 完全符合 sing-box 1.12.0+ 标准
2. **✅ 安全性**: 优于官方脚本（SHA256 验证）
3. **⚠️ 版本管理**: 需要改进（Phase 3）
4. **✅ 向前兼容**: 没有使用废弃功能

### Phase 3 实施策略

**参考官方**:
- ✅ 版本选择机制（stable/latest/specific）
- ✅ GitHub API 使用方式
- ✅ 版本号格式规范

**保持优势**:
- ✅ SHA256 校验和验证
- ✅ 通用二进制安装
- ✅ 完整配置生成
- ✅ TDD 测试方法

**不采用**:
- ❌ 包管理器依赖
- ❌ 特定发行版优化

### 可以安全继续 Phase 3

所有审查完成，没有发现阻塞问题。可以按照原计划实施 Phase 3：版本别名支持。

---

**审查人**: Claude Code
**日期**: 2025-11-08
**状态**: ✅ 通过 - 可以继续实施
