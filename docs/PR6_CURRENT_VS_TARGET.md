# PR #6 Implementation: Current State vs Target State

**Visual Guide** - What needs to change

---

## Issue 1: Missing Strict Mode (HIGH PRIORITY)

### ❌ Current State

**File**: `lib/common.sh` (and 13 other modules)

```bash
#!/usr/bin/env bash
# lib/common.sh - Common utilities, global variables, and logging functions
# Part of sbx-lite modular architecture

# Prevent multiple sourcing
[[ -n "${_SBX_COMMON_LOADED:-}" ]] && return 0
readonly _SBX_COMMON_LOADED=1

#==============================================================================
# Global Constants
#==============================================================================
declare -r SB_BIN="/usr/local/bin/sing-box"
# ... rest of file
```

**Problem**: No error handling. Silent failures possible.

---

### ✅ Target State

```bash
#!/usr/bin/env bash
# lib/common.sh - Common utilities, global variables, and logging functions
# Part of sbx-lite modular architecture

# Strict mode for error handling and safety
set -euo pipefail

# Prevent multiple sourcing
[[ -n "${_SBX_COMMON_LOADED:-}" ]] && return 0
readonly _SBX_COMMON_LOADED=1

#==============================================================================
# Global Constants
#==============================================================================
declare -r SB_BIN="/usr/local/bin/sing-box"
# ... rest of file
```

**Benefits**:
- ✅ Exit immediately on errors (`-e`)
- ✅ Catch undefined variables (`-u`)
- ✅ Detect pipeline failures (`-o pipefail`)

---

## Issue 2: Magic Numbers (MEDIUM PRIORITY)

### ❌ Current State

**File**: `install_multi.sh`

```bash
# Line 39: Magic timeout values
if ! curl -fsSL --connect-timeout 10 --max-time 30 "${module_url}" -o "${module_file}"; then
    return 1
fi

# Line 62: Magic file size threshold
if [[ "${file_size}" -lt 100 ]]; then
    echo "FILE_TOO_SMALL"
    return 1
fi

# Line 291: Magic permission value
chmod 700 "${temp_lib_dir}"

# Line 826: Magic permission value
chmod 600 "$CLIENT_INFO"
```

**Problems**:
- ❌ What does `10` mean? Connection timeout? Retries?
- ❌ What does `100` mean? Bytes? Lines? Percentage?
- ❌ What does `700` mean? Why not 755 or 600?
- ❌ Hard to change all occurrences consistently
- ❌ No documentation of intent

---

### ✅ Target State

**File**: `lib/common.sh`

```bash
#==============================================================================
# Network Timeouts
#==============================================================================
# These timeouts protect against hanging network operations and ensure
# responsive failure handling.

# Maximum time to establish connection (seconds)
# Used by: curl --connect-timeout, wget --timeout
declare -r DOWNLOAD_CONNECT_TIMEOUT_SEC=10

# Maximum total time for download operation (seconds)
# Used by: curl --max-time, wget --timeout
declare -r DOWNLOAD_MAX_TIMEOUT_SEC=30

#==============================================================================
# File Validation Thresholds
#==============================================================================
# Security thresholds to detect incomplete downloads and malicious input.

# Minimum valid module file size (bytes)
# Any downloaded module smaller than this is considered corrupt
declare -r MIN_MODULE_FILE_SIZE_BYTES=100

#==============================================================================
# Security: File Permissions
#==============================================================================
# Strict permissions following principle of least privilege.

# Directory permissions (octal 700 = rwx------)
# Owner: read, write, execute
# Group: none
# Other: none
declare -r SECURE_DIR_PERMISSIONS=700

# File permissions (octal 600 = rw-------)
# Owner: read, write
# Group: none
# Other: none
declare -r SECURE_FILE_PERMISSIONS=600
```

**File**: `install_multi.sh`

