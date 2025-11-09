# sbx-lite

One-click deployment script for sing-box proxy server with VLESS-REALITY support.

## Features

- **Zero configuration** - Auto-detects server IP, works immediately
- **Multi-protocol** - VLESS-REALITY (default), WS-TLS, Hysteria2 (optional)
- **Auto management** - Built-in backup, client export, QR codes
- **Production ready** - sing-box 1.12.0+, encrypted backups, CI/CD tested
- **Enterprise logging** - Debug mode, JSON output, log files, timestamps
- **Easy sharing** - Generate client configs, QR codes, subscription links

## Quick Start

**Install (Reality mode, no domain required)**
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/install_multi.sh)
```

**Install with domain (enables WS-TLS + Hysteria2)**
```bash
DOMAIN=your.domain.com bash <(curl -fsSL https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/install_multi.sh)
```

After installation, connection URIs are displayed automatically. Copy them to your client.

## Common Commands

```bash
sbx info          # Show connection URIs and config
sbx qr            # Display QR codes
sbx status        # Check service status
sbx restart       # Restart service
sbx backup create # Create backup
sbx uninstall     # Remove everything
```

**Full command list**: Run `sbx help`

## Client Setup

**Recommended clients**:
- **NekoRay/NekoBox** (Windows/Linux/Mac) - Native sing-box support
- **v2rayN** (Windows) - Switch core to sing-box: Settings → Core → VLESS → sing-box
- **Shadowrocket** (iOS)
- **sing-box official clients** (All platforms)

**Import methods**:
1. Copy URI from terminal output → Paste in client
2. Scan QR code: Run `sbx qr` → Scan with client camera
3. Use exported config: Run `sbx export v2rayn reality` → Import JSON file

## Troubleshooting

**Can't connect**
```bash
sbx status        # Check if service is running
sbx check         # Validate configuration
sbx log           # View error messages
```

**Installation issues - Enable debug logging**
```bash
# Run with detailed debug output and timestamps
DEBUG=1 LOG_TIMESTAMPS=1 bash <(curl -fsSL https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/install_multi.sh)

# Save debug log to file for sharing
DEBUG=1 LOG_FILE=/tmp/install-debug.log bash <(curl -fsSL ...)
```

**v2rayN shows "connection failed"**
Switch VLESS core from Xray to sing-box in client settings.

**Need to reconfigure**
Re-run the installation command - it will detect existing installation and offer upgrade/reconfigure options.

**Port conflicts**
Script auto-selects alternative ports (24443, 24444, 24445) if defaults are occupied.

## Advanced Usage

**Debugging & Logging**
```bash
# Debug mode with timestamps (troubleshooting)
DEBUG=1 LOG_TIMESTAMPS=1 bash <(curl -fsSL ...)

# Save installation log to file
LOG_FILE=/var/log/sbx-install.log bash <(curl -fsSL ...)

# JSON format for log analysis tools
LOG_FORMAT=json bash <(curl -fsSL ...)

# Show only errors (silent mode)
LOG_LEVEL_FILTER=ERROR bash <(curl -fsSL ...) 2>/dev/null
```

**Backup and restore**
```bash
sbx backup create --encrypt     # Encrypted backup
sbx backup restore <file>       # Restore from backup
sbx backup cleanup              # Delete old backups
```

**Export configs for different clients**
```bash
sbx export v2rayn reality       # v2rayN JSON
sbx export clash                # Clash YAML
sbx export uri all              # All URIs
sbx export qr ./qr-codes/       # QR code images
```

**Version selection**
```bash
# Latest stable (default)
bash <(curl -fsSL ...)

# Specific version
SINGBOX_VERSION=v1.10.7 bash <(curl -fsSL ...)

# Latest including pre-releases
SINGBOX_VERSION=latest bash <(curl -fsSL ...)
```

## Documentation

- **User Guide**: This README
- **Developer Guide**: [CLAUDE.md](CLAUDE.md) - Architecture, development workflow, coding standards
- **Changelog**: [CHANGELOG.md](CHANGELOG.md) - Version history and migration notes

## System Requirements

- Linux (Debian/Ubuntu/CentOS/RHEL/Fedora)
- Port 443 available (or will use fallback port 24443)
- Root or sudo access
- curl or wget installed

## File Locations

- Configuration: `/etc/sing-box/config.json`
- Service: `/etc/systemd/system/sing-box.service`
- Backups: `/var/backups/sbx/`
- Manager: `/usr/local/bin/sbx`

## License

MIT License - Based on official [sing-box](https://github.com/SagerNet/sing-box)
