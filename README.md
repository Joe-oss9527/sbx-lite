# sbx-lite (optimized, ACME-ready)

一个围绕 **sing-box** 的轻量部署与管理工具：**默认 REALITY**，可选 **VLESS WS+TLS**、**Hysteria2**，带本地 **面板 + CLI**、订阅生成、健康体检与**内置 ACME 自动签发**支持。

> 面板默认仅监听 127.0.0.1:7789（Basic Auth），请通过 **SSH 隧道**访问：
>
> ```bash
> ssh -N -L 7789:127.0.0.1:7789 root@your-server
> ```
>
> 将 `your-server` 替换为 **你的服务器公网 IP 或域名**（如 `root@203.0.113.10` / `root@sbx.example.com`）。

---

## 一键安装（推荐）
支持 curl 和 wget：
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/quick.sh)
# 或
bash <(wget -qO- https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/quick.sh)
```
> 环境变量：`SBX_REPO` 指定仓库（默认 `YYvanYang/sbx-lite`），`SBX_BRANCH` 指定分支（默认 `main`）。

安装完成：
- 面板：`http://127.0.0.1:7789/`（首页显示 admin 密码）
- 服务：`systemctl status sing-box` / `systemctl status sbx-panel`

---

## 首次使用（按场景）

> 不需要把下面所有命令都执行一遍，**按你的方案挑选对应几条即可**。

### A. 仅用 REALITY（推荐）
```bash
sudo sbxctl sethost-auto          # 或：sudo sbxctl sethost your.domain.com
sudo sbxctl reality-keys          # 生成 Reality 私钥/公钥
# 打开 /etc/sbx/sbx.yml，把 reality.short_id 设置为 1~8 位十六进制（例：ab12cd34）
sudo sbxctl apply
sudo sbx-diagnose
```
> 说明：默认已启用 Reality，WS/Hy2 默认关闭，无需额外 disable。

### B. 使用 VLESS WS+TLS（证书/ACME）
```bash
sudo sbxctl sethost your.domain.com
sudo sbxctl cf proxied|direct     # Cloudflare 橙云选 proxied，直连选 direct
# 打开 /etc/sbx/sbx.yml：启用 vless_ws_tls.enabled，并在 tls.acme.* 填写 domain/email（DNS-01 推荐填 Cloudflare API Token）
# 如果 443 被 Reality 占用：sudo sbxctl disable reality  或者改其中任一协议的端口
sudo sbxctl apply
sudo sbx-diagnose
```

### C. 使用 Hysteria2（Hy2）+ ACME
```bash
sudo sbxctl sethost your.domain.com
# 打开 /etc/sbx/sbx.yml：启用 hysteria2.enabled，并在 hysteria2.tls.acme.* 填写 domain/email（DNS-01 推荐）
# up_mbps/down_mbps 可留空（不写入 JSON，走服务端默认/BBR）
sudo sbxctl apply
sudo sbx-diagnose
```

---

## 目录结构与路径
- 配置（期望态）：`/etc/sbx/sbx.yml`
- 生成（实态）：`/etc/sing-box/config.json`
- 面板与逻辑：`/opt/sbx/panel`
- 脚本与 CLI：`/opt/sbx/scripts`
- Systemd：`/etc/systemd/system/{sbx-panel.service,sing-box.service}`

---

## 配置说明（/etc/sbx/sbx.yml）

### 全局导出字段
```yaml
export:
  host: "你的公网域名或IP"
  name_prefix: "sbx"   # 生成订阅时的节点名前缀
cloudflare_mode: "proxied"   # proxied | direct（影响 WS 默认证书路径）
panel:
  bind: 127.0.0.1
  port: 7789
```

### 用户管理
```yaml
users:
  - name: "phone"
    enabled: true
    token: ""         # 订阅访问令牌（创建/旋转自动生成）
    vless_uuid: ""    # VLESS 用户 UUID（自动生成）
    hy2_pass: ""      # Hy2 用户密码（自动生成）
```

### Reality（VLESS+XTLS-Vision+REALITY）
```yaml
inbounds:
  reality:
    enabled: true
    listen_port: 443
    server_name: "www.cloudflare.com"  # 伪装站点（SNI/握手）
    private_key: ""                    # 服务端私钥
    public_key: ""                     # 可选，供客户端订阅
    short_id: ""                       # 0-8 hex，客户端必需
```

### VLESS WS+TLS（支持 ACME）
```yaml
inbounds:
  vless_ws_tls:
    enabled: false
    listen_port: 443
    domain: "example.com"
    path: "/ws"

    # 证书方式一：直接使用证书文件
    cert_path: "/etc/ssl/cf/origin.pem"
    key_path:  "/etc/ssl/cf/origin.key"

    # 证书方式二：内置 ACME（存在且 enabled:true 时优先生效）
    acme:
      enabled: false
      provider: "letsencrypt"          # letsencrypt | zerossl | custom
      directory_url: ""                # 自定义 ACME 端点可用
      email: "[email protected]"
      domain: ["example.com"]
      data_directory: "/var/lib/sbx/acme"
      disable_http_challenge: true
      disable_tls_alpn_challenge: true
      alternative_http_port: 18080     # 占用80时可改用备用端口
      alternative_tls_port: 15443      # 占用443时可改用备用端口
      dns01_challenge:
        provider: "cloudflare"
        api_token: "CF_API_TOKEN"
```

