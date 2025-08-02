# sbx-lite (sing-box + systemd + lightweight panel)

A minimal, auditable one-click deployment for **sing-box** with a tiny local config panel.
- **Stack:** official sing-box (systemd), Node.js (Express) panel (binds to `127.0.0.1:7789` by default).
- **Features:** VLESS-REALITY, VLESS-WS-TLS (CDN-ready), Hysteria2.
- **Security defaults:** panel bound to localhost; random admin password stored at `/etc/sbx/panel.env`.

> This is a minimal educational project. Review scripts before running in production.


---

## Multi-user & Subscriptions

- Edit `/etc/sbx/sbx.yml`:
  - Set `export.host` to your **public domain/IP** (REALITY/Hy2 使用此 host；WS-TLS 使用 `vless_ws_tls.domain`).
  - Under `users:` add entries or use the API below.
- Subscription endpoint (no admin auth; protected by per-user token):
  - `GET /sub/<token>?format=shadowrocket` → returns URI list (Shadowrocket friendly).
  - Supported formats: `shadowrocket|uri`, `singbox|json`, `clash|yaml`.
  - Example (via SSH tunnel): `http://127.0.0.1:7789/sub/USER_TOKEN?format=shadowrocket`
- Create user via API (requires admin auth):
  - `POST /api/user/new` JSON `{ "name": "alice" }` → returns `token / vless_uuid / hy2_pass`.
- Apply config: `/api/apply` or `sudo /opt/sbx/scripts/sbxctl apply`

## Notes
- REALITY links include `pbk/sid/sni`. For best compatibility keep `fp=chrome` and `alpn=h2,http/1.1`.
- Hy2 URI conventions vary across clients; Shadowrocket recognizes the `hy2://PASSWORD@host:port?...` form in recent versions.
- If enabling WS-TLS through CDN, ensure `vless_ws_tls.domain/path` match and certificates are valid (or use origin cert behind CDN).

## Minimal Security
- Panel binds to `127.0.0.1` by default. Use SSH port-forwarding for remote access.
- Subscription endpoints are public but protected by **unguessable tokens** per user; rotate tokens if leaked.
- To expose panel publicly, front it with TLS + IP allowlist or Cloudflare Access.



## ACME 自动签发（可选，用于直连 TLS / 灰云场景）
在 `/etc/sbx/sbx.yml` 的 `inbounds.vless_ws_tls.acme` 里开启：
```yaml
inbounds:
  vless_ws_tls:
    enabled: true
    domain: "your.domain"
    path: "/ws"
    acme:
      enabled: true
      provider: "letsencrypt"
      email: "you@example.com"
      # CDN 场景建议 DNS-01（需自行配置相应 provider 的凭据/环境变量）
      dns01: {}
      # alternative_http_port: 8080
      # alternative_tls_port: 8443
```
> 提示：在 CDN 橙云下，HTTP-01/TLS-ALPN-01 可能受影响，建议 DNS-01；
> 证书由 sing-box 内置 ACME 自动申请与续期，无需手工跑 certbot。

## 卸载
仅移除 sbx-lite（保留 sing-box）：
```bash
sudo ./uninstall.sh
```
连同 sing-box 一并移除：
```bash
sudo ./uninstall.sh --remove-singbox
```


## Stability-first (no ACME path)
- 默认不包含 ACME。VLESS-WS-TLS 如需证书有两条稳妥路径：
  1) **走 CDN（橙云）**：在源站安装 **Cloudflare Origin Cert**，把路径填到 `cert_path/key_path`；客户端只连 CDN。
  2) **你已有有效公认证书**：将其拷贝到服务器并设置 `cert_path/key_path`。
- 若暂时不用 WS-TLS，直接保持 `vless_ws_tls.enabled: false`，仅使用 **REALITY / Hy2**，稳定性更高、依赖更少。


---

# 使用指南（清晰上手）

## 1. 快速开始
```bash
unzip sbx-lite-v5.zip
cd sbx-lite
sudo ./install.sh
# 编辑导出主机名（用于生成链接）
sudo sed -i 's/YOUR_PUBLIC_HOST/example.com/' /etc/sbx/sbx.yml
# 应用配置
sudo /opt/sbx/scripts/sbxctl apply
```

## 2. 协议与配置位置
- 源 YAML：`/etc/sbx/sbx.yml` → 生成：`/etc/sing-box/config.json`
- 默认启用：**VLESS-REALITY@443/TCP**
- 可选启用：
  - **VLESS-WS-TLS**（走 CDN 建议使用 Origin Cert：填 `cert_path/key_path`）
  - **Hysteria2@8443/UDP**
- 修改后执行：`sudo /opt/sbx/scripts/sbxctl apply`

## 3. 多用户与订阅
- 新增用户（需 admin 认证）
  ```bash
  curl -u admin:$(sudo awk -F= '/ADMIN_PASS/{print $2}' /etc/sbx/panel.env)        -H 'Content-Type: application/json'        -d '{"name":"alice"}'        http://127.0.0.1:7789/api/user/new
  ```
