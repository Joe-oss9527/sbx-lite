# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **sbx-lite**, a one-click bash deployment script for official sing-box proxy server. The project consists of a single comprehensive script (`install_multi.sh`) that supports three protocols: VLESS-REALITY (default), VLESS-WS-TLS (optional), and Hysteria2 (optional).

## Development Commands

### Testing Script Changes
```bash
# Test basic Reality-only installation (auto-detect IP)
bash install_multi.sh

# Test Reality with manual IP
DOMAIN=1.2.3.4 bash install_multi.sh

# Test Reality with domain
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

# Complete uninstall (stops service first, requires root)
sudo sbx uninstall
```

## Reality Protocol & IP Detection

### Reality-Only Mode Features
- **Zero Configuration**: No domain or certificate required
- **Auto IP Detection**: Automatically detects server public IP via multiple services
- **Direct IP Usage**: Client connects directly to IP address, no DNS resolution needed
- **SNI Masquerading**: Uses `www.cloudflare.com` as SNI for traffic camouflage
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

### Installation Flow
- `install_flow()` - Main entry point with interactive menu for existing installations
- `check_existing_installation()` - Detects existing sing-box and presents upgrade/reconfigure options
- `gen_materials()` - Handles DOMAIN/IP detection, generates Reality keypairs, UUIDs, short_ids (exactly 8 hex chars), passwords
- `get_public_ip()` - Auto-detects server public IP with timeout protection and validation
- `validate_ip_address()` - Enhanced IP validation with octet range and reserved address checks
- `write_config()` - Creates JSON configuration using `jq` with comprehensive error checking
- `setup_service()` - Creates systemd service and enables it
- `create_manager_script()` - Installs `/usr/local/bin/sbx-manager` and `/usr/local/bin/sbx` alias

### Security-Critical Functions
- `sanitize_input()` - Removes dangerous shell metacharacters from user input
- `cleanup()` - Secure cleanup function with `trap` integration for temporary file removal
- `safe_http_get()` - Network operations with timeout and retry protection
- `validate_cert_files()` - Certificate file validation with proper error handling

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

### Optional Variables (Reality-only mode works without any variables)
- `DOMAIN=your.domain.com` - Target domain or IP address
  - **Not required for Reality-only**: Script auto-detects server IP if omitted
  - **IP addresses supported**: `DOMAIN=1.2.3.4` enables Reality-only mode
  - **Domains enable full mode**: Can add WS-TLS and Hysteria2 with certificates

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
- **Enhanced Certificate Validation**: Expiry checks, key compatibility with proper modulus comparison
- **Secure IP Detection**: Multi-service redundancy with `timeout` protection and enhanced validation

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
- Binary: `/usr/local/bin/sing-box`
- Config: `/etc/sing-box/config.json` 
- Client info: `/etc/sing-box/client-info.txt` (persisted for `sbx info` command)
- Service: `/etc/systemd/system/sing-box.service`
- Certificates: `/etc/ssl/sbx/<domain>/fullchain.pem` and `privkey.pem`
- Management tools: `/usr/local/bin/sbx-manager` and `/usr/local/bin/sbx` (symlink)

## Bash Coding Standards & Security Best Practices

### Code Quality Standards
- Always use `set -euo pipefail` at script start
- Use existing logging functions: `msg()`, `warn()`, `err()`, `success()`, `die()`  
- Wrap all variables in quotes: `"$VARIABLE"` not `$VARIABLE`
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

## Client Compatibility Requirements
- Script generates sing-box-compatible Reality configurations
- v2rayN users must switch from Xray core to sing-box core in client settings
- Generated URIs include aliases: `#Reality-domain`, `#WS-TLS-domain`, `#Hysteria2-domain`
- Short IDs are 8 characters (sing-box limit), not 16 characters (Xray limit)

## Recent Critical Fixes & Improvements (2025-08)

### Major Enhancements
- **Reality Zero-Config Deployment**: Removed domain requirement for Reality-only mode, added auto IP detection
- **JSON Generation Overhaul**: Replaced string concatenation with `jq` for robust JSON generation
- **Enhanced Error Handling**: Added `trap`-based cleanup and comprehensive network retry logic
- **Input Validation Strengthening**: Added sanitization functions and comprehensive validation