```bash
# Line 39: Now uses documented constants
if ! curl -fsSL \
    --connect-timeout "${DOWNLOAD_CONNECT_TIMEOUT_SEC}" \
    --max-time "${DOWNLOAD_MAX_TIMEOUT_SEC}" \
    "${module_url}" -o "${module_file}"; then
    return 1
fi

# Line 62: Clear intent and easy to adjust
if [[ "${file_size}" -lt "${MIN_MODULE_FILE_SIZE_BYTES}" ]]; then
    echo "FILE_TOO_SMALL"
    return 1
fi

# Line 291: Self-documenting
chmod "${SECURE_DIR_PERMISSIONS}" "${temp_lib_dir}"

# Line 826: Consistent with policy
chmod "${SECURE_FILE_PERMISSIONS}" "$CLIENT_INFO"
```

**Benefits**:
- ✅ Self-documenting code
- ✅ Single source of truth
- ✅ Easy to adjust globally
- ✅ Clear security policy

---

## Issue 3: CI Enforcement (MEDIUM PRIORITY)

### ⚠️ Current State

**File**: `.github/workflows/shellcheck.yml` (lines 87-93)

```yaml
echo "Checking for missing set -euo pipefail..."
for script in lib/*.sh; do
  [[ -f "$script" ]] || continue
  if ! head -20 "$script" | grep -q 'set -'; then
    echo "::warning file=$script::Missing 'set -euo pipefail' or similar"
  fi
done
```

**Problems**:
- ⚠️ Only produces warnings
- ⚠️ Does not fail build
- ⚠️ Issues accumulate over time
- ⚠️ No enforcement of quality standards

---

### ✅ Target State

```yaml
echo "Checking for missing set -euo pipefail..."
STRICT_MODE_ERRORS=0
for script in lib/*.sh; do
  [[ -f "$script" ]] || continue
  if ! head -20 "$script" | grep -qE '^set -[euo]{3,5}$|^set -euo pipefail$'; then
    echo "::error file=$script,line=1::Missing 'set -euo pipefail'"
    ((STRICT_MODE_ERRORS++))
  fi
done

if [[ $STRICT_MODE_ERRORS -gt 0 ]]; then
  echo "::error::Found $STRICT_MODE_ERRORS file(s) without strict mode"
  exit 1
fi

echo "✓ All library modules have strict mode"
```

**Benefits**:
- ✅ Errors fail the build
- ✅ Prevents regressions
- ✅ Enforces quality standards
- ✅ Clear error messages

---

## Implementation Workflow Visualization

```
Current State                  Implementation Process              Target State
═════════════                  ══════════════════════             ════════════

14 modules                     Phase 1: Add Strict Mode           14 modules
WITHOUT strict mode    ─────>  • Write tests (RED)        ─────>  WITH strict mode
                               • Implement (GREEN)                 ✓ Error handling
❌ Silent failures              • Refactor & test                  ✓ Fail fast
❌ Undefined vars allowed                                          ✓ Pipeline safety
❌ Pipeline errors hidden      Phase 2: Extract Constants

Magic numbers          ─────>  • Write tests (RED)        ─────>  Named constants
scattered in code              • Define constants (GREEN)          ✓ lib/common.sh
                               • Replace usage                     ✓ Documented
❌ Hard to maintain            • Update docs                       ✓ Single source
❌ No documentation                                                ✓ Self-documenting
❌ Inconsistent values         Phase 3: CI Enforcement

CI warnings only       ─────>  • Update workflow          ─────>  CI errors block
                               • Test enforcement                  ✓ Quality gates
⚠️ Not blocking                • Add badges                       ✓ Prevents regressions
⚠️ Issues accumulate                                              ✓ Automated checks
                               Phase 4: Validation

No comprehensive       ─────>  • Run all tests            ─────>  Full test coverage
testing                        • Real installations               ✓ Unit tests
                               • Performance checks               ✓ Integration tests
⚠️ Regressions possible        • Documentation                    ✓ E2E tests
                                                                  ✓ Zero regressions
```

---

## Test Coverage Visualization

### Current Test Infrastructure