- 分发订阅（订阅接口无需 admin 认证，靠 token 保护）
  - Shadowrocket（URI 列表）：`http://127.0.0.1:7789/sub/<TOKEN>?format=shadowrocket`
  - Sing-box（JSON）：`http://127.0.0.1:7789/sub/<TOKEN>?format=singbox`
  - Clash（YAML）：`http://127.0.0.1:7789/sub/<TOKEN>?format=clash`

> 面板默认仅监听 `127.0.0.1:7789`，建议用 SSH 隧道：
> `ssh -N -L 7789:127.0.0.1:7789 root@你的服务器`

## 4. 自检脚本（强烈建议）
```bash
sudo /opt/sbx/scripts/diagnose.sh
```
会自动检查：
- sing-box 是否安装/运行、配置是否通过 `check`；
- REALITY/WS-TLS/Hy2 对应端口是否监听；
- 订阅接口是否可用；
- 若启用 WS-TLS，则简要探测 HTTPS 可达性。

## 5. 卸载
- 仅移除 sbx-lite：`sudo ./uninstall.sh`
- 连同 sing-box 一并移除：`sudo ./uninstall.sh --remove-singbox`

## 6. 安全与最佳实践
- 面板仅本地监听；如需公网，务必加反代 + TLS + IP 白名单或 Zero Trust。
- 多人使用请为每个用户分配独立 `uuid/token`，泄露时单独吊销即可。
- REALITY 推荐 `server_name` 选常见大站；WS-TLS 走 CDN 时固定 `path`，证书用 Origin Cert 更稳。

## 7. 常见问题
- **订阅 404**：token 不存在或用户未启用；检查 `/etc/sbx/sbx.yml` 的 `users:`。
- **REALITY 无法连接**：核对 `public_key/short_id/SNI`、时间同步、客户端指纹先用 `chrome`。
- **WS-TLS 握手失败**：确认证书路径与域名一致；CDN 回源正常；必要时灰云测试。
- **Hy2 不通**：确认放行 UDP，必要时更换端口或排查运营商限制；服务器用 `ss -plun` 查看监听。


## 一键命令（开关协议 / CF 模式 / 主机名）
```bash
# 开关协议（默认 REALITY 已启用）
sudo /opt/sbx/scripts/sbxctl enable reality|ws|hy2
sudo /opt/sbx/scripts/sbxctl disable reality|ws|hy2

# 切换 Cloudflare 模式：proxied=橙云（CDN），direct=灰云（直连）
sudo /opt/sbx/scripts/sbxctl cf proxied
sudo /opt/sbx/scripts/sbxctl cf direct

# 设置导出主机（订阅里使用）与 WS-TLS 域名
sudo /opt/sbx/scripts/sbxctl sethost example.com
sudo /opt/sbx/scripts/sbxctl setdomain example.com

# 用户管理
sudo /opt/sbx/scripts/sbxctl adduser phone
sudo /opt/sbx/scripts/sbxctl rmuser phone
```

> 安装时会自动：
> - 生成 `REALITY` 密钥/短ID/UUID；
> - **探测公网IP** 并在仍为占位时把它填入 `export.host`；
> - 预置 `phone` 与 `laptop` 两个用户（可按需删除/新增）。


## 系统支持
- 支持 **Ubuntu 22.04 / 24.04 LTS**（安装脚本会做版本检查）。
- 其他发行版可手动安装 Node/npm 与 sing-box，然后把本项目文件按同样目录布局部署。



## v9 新增功能
- **外网连通性探测**（diagnose.sh）：
  - 对启用的 **WS-TLS**，使用 `curl --resolve domain:port:IP` 做 SNI/直连探测，并做基于 DNS 的直连探测。
- **Cloudflare Origin Cert 助手**：
  ```bash
  sudo /opt/sbx/scripts/cf_origin_helper.sh check            # 检查证书存在/权限/有效期
  sudo /opt/sbx/scripts/cf_origin_helper.sh install cert.pem key.pem
  sudo /opt/sbx/scripts/cf_origin_helper.sh stdin            # 交互粘贴写入
  ```
  证书默认放置在：`/etc/ssl/cf/origin.pem` 与 `/etc/ssl/cf/origin.key`。


## 配置注释更清晰（v10）
- 默认 `/etc/sbx/sbx.yml` 已对每个字段标注 **[必需]/[推荐]/[可选]/[自动生成]**。
- `diagnose.sh` 会针对缺失的必填项给出**明确的修复建议**（例如放置证书、补充域名、添加用户等）。


## v11 面板增强
- 面板新增 **Checklist**：自动检测缺失/风险项（用户、REALITY SNI、WS 证书等），并提供**一键修复按钮**（启用协议、设置 Host、添加用户等）。
- 仍建议在变更后运行：`sudo /opt/sbx/scripts/diagnose.sh` 进行更全面的校验与外部探测。


