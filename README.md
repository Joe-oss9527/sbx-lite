# sbx-lite

Official sing-box one-click deployment script with VLESS-REALITY, VLESS-WS-TLS, and Hysteria2 support.

**v2.0** - Modular architecture with enhanced features and production-grade quality.

## Features

- **Zero-config Reality deployment** - Auto IP detection, no domain required
- **Multi-protocol support** - REALITY (default), WS-TLS, Hysteria2 (optional)
- **sing-box 1.12.0+ compliant** - Modern DNS configuration, IPv6 dual-stack
- **Backup & restore** - AES-256 encrypted backups with 30-day retention
- **Client config export** - v2rayN, Clash, QR codes, subscription links
- **Modular architecture** - 9 focused modules, streamlined codebase
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

**Service Management**
```bash
sbx info          # Show configuration and URIs
sbx qr            # Display QR codes for client import
sbx status        # Check service status
sbx restart       # Restart service
sbx log           # View live logs
sbx check         # Validate configuration
sbx start|stop    # Control service
```

**Backup & Restore**
```bash
sbx backup create --encrypt     # Create encrypted backup
sbx backup list                 # List available backups
sbx backup restore <file>       # Restore from backup
sbx backup cleanup              # Delete old backups (30+ days)
```

**Client Configuration Export**
```bash
sbx export v2rayn reality       # Export v2rayN JSON config
sbx export clash                # Export Clash YAML config
sbx export uri all              # Export all share URIs
sbx export qr ./qr-codes/       # Generate QR code images
sbx export subscription         # Generate subscription link
```

**System**
```bash
sbx uninstall     # Complete removal (requires root)
sbx help          # Show all commands
```

**Configuration**: `/etc/sing-box/config.json`
**Default ports**: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)
**Backups**: `/var/backups/sbx/` (encrypted with AES-256)

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

## Architecture (v2.0)

**Modular Design**
- **9 library modules** (3,153 lines) in `lib/` directory
- **Streamlined installer** (~500 lines, down from 2,294)
- **CI/CD integration** with automated quality checks
- **Production-grade** error handling and validation

**Key Modules**
- `lib/common.sh` - Global utilities and logging
- `lib/network.sh` - Network operations and IP detection
- `lib/validation.sh` - Input validation and security
- `lib/certificate.sh` - ACME/Let's Encrypt integration
- `lib/config.sh` - sing-box JSON configuration generation
- `lib/service.sh` - systemd service management
- `lib/ui.sh` - User interface and prompts
- `lib/backup.sh` - Backup and restore functionality
- `lib/export.sh` - Client configuration export

**Installed Components**
- Main installer: `install_multi.sh`
- Management tool: `/usr/local/bin/sbx-manager`
- Library modules: `/usr/local/lib/sbx/*.sh`
- Configuration: `/etc/sing-box/config.json`
- Client info: `/etc/sing-box/client-info.txt`

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
