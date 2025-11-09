# Root Cause Analysis & Fix Plan: One-Liner Installation Issues

**Date**: 2025-11-09
**Issue**: `sbx info` doesn't show URIs and `sbx qr` command missing after one-liner installation

---

## Root Cause Identified ✅

### Problem Summary

When users install via one-liner command (e.g., `bash <(curl -L https://...)`), they get a **degraded version** of `sbx-manager` that:
- ❌ `sbx info` only shows raw client-info.txt (no URI display, no field validation)
- ❌ `sbx qr` command doesn't exist
- ❌ No `export`, `backup`, or other advanced commands
- ❌ Only 3 basic commands work: info, status, restart

### Technical Root Cause

**File**: `install_multi.sh`
**Function**: `_load_modules()` (lines 300-398) and `install_manager_script()` (lines 894-965)

**Issue Flow**:

1. **Module Download** (lines 300-360):
   ```bash
   # _load_modules() downloads ONLY lib/ directory modules
   local modules=(common retry download network validation checksum version
                  certificate caddy config service ui backup export)

   # Downloads these to ${SCRIPT_DIR}/lib/*.sh
   # Does NOT download bin/sbx-manager.sh ❌
   ```

2. **Manager Installation** (lines 898-965):
   ```bash
   local manager_template="${SCRIPT_DIR}/bin/sbx-manager.sh"

   if [[ -f "$manager_template" ]]; then
       # Full version: 412 lines, all features ✅
       cp "$manager_template" /usr/local/bin/sbx-manager
       # ... install lib modules to /usr/local/lib/sbx/
   else
       # ❌ FALLBACK: File not found in one-liner install
       warn "Manager template not found, creating basic version..."

       # Creates minimal 9-line version:
       cat > /usr/local/bin/sbx-manager <<'EOF'
   #!/bin/bash
   case "$1" in
       info) [[ -f /etc/sing-box/client-info.txt ]] && cat /etc/sing-box/client-info.txt ;;
       status) systemctl status sing-box ;;
       restart) systemctl restart sing-box ;;
       *) echo "Usage: sbx {info|status|restart}"; exit 1 ;;
   esac
   EOF
   fi
   ```

### Comparison: Full vs Fallback Version

