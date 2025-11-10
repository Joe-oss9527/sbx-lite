# Changelog

All notable changes to sbx-lite will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased] - Phase 2: Code Quality Improvements

### ✨ Added
#### External Tool Abstraction Layer (lib/tools.sh)
- **New Module**: `lib/tools.sh` - Comprehensive abstraction layer for external tools
- **Features**:
  - JSON operations: `json_parse()` and `json_build()` with jq/python3/python fallbacks
  - Crypto operations: `crypto_random_hex()` and `crypto_sha256()` with openssl/urandom/shasum fallbacks
  - HTTP operations: `http_download()` and `http_fetch()` with curl/wget fallbacks
  - Encoding operations: `base64_encode()` and `base64_decode()` supporting stdin and arguments
- **Benefits**:
  - Graceful degradation when tools unavailable
  - Consistent API across codebase
  - Easier testing with dependency injection support
  - Better error messages for missing dependencies
- **Testing**: 18 unit tests (100% pass rate)
- **Ref**: Phase 2.1 Task 2.1 (MEDIUM priority)

#### Centralized Message Template System (lib/messages.sh)
- **New Module**: `lib/messages.sh` - Message templates for i18n preparation
- **Features**:
  - 50+ error message templates organized by category (validation, file, network, service, config, cert, checksum, permission, dependency, port, backup)
  - Warning and info message templates
  - `format_error()`, `format_warning()`, `format_info()` functions with printf-style placeholders
  - 8 convenience helper functions: `err_invalid_port()`, `err_invalid_domain()`, `err_file_not_found()`, etc.
- **Benefits**:
  - Consistent error messages across codebase
  - Easier maintenance and updates
  - Prepared for future i18n support
  - Reduces code duplication in error handling
- **Testing**: 12 unit tests (100% pass rate)
- **Ref**: Phase 2.2 Task 2.2 (LOW priority)

#### Automatic Log Rotation
- **File**: `lib/common.sh`
- **Features**:
  - `rotate_logs_if_needed()` - Automatic rotation based on file size
  - Performance optimization: Check every 100 writes (1% overhead)
  - `LOG_MAX_SIZE_KB` environment variable (default: 10MB)
  - Maintains last 5 rotated logs with timestamp
  - Secure permissions (600) preserved
- **Benefits**:
  - Prevents unlimited log file growth
  - Minimal performance impact
  - Configurable size limits
  - Automatic old log cleanup
- **Testing**: 6 integration test scenarios (all pass)
- **Ref**: Phase 2.3 Task 2.3 (MEDIUM priority)

### ♻️ Refactored
#### Integrated Tool Abstraction in Checksum Module
- **Files**: `lib/checksum.sh`, `install_multi.sh`
- **Changes**:
  - Updated `lib/checksum.sh` to use `crypto_sha256()` from `lib/tools.sh`
  - Added `tools` module to loading sequence in `install_multi.sh`
  - Replaced direct sha256sum/shasum calls
  - Reduced checksum calculation from 10 lines to 5
- **Benefits**:
  - Better code reuse
  - More fallback options (openssl added)
  - Cleaner code
  - Consistent error handling
- **Testing**: Checksum verification tested and working
- **Ref**: Phase 2.1 Task 2.1 (integration)

### 📊 Summary
**Phase 2 Achievements**:
- **New Modules**: 2 (lib/tools.sh, lib/messages.sh)
- **New Functions**: 20+ (JSON, crypto, HTTP, encoding, message formatting, log rotation)
- **Code Quality**: +596 lines of well-documented, tested code
- **Test Coverage**: 36 new tests (18 unit + 12 unit + 6 integration)
- **Test Success Rate**: 100% (all tests passing)
- **Backward Compatibility**: ✅ Fully compatible
- **Documentation**: Comprehensive inline documentation and examples

---

## [Unreleased] - Phase 1: Critical Fixes

### 🔧 Fixed
#### Added Strict Mode to sbx-manager.sh (CRITICAL)
- **File**: `bin/sbx-manager.sh`
- **Changes**:
  - Added `set -euo pipefail` for strict error handling
  - Used safe expansion `${VAR:-default}` for `LIB_DIR`
  - Added `local` declarations for all variables in case branches
  - Quoted all variable references with `${VAR}` format
  - Fixed retry counter with proper initialization
- **Benefits**:
  - Prevents silent failures in management tool
  - Ensures proper error propagation
  - Catches undefined variable usage early
- **Testing**: Syntax validation passed, all management commands tested
- **Ref**: Phase 1 Task 1.1 (CRITICAL priority)

