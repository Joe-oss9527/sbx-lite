# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **sbx-lite**, a one-click bash deployment script for official sing-box proxy server. The project consists of a single comprehensive script (`install_multi.sh`) that supports three protocols: VLESS-REALITY (default), VLESS-WS-TLS (optional), and Hysteria2 (optional).

## Development Commands

### Testing Script Changes
```bash
# Test basic Reality-only installation
DOMAIN=test.domain.com bash install_multi.sh

# Test full installation with certificates  
DOMAIN=test.domain.com CERT_MODE=cf_dns CF_Token='token' bash install_multi.sh

# Test uninstall functionality
FORCE=1 bash install_multi.sh uninstall

# Validate configuration syntax
/usr/local/bin/sing-box check -c /etc/sing-box/config.json
```

### Management Commands (Post-Installation)
```bash
# View all URIs and configuration
sbx info

# Check service status and logs
sbx status
sbx log

# Service control
sbx restart
sbx start 
sbx stop

# Validate configuration
sbx check
```

## Code Architecture & Critical Functions

### Installation Flow
- `install_flow()` - Main entry point with interactive menu for existing installations
- `check_existing_installation()` - Detects existing sing-box and presents upgrade/reconfigure options
- `gen_materials()` - Generates Reality keypairs, UUIDs, short_ids (exactly 8 hex chars), passwords
- `write_config()` - Creates JSON configuration via string concatenation (not jq-dependent)
- `setup_service()` - Creates systemd service and enables it
- `create_manager_script()` - Installs `/usr/local/bin/sbx-manager` and `/usr/local/bin/sbx` alias

### Port Management Architecture
- `allocate_port()` - Implements retry logic (3 attempts, 2-second intervals) for port allocation
- Primary ports: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)  
- Fallback ports: 24443, 24444, 24445
- Fresh install mode stops existing service first to free ports, then waits up to 10 seconds for complete shutdown

### Certificate Integration
- `maybe_issue_cert()` - Routes to appropriate ACME method based on CERT_MODE
- `issue_cert_cf_dns()` - Cloudflare DNS-01 via acme.sh integration
- `issue_cert_http()` - Let's Encrypt HTTP-01 via acme.sh integration  
- Certificate files stored in `/etc/ssl/sbx/<domain>/`

## Environment Variables & Configuration

### Required Variables
- `DOMAIN=your.domain.com` - Target domain (must be set for all installations)

### Certificate Configuration
- `CERT_MODE=cf_dns` + `CF_Token='token'` - Cloudflare DNS-01 challenge
- `CERT_MODE=le_http` - Let's Encrypt HTTP-01 challenge (requires port 80 open)
- `CERT_FULLCHAIN=/path/fullchain.pem` + `CERT_KEY=/path/privkey.pem` - Use existing certificates

### Port Overrides (Optional)
- `REALITY_PORT=443` (default), `WS_PORT=8444` (default), `HY2_PORT=8443` (default)
- Fallback ports (24443, 24444, 24445) used automatically if primary ports occupied

## Critical Implementation Details

### Security & Validation Rules
- Short IDs must be exactly 8 hexadecimal characters (sing-box limitation, not Xray's 16-char limit)
- Use `[[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]]` pattern for validation
- Input validation with `[[ ! "$choice" =~ ^[1-6]$ ]]` prevents injection attacks
- Certificate files get 600 permissions and root:root ownership

### Configuration Generation Patterns
- Use `"$SB_BIN" generate reality-keypair` for Reality key generation (not openssl)
- JSON config built via string concatenation, not jq (reduces dependencies)
- Validate generated short_id immediately after creation with die() on failure
- Always use `openssl rand -hex 4` for 8-character short_ids (not -hex 8)

### Service Management Best Practices  
- Fresh install: Stop service → Wait 10s for shutdown → Check ports → Continue
- Use `systemctl is-active sing-box >/dev/null 2>&1` for status checks
- Port allocation: 3 retries with 2-second intervals before fallback
- Both primary and fallback ports must be validated before proceeding

### Installation Flow States
1. **Fresh install** - Stops service, backs up config to `.backup.YYYYMMDD_HHMMSS`, clean reinstall
2. **Upgrade binary only** - Sets `SKIP_CONFIG_GEN=1`, preserves existing configuration  
3. **Reconfigure** - Sets `SKIP_BINARY_DOWNLOAD=1`, regenerates configuration only
4. **Complete uninstall** - Removes binary, config, service, certificates, management scripts
5. **Show current config** - Displays existing config.json and returns to menu

## Key File Locations
- Binary: `/usr/local/bin/sing-box`
- Config: `/etc/sing-box/config.json` 
- Client info: `/etc/sing-box/client-info.txt` (persisted for `sbx info` command)
- Service: `/etc/systemd/system/sing-box.service`
- Certificates: `/etc/ssl/sbx/<domain>/fullchain.pem` and `privkey.pem`
- Management tools: `/usr/local/bin/sbx-manager` and `/usr/local/bin/sbx` (symlink)

## Bash Coding Standards
- Always use `set -euo pipefail` at script start
- Use existing logging functions: `msg()`, `warn()`, `err()`, `success()`, `die()`  
- Wrap all variables in quotes: `"$VARIABLE"` not `$VARIABLE`
- Use `[[ ]]` for conditionals, not `[ ]`
- Local variables in functions: `local var_name="$1"`
- Error handling: Check command success with `|| die "Error message"`

## Client Compatibility Requirements
- Script generates sing-box-compatible Reality configurations
- v2rayN users must switch from Xray core to sing-box core in client settings
- Generated URIs include aliases: `#Reality-domain`, `#WS-TLS-domain`, `#Hysteria2-domain`
- Short IDs are 8 characters (sing-box limit), not 16 characters (Xray limit)