```
tests/
├── test-runner.sh                    ✅ Exists
├── test_module_loading.sh            ✅ Exists
├── test_retry.sh                     ✅ Exists
├── unit/
│   ├── test_checksum.sh              ✅ Exists
│   └── test_version_resolver.sh      ✅ Exists
└── integration/
    ├── test_checksum_integration.sh  ✅ Exists
    └── test_version_integration.sh   ✅ Exists
```

### Target Test Infrastructure

```
tests/
├── test-runner.sh                    ✅ Exists
├── test_module_loading.sh            ✅ Exists
├── test_retry.sh                     ✅ Exists
├── unit/
│   ├── test_checksum.sh              ✅ Exists
│   ├── test_version_resolver.sh      ✅ Exists
│   ├── test_strict_mode.sh           🆕 NEW (56 tests)
│   └── test_constants.sh             🆕 NEW (20+ tests)
├── integration/
│   ├── test_checksum_integration.sh  ✅ Exists
│   └── test_version_integration.sh   ✅ Exists
└── phase4_validation.sh              🆕 NEW (comprehensive)
```

---

## Code Quality Metrics

### Before Implementation

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| **Modules with strict mode** | 0/14 (0%) | 14/14 (100%) | ❌ |
| **Named constants** | ~20 | 40+ | ⚠️ |
| **Magic numbers** | 15+ | 0 | ❌ |
| **CI quality gates** | Warnings only | Errors | ⚠️ |
| **Test coverage** | ~70% | 90%+ | ⚠️ |
| **ShellCheck issues** | 0 (good!) | 0 | ✅ |
| **Code maintainability** | B+ | A | ⚠️ |

### After Implementation (Target)

| Metric | Current | Target | Status |
|--------|---------|--------|--------|
| **Modules with strict mode** | 14/14 (100%) | 14/14 (100%) | ✅ |
| **Named constants** | 40+ | 40+ | ✅ |
| **Magic numbers** | 0 | 0 | ✅ |
| **CI quality gates** | Errors | Errors | ✅ |
| **Test coverage** | 90%+ | 90%+ | ✅ |
| **ShellCheck issues** | 0 | 0 | ✅ |
| **Code maintainability** | A | A | ✅ |

---

## File Changes Summary

### Files to Modify

```
Modified Files (18 total):
═══════════════════════════════

Library Modules (14 files):
├── lib/common.sh              +3 lines (add strict mode + constants)
├── lib/network.sh             +3 lines (add strict mode)
├── lib/validation.sh          +3 lines (add strict mode)
├── lib/checksum.sh            +3 lines (add strict mode)
├── lib/certificate.sh         +3 lines (add strict mode)
├── lib/caddy.sh               +3 lines (add strict mode)
├── lib/config.sh              +3 lines (add strict mode)
├── lib/service.sh             +3 lines (add strict mode)
├── lib/ui.sh                  +3 lines (add strict mode)
├── lib/backup.sh              +3 lines (add strict mode)
├── lib/export.sh              +3 lines (add strict mode)
├── lib/retry.sh               +3 lines (add strict mode)
├── lib/download.sh            +3 lines (add strict mode)
└── lib/version.sh             +3 lines (add strict mode)

Main Scripts:
├── install_multi.sh           ~15 changes (use constants)

CI/CD:
├── .github/workflows/shellcheck.yml   ~30 lines (enforce)

Documentation:
├── CHANGELOG.md               +50 lines (v2.2.0 entry)
├── CLAUDE.md                  +30 lines (update constants)
└── README.md                  +10 lines (badges)
```

### New Files to Create

```
New Files (5 total):
════════════════════

Tests:
├── tests/unit/test_strict_mode.sh       NEW (200+ lines)
├── tests/unit/test_constants.sh         NEW (150+ lines)
└── tests/phase4_validation.sh           NEW (100+ lines)

Documentation:
├── docs/TDD_IMPLEMENTATION_PLAN.md      ✅ CREATED (2,239 lines)
├── docs/PR6_ANALYSIS_SUMMARY.md         ✅ CREATED (241 lines)
├── docs/PR6_CURRENT_VS_TARGET.md        ✅ THIS FILE
└── docs/RELEASE_NOTES_v2.2.0.md         NEW (template in plan)
```