### Security Hardening (Latest)
- **Command Injection Prevention**: Fixed unsafe shell globbing in cleanup functions
- **Secure Temporary Files**: All temp files now created with `mktemp` and proper permissions (600/700)
- **Enhanced IP Validation**: `validate_ip_address()` with octet range checks and reserved address filtering
- **Certificate Validation Fixes**: Fixed logic bugs in certificate-key matching verification
- **jq Error Handling**: All JSON generation operations now have explicit error checking
- **Version Comparison Bug Fix**: Corrected semantic version comparison algorithm
- **Timeout Protection**: Added `timeout` commands for network operations to prevent hangs

### Bug Fixes & Stability
- **Fresh Install Service Issue**: Fixed Hysteria2 not working after Fresh install by implementing proper service restart logic
- **Port Allocation Race Conditions**: Added post-allocation validation to prevent port conflicts
- **Configuration Atomicity**: Implemented atomic config file operations with validation before applying
- **Certificate Security**: Enhanced certificate validation with expiry warnings and key compatibility checks
- **Service Startup Verification**: Added retry logic and port listening validation after service start
- **Service Startup Timing Issue**: Fixed race condition where port validation occurred before service fully initialized (added 3-second delay)
- **Port Checking Logic Error**: Fixed setup_service() checking for Hysteria2 ports even in Reality-only mode
- **Management Script Local Variables**: Fixed incorrect use of 'local' keyword outside functions in sbx uninstall command
- **Undefined Variable Errors**: Fixed script failures due to unset variables in post-installation steps with proper ${VAR:-} syntax

### User Experience Improvements
- **Simplified Installation**: `bash install_multi.sh` now works without any parameters
- **Smart Mode Detection**: Automatic Reality-only vs full setup based on input type
- **Better Error Messages**: More informative validation and error reporting
- **Network Resilience**: Multiple IP detection services with fallback mechanisms

### Code Quality & Maintainability
- **Production-Grade Security**: All critical vulnerabilities identified in code review have been fixed
- **Comprehensive Error Handling**: Consistent error checking patterns throughout the script
- **Atomic Operations**: Enhanced file operations with proper rollback on failures
- **Input Sanitization**: Robust protection against shell injection attacks

## Troubleshooting & Debugging

### Common Installation Failures

#### "Script execution failed with exit code 1" after "Starting sing-box service..."
**Root Cause**: Race condition in service startup verification - port checking occurs before service fully initializes

**Symptoms**:
- Script shows `[*] Starting sing-box service...` then immediately fails
- sing-box service actually starts successfully (can be verified with `systemctl status sing-box`)
- Installation appears to fail but service is running

**Debug Method**:
```bash
# Check if service is actually running
systemctl status sing-box

# Check if configuration is valid
/usr/local/bin/sing-box check -c /etc/sing-box/config.json

# Check if client files were created (if not, script failed after service start)
ls -la /etc/sing-box/client-info.txt /usr/local/bin/sbx
```

**Solution**: Fixed in setup_service() by adding 3-second delay after service start and improving port checking logic for Reality-only vs full mode.

#### Management Script "local: can only be used in a function" Errors
**Root Cause**: Incorrect use of `local` keyword in sbx management script outside of function contexts

**Symptoms**:
```bash
/usr/local/bin/sbx: line 106: local: can only be used in a function
```

**Solution**: Remove `local` keywords from variable declarations in case statements - they should be regular script variables.

### Debugging Methodology

#### Adding Diagnostic Logging
When script fails mysteriously:
1. Add debug messages with `msg "[DEBUG] function_name: step description"`
2. Check exact failure point with timing information
3. Sometimes the debug logging itself reveals timing issues by adding small delays

#### Service Startup Verification
```bash
# Proper service validation with timing consideration
systemctl start sing-box
sleep 3  # Allow service to fully initialize
# Then check ports and status
```

#### Variable Safety Patterns
Use safe variable expansion to prevent undefined variable errors:
```bash
# Safe - provides fallback value
echo "Port: ${CHOSEN_PORT:-$DEFAULT_PORT}"

# Unsafe - fails with set -u if CHOSEN_PORT is unset
echo "Port: $CHOSEN_PORT"
```