## v12 更新
- `sethost` 支持**空参数自动探测公网 IP**（面板 `/api/fix` 同步支持）。
- 新增 `sbxctl doctor`，等价于运行 `diagnose.sh`。
- 诊断脚本在 WS-TLS 证书存在时会显示**证书到期信息**（需要安装 openssl）。


## v13 更新
- **Clash/Mihomo 订阅**：在 `?format=clash` 输出中新增 `proxy-groups`：
  - `🟢 Auto`（`type: url-test`，`url: https://www.gstatic.com/generate_204`，`interval: 300`，`tolerance: 50`，`lazy: true`），
  - `🔀 Select`（`type: select`，包含 `Auto`、全部节点与 `DIRECT`）。
- **面板用户管理**：新增“Users”面板（需 admin 认证）：
  - 列表展示用户与 token/UUID/Hy2 状态；
  - 一键 **Rotate token**、**Enable/Disable**、**Delete**、**Add**。
- **命令行**：新增 `sbxctl user-rotate|user-enable|user-disable <name>`。


## v14 更新
- 新增 `?format=clash_full`：输出 **完整 Mihomo 模板**（`proxies + proxy-groups + rule-providers + rules`），默认 Rule 模式、常见规则顺序（applications/private/reject/direct/proxy/tld-not-cn/geoip-cn/match）。
- 面板“Users”表中新增：
  - **Copy subs**（一键复制该用户四种订阅 URL）；
  - 顶部 **Share all subs**（批量生成所有用户的分享链接，便于分发）。
> 规则提供者使用开源公共列表（如 Loyalsoldier），如需私有镜像可手动替换生成的订阅内容中的 URL。


## v15 更新
- `?format=clash_full` 现已包含 **DNS** 配置（`enhanced-mode: fake-ip`、DoH/DoT 远程 DNS、`proxy-server-nameserver`、`fake-ip-filter` 基线）。
- 支持多模板选择（通过 URL 参数 `tpl=`）：
  - `tpl=global`：**全局代理**（除私有网段/应用/CN 外全部走代理）。
  - `tpl=cn`：**中国大陆优先直连**（默认，平衡常用需求）。
  - 未指定或其它值 → 与 `tpl=cn` 相同的**平衡**模板。
- 面板“Users”增加 **二维码**：可为每位用户生成 **Shadowrocket/Sing-box 订阅**二维码，扫码即导入。


## v16 更新
- **Clash Full DNS 分流**：在 `?format=clash_full` 的 `dns` 段中加入：
  - `nameserver-policy`：`geosite:cn` → 本地 DNS（119.29.29.29 / 223.5.5.5）；`geosite:geolocation-!cn` → DoH（1.1.1.1 / 8.8.8.8）。
  - `fallback-filter`：基于 `geoip CN` 与常见外网域名强制走回退解析，提升结果稳定性。
- **面板模板选择**：在面板加入下拉框（CN直连/平衡/全局），一键复制对应的 `clash_full` 订阅链接。
- **二维码图片下载**：二维码弹窗支持导出 **PNG 文件**（Shadowrocket / Sing-box 各一张），便于分享。
> 注：`nameserver-policy` 中的 `geosite:*` 依赖客户端侧内置/可更新的地理库（Mihomo/Clash Meta 常见发行版会自动下载）。


### 重要：Hy2 证书必填
- 启用 Hysteria2 时，`/etc/sbx/sbx.yml` 中必须提供：
  ```yaml
  hysteria2:
    tls:
      certificate_path: /etc/ssl/fullchain.pem
      key_path: /etc/ssl/privkey.pem
  ```
  或使用 `tls.acme`（如果你有内置 ACME 环境）。没有 TLS 将无法生成有效配置。

### Shadowrocket / URI 完整性
- REALITY（VLESS）：URI 已包含 `flow=xtls-rprx-vision`、`security=reality`、`pbk/sid/sni/fp` 等关键参数。
- WS-TLS（VLESS）：URI 包含 `security=tls&sni=...&type=ws&host=...&path=...&encryption=none`。
- Hy2：URI 包含 `sni`、`alpn=h3`，并默认 `insecure=0`。


## v19 更新
- **Hy2 一键证书向导**：
  - 新增脚本 `hy2_wizard.sh`：检测证书存在性、打印证书信息（若装有 openssl），并写入 `hysteria2.tls.certificate_path/key_path`。
  - 面板提供 `/api/hy2/tls-check` 与 `/api/hy2/tls-set`，可在 UI 中“检查/保存”。
- **配置体检（Health）页面**：
  - 面板新增“Health / 配置体检”卡片：一键运行体检，展示 `sing-box check`、服务状态、端口监听、启用入站摘要等。
  - 后端 `/api/health` 汇总 `diag.js` 信息与系统检查结果。