| Feature | Full Version (bin/sbx-manager.sh) | Fallback Version (One-liner) |
|---------|-----------------------------------|------------------------------|
| **File Size** | 412 lines | 9 lines |
| **URI Display in `sbx info`** | ✅ Yes (lines 144, 161, 166) | ❌ No (just cats file) |
| **Field Validation** | ✅ Yes (checks PUBLIC_KEY, UUID, etc.) | ❌ No validation |
| **Invalid URI Detection** | ✅ Yes (warns about empty params) | ❌ No detection |
| **`sbx qr` Command** | ✅ Yes (lines 180-226) | ❌ Command doesn't exist |
| **`sbx export` Commands** | ✅ Yes (v2rayn, clash, uri, qr, sub) | ❌ Command doesn't exist |
| **`sbx backup` Commands** | ✅ Yes (create, list, restore, cleanup) | ❌ Command doesn't exist |
| **Help Documentation** | ✅ Yes (comprehensive --help) | ❌ Basic usage only |
| **Module Integration** | ✅ Yes (loads lib/*.sh modules) | ❌ No module loading |
| **QR Code Support** | ✅ Yes (inline + export) | ❌ No QR support |

### Why This Went Unnoticed

1. **Local Development**: Developers have `bin/` directory, so full version is always installed
2. **Testing Gap**: One-liner installation not tested frequently
3. **Silent Degradation**: Script shows warning but continues (line 963):
   ```bash
   warn "  ⚠ Basic manager installed (template not found)"
   ```
4. **Functional Core**: Basic commands (info, status, restart) still work, hiding the issue

---

## Reproduction Steps

### Test 1: One-Liner Installation (Simulated)

```bash
# Simulate one-liner install by removing bin/ directory
cd /tmp
git clone https://github.com/Joe-oss9527/sbx-lite.git test-install
cd test-install
rm -rf bin/  # Simulate one-liner (no bin/ directory)

# Run installation
sudo bash install_multi.sh

# Check installed manager version
cat /usr/local/bin/sbx-manager
# Expected: Will show 9-line fallback version ❌

# Try to use features
sbx info     # Shows raw client-info.txt, no URIs ❌
sbx qr       # Command not found or shows usage error ❌
sbx export   # Shows usage error ❌
sbx --help   # Shows minimal help ❌
```

### Test 2: Normal Installation (With bin/)

```bash
# With bin/ directory present
cd /tmp
git clone https://github.com/Joe-oss9527/sbx-lite.git normal-install
cd normal-install
ls -la bin/sbx-manager.sh  # File exists ✅

sudo bash install_multi.sh

cat /usr/local/bin/sbx-manager
# Expected: Will show full 412-line version ✅

sbx info     # Shows URIs, validation, QR hints ✅
sbx qr       # Works (if qrencode installed) ✅
sbx export   # Works ✅
sbx --help   # Full documentation ✅
```

---

## Fix Plan

### Solution: Download `bin/sbx-manager.sh` in One-Liner Install

**Approach**: Modify `_load_modules()` to also download `bin/sbx-manager.sh`

### Implementation Options

#### Option 1: Add to Module Download List (RECOMMENDED)

**Files to Modify**: `install_multi.sh` (lines 300-360)

**Changes**:
```bash
# Current (line 307-308)
if [[ ! -d "${SCRIPT_DIR}/lib" ]]; then
    echo "[*] One-liner install detected, downloading required modules..."

# After downloading lib modules, download bin/sbx-manager.sh
# Add new function call after line 344

    # Download bin/sbx-manager.sh for one-liner install
    echo "  Downloading sbx-manager script..."
    mkdir -p "${SCRIPT_DIR}/bin"

    local manager_url="${github_repo}/bin/sbx-manager.sh"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --connect-timeout 10 --max-time 30 \
            "${manager_url}" -o "${SCRIPT_DIR}/bin/sbx-manager.sh"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=30 "${manager_url}" \
            -O "${SCRIPT_DIR}/bin/sbx-manager.sh"
    else
        echo "ERROR: Neither curl nor wget available"
        exit 1
    fi

    # Validate downloaded file
    if [[ ! -f "${SCRIPT_DIR}/bin/sbx-manager.sh" ]]; then
        echo "ERROR: Failed to download sbx-manager.sh"
        exit 1
    fi

    # Check file size (should be >10KB for full version)
    local mgr_size
    mgr_size=$(stat -c%s "${SCRIPT_DIR}/bin/sbx-manager.sh" 2>/dev/null || \
               stat -f%z "${SCRIPT_DIR}/bin/sbx-manager.sh" 2>/dev/null || echo "0")

    if [[ "${mgr_size}" -lt 5000 ]]; then
        echo "ERROR: Downloaded sbx-manager.sh is too small (${mgr_size} bytes)"
        echo "Expected: >5000 bytes (full version is ~15KB)"
        exit 1
    fi

    # Validate bash syntax
    if ! bash -n "${SCRIPT_DIR}/bin/sbx-manager.sh" 2>/dev/null; then
        echo "ERROR: Invalid bash syntax in sbx-manager.sh"
        exit 1
    fi

    echo "  ✓ sbx-manager.sh downloaded (${mgr_size} bytes)"
fi
```

**Pros**:
- ✅ Simple implementation
- ✅ Reuses existing download logic
- ✅ Minimal code changes
- ✅ Easy to test

**Cons**:
- ⚠ Separate download (not parallelized with modules)
- ⚠ Slightly slower (one additional HTTP request)

#### Option 2: Integrated Parallel Download

**Changes**: Create unified download system for both lib/ and bin/ files

**Pros**:
- ✅ Faster (parallel download)
- ✅ More elegant architecture

**Cons**:
- ❌ More complex changes
- ❌ Higher risk
- ❌ Longer development time

**Recommendation**: Use Option 1 for quick fix, consider Option 2 for future refactoring

---

## Implementation Plan

### Phase 1: Quick Fix (Option 1) - PRIORITY: HIGH

**Timeline**: 30 minutes

**Steps**:

1. **Modify `_load_modules()` function** (after line 344):
   - Add bin/sbx-manager.sh download logic
   - Add validation (file size, syntax check)
   - Add success message

2. **Update fallback warning** (line 950):
   - Change from generic warning to error with instructions
   - This should never happen now, but keep as safety net

3. **Test locally**:
   ```bash
   # Remove bin/ to simulate one-liner
   rm -rf bin/
   bash install_multi.sh

   # Verify full manager installed
   grep -c "sbx qr" /usr/local/bin/sbx-manager  # Should find matches
   sbx --help | wc -l  # Should be >50 lines
   sbx info  # Should show URIs
   ```

4. **Test actual one-liner** (if possible):
   ```bash
   bash <(curl -L https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/install_multi.sh)
   ```

### Phase 2: Enhanced Validation - PRIORITY: MEDIUM

**Timeline**: 1 hour

**Enhancements**:

1. **Add version check**:
   - Verify downloaded sbx-manager.sh matches expected version
   - Compare checksums or version strings

2. **Better error messages**:
   - Provide download URL in error messages
   - Suggest manual download as fallback

3. **Retry logic**:
   - Retry download on failure (2-3 attempts)
   - Try multiple mirrors if available

### Phase 3: Testing & Documentation - PRIORITY: HIGH

**Timeline**: 1 hour

**Tasks**:

1. **Create test script**: `tests/test_oneliner_install.sh`
   ```bash
   #!/bin/bash
   # Test one-liner installation

   # Setup: Remove bin/ to simulate one-liner
   # Execute: Run install_multi.sh
   # Verify: Check all commands work
   #   - sbx info shows URIs
   #   - sbx qr available (even if qrencode missing)
   #   - sbx export available
   #   - sbx backup available
   #   - Manager file size >10KB
   ```

2. **Update CLAUDE.md**:
   - Document one-liner installation behavior
   - Add troubleshooting section
   - Note about fallback version (should never happen)

3. **Update README**:
   - Emphasize one-liner installation is fully supported
   - List features available after installation

---

## Verification Checklist

After implementing fix, verify:

- [ ] One-liner install downloads bin/sbx-manager.sh
- [ ] Downloaded file size >5KB (full version)
- [ ] Bash syntax validation passes
- [ ] `/usr/local/bin/sbx-manager` is full version (not fallback)
- [ ] `sbx info` displays URIs with validation
- [ ] `sbx qr` command exists (checks for qrencode)
- [ ] `sbx export` commands work
- [ ] `sbx backup` commands work
- [ ] `sbx --help` shows full documentation
- [ ] Warning "Basic manager installed" never appears
- [ ] Fallback version only used if download fails (error case)

---

## Risk Assessment

### Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Download failure | LOW | MEDIUM | Keep fallback version as safety net |
| Network timeout | MEDIUM | LOW | Set reasonable timeout (30s) |
| Syntax error in downloaded file | LOW | HIGH | Validate bash syntax before install |
| File corruption | LOW | MEDIUM | Check file size, validate content |
| GitHub API rate limit | LOW | MEDIUM | Use raw.githubusercontent.com (no API) |

### Safety Measures

1. **Fallback Still Available**: If download fails, fallback version still works
2. **Syntax Validation**: Bash -n check before installing
3. **File Size Check**: Ensure >5KB (full version is ~15KB)
4. **Atomic Installation**: Use temp file + mv (existing pattern)
5. **Error Messages**: Clear errors with actionable instructions

---

## Expected Outcomes

### Before Fix (Current State)

```bash
$ bash <(curl -L https://.../install_multi.sh)
...
[WARN] Manager template not found, creating basic version...
[WARN]   ⚠ Basic manager installed (template not found)

$ sbx info
DOMAIN=1.2.3.4
UUID=xxx-xxx-xxx
PUBLIC_KEY=xxx
# No URIs, no validation ❌

$ sbx qr
Usage: sbx {info|status|restart}  # qr not available ❌

$ sbx --help
Usage: sbx {info|status|restart}  # Minimal help ❌
```

### After Fix (Expected State)

```bash
$ bash <(curl -L https://.../install_multi.sh)
...
  Downloading sbx-manager script...
  ✓ sbx-manager.sh downloaded (15234 bytes)
...
  ✓ Management commands installed: sbx-manager, sbx
  ✓ Library modules installed to /usr/local/lib/sbx/

$ sbx info
=== sing-box Configuration ===
Domain    : 1.2.3.4
...
INBOUND   : VLESS-REALITY  443/tcp
  PublicKey = xxx
  Short ID  = xxx
  UUID      = xxx
  URI       = vless://xxx@1.2.3.4:443?...  ✅

Commands:
  sbx qr         - Show QR codes (requires: apt install qrencode)  ✅
  sbx export qr  - Save QR code images (requires qrencode)

$ sbx qr
[ERR] qrencode not installed. Install with: apt install qrencode  ✅
# (Command exists, just needs qrencode)

$ sbx --help
sbx-manager - sing-box management tool

Usage:
  sbx <command> [options]

Service Management:
  status              Show service status
  ...
# Full 80+ line help documentation ✅
```

---

## Monitoring & Rollback Plan

### Monitoring

After deployment, monitor for:
1. Installation success rate (should be ~100%)
2. Fallback version usage (should be 0%)
3. User reports of missing features
4. Download failures from GitHub

### Rollback Plan

If critical issues discovered:

1. **Immediate**: Revert `_load_modules()` changes
2. **Fallback**: Fallback version still provides basic functionality
3. **Communication**: Document known issue, manual workaround
4. **Alternative**: Provide full script as single file (no modules)

### Manual Workaround (If Needed)

Users can manually download and install full manager:

```bash
# Manual fix for degraded installation
curl -fsSL https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/bin/sbx-manager.sh \
    -o /usr/local/bin/sbx-manager
chmod 755 /usr/local/bin/sbx-manager

# Download lib modules
mkdir -p /usr/local/lib/sbx
cd /usr/local/lib/sbx
for module in common retry download network validation checksum version \
              certificate caddy config service ui backup export; do
    curl -fsSL "https://raw.githubusercontent.com/Joe-oss9527/sbx-lite/main/lib/${module}.sh" \
        -o "${module}.sh"
done
chmod 644 /usr/local/lib/sbx/*.sh

# Verify
sbx --help
sbx info
```

---

## Summary

**Root Cause**: `bin/sbx-manager.sh` not downloaded in one-liner install → fallback version used → missing URI display and QR features

**Fix**: Download `bin/sbx-manager.sh` alongside lib modules in `_load_modules()`

**Impact**:
- ✅ One-liner installations will have full features
- ✅ All users get URI display in `sbx info`
- ✅ All users get `sbx qr` command
- ✅ Consistent behavior across all installation methods

**Timeline**:
- Phase 1 (Quick Fix): 30 minutes
- Phase 2 (Validation): 1 hour
- Phase 3 (Testing): 1 hour
- **Total**: 2.5 hours

**Risk**: LOW (Fallback version still available, syntax validation, file size checks)

---

**Ready to Implement**: YES ✅

Next step: Implement Phase 1 quick fix
