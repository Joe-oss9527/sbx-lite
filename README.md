# sbx-lite

Official sing-box one-click deployment script with VLESS-REALITY, VLESS-WS-TLS, and Hysteria2 support.

## Features

- **Zero-config Reality deployment** - Auto IP detection, no domain required
- **Multi-protocol support** - REALITY (default), WS-TLS, Hysteria2 (optional)
- **sing-box 1.12.0+ compliant** - Modern DNS configuration, IPv6 dual-stack
- **QR code generation** - Easy client import via terminal display
- **Performance optimized** - TCP Fast Open enabled, 5-10% latency reduction

## Quick Start

**Reality only (recommended)**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**Reality + WS-TLS + Hysteria2 (requires domain and certificate)**
```bash
DOMAIN=your.domain.com \
CERT_MODE=cf_dns \
CF_Token='your_cloudflare_token' \
bash <(curl -fsSL https://raw.githubusercontent.com/YYvanYang/sbx-lite/main/install_multi.sh)
```

**Additional options**
```bash
# Specify IP or domain
DOMAIN=1.2.3.4 bash <(curl -fsSL ...)

# Use existing certificates
DOMAIN=your.domain.com CERT_FULLCHAIN=/path/to/fullchain.pem CERT_KEY=/path/to/privkey.pem bash <(curl -fsSL ...)

# HTTP-01 ACME (requires port 80)
DOMAIN=your.domain.com CERT_MODE=le_http bash <(curl -fsSL ...)
```

## Management Commands

```bash
sbx info          # Show configuration and URIs
sbx qr            # Display QR codes for client import
sbx status        # Check service status
sbx restart       # Restart service
sbx log           # View live logs
sbx check         # Validate configuration
sbx start|stop    # Control service
sbx uninstall     # Complete removal (requires root)
```

**Configuration**: `/etc/sing-box/config.json`
**Default ports**: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)

## Client Compatibility

- **NekoRay/NekoBox** (recommended, native sing-box support)
- **v2rayN** (requires switching core to sing-box: Settings → Core → VLESS → sing-box)
- **Shadowrocket** (iOS)
- **sing-box official clients**

## Troubleshooting

**Reality connection issues**
- Domain users: Verify DNS-only mode (Cloudflare gray cloud)
- IP users: Check firewall allows port 443
- v2rayN users: Switch VLESS core from Xray to sing-box

**Hysteria2 not working**
- Verify certificate exists and UDP port is open

**Reconfiguration**
- Re-run installation command to overwrite existing setup

## Technical Details

**sing-box 1.12.0+ compliance**
- Explicit DNS configuration with `type: "local"` format
- Global `dns.strategy` instead of deprecated per-outbound settings
- IPv6 dual-stack listen (`::`), IPv4-only DNS strategy for compatible networks
- Modern route rules with `action: "sniff"` and `action: "hijack-dns"`
- TCP Fast Open enabled for reduced connection latency

**Security enhancements**
- Anti-replay protection via `max_time_difference` in REALITY config
- Input validation and sanitization against command injection
- Secure temporary file handling (600/700 permissions)
- Enhanced IP validation with reserved address filtering

## License

MIT License - Based on official sing-box
