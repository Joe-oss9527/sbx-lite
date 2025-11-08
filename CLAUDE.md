# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Quick Navigation

**Core Reference**:
- [Development Commands](#development-commands) - Testing, validation, management commands
- [Modular Architecture](#modular-architecture-v20) - 11 library modules structure
- [Critical Implementation Details](#critical-implementation-details) - Security rules, patterns, compliance

**Configuration**:
- [sing-box 1.12.0 Standards](#sing-box-1120-configuration-standards) - Modern configuration patterns
- [Environment Variables](#environment-variables--configuration) - Optional configuration variables
- [Critical Configuration Notes](#critical-configuration-notes) - IPv6 issue and key rules

**Development**:
- [Code Architecture](#code-architecture--critical-functions) - Key functions and flow
- [Bash Coding Standards](#bash-coding-standards--security-best-practices) - Quality and security requirements
- [Troubleshooting](#troubleshooting) - Quick diagnostics and common issues

---

## Project Overview

This is **sbx-lite**, a one-click bash deployment script for official sing-box proxy server. The project features a **modular architecture (v2.0)** with 11 specialized library modules and a streamlined main installer (`install_multi.sh`) that supports three protocols: VLESS-REALITY (default), VLESS-WS-TLS (optional), and Hysteria2 (optional).

### Architecture Highlights
- **Modular Design**: 11 focused library modules (3,523 lines) in `lib/` directory
- **Streamlined Installer**: Main script reduced from 2,294 to ~500 lines
- **Enhanced Features**: Backup/restore, multi-client export, CI/CD integration
- **Production-Grade**: ShellCheck validation, automated testing, comprehensive error handling

## Development Commands

### Testing Script Changes

#### 🚨 MANDATORY Validation Steps (Execute After EVERY Configuration Change)
```bash
# 1. Validate configuration syntax (MUST show no warnings/errors)
/usr/local/bin/sing-box check -c /etc/sing-box/config.json

# 2. Verify configuration content (check key sections)
cat /etc/sing-box/config.json | head -30

# 3. Check service status and restart if needed
systemctl status sing-box
# If service is running, restart to apply changes:
systemctl restart sing-box && sleep 3 && systemctl status sing-box

# 4. Monitor logs for errors (run for 10-15 seconds)
journalctl -u sing-box -f
```

#### Full Integration Testing
```bash
# Test basic Reality-only installation (auto-detect IP)
bash install_multi.sh

# Test Reality with manual IP
DOMAIN=1.2.3.4 bash install_multi.sh

# Test Reality with domain
DOMAIN=test.domain.com bash install_multi.sh

# Test full installation with automatic certificates (Caddy)
DOMAIN=test.domain.com bash install_multi.sh

# Test uninstall functionality
FORCE=1 bash install_multi.sh uninstall

# Test reconfiguration (preserves binary)
bash install_multi.sh
# Choose option 3) Reconfigure
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

# Complete uninstall (stops service first, requires root)
sudo sbx uninstall

# Backup and restore operations
sbx backup create --encrypt    # Create encrypted backup
sbx backup list                # List available backups
sbx backup restore <file>      # Restore from backup

# Export client configurations
sbx export v2rayn reality      # Export v2rayN JSON config
sbx export clash               # Export Clash YAML config
sbx export uri all             # Export all share URIs
sbx export qr ./qr-codes/      # Generate QR code images
sbx export subscription        # Generate subscription link
```

## Modular Architecture (v2.0)

The project follows a clean modular architecture with clear separation of concerns:

### Library Modules (`lib/` directory)

1. **lib/common.sh** (308 lines) - Global utilities and logging
   - Constants: File paths, default ports, fallback ports
   - Color definitions and initialization
   - Logging functions: `msg()`, `warn()`, `err()`, `success()`, `die()`
   - Core utilities: `generate_uuid()`, `generate_reality_keypair()`, `have()`, `need_root()`
   - UUID generation with multiple fallback methods
   - Secure temporary file handling

2. **lib/network.sh** (242 lines) - Network operations
   - `get_public_ip()` - Multi-service IP detection with timeout protection
   - `allocate_port()` - Port allocation with retry logic (3 attempts, 2s intervals)
   - `detect_ipv6_support()` - IPv6 capability detection
   - `safe_http_get()` - HTTP operations with timeout and retry
   - `port_in_use()` - Port occupancy checking
   - Network interface detection

3. **lib/validation.sh** (331 lines) - Input validation and security
   - `sanitize_input()` - Remove shell metacharacters
   - `validate_domain()` - Domain format and length validation
   - `validate_ip_address()` - Enhanced IP validation with octet range checks
   - `validate_cert_files()` - Certificate file validation
   - `validate_env_vars()` - Environment variable validation
   - `validate_menu_choice()`, `validate_yes_no()` - User input validation

4. **lib/checksum.sh** (200 lines) - SHA256 binary verification ⭐ NEW
   - `verify_file_checksum()` - Generic file SHA256 verification
   - `verify_singbox_binary()` - sing-box specific binary verification
   - Downloads official `.sha256sum` files from GitHub releases
   - Supports both `sha256sum` and `shasum` tools
   - Case-insensitive checksum comparison
   - Graceful degradation when checksums unavailable
   - Fatal error on verification failure to prevent compromised installations

5. **lib/certificate.sh** (102 lines) - Caddy-based certificate management
   - `maybe_issue_cert()` - Automatic certificate issuance via Caddy
   - `check_cert_expiry()` - Certificate expiration checking
   - Automatic certificate mode detection for domains
   - Certificate-key compatibility verification
   - Integration with Caddy for Let's Encrypt certificates

6. **lib/caddy.sh** (429 lines) - Caddy automatic TLS management
   - `caddy_install()` - Install/upgrade Caddy binary from GitHub
   - `caddy_setup_auto_tls()` - Configure Caddy for automatic HTTPS
   - `caddy_setup_cert_sync()` - Sync certificates from Caddy to sing-box
   - `caddy_wait_for_cert()` - Wait for certificate issuance with timeout
   - `caddy_create_renewal_hook()` - Automatic certificate renewal hooks
   - `caddy_uninstall()` - Clean Caddy removal
   - Non-conflicting port configuration (8445 for HTTPS cert management)
   - Systemd service integration with automatic startup
   - Daily certificate sync via systemd timer

7. **lib/config.sh** (330 lines) - sing-box configuration generation
   - `create_base_config()` - Base configuration with DNS settings
   - `create_reality_inbound()` - VLESS-REALITY inbound configuration
   - `create_ws_inbound()` - VLESS-WS-TLS inbound configuration
   - `create_hysteria2_inbound()` - Hysteria2 inbound configuration
   - `add_route_config()` - Modern route rules (sing-box 1.12.0+)
   - `add_outbound_config()` - Outbound configuration with TCP Fast Open
   - `write_config()` - Complete JSON generation with jq
   - Atomic configuration writes with validation

8. **lib/service.sh** (230 lines) - systemd service management
   - `create_service_file()` - Generate systemd unit file
   - `setup_service()` - Install and start service with validation
   - `validate_port_listening()` - Port verification with retries
   - `check_service_status()` - Service status checking
   - `restart_service()`, `stop_service()`, `reload_service()` - Service control
   - `remove_service()` - Clean service uninstallation
   - `show_service_logs()` - Log viewing utilities

9. **lib/ui.sh** (310 lines) - User interface and interaction
   - `show_logo()`, `show_sbx_logo()` - ASCII art banners
   - `show_existing_installation_menu()` - Interactive upgrade menu
   - `prompt_menu_choice()`, `prompt_yes_no()` - User prompts with validation
   - `prompt_input()`, `prompt_password()` - Secure input handling
   - `show_spinner()`, `show_progress()` - Progress indicators
   - `show_config_summary()`, `show_installation_summary()` - Information display
   - `show_error()` - Error display with context and suggestions

10. **lib/backup.sh** (291 lines) - Backup and restore functionality
   - `backup_create()` - Create backups with optional AES-256 encryption
   - `backup_restore()` - Restore from encrypted/unencrypted backups
   - `backup_list()` - List all available backups with details
   - `backup_cleanup()` - Auto-cleanup of backups older than 30 days
   - PBKDF2 key derivation for encryption
   - Integrity verification on restore

11. **lib/export.sh** (345 lines) - Client configuration export
   - `export_v2rayn_json()` - v2rayN/v2rayNG JSON format
   - `export_nekoray_json()` - NekoRay JSON format
   - `export_clash_yaml()` - Clash/Clash Meta YAML format
   - `export_uri()` - Share URIs (vless://, hysteria2://)
   - `export_qr_codes()` - QR code image generation
   - `export_subscription()` - Base64-encoded subscription links
   - Multi-protocol support (Reality, WS-TLS, Hysteria2)

### Main Components

- **install_multi.sh** (~583 lines) - Main installer orchestrating all modules
  - **Smart module loading** with automatic download for one-liner installations
  - `_load_modules()` function (lines 23-96): Intelligent module detection and auto-download
    - Detects missing `lib/` directory for remote installations
    - Downloads 11 modules from GitHub to temporary directory
    - Supports both curl and wget with timeout protection
    - Secure temporary file handling with automatic cleanup
  - Installation flow coordination
  - Upgrade and reconfiguration scenarios
  - Uninstallation flow
  - Preserved backward compatibility
  - **Deployment flexibility**: Works both locally (development) and remotely (production)
  - **Module list**: common, retry, download, network, validation, **checksum**, certificate, caddy, config, service, ui, backup, export

- **bin/sbx-manager.sh** (357 lines) - Enhanced management tool
  - Service management commands
  - Configuration display
  - Backup operations (create, list, restore, cleanup)
  - Export operations (v2rayn, clash, uri, qr, subscription)
  - Module integration with graceful fallback

### CI/CD Infrastructure

- **GitHub Actions** - Automated quality checks
  - ShellCheck static analysis (`.github/workflows/shellcheck.yml`)
  - Syntax validation across all scripts
  - Code style enforcement
  - Security scanning

- **Makefile** - Local development commands
  - `make check` - Run all validation
  - `make lint` - ShellCheck analysis
  - `make syntax` - Bash syntax validation
  - `make security` - Security checks

- **.shellcheckrc** - ShellCheck configuration
  - Enable all checks with selective disables
  - SC1090 disabled for dynamic module loading

### Module Loading Pattern

```bash
# All modules use guard variables to prevent re-sourcing
[[ -n "${_SBX_COMMON_LOADED:-}" ]] && return 0
readonly _SBX_COMMON_LOADED=1

# Modules explicitly source their dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
source "${SCRIPT_DIR}/network.sh"

# Functions are exported for use in other contexts
export -f msg warn err success die
```

## Reality Protocol & IP Detection

### Reality-Only Mode Features
- **Zero Configuration**: No domain or certificate required
- **Auto IP Detection**: Automatically detects server public IP via multiple services
- **Direct IP Usage**: Client connects directly to IP address, no DNS resolution needed
- **SNI Masquerading**: Uses `www.microsoft.com` as SNI for traffic camouflage
- **No Certificate Dependency**: Bypasses traditional TLS certificate requirements

### Installation Modes
1. **Auto-detect Mode**: `bash install_multi.sh` (detects IP automatically)
2. **IP Specification**: `DOMAIN=1.2.3.4 bash install_multi.sh` (Reality-only)
3. **Domain Mode**: `DOMAIN=example.com bash install_multi.sh` (enables full setup)
4. **Full Setup**: Domain + certificate parameters (Reality + WS-TLS + Hysteria2)

### IP Detection Architecture
- **Service Redundancy**: ipify.org, icanhazip.com, ifconfig.me, ipinfo.io
- **Timeout Control**: 5-second timeout per service
- **Error Handling**: Falls back to manual input on detection failure
- **IPv4 Validation**: Regex validation of detected IP addresses

## Code Architecture & Critical Functions

### Installation Flow (install_multi.sh)
- `_load_modules()` - **Smart module loader** (NEW: 2025-10-17)
  - Automatically detects execution context (local vs remote)
  - Downloads missing modules from GitHub for one-liner installations
  - Creates secure temporary directory with 700 permissions
  - Implements timeout protection (10s connection, 30s download per module)
  - Supports curl and wget with graceful fallback
  - Automatic cleanup via `trap` on script exit
  - Downloads 10 modules: common, network, validation, certificate, caddy, config, service, ui, backup, export
- `install_flow()` - Main entry point orchestrating all installation steps
- `check_existing_installation()` - Detects existing installations and presents upgrade menu (uses `lib/ui.sh`)
- `gen_materials()` - Handles DOMAIN/IP detection, generates Reality keypairs, UUIDs, short_ids, passwords
- `download_singbox()` - Downloads and installs latest sing-box binary
- `save_client_info()` - Saves configuration to `/etc/sing-box/client-info.txt`
- `install_manager_script()` - Installs management tools and library modules
- `uninstall_flow()` - Complete removal with confirmation

### Security-Critical Functions (lib/validation.sh, lib/common.sh)
- `sanitize_input()` - Removes dangerous shell metacharacters from user input (lib/validation.sh)
- `cleanup()` - Secure cleanup function with `trap` integration for temporary file removal (lib/common.sh)
- `safe_http_get()` - Network operations with timeout and retry protection (lib/network.sh)
- `validate_cert_files()` - Certificate file validation with proper error handling (lib/validation.sh)
- `validate_domain()` - Domain format validation with length limits (lib/validation.sh)
- `validate_ip_address()` - Enhanced IP validation with octet range checks (lib/validation.sh)

### Network Operations (lib/network.sh)
- `get_public_ip()` - Auto-detects server public IP with timeout protection and validation
- `allocate_port()` - Implements retry logic (3 attempts, 2-second intervals) for port allocation
- `detect_ipv6_support()` - IPv6 capability detection and configuration
- `port_in_use()` - Port occupancy checking
- Primary ports: 443 (Reality), 8444 (WS-TLS), 8443 (Hysteria2)
- Fallback ports: 24443, 24444, 24445

### Configuration Generation (lib/config.sh)
- `write_config()` - Complete sing-box JSON configuration generation using `jq`
- `create_base_config()` - Base configuration with DNS settings (IPv4-only or dual-stack)
- `create_reality_inbound()` - VLESS-REALITY inbound with XTLS-RPRX-Vision
- `create_ws_inbound()` - VLESS-WS-TLS inbound configuration
- `create_hysteria2_inbound()` - Hysteria2 protocol configuration
- `add_route_config()` - Modern route rules with `action: "sniff"` (sing-box 1.12.0+)
- `add_outbound_config()` - Outbound configuration with TCP Fast Open
- Atomic configuration writes with validation before applying

### Service Management (lib/service.sh)
- `setup_service()` - Creates systemd service, validates config, starts service
- `create_service_file()` - Generates systemd unit file with proper dependencies
- `validate_port_listening()` - Port verification with retries (up to 5 attempts)
- `check_service_status()` - Service status checking
- `restart_service()` - Restart with configuration validation
- `stop_service()` - Graceful shutdown with timeout
- `remove_service()` - Clean service uninstallation

### Certificate Integration (lib/certificate.sh, lib/caddy.sh)
- `maybe_issue_cert()` - Automatic certificate issuance when domain is provided
- Certificate files stored in `/etc/ssl/sbx/<domain>/`
- Certificate expiry checking and validation support
- **Caddy Integration** (lib/caddy.sh):
  - `caddy_install()` - Installs latest Caddy from GitHub releases
  - `caddy_setup_auto_tls()` - Configures Caddy for automatic HTTPS on port 8445
  - `caddy_setup_cert_sync()` - Syncs certificates from Caddy to sing-box directory
  - `caddy_wait_for_cert()` - Waits for Let's Encrypt certificate issuance (60s timeout)
  - `caddy_create_renewal_hook()` - Daily systemd timer for certificate sync
  - Caddy runs on dedicated ports to avoid conflicts with sing-box:
    - Port 80: HTTP (ACME HTTP-01 challenge)
    - Port 8445: HTTPS (certificate management only)
    - Port 8080: Fallback handler
  - sing-box uses standard ports for proxy traffic:
    - Port 443: VLESS-REALITY
    - Port 8444: VLESS-WS-TLS
    - Port 8443: Hysteria2

### User Interface (lib/ui.sh)
- `show_logo()` - Display application banner
- `show_existing_installation_menu()` - Interactive upgrade/reconfigure menu
- `prompt_yes_no()`, `prompt_input()` - User input prompts with validation
- `show_config_summary()` - Display configuration summary
- `show_installation_summary()` - Post-installation information
- `show_error()` - Error display with context and suggestions

### Backup & Export (lib/backup.sh, lib/export.sh)
- `backup_create()` - Create backups with optional AES-256 encryption (lib/backup.sh)
- `backup_restore()` - Restore from encrypted/unencrypted backups (lib/backup.sh)
- `export_v2rayn_json()` - v2rayN/v2rayNG configuration export (lib/export.sh)
- `export_clash_yaml()` - Clash/Clash Meta configuration export (lib/export.sh)
- `export_uri()` - Generate share URIs for client import (lib/export.sh)
- `export_qr_codes()` - Generate QR code images (lib/export.sh)

## Environment Variables & Configuration

### Optional Variables (Reality-only mode works without any variables)
- `DOMAIN=your.domain.com` - Target domain or IP address
  - **Not required for Reality-only**: Script auto-detects server IP if omitted
  - **IP addresses supported**: `DOMAIN=1.2.3.4` enables Reality-only mode
  - **Domains enable full mode**: Can add WS-TLS and Hysteria2 with certificates

### Version Management (Optional) ⭐ NEW
- **Version Selection**:
  - `SINGBOX_VERSION=stable` - Latest stable release (default, no pre-releases)
  - `SINGBOX_VERSION=latest` - Absolute latest release (including beta/alpha)
  - `SINGBOX_VERSION=v1.10.7` - Specific version with 'v' prefix
  - `SINGBOX_VERSION=1.10.7` - Specific version (auto-prefixed with 'v')
  - `SINGBOX_VERSION=v1.11.0-beta.1` - Pre-release version
- **Default**: Uses `stable` if not specified
- **Case Insensitive**: `STABLE`, `LATEST`, `stable`, `latest` all work
- **GitHub Token** (optional): `GITHUB_TOKEN=ghp_xxx` for higher API rate limits

**Examples**:
```bash
# Latest stable (default)
bash install_multi.sh

# Explicit stable
SINGBOX_VERSION=stable bash install_multi.sh

# Latest including pre-releases
SINGBOX_VERSION=latest bash install_multi.sh

# Specific version
SINGBOX_VERSION=v1.10.7 bash install_multi.sh
SINGBOX_VERSION=1.10.7 bash install_multi.sh  # Auto-prefixed

# Pre-release
SINGBOX_VERSION=v1.11.0-beta.1 bash install_multi.sh
```

### Certificate Configuration
- **Automatic Mode** (default when domain is provided): Uses Caddy for Let's Encrypt HTTP-01 challenge
- `CERT_MODE=caddy` - Explicitly use Caddy for automatic TLS (default for domain-based installations)
- `CERT_FULLCHAIN=/path/fullchain.pem` + `CERT_KEY=/path/privkey.pem` - Use existing certificates
- **Port Requirements**: Port 80 must be open for HTTP-01 ACME challenge verification

### Port Overrides (Optional)
- **sing-box Ports**:
  - `REALITY_PORT=443` (default), `WS_PORT=8444` (default), `HY2_PORT=8443` (default)
  - Fallback ports (24443, 24444, 24445) used automatically if primary ports occupied
- **Caddy Ports** (for certificate management):
  - `CADDY_HTTP_PORT=80` (default) - HTTP and ACME HTTP-01 challenge
  - `CADDY_HTTPS_PORT=8445` (default) - HTTPS certificate management only
  - `CADDY_FALLBACK_PORT=8080` (default) - Fallback handler

### Security Configuration (Optional)
- **Binary Verification**:
  - `SKIP_CHECKSUM=1` - Skip SHA256 checksum verification (NOT recommended)
  - **Default**: Checksum verification enabled automatically
  - **Security**: Downloads official `.sha256sum` files from GitHub releases
  - **Tools**: Supports both `sha256sum` and `shasum` utilities
  - **Behavior**: Gracefully degrades if checksum files unavailable (with warning)
  - **Fatal on mismatch**: Installation aborts if checksums don't match

## Critical Implementation Details

### Security & Validation Rules
- Short IDs must be exactly 8 hexadecimal characters (sing-box limitation, not Xray's 16-char limit)
- Use `[[ "$SID" =~ ^[0-9a-fA-F]{1,8}$ ]]` pattern for validation
- **Enhanced Input Sanitization**: `sanitize_input()` function removes shell metacharacters (`;&|`$()`)
- **Command Injection Protection**: Input validation with `[[ ! "$choice" =~ ^[1-6]$ ]]` prevents injection attacks
- **Robust Domain Validation**: Length limits (253 chars), format checks, reserved name filtering
- **Enhanced IP Address Validation**: `validate_ip_address()` with octet range checks and reserved address filtering
- **Secure File Permissions**: Certificate files get 600 permissions, config files 600, temp dirs 700
- **Secure Temporary Files**: All temporary files created with `mktemp` and secure permissions
- **Certificate Validation**: Proper certificate-key matching verification with modulus comparison

### Configuration Generation Patterns
- Use `"$SB_BIN" generate reality-keypair` for Reality key generation (not openssl)
- **JSON config built via `jq`** for robust generation and type safety with comprehensive error checking
- **All jq operations have explicit error handling**: Each jq command checks for success and calls `die()` on failure
- Validate generated short_id immediately after creation with die() on failure
- Always use `openssl rand -hex 4` for 8-character short_ids (not -hex 8)
- **ATOMIC CONFIG WRITES**: Use secure temporary files (`mktemp`) and validation before applying
- **🚨 MANDATORY POST-GENERATION VALIDATION**: After every config change, MUST run complete validation (see Development Commands section)
- **Enhanced Certificate Validation**: Expiry checks, key compatibility with proper modulus comparison
- **Secure IP Detection**: Multi-service redundancy with `timeout` protection and enhanced validation
- **sing-box 1.12.0+ DNS Configuration**: Use explicit DNS servers with `type: "local"` format and global `dns.strategy` instead of deprecated `domain_strategy` in outbounds

### sing-box 1.12.0 Compliance Rules (⚠️ CRITICAL FOR IPv6 ISSUE PREVENTION)
- **NEVER use deprecated inbound fields**: `sniff`, `sniff_override_destination`, `domain_strategy`
- **🚨 NEVER use deprecated outbound fields**: `domain_strategy` (use global `dns.strategy` instead) - **THIS CAUSES IPv6 CONNECTION FAILURES**
- **ALWAYS include route configuration**: Required for sniffing and DNS handling
- **Dynamic route rules**: Adapt inbound list based on enabled protocols (Reality-only vs full mode)
- **🚨 IPv6 dual-stack**: Always use `listen: "::"` for dual-stack support (sing-box 1.12.0 standard) - **NEVER use "0.0.0.0"**
- **Security parameters**: Include `max_time_difference: "1m"` in REALITY configuration
- **Optimized logging**: Default to `warn` level with timestamps enabled
- **🚨 DNS Strategy Configuration**: Use `dns.strategy: "ipv4_only"` for IPv4-only networks instead of deprecated outbound options - **CRITICAL FOR PREVENTING IPv6 ERRORS**

### Service Management Best Practices  
- Fresh install: Stop service → Wait 10s for shutdown → Check ports → Continue
- Use `systemctl is-active sing-box >/dev/null 2>&1` for status checks
- Port allocation: 3 retries with 2-second intervals before fallback
- Both primary and fallback ports must be validated before proceeding
- **CRITICAL**: Service restart required after config changes (see setup_service() function)
- Post-allocation port validation prevents race conditions (see gen_materials() function)
- **Enhanced Error Handling**: `trap cleanup EXIT INT TERM` for automatic cleanup with secure temp file removal
- **Network Operations**: Retry logic with timeout protection for download failures
- **Secure Cleanup**: Use `find` with time limits instead of shell globbing for temporary file cleanup

### Installation Flow States
1. **Fresh install** - Stops service, backs up config to `.backup.YYYYMMDD_HHMMSS`, clean reinstall
2. **Upgrade binary only** - Sets `SKIP_CONFIG_GEN=1`, preserves existing configuration  
3. **Reconfigure** - Sets `SKIP_BINARY_DOWNLOAD=1`, regenerates configuration only
4. **Complete uninstall** - Removes binary, config, service, certificates, management scripts
5. **Show current config** - Displays existing config.json and returns to menu

## Key File Locations

### Runtime Files
- Binary: `/usr/local/bin/sing-box`
- Config: `/etc/sing-box/config.json`
- Client info: `/etc/sing-box/client-info.txt` (persisted for `sbx info` command)
- Service: `/etc/systemd/system/sing-box.service`
- Certificates: `/etc/ssl/sbx/<domain>/fullchain.pem` and `privkey.pem`

### Management Tools
- Manager script: `/usr/local/bin/sbx-manager`
- Manager symlink: `/usr/local/bin/sbx`
- Library modules: `/usr/local/lib/sbx/*.sh` (9 modules installed during setup)

### Backup & Data
- Backup directory: `/var/backups/sbx/`
- Backup files: `sbx-backup-YYYYMMDD-HHMMSS.tar.gz[.enc]`
- Backup retention: 30 days (configurable via `sbx backup cleanup`)

## Official Documentation Access (Git Submodule)

This project includes the official sing-box repository as a git submodule for easy access to the latest documentation, configuration examples, and source code reference.

### Submodule Location
- **Path**: `docs/sing-box-official/`
- **Contains**: Complete official sing-box repository
- **Key Resources**:
  - Documentation: `docs/sing-box-official/docs/`
  - Configuration Examples: `docs/sing-box-official/test/config/`
  - Source Code: `docs/sing-box-official/protocol/`, `docs/sing-box-official/option/`
  - Release Configs: `docs/sing-box-official/release/config/`

### Submodule Management Commands
```bash
# Initialize and update submodule (after cloning this repository)
git submodule update --init --recursive

# Update submodule to latest official version
git submodule update --remote docs/sing-box-official

# Check submodule status
git submodule status

# Update all submodules to latest
git submodule update --remote --merge
```

### Key Documentation Paths
- **Listen Configuration**: `docs/sing-box-official/docs/configuration/shared/listen/`
- **Inbound Configuration**: `docs/sing-box-official/docs/configuration/inbound/`
- **VLESS Documentation**: `docs/sing-box-official/docs/configuration/inbound/vless/`
- **Reality Configuration**: `docs/sing-box-official/docs/configuration/shared/tls/`
- **Migration Guide**: `docs/sing-box-official/docs/migration.md`

### Configuration Reference Examples
- **VLESS-Reality**: `docs/sing-box-official/test/config/vless-server.json`
- **System Service**: `docs/sing-box-official/release/config/sing-box.service`
- **Example Configurations**: `docs/sing-box-official/release/config/config.json`

### Using Submodule for Development
```bash
# View official configuration examples
ls docs/sing-box-official/test/config/

# Read official documentation
cat docs/sing-box-official/docs/configuration/inbound/vless/index.md

# Check latest migration requirements
cat docs/sing-box-official/docs/migration.md

# Reference systemd service configuration
cat docs/sing-box-official/release/config/sing-box.service
```

This ensures you always have access to the most up-to-date official documentation and can reference official configuration examples when modifying this deployment script.

## Bash Coding Standards & Security Best Practices

### Code Quality Standards
- Always use `set -euo pipefail` at script start
- Use existing logging functions: `msg()`, `warn()`, `err()`, `success()`, `die()`
- Wrap all variables in quotes: `"$VARIABLE"` not `$VARIABLE`
- **Strict mode variable references**: Always use safe expansion `${VAR:-default}` for constants and readonly variables
  - Example: `${LOG_LEVEL:-warn}` instead of `$LOG_LEVEL`
  - Prevents "unbound variable" errors in strict mode (`set -u`)
  - Apply to all readonly constants from `lib/common.sh`: `SERVICE_STARTUP_MAX_WAIT_SEC`, `BACKUP_RETENTION_DAYS`, `CLEANUP_OLD_FILES_MIN`, etc.
  - Also use for indirect variable expansion: `${!var_name:-}` instead of `${!var_name}`
- Use `[[ ]]` for conditionals, not `[ ]`
- Local variables in functions: `local var_name="$1"`
- Error handling: Check command success with `|| die "Error message"`

### Security Requirements
- **Input Validation**: All user input MUST be validated before use
- **Temporary Files**: Use `mktemp` with secure permissions (600 for files, 700 for directories)
- **Command Injection**: Never use unvalidated input in shell commands
- **Privilege Escalation**: Run with minimum required privileges
- **Error Information**: Don't leak sensitive information in error messages
- **Network Operations**: Always use timeout protection
- **JSON Generation**: Use `jq` with explicit error checking, never string concatenation
- **Cleanup**: Use `trap` for reliable cleanup on exit/interrupt
- **Character Encoding**: Never use Chinese characters in script output - use only English to ensure compatibility with terminals that don't support Unicode display

## Client Compatibility Requirements
- Script generates sing-box-compatible Reality configurations
- v2rayN users must switch from Xray core to sing-box core in client settings
- Generated URIs include aliases: `#Reality-domain`, `#WS-TLS-domain`, `#Hysteria2-domain`
- Short IDs are 8 characters (sing-box limit), not 16 characters (Xray limit)

## sing-box 1.12.0 Configuration Standards

### Current Implementation (Fully Compliant)
- **Modern DNS Configuration**: Using explicit DNS servers with 1.12.0+ format (`type: "local"`) instead of implicit configuration
- **Default Domain Resolver**: Configured `route.default_domain_resolver` for 1.14.0 compatibility
- **Modern Route Rules**: Using `action: "sniff"` and `action: "hijack-dns"` for traffic handling
- **Global DNS Strategy**: Using `dns.strategy: "ipv4_only"` for IPv4-only networks instead of deprecated outbound options
- **Dual-Stack Listen**: Always using `listen: "::"` for optimal network support
- **Auto Interface Detection**: Enabled `auto_detect_interface: true` to prevent routing loops

### Performance & Security Features
- **Log Level Optimization**: Default `warn` level with timestamps enabled
- **Anti-Replay Protection**: `max_time_difference: "1m"` in REALITY configuration
- **TCP Fast Open**: Enabled by default for reduced connection latency (~5-10% improvement)

### Configuration Structure (1.12.0+)
```json
{
  "log": { "level": "warn", "timestamp": true },
  "dns": {
    "servers": [
      {
        "type": "local",
        "tag": "dns-local"
      }
    ],
    "strategy": "ipv4_only"  // IPv4-only networks
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "in-reality",
      "listen": "::",  // IPv4/IPv6 dual-stack
      "users": [{ "uuid": "UUID", "flow": "xtls-rprx-vision" }],
      "tls": {
        "reality": {
          "max_time_difference": "1m"  // Anti-replay protection
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct",
      "tcp_fast_open": true  // Performance optimization
    },
    { "type": "block", "tag": "block" }
  ],
  "route": {
    "rules": [
      { "inbound": ["in-reality"], "action": "sniff" },
      { "protocol": "dns", "action": "hijack-dns" }
    ],
    "auto_detect_interface": true,
    "default_domain_resolver": {
      "server": "dns-local"  // 1.14.0 compatibility
    }
  }
}
```

## Recent Updates

### Latest Version: v2.1.0 (2025-10-17)
**Focus**: Security hardening and stability improvements

**Key Improvements**:
- Fixed 7 critical/high-priority security vulnerabilities
- Enhanced backup encryption to full 256-bit entropy
- Improved service startup with intelligent polling (2-10s adaptive)
- Added domain validation to prevent command injection
- Removed 88 lines of dead code, extracted 8 magic number constants
- All changes backward compatible

**For detailed release notes**, see `CHANGELOG.md`

### Architecture Evolution
- **v2.1.0** (2025-10-17): Security audit and stability hardening
- **v2.0.0** (2025-10-08): Modular architecture with 9 library modules
- **v1.x** (2025-08): Single-file deployment, Reality-only support

## Critical Configuration Notes

### IPv6 Connection Issue (sing-box 1.12.0+)

**Symptom**: "network unreachable" errors on IPv4-only servers

**Root Cause**: Deprecated `domain_strategy` in outbounds causes IPv6 connection attempts

**Solution**: Use global DNS strategy (1.12.0+ compliant)
```json
{
  "dns": {
    "servers": [{"type": "local", "tag": "dns-local"}],
    "strategy": "ipv4_only"  // For IPv4-only servers
  },
  "inbounds": [{"listen": "::"}],  // Dual-stack listen
  "outbounds": [{"type": "direct"}]  // NO domain_strategy field
}
```

**Key Rules**:
- Use `dns.strategy: "ipv4_only"` for IPv4-only networks
- Use `listen: "::"` for dual-stack (NEVER "0.0.0.0")
- Remove deprecated `domain_strategy` from outbounds
- Configure `route.default_domain_resolver` for 1.14.0 compatibility

## Troubleshooting

### Quick Diagnostics
```bash
# Verify service status
systemctl status sing-box

# Validate configuration
/usr/local/bin/sing-box check -c /etc/sing-box/config.json

# Check logs for errors
journalctl -u sing-box -n 50

# Verify port listening
ss -lntp | grep -E ':(443|8443|8444)'
```

### Common Issues

**Service fails to start**: Check config validation and logs above

**Port conflicts**: Script automatically uses fallback ports (24443, 24444, 24445) if primary ports occupied

**"unbound variable" errors in strict mode**:
- **Symptom**: Script fails with `variable: unbound variable` errors (e.g., `LOG_LEVEL: unbound variable`)
- **Root cause**: Readonly constants referenced without default values in `set -euo pipefail` strict mode
- **Quick fix**: Use safe expansion `${VAR:-default}` instead of `$VAR`
- **Affected files**: `lib/config.sh`, `lib/service.sh`, `lib/backup.sh`, `lib/common.sh`
- **See**: [Bash Coding Standards](#bash-coding-standards--security-best-practices) section for complete guidelines and examples

**Timing issues**: Service startup uses intelligent polling (up to 10s) to handle slow systems