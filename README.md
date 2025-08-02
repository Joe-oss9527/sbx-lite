# sbx-lite

**sbx-lite** 是一个面向个人/小团队的 **sing-box** 轻量化部署与管理工具，主打：**稳定、可维护、默认安全**。
支持 **VLESS-REALITY**（默认）、**VLESS-WS-TLS**（可走 CDN 兜底）、**Hysteria2（Hy2）**，并带有**本地面板**、**一键诊断**、\*\*订阅自动生成（含 Mihomo/Clash 完整模板）\*\*等能力。

> 面板默认只绑定 **127.0.0.1**，**请通过 SSH 隧道**访问；除非你非常清楚地配置了反向代理与加固策略。

---

## 目录

* [特性总览](#特性总览)
* [系统要求](#系统要求)
* [快速开始](#快速开始)
* [配置文件 `sbx.yml` 说明](#配置文件-sbxyml-说明)
* [协议与证书](#协议与证书)
* [订阅输出与模板](#订阅输出与模板)
* [面板与命令行](#面板与命令行)
* [诊断与健康检查](#诊断与健康检查)
* [安全建议](#安全建议)
* [常见问题](#常见问题)
* [变更记录（摘要）](#变更记录摘要)

---

## 特性总览

* **协议**

  * **VLESS-REALITY**（默认开启，抗探测、依赖最少）
  * **VLESS-WS-TLS**（可选；支持 Cloudflare 橙云/灰云）
  * **Hysteria2（Hy2）**（可选；**必须** TLS 证书）
* **订阅**

  * `shadowrocket` / `singbox`（JSON）/ `clash`（分组）/ `clash_full`（含 `proxy-groups + rule-providers + rules + DNS`）
  * 支持 `tpl=` 模板选择（`cn | balanced | global`）、`test=` 测速 URL 自定义、`test=auto&region=` 地区自适应
* **面板（仅本地）**

  * Checklist（必填项检测 + 一键修复）
  * Users（增删改、启用/禁用、**一键轮换 token**、复制订阅、**二维码 PNG 下载**）
  * Health/配置体检（`sing-box check`、服务状态、监听端口、证书摘要等）
  * Hy2 证书向导（检查/保存证书路径）
* **工具脚本**

  * `sbxctl`（启停协议、用户管理、应用配置、诊断别名 `doctor`）
  * `diagnose.sh`（覆盖服务、配置、端口、外网探测、证书等关键检查）
  * `hy2_wizard.sh`（一键检查并写入 Hy2 证书路径）
  * `cf_origin_helper.sh`（Cloudflare Origin Cert 放置与校验）
* **稳健性**

  * 生成器严格校验（无入站/缺关键字段直接报错）
  * 安装备有可选 “冒烟测试”（可用 `SKIP_SMOKE=1` 跳过）

---

## 系统要求

* **操作系统**：Ubuntu **22.04 / 24.04**（apt）
* **权限**：`root` 或具备 `sudo`
* **依赖**：安装脚本会自动安装 `sing-box`、`nodejs/npm`、`jq` 等
* **端口**：默认 `443/TCP`（REALITY/WS-TLS），`8443/UDP`（Hy2，若启用）

---

## 快速开始

```bash
# 1) 安装
unzip sbx-lite-v20.zip
cd sbx-lite
sudo ./install.sh              # 若暂时无证书，可 SKIP_SMOKE=1 ./install.sh

# 2) 基本设置（导出 host、Cloudflare 模式与域名）
sudo /opt/sbx/scripts/sbxctl sethost           # 可无参→自动探测公网IP
sudo /opt/sbx/scripts/sbxctl cf proxied        # 橙云（CDN）或 direct（灰云）
sudo /opt/sbx/scripts/sbxctl setdomain your.domain

# 3) 协议（默认开启 REALITY）
sudo /opt/sbx/scripts/sbxctl enable reality
sudo /opt/sbx/scripts/sbxctl disable ws
sudo /opt/sbx/scripts/sbxctl disable hy2

# 4) 应用并诊断
sudo /opt/sbx/scripts/sbxctl apply
sudo /opt/sbx/scripts/diagnose.sh
```

**访问面板（仅本地回环）**

```bash
ssh -N -L 7789:127.0.0.1:7789 root@server
# 然后浏览器打开 http://127.0.0.1:7789 （Basic-Auth）
```

---

## 配置文件 `sbx.yml` 说明

路径：`/etc/sbx/sbx.yml`。字段按 **\[必需] / \[推荐] / \[可选] / \[自动生成]** 注释。

```yaml
panel:
  bind: 127.0.0.1         # [可选] 面板监听（默认仅本地，建议保持）
  port: 7789              # [可选]

export:
  host: "YOUR_PUBLIC_HOST"  # [推荐] 订阅/链接用的主机名或IP；也可在订阅URL用 ?host= 临时覆盖
  name_prefix: "sbx"        # [可选] 节点名前缀

cloudflare_mode: "proxied"  # [推荐] proxied(橙云) | direct(灰云)

users:                      # 至少1个 enabled:true 用户（安装时会创建）
  - name: "phone"           # [必需]
    enabled: true           # [必需]
    token: "..."            # [必需, 自动生成] 订阅鉴权
    vless_uuid: "..."       # [必需, 自动生成] VLESS/REALITY/WS-TLS
    hy2_pass: "..."         # [必需]* 启用Hy2时必需（自动生成）
  - name: "laptop"
    enabled: true
    token: "..."
    vless_uuid: "..."
    hy2_pass: "..."

inbounds:
  reality:
    enabled: true                 # [必需]
    listen_port: 443              # [可选]
    server_name: "www.cloudflare.com"  # [必需] 握手SNI
    private_key: "..."            # [自动生成]
    public_key: "..."             # [可选]* 客户端必需；请填写（诊断会检查）
    short_id: "..."               # [自动生成]

  vless_ws_tls:
    enabled: false                # [必需]* 需要时设 true
    listen_port: 443              # [可选]
    domain: "example.com"         # [必需] 橙云→CDN 域、灰云→源站域
    path: "/ws"                   # [可选]
    # 橙云(推荐)：Cloudflare Origin Cert
    cert_path: "/etc/ssl/cf/origin.pem"
    key_path:  "/etc/ssl/cf/origin.key"
    # 灰云：/etc/ssl/fullchain.pem 与 /etc/ssl/privkey.pem

  hysteria2:
    enabled: false                # [必需]* 需要时设 true（放行UDP）
    listen_port: 8443             # [可选]
    up_mbps: 100                  # [可选]
    down_mbps: 100                # [可选]
    global_password: ""           # [可选]* 不推荐多人共用
    tls:                          # [必需]* 启用Hy2必须 TLS
      certificate_path: "/etc/ssl/fullchain.pem"
      key_path:         "/etc/ssl/privkey.pem"
      # 或 acme: {...}
```

> 修改后运行：`sudo /opt/sbx/scripts/sbxctl apply`（内部会先 `sing-box check` 通过才重启）。

---

## 协议与证书

### VLESS-REALITY（默认）

* 最少依赖、抗探测。
* 必填：`server_name`、`private_key`、`short_id`；**建议**填 `public_key`（用于客户端订阅）。
* 客户端（Mihomo/Clash/Shadowrocket）需要 `flow=xtls-rprx-vision`（订阅已包含）。

### VLESS-WS-TLS（可选，CDN 兜底）

* **橙云（proxied）**：用 **Cloudflare Origin Cert**（放置到 `/etc/ssl/cf/*`，用 `cf_origin_helper.sh` 助手）。
* **灰云（direct）**：用公认证书 `/etc/ssl/fullchain.pem + /etc/ssl/privkey.pem`。
* 订阅会填 `security=tls&sni&host&path&encryption=none`。

### Hysteria2（可选）

* **必须** TLS：`hysteria2.tls.certificate_path/key_path` 或 `acme`。无证书 → **生成器拒绝**。
* 用户密码优先使用每用户 `hy2_pass`，否则退回 `global_password`。
* 提供 CLI/面板向导：`hy2_wizard.sh` / “Hy2 证书向导”卡片。

---

## 订阅输出与模板

基础形式：

```
http://127.0.0.1:7789/sub/<TOKEN>?format=<shadowrocket|singbox|clash|clash_full>
```

* `shadowrocket`：VLESS-REALITY/WS、Hy2 URI（参数完整，含 flow/security/sni 等）
* `singbox`：原生 JSON
* `clash`：`proxies + proxy-groups`（含 `🟢 Auto(url-test)` / `🔀 Select`）
* `clash_full`：**完整模板**（`proxies + proxy-groups + rule-providers + rules + DNS`）

**模板与测速 URL**（仅 clash/clash\_full）：

* `tpl=cn | balanced | global`（默认 `cn`）
* `test=<URL>` 或 `test=auto&region=cn|cloudflare|global`

  * `auto, cn → http://connect.rom.miui.com/generate_204`
  * `auto, cloudflare → https://cp.cloudflare.com/generate_204`
  * `auto, global → https://www.gstatic.com/generate_204`

**clash\_full 的 DNS 段（要点）**

* `enhanced-mode: fake-ip`，`listen: 127.0.0.1:1053`（避免冲突与暴露）
* `nameserver-policy`：`geosite:cn` 走本地 DNS；`geosite:geolocation-!cn` 走 DoH
* `fallback-filter`: 基于 `geoip CN` 与常见外网域名，提高返回结果稳定性

> `geosite:*` 依赖客户端 geodata（Mihomo/Clash Meta 会自动下载）。

---

## 面板与命令行

### 面板（默认仅 127.0.0.1）

* **Checklist**：检测 `export.host`、用户、Reality SNI、公钥、WS 域名/证书、Hy2 密码/证书等 → 一键修复
* **Users**：新增/删除、启用/禁用、**Rotate token**、复制订阅、**二维码显示+PNG 下载**
* **Health**：`sing-box check`、服务状态、监听端口、Hy2 证书到期/签发者摘要
* **Hy2 证书向导**：检查/保存证书路径（配合 `hy2_wizard.sh`）

### CLI `sbxctl`（常用）

```bash
# 协议
sbxctl enable {reality|ws|hy2}
sbxctl disable {reality|ws|hy2}

# Cloudflare 模式与域名/导出主机
sbxctl cf {proxied|direct}
sbxctl setdomain <domain>
sbxctl sethost [host_or_ip]     # 可无参→自动探测公网IPv4

# 用户
sbxctl adduser <name>
sbxctl rmuser <name>
sbxctl user-rotate <name>
sbxctl user-enable <name>
sbxctl user-disable <name>

# 应用/诊断
sbxctl apply
sbxctl doctor                   # 等价 /opt/sbx/scripts/diagnose.sh
```

---

## 诊断与健康检查

* **diagnose.sh**（建议每次改动后运行）

  * `sing-box check`、服务进程、端口监听
  * WS-TLS 证书存在性与到期信息（若装 `openssl`）
  * 订阅接口可用性、外网连通性探测（WS 场景）
  * Hy2 必填项（密码/证书）与 Reality `public_key` 缺失 → **FAIL** 提示
* **面板 → Health / 配置体检**

  * 展示 `sing-box check` 简要结果、服务状态、监听端口、Hy2 证书摘要
  * 不替代 CLI 诊断的全量检查（但足够直观定位常见问题）

---

## 安全建议

* **面板只本地监听**：默认 `127.0.0.1:7789`，请用 **SSH 隧道**访问。
* **部署反代前**：务必加 Basic-Auth 之外的额外防护（IP 白名单、CSRF Token、WAF 等）。
* **凭据文件权限**：`/etc/sbx/panel.env` 建议 `0600`。
* **证书管理**：橙云用 Origin Cert（helper 脚本可用），灰云确保公认证书定期续期。
* **升级前备份**：`/etc/sbx/sbx.yml` 与用户数据（尤其 tokens/uuid）。

---

## 常见问题

**Q1: 诊断提示 “No inbound enabled”？**
A：至少启用一个入站：`sbxctl enable reality` → `sbxctl apply`。

**Q2: Reality 客户端连不上，诊断提示 “public\_key missing”？**
A：把生成的 Reality **公钥**写入 `sbx.yml` 的 `inbounds.reality.public_key`（订阅需要）。

**Q3: WS-TLS 失败，提示证书缺失？**
A：根据 `cloudflare_mode` 放置对应证书并在 `sbx.yml` 写入 `cert_path/key_path`。
橙云可用：`/opt/sbx/scripts/cf_origin_helper.sh install <cert> <key>`。

**Q4: Hy2 启用但报 TLS 缺失？**
A：使用 `hy2_wizard.sh` 写入证书路径，或在 `sbx.yml` 的 `hysteria2.tls` 指定证书/ACME，然后 `sbxctl apply`。

**Q5: clash\_full 导入后 DNS 端口冲突？**
A：项目默认 `127.0.0.1:1053`；如仍冲突，可在客户端侧改为其它端口并重启客户端。

---

## 变更记录（摘要）

* **v14–v16**：`clash_full` 模板（规则/分组/DNS/分流）、模板下拉、订阅二维码/PNG 下载
* **v17**：测速 URL 自定义与地区自适应、深色主题、用户搜索
* **v18**：生成器重写（Hy2 强制 TLS、Reality/WS 校验）、Shadowrocket URI 完整化、诊断增强、安装冒烟
* **v19**：Hy2 证书向导（CLI + 面板）、Health 体检页
* **v20**：更安全的 `/api/fix`（spawn + 校验）、Reality 公钥缺失告警、DNS 监听改回环、安装可跳过冒烟