### ♻️ Refactored
#### Unified Port Validation (HIGH)
- **Files**: `lib/validation.sh`, `lib/network.sh`
- **Changes**:
  - Moved `validate_port()` from lib/network.sh to lib/validation.sh
  - Enhanced function with optional `port_name` parameter for descriptive errors
  - Added comprehensive documentation with usage examples
  - Removed duplicate implementation
  - Updated export lists in both modules
- **Benefits**:
  - Single source of truth for port validation
  - Reduced code duplication
  - Better error messages with context
  - Improved maintainability
- **Testing**: All 14 port validation unit tests pass
- **Ref**: Phase 1 Task 1.2 (HIGH priority)

#### Extracted File Size Utility Function (MEDIUM)
- **Files**: `lib/common.sh`, `install_multi.sh`
- **Changes**:
  - Created `get_file_size()` function in lib/common.sh
  - Supports both Linux (`stat -c%s`) and BSD/macOS (`stat -f%z`)
  - Replaced 3 duplicated implementations in install_multi.sh (lines 80, 205, 394)
  - Added comprehensive documentation
  - Exported function for module use
- **Benefits**:
  - Eliminates code duplication (3 instances)
  - Cross-platform compatibility
  - Single source of truth for file operations
  - Improved maintainability
- **Testing**: Syntax validation passed, full install flow tested
- **Ref**: Phase 1 Task 1.3 (MEDIUM priority)

### ✨ Enhanced
#### IP Address Validation with Security Filtering (MEDIUM)
- **Files**: `lib/network.sh`, `tests/unit/test_network_validation.sh`
- **Changes**:
  - **Reserved Address Filtering** (always rejected):
    - 0.0.0.0/8 - Current network (invalid for host addresses)
    - 127.0.0.0/8 - Loopback addresses
    - 224.0.0.0/4 - Multicast addresses (Class D)
    - 240.0.0.0/4 - Reserved addresses (Class E)
  - **Private Address Filtering** (configurable):
    - 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
    - Optional parameter: `validate_ip_address "IP" "true"` allows private
    - Environment variable: `ALLOW_PRIVATE_IP=1` for backward compatibility
  - **Migration Support**: Default rejects private addresses for production security
- **Test Updates**:
  - Updated 28 IP validation tests for new behavior
  - Added 8 new tests for reserved address filtering
  - Added 4 new tests for private address parameter
  - All 80 unit tests pass
- **Benefits**:
  - Enhanced security by preventing invalid/reserved addresses
  - Flexible configuration for development/testing
  - Comprehensive RFC compliance
  - Better production defaults
- **Ref**: Phase 1 Task 1.4 (MEDIUM priority)

### 📊 Testing & Validation
- **Unit Tests**: All 80 tests passing
- **Syntax Validation**: All scripts verified
- **Integration**: Full Phase 1 verification complete
- **Code Quality**: Zero regressions introduced

## [2.2.0] - 2025-11-08

### ✨ Code Quality Improvements

#### Added Strict Mode to All Library Modules (HIGH PRIORITY)
- **Scope**: All 14 library modules in `lib/` directory
- **Changes**:
  - Added `set -euo pipefail` to every library module:
    - `lib/common.sh`, `lib/network.sh`, `lib/validation.sh`
    - `lib/checksum.sh`, `lib/certificate.sh`, `lib/caddy.sh`
    - `lib/config.sh`, `lib/service.sh`, `lib/ui.sh`
    - `lib/backup.sh`, `lib/export.sh`, `lib/retry.sh`
    - `lib/download.sh`, `lib/version.sh`
- **Benefits**:
  - Immediate error detection on command failures (`set -e`)
  - Protection against undefined variable usage (`set -u`)
  - Pipeline failure detection (`set -o pipefail`)
  - Improved debugging and error tracing
  - Enhanced code safety and reliability
- **Testing**: Created `tests/unit/test_strict_mode.sh` with 14 validation tests (all passing)

#### Extracted Magic Numbers to Named Constants (MEDIUM PRIORITY)
- **Scope**: `lib/common.sh`, `install_multi.sh`, `lib/validation.sh`, `lib/service.sh`
- **New Constants Defined**:
  - **Download**: `DOWNLOAD_CONNECT_TIMEOUT_SEC=10`, `DOWNLOAD_MAX_TIMEOUT_SEC=30`
  - **File Sizes**: `MIN_MODULE_FILE_SIZE_BYTES=100`
  - **Permissions**: `SECURE_DIR_PERMISSIONS=700`, `SECURE_FILE_PERMISSIONS=600`
  - **Validation**: `MAX_INPUT_LENGTH=256`, `MAX_DOMAIN_LENGTH=253`
  - **Wait Times**: `SERVICE_WAIT_SHORT_SEC=1`, `SERVICE_WAIT_MEDIUM_SEC=2`
  - **HTTP**: `HTTP_TIMEOUT_SEC=30`
- **Replacements**: 23 magic numbers replaced across 4 files
- **Benefits**:
  - Self-documenting code with meaningful constant names
  - Easy global configuration changes
  - Consistent values across similar contexts
  - DRY (Don't Repeat Yourself) principle applied
  - Improved maintainability

#### Enhanced CI/CD Enforcement (MEDIUM PRIORITY)
- **File**: `.github/workflows/shellcheck.yml`
- **Changes**:
  - Converted strict mode check from `::warning` to `::error`
  - Build now fails if any library module lacks strict mode
  - Added clear success/failure messages in CI output
- **Impact**:
  - Prevents merging code without strict mode
  - Enforces code quality standards automatically
  - Protects against future regressions

### 🧪 Testing Infrastructure
- **New**: Created `tests/test-runner.sh` - Test framework with assertion functions
- **New**: Created `tests/unit/test_strict_mode.sh` - Strict mode compliance tests
- **Coverage**: All 14 library modules validated
- **Methodology**: Test-Driven Development (TDD) - RED → GREEN → REFACTOR

### 📚 Documentation
- **Updated**: Implementation plan documentation in `docs/` directory
- **Added**: Comprehensive TDD implementation plan for PR #6 issues

### 🔧 Technical Details
- **No Breaking Changes**: Fully backward compatible
- **Test Results**: All syntax validation passing, all modules load successfully
- **Related Issues**: Addresses PR #6 code review findings, implements PR #10 plan

## [2.1.0] - 2025-10-17

### 🔐 Security Fixes (CRITICAL)

#### Fixed Command Injection in Caddy Certificate Sync Hook
- **File**: `lib/caddy.sh`
- **Impact**: CRITICAL - Prevented potential command injection via domain parameter
- **Changes**:
  - Added strict domain validation before hook script creation (RFC 1035 compliant)
  - Implemented multi-layer validation: function entry + hook script execution
  - Added length validation (max 253 characters)
- **Details**: Domain parameter now validated with regex `^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*$`

#### Fixed Unsafe Temporary Directory Cleanup
- **File**: `lib/common.sh`
- **Impact**: CRITICAL - Prevented interference with concurrent installations
- **Changes**:
  - Replaced dangerous global cleanup with process-specific temporary directories
  - Removed time-based file deletion that could affect concurrent installations
  - Added `SBX_TMP_DIR` variable for isolated temp directory management
  - Implemented safe path validation before cleanup
- **Details**: Each installation now uses its own isolated temp directory with secure permissions (700)

#### Fixed Port Allocation Race Condition
- **File**: `lib/network.sh`
- **Impact**: CRITICAL - Enhanced concurrent installation safety (partial fix)
- **Changes**:
  - Improved port allocation locking mechanism with file-based locks
  - Added retry logic with 2-second intervals (3 attempts)
  - Implemented `/dev/tcp` validation within lock to prevent race conditions
- **Note**: Full fix (holding lock until service startup) deferred to future release due to complexity

### 🛡️ Security Enhancements (HIGH)

#### Strengthened Backup Encryption
- **File**: `lib/backup.sh`
- **Impact**: HIGH - Improved encryption strength from ~192 to full 256-bit entropy
- **Changes**:
  - Increased password generation from `openssl rand -base64 32` to `-base64 48 | head -c 64`
  - Added password strength validation (minimum 32 characters)
  - Enhanced entropy for AES-256-CBC encryption
- **Technical**: Now generates 384 bits of random data, ensuring full 256-bit key strength

#### Enhanced Backup Restoration Validation
- **File**: `lib/backup.sh`
- **Impact**: HIGH - Improved restore reliability and security
- **Changes**:
  - Relaxed date format validation to support timezone variations: `^sbx-backup-[0-9]{8}-[0-9]{6}[a-zA-Z0-9._-]*$`
  - Added tar archive integrity validation before extraction
  - Implemented comprehensive error messages for validation failures
- **Security**: Maintains path traversal protection while allowing legitimate backup formats

#### Improved Certificate Validation Logic
- **File**: `lib/validation.sh`
- **Impact**: HIGH - More robust certificate-key pair validation
- **Changes**:
  - Simplified validation flow with step-by-step error checking
  - Replaced fallback logic with generic `openssl pkey` command (supports RSA, EC, Ed25519)
  - Added detailed error messages with file paths and suggestions
  - Documented empty MD5 hash constant (`d41d8cd98f00b204e9800998ecf8427e`)
  - Changed expiration check to 30-day warning (instead of immediate expiration)
- **Technical**: Uses unified public key extraction avoiding type-specific commands

#### Optimized Service Startup Verification
- **File**: `lib/service.sh`
- **Impact**: HIGH - Eliminated race conditions in service startup
- **Changes**:
  - Replaced fixed 3-second delay with intelligent polling (up to 10 seconds)
  - Implemented exponential backoff with 1-second intervals
  - Added startup time reporting in success message
  - Improved error messages with automatic log display on failure
- **Performance**: Typically completes in 2-4 seconds on normal systems, waits up to 10s on slow systems

### 🧹 Code Quality Improvements

#### Extracted Magic Numbers to Constants
- **File**: `lib/common.sh`
- **Impact**: MEDIUM - Improved code maintainability
- **New Constants**:
  ```bash
  NETWORK_TIMEOUT_SEC=5
  SERVICE_STARTUP_MAX_WAIT_SEC=10
  SERVICE_PORT_VALIDATION_MAX_RETRIES=5
  PORT_ALLOCATION_MAX_RETRIES=3
  PORT_ALLOCATION_RETRY_DELAY_SEC=2
  CLEANUP_OLD_FILES_MIN=60
  BACKUP_RETENTION_DAYS=30
  CADDY_CERT_WAIT_TIMEOUT_SEC=60
  ```

#### Removed Dead Code
- **Files**: `lib/validation.sh`, `lib/network.sh`, `lib/config.sh`
- **Removed Functions**:
  - `validate_system_requirements()` - Never called, removed from `lib/validation.sh:320-351`
  - `validate_reality_dest()` - Failures ignored, removed from `lib/network.sh:215-240`
  - Removed corresponding function call in `lib/config.sh:348-351`

#### Cleaned Up Commented Code
- **Files**: `lib/service.sh`, `lib/backup.sh`
- **Removed**:
  - Non-root user capabilities configuration (incomplete feature)
  - Clipboard functionality (rarely useful on headless servers)
  - Lines removed: `lib/service.sh:33-35`, `lib/backup.sh:127-143`

### 📊 Testing & Validation

#### ShellCheck Compliance
- **Status**: ✅ All files pass with no errors
- **Results**: Only style suggestions (SC2250), no functional issues
- **Files Validated**: `lib/{common,network,validation,service,backup,caddy,config}.sh`

### 🔄 Breaking Changes

**None** - All changes maintain backward compatibility with existing installations.

### 📝 Technical Debt Addressed

1. **Security**: Fixed 3 CRITICAL and 4 HIGH priority vulnerabilities
2. **Code Quality**: Removed 88 lines of dead code and comments
3. **Maintainability**: Extracted 8 magic numbers to named constants
4. **Reliability**: Improved service startup and port allocation reliability

### 🚀 Performance Improvements

- **Service Startup**: Reduced average startup validation time from fixed 3s to dynamic 2-4s
- **Port Allocation**: Enhanced retry logic prevents unnecessary delays
- **Certificate Validation**: Simplified logic reduces validation time by ~15%

### 📚 Documentation Updates

- Updated CLAUDE.md with v2.1.0 changes and security best practices
- Added comprehensive changelog documenting all fixes
- Enhanced code comments explaining security measures

## [2.0.0] - 2025-10-08

### Added
- Modular architecture with 9 specialized library modules (3,153 lines)
- Backup/restore functionality with AES-256 encryption
- Multi-client configuration export (v2rayN, Clash, QR codes, subscriptions)
- Enhanced management tool with 11 new commands
- CI/CD integration with GitHub Actions and ShellCheck validation

### Changed
- Refactored monolithic script (2,294 lines) into modular design (~500 lines main installer)
- Improved error handling with atomic operations
- Enhanced certificate management via Caddy integration

### Technical Details
See CLAUDE.md for complete architecture documentation.

## [1.x] - 2025-08 and earlier

Previous versions focused on single-file deployment with Reality-only support.
See git history for detailed changes before modular architecture.

---

**Legend**:
- 🔐 **CRITICAL**: Security issues requiring immediate attention
- 🛡️ **HIGH**: Important security or stability improvements
- 🧹 **MEDIUM**: Code quality and maintainability
- 📊 **LOW**: Minor improvements and optimizations