### Hysteria2（支持 ACME）
```yaml
inbounds:
  hysteria2:
    enabled: false
    listen_port: 8443
    # 允许留空（不输出到 JSON -> 走服务端默认，有利于 BBR/Brutal）
    up_mbps:
    down_mbps:
    global_password: ""   # 可选，全局密码（若用户未单独设置 hy2_pass）
    tls:
      # 文件证书
      certificate_path: "/etc/ssl/fullchain.pem"
      key_path: "/etc/ssl/privkey.pem"
      # 或 ACME（结构与 WS 相同）
      acme:
        enabled: false
        provider: "letsencrypt"
        email: "[email protected]"
        domain: ["hy2.example.com"]
        data_directory: "/var/lib/sbx/acme"
        disable_http_challenge: true
        disable_tls_alpn_challenge: true
        dns01_challenge:
          provider: "cloudflare"
          api_token: ""
```

### Cloudflare 模式
- `proxied` 橙云：WS 默认指向 `/etc/ssl/cf/origin.{pem,key}`（**仅 CF 信任**）；建议 **DNS-01 ACME**。
- `direct` 直连：WS 默认指向 `/etc/ssl/{fullchain,privkey}.pem`（例如 Let’s Encrypt）。
- 通过 `sudo sbxctl cf proxied|direct` 自动切换并更新默认路径。

---

## 应用配置与体检
```bash
sudo sbxctl apply          # 生成 /etc/sing-box/config.json → sing-box check → 重启
sudo sbx-diagnose          # 关键项体检（Reality/WS/Hy2/证书/用户等）
```
- 若同时启用 **Reality 与 WS 且端口相同**，会在生成阶段**报错**（避免 443 端口冲突）。
- 若使用 ACME：
  - **DNS-01**：确保填好 `api_token`；无需开放 80/443。
  - **HTTP-01/TLS-ALPN-01**：若 80/443 被占用，可使用 `alternative_*_port` 并在防火墙/端口转发中做好映射。
  - 系统需安装 **带 ACME** 的 `sing-box` 构建；可用一份最小 ACME 配置跑 `sing-box check` 验证。

---

## 订阅与客户端适配
```
http://127.0.0.1:7789/sub/<TOKEN>?format=<shadowrocket|singbox|clash|clash_full>
# 额外参数：
#   tpl=cn|balanced|global
#   test=<URL>  或 test=auto&region=cn|cloudflare|global
```
- **Shadowrocket**：返回多行标准 URI（支持 Reality / WS / Hy2）。
- **sing-box**：返回极简 JSON（移动端易用）。
- **Clash**：返回 `proxies + proxy-groups` 的精简 YAML（由 `yaml.dump()` 输出）。
- **Clash Full**：返回可直接运行的完整配置（规则/提供者/DNS 已内置）。

> **命名**：节点名前缀来自 `export.name_prefix`，例如 `sbx-re-xxx / sbx-ws-xxx / sbx-hy2-xxx`。

---

## 常见操作（CLI）
```bash
# 协议开关
sudo sbxctl enable reality|ws|hy2
sudo sbxctl disable reality|ws|hy2

# Cloudflare/域名
sudo sbxctl cf proxied|direct
sudo sbxctl setdomain your.domain.com
sudo sbxctl sethost 1.2.3.4   # 或 sethost-auto

# 用户
sudo sbxctl user-add iphone
sudo sbxctl user-enable iphone
sudo sbxctl user-disable iphone
sudo sbxctl user-rotate iphone

# Reality 密钥
sudo sbxctl reality-keys
```

---

## 故障处理与排错
- `sbx-diagnose` 显示：缺用户/缺密钥/证书缺失/端口冲突/ACME 配置缺项等。
- `sing-box check -c /etc/sing-box/config.json`：总是第一手验证器。
- 端口冲突：确保 Reality 与 WS 不在同一端口（默认 443）。
- ACME 失败：
  - DNS-01：检查 `api_token` 权限与解析域名是否在同账户下。
  - HTTP-01/TLS-ALPN-01：确认 80/443 可达或已配置 `alternative_*_port` 转发。
- Cloudflare 橙云：优先 DNS-01；Origin 证书**不被公众信任**，仅 CF 直连可用。
- Hy2 吞吐：不设置 `up_mbps/down_mbps` ⇒ 采用服务端默认（利于高带宽/低延迟）。
- 日志：`journalctl -u sing-box -e`，`journalctl -u sbx-panel -e`。

---

## 安全建议
- 面板只绑定 `127.0.0.1`，通过 SSH 隧道访问；不要裸露到公网。
- 订阅链接携带 Token，请仅在可信渠道分发；定期 `user-rotate`。
- 及时更新系统与 `sing-box`，并限制入站端口的访问面。

---

## 升级卸载
```bash
# 升级：覆盖 /opt/sbx 与脚本后
sudo systemctl daemon-reload
sudo systemctl restart sbx-panel
sudo sbxctl apply

# 卸载
sudo ./uninstall.sh
```

---

## FAQ
**Q: 必须使用带 ACME 的 sing-box 吗？**
A: 仅当你要用 `tls.acme` 自动签发时需要；否则可直接放置证书文件。

**Q: Reality 与 WS 能同时开吗？**
A: 可以，但需**不同端口**；默认都在 443 时会被拦截提示。

**Q: Clash Full 的规则能自定义吗？**
A: 可以，修改面板服务端生成逻辑或在客户端侧叠加你自己的规则。

---

## 致谢与许可
- 核心依赖：**sing-box**（SagerNet）；部分规则/思路参考社区常用模板。
- License：MIT（可按需调整）。