---

## Quick Start Commands

### 1. Verify Current Issues

```bash
# Check which modules lack strict mode
echo "Checking strict mode compliance..."
for f in lib/*.sh; do
  printf "%-30s" "$f: "
  head -20 "$f" | grep -qE "^set -[euo]" && echo "✓ OK" || echo "✗ MISSING"
done

# Count magic numbers
echo ""
echo "Counting magic numbers..."
grep -rn '\b[0-9]\{2,\}\b' install_multi.sh lib/*.sh 2>/dev/null | \
  grep -vE '(#|readonly|declare -r)' | wc -l
```

**Expected output**:
```
Checking strict mode compliance...
lib/common.sh:                 ✗ MISSING
lib/network.sh:                ✗ MISSING
... (all 14 will show MISSING)

Counting magic numbers...
18
```

### 2. Read Implementation Details

```bash
# Quick summary (1 page)
cat docs/PR6_ANALYSIS_SUMMARY.md

# This visual guide
cat docs/PR6_CURRENT_VS_TARGET.md

# Full implementation plan (2,239 lines)
less docs/TDD_IMPLEMENTATION_PLAN.md
```

### 3. Start Implementation

```bash
# Create feature branch
git checkout -b implement-pr6-fixes

# Start with Phase 1: Strict Mode
# See docs/TDD_IMPLEMENTATION_PLAN.md for detailed steps
```

---

## Success Visualization

```
Implementation Progress Tracker
════════════════════════════════

Phase 1: Strict Mode                [░░░░░░░░░░] 0%  ← START HERE
  ├─ Stage 1.1: Tests               [░░░░░░░░░░] 0%
  ├─ Stage 1.2: Implementation      [░░░░░░░░░░] 0%
  ├─ Stage 1.3: Integration         [░░░░░░░░░░] 0%
  └─ Stage 1.4: Documentation       [░░░░░░░░░░] 0%

Phase 2: Constants                  [░░░░░░░░░░] 0%
  ├─ Stage 2.1: Tests               [░░░░░░░░░░] 0%
  ├─ Stage 2.2: Implementation      [░░░░░░░░░░] 0%
  └─ Stage 2.3: Documentation       [░░░░░░░░░░] 0%

Phase 3: CI Enforcement             [░░░░░░░░░░] 0%
  ├─ Stage 3.1: Workflow            [░░░░░░░░░░] 0%
  └─ Stage 3.2: Documentation       [░░░░░░░░░░] 0%

Phase 4: Validation                 [░░░░░░░░░░] 0%
  ├─ Stage 4.1: Test Suite          [░░░░░░░░░░] 0%
  ├─ Stage 4.2: Real Installation   [░░░░░░░░░░] 0%
  ├─ Stage 4.3: Performance         [░░░░░░░░░░] 0%
  └─ Stage 4.4: Release             [░░░░░░░░░░] 0%

Overall Progress:                   [░░░░░░░░░░] 0%


After completion:
════════════════════════════════

Phase 1: Strict Mode                [██████████] 100% ✓
Phase 2: Constants                  [██████████] 100% ✓
Phase 3: CI Enforcement             [██████████] 100% ✓
Phase 4: Validation                 [██████████] 100% ✓

Overall Progress:                   [██████████] 100% ✓

🎉 READY FOR v2.2.0 RELEASE
```

---

## Questions?

**Quick Reference**: [PR6_ANALYSIS_SUMMARY.md](./PR6_ANALYSIS_SUMMARY.md)
**Full Details**: [TDD_IMPLEMENTATION_PLAN.md](./TDD_IMPLEMENTATION_PLAN.md)
**Project Guidelines**: [../CLAUDE.md](../CLAUDE.md)

**Ready to start?** Follow Phase 1 in the implementation plan!
