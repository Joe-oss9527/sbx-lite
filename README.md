# sbx-lite（官方 sing-box 极简最佳实践）

**sbx-lite** 提供一套**最简、稳健**的官方 **sing-box** 部署流程：
默认仅启用 **VLESS-REALITY**（无需证书，抗探测），可选一并启用 **VLESS-WS-TLS** 与 **Hysteria2（Hy2）**（自动签证书或使用现有证书）。
脚本安装完成会直接**打印客户端导入 URI**；同样提供**一键卸载**。

> **重要前提（Cloudflare）**：
>
> * **Reality 必须灰云（DNS only）**；
> * **Hy2 只能灰云**；
> * **WS-TLS 可灰/橙云**（橙云时客户端看到的是 CF 证书，源站证书仅用于回源校验）。

---

## 目录

* [特性](#特性)
* [系统要求](#系统要求)
* [一键安装](#一键安装)
* [一键卸载](#一键卸载)
* [参数与默认值](#参数与默认值)
* [协议与端口](#协议与端口)
* [验证与运维](#验证与运维)
* [常见问题](#常见问题)
* [安全与建议](#安全与建议)
* [许可证](#许可证)

---

## 特性

* **官方二进制**：自动下载并安装 sing-box 最新版。
* **最小配置**：默认仅配 **VLESS-REALITY**，无需证书；按需启用 **WS-TLS** 与 **Hy2**。
* **自动生成凭据**：Reality 私钥/公钥、`short_id`、`UUID`、Hy2 密码均自动生成。
* **ACME（可选）**：支持 **DNS-01（Cloudflare，推荐）** 与 **HTTP-01** 自动签发与落盘。
* **系统托管**：`systemd` 服务一键创建与启动。
* **导入即用**：安装完成立即**打印** Reality/WS/Hy2 的**URI**。

---

## 系统要求

* OS：Ubuntu 22.04/24.04（或等价 Linux，需 `bash`、`systemd`）。
* 权限：`root` 或 `sudo`。
* DNS：准备一个**灰云**域名/子域（如 `r.example.com`）指向服务器公网 IP。
* 端口：默认 `443/tcp`（Reality），`8444/tcp`（WS-TLS），`8443/udp`（Hy2）。若占用将自动切换备用口。

---

## 一键安装

> 默认只启用 **Reality**（最简稳）。如设置证书参数或启用 ACME，则**同时**启用 **WS-TLS** 与 **Hy2**。
> 请把 `r.example.com` 替换为你的**灰云**域名。

**仅 Reality（推荐）**

```bash
DOMAIN=r.example.com \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**DNS-01（Cloudflare）自动签证书 → 同时启用 WS-TLS + Hy2（推荐）**

```bash
DOMAIN=r.example.com \
CERT_MODE=cf_dns \
CF_Token='<你的Cloudflare API Token（Zone.DNS:Edit + Zone:Read）>' \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**HTTP-01 自动签证书（需灰云 & 80 直达且未被占用）**

```bash
DOMAIN=r.example.com \
CERT_MODE=le_http \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**已有证书直接启用 WS-TLS + Hy2**

```bash
DOMAIN=r.example.com \
CERT_FULLCHAIN=/etc/letsencrypt/live/r.example.com/fullchain.pem \
CERT_KEY=/etc/letsencrypt/live/r.example.com/privkey.pem \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

安装完成后终端会打印：

* **VLESS-REALITY URI**（含 `pbk/sid/sni/flow/security` 等必需参数）
* 若启用证书：**VLESS-WS-TLS URI** 与 **Hy2 URI**

---

## 一键卸载

```bash
curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh \
| sudo FORCE=1 bash -s -- uninstall
```

> 卸载将停止服务并删除二进制与 `/etc/sing-box/` 配置文件。

---

## 参数与默认值

| 变量名              | 说明                                                     | 必需           | 默认                 |
| ---------------- | ------------------------------------------------------ | ------------ | ------------------ |
| `DOMAIN`         | 你的域名（灰云/DNS only）                                      | ✅            | —                  |
| `CERT_MODE`      | ACME 模式：`cf_dns`（DNS-01，推荐）或 `le_http`（HTTP-01）        | 否            | 空（不签，Reality-only） |
| `CF_Token`       | Cloudflare API Token（最小权限：Zone.DNS\:Edit + Zone\:Read） | `cf_dns` 时必需 | —                  |
| `CERT_FULLCHAIN` | 现有证书路径（fullchain.pem）                                  | 否            | —                  |
| `CERT_KEY`       | 现有证书路径（privkey.pem）                                    | 否            | —                  |

> 端口与路径：
>
> * 配置：`/etc/sing-box/config.json`
> * 二进制：`/usr/local/bin/sing-box`
> * 服务：`systemctl enable --now sing-box`

---

## 协议与端口

| 协议            |   端口（默认） | 证书 | 说明                                                                                             |
| ------------- | -------: | -- | ---------------------------------------------------------------------------------------------- |
| VLESS-REALITY |  443/tcp | 否  | 抗探测，最稳，需灰云；`flow=xtls-rprx-vision`；服务端含 `handshake`/`private_key`/`short_id`，客户端需 `public_key` |
| VLESS-WS-TLS  | 8444/tcp | 是  | 可走橙云；客户端看到 CF 证书，源站证书用于回源                                                                      |
| Hy2           | 8443/udp | 是  | 高性能 QUIC，仅灰云；必须 `tls.certificate_path/key_path`                                                |

> 如端口被占用，脚本会自动切换备用口（并在终端明确提示）。

---

## 验证与运维

**配置校验与服务状态**

```bash
sing-box check -c /etc/sing-box/config.json
systemctl status sing-box --no-pager
journalctl -u sing-box -e --no-pager
```

**客户端导入（Reality 示例 URI）**

```
vless://UUID@r.example.com:443?
  encryption=none
  &security=reality
  &flow=xtls-rprx-vision
  &sni=www.cloudflare.com
  &pbk=PUBLIC_KEY
  &sid=SHORTID
  &type=tcp
  &fp=chrome
# 实际使用请合并为一行，去掉换行与空格
```

**字段要点（Reality）**

* 服务端：`reality.enabled`、`handshake.server/server_port`、`private_key`、`short_id`；
* 客户端：`public_key (pbk)`、`short_id (sid)`、`sni`、`flow=xtls-rprx-vision`；
* `alpn` 建议含 `h2,http/1.1`（服务端已默认配置）。

---

## 常见问题

**1) Reality 连不通？**

* 域名须 **灰云**；
* `sing-box check` 是否通过；
* 443 端口是否被占；
* 本机时间是否正确（TLS/Reality 对时钟敏感）。

**2) Hy2 不工作？**

* 必须有证书（自动签或自备），并放通 **UDP** 端口（默认 8443）。

**3) WS-TLS 橙云是否可用？**

* 可用。客户端看到的是 **CF 证书**（正常）；源站证书用于 CF 回源。

**4) 重装/变更怎么做？**

* 直接用同一安装命令覆盖（例如后续补充证书即可启用 WS/Hy2）。

---

## 安全与建议

* **最小化暴露**：只开放必要端口；非必须不在 0.0.0.0 上开启额外服务。
* **Cloudflare 最小权限**：DNS-01 推荐为自定义 Token，只授予 Zone.DNS\:Edit + Zone\:Read。
* **定期审查**：关注 `journalctl -u sing-box` 日志与证书到期时间。
* **备份**：保存好 `/etc/sing-box/config.json`（含自动生成的密钥与凭据）。

---

## 许可证

* 本仓库脚本与文档：MIT License。
* **sing-box** 版权与许可证请以其官方仓库为准。

---

### 附：脚本位置

* **一键脚本**：[`install_multi.sh`](./install_multi.sh)（在线安装命令已见上文）。

  * 默认启用 **VLESS-REALITY**；
  * 设置 `CERT_MODE`/`CF_Token` 或提供 `CERT_FULLCHAIN`/`CERT_KEY` 即可同时启用 **WS-TLS** 与 **Hy2**；
  * 安装结束自动打印各协议的**导入 URI**；
  * 卸载命令见上文“一键卸载”。