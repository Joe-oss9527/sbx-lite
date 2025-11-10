# Code Improvement Implementation Checklist

**目标版本**: v2.2.0
**创建日期**: 2025-11-10
**状态**: 待实施

---

## 📋 Quick Reference

### Phase 1: Critical Fixes (Week 1) - 2-3小时
- [ ] **1.1** Add strict mode to sbx-manager.sh (30分钟)
- [ ] **1.2** Unify port validation in lib/validation.sh (1小时)
- [ ] **1.3** Extract file size utility function (45分钟)
- [ ] **1.4** Enhance IP address validation (1小时)

### Phase 2: Code Quality (Week 2-3) - 8-10小时
- [ ] **2.1** Create external tool abstraction layer (4小时)
- [ ] **2.2** Implement message templates (2小时)
- [ ] **2.3** Optimize log rotation (2小时)

### Phase 3: Architecture (Week 4-5) - 10-12小时
- [ ] **3.1** Split lib/common.sh module (6小时)
- [ ] **3.2** Implement config validation pipeline (4小时)
- [ ] **3.3** Implement dependency injection (6小时)

### Phase 4: Testing & Docs (Week 6) - 6-8小时
- [ ] **4.1** Implement code coverage tracking (4小时)
- [ ] **4.2** Enhance unit tests (4小时)
- [ ] **4.3** Create performance benchmarks (3小时)
- [ ] **4.4** Update documentation (2小时)

---

## 🎯 Daily Task Breakdown

### Week 1: Phase 1 Implementation

#### Day 1 (2小时)
```bash
# Morning: Task 1.1
[ ] Open bin/sbx-manager.sh
[ ] Add "set -euo pipefail" after shebang
[ ] Replace $VAR with ${VAR:-default} for all variables
[ ] Test: sbx status, sbx info, sbx backup list
[ ] Commit: "fix: add strict mode to sbx-manager.sh"

# Afternoon: Task 1.2 (Start)
[ ] Create validate_port() in lib/validation.sh
[ ] Add unit tests for port validation
[ ] Document function with examples
```

#### Day 2 (3小时)
```bash
# Morning: Task 1.2 (Finish)
[ ] Remove duplicate validate_port from lib/network.sh
[ ] Update all callers to use lib/validation.sh version
[ ] Run: bash tests/unit/test_port_allocation.sh
[ ] Commit: "refactor: unify port validation in lib/validation.sh"

# Afternoon: Task 1.3
[ ] Create get_file_size() in lib/common.sh
[ ] Replace 3 occurrences in install_multi.sh
[ ] Add unit tests
[ ] Test one-liner install
[ ] Commit: "refactor: extract file size utility function"
```

#### Day 3 (2小时)
```bash
# Task 1.4
[ ] Enhance validate_ip_address() in lib/validation.sh
[ ] Add reserved address checks (0.0.0.0, 127.x, 224.x, 240.x)
[ ] Add private address detection (10.x, 172.16-31.x, 192.168.x)
[ ] Create tests/unit/test_ip_validation.sh
[ ] Document ALLOW_PRIVATE_IP environment variable
[ ] Commit: "feat: enhance IP address validation with reserved checks"
```

#### Day 4-5 (4小时)
```bash
# Phase 1 Testing & Integration
[ ] Run: make check (lint, syntax, security)
[ ] Run: bash tests/test-runner.sh (all unit tests)
[ ] Test: DEBUG=1 bash install_multi.sh (full install)
[ ] Test: DOMAIN=8.8.8.8 bash install_multi.sh (IP mode)
[ ] Test: DOMAIN=example.com bash install_multi.sh (domain mode)
[ ] Update CHANGELOG.md with Phase 1 changes
[ ] Create PR: "Phase 1: Critical security and reliability fixes"
```

---

### Week 2-3: Phase 2 Implementation

#### Day 6-8 (12小时)
```bash
# Task 2.1: Tool Abstraction Layer
[ ] Create lib/tools.sh with module header
[ ] Implement json_parse() with jq/python3 fallback
[ ] Implement json_build() wrapper
[ ] Implement crypto_random_hex() with openssl/urandom
[ ] Implement crypto_sha256() with sha256sum/shasum fallback
[ ] Implement http_download() with curl/wget
[ ] Add unit tests: tests/unit/test_tools.sh
[ ] Update lib/config.sh to use tools.sh
[ ] Update lib/checksum.sh to use tools.sh
[ ] Update install_multi.sh module list
[ ] Test all abstracted functions
[ ] Commit: "feat: add external tool abstraction layer"
```

#### Day 9 (3小时)
```bash
# Task 2.2: Message Templates
[ ] Create lib/messages.sh
[ ] Define ERROR_MESSAGES associative array
[ ] Implement format_error() function
[ ] Create error helper functions (optional)
[ ] Add to module loading list
[ ] Document usage in CLAUDE.md
[ ] Commit: "feat: add message templates for i18n preparation"
```

#### Day 10 (3小时)
```bash
# Task 2.3: Log Rotation
[ ] Add rotate_logs_if_needed() to lib/common.sh
[ ] Implement call counter in _log_to_file()
[ ] Add LOG_MAX_SIZE_KB environment variable
[ ] Create tests/integration/test_log_rotation.sh
[ ] Test with large log generation
[ ] Document in CLAUDE.md environment variables section
[ ] Commit: "feat: implement automatic log rotation"
```

#### Day 11 (4小时)
```bash
# Phase 2 Testing & Integration
[ ] Run: make check
[ ] Run: bash tests/test-runner.sh
[ ] Test: LOG_FORMAT=json DEBUG=1 bash install_multi.sh
[ ] Test: LOG_FILE=/tmp/test.log bash install_multi.sh
[ ] Verify tool abstraction with mock services
[ ] Update CHANGELOG.md
[ ] Create PR: "Phase 2: Code quality improvements"
```

---

### Week 4-5: Phase 3 Implementation

#### Day 12-14 (12小时)
```bash
# Task 3.1: Module Splitting
[ ] Create lib/logging.sh (move logging functions)
[ ] Create lib/generators.sh (move generation functions)
[ ] Update lib/common.sh (remove moved functions, keep core)
[ ] Update all modules to source new dependencies
[ ] Update install_multi.sh module list: add logging, generators
[ ] Test each module individually: bash -n lib/*.sh
[ ] Run full test suite
[ ] Document deprecation plan
[ ] Commit: "refactor: split lib/common.sh into focused modules"
```

#### Day 15-16 (8小时)
```bash
# Task 3.2: Validation Pipeline
[ ] Create lib/config_validator.sh
[ ] Implement validate_config_pipeline()
[ ] Implement validate_json_syntax()
[ ] Implement validate_singbox_schema()
[ ] Implement validate_port_conflicts()
[ ] Implement validate_tls_config()
[ ] Implement validate_route_rules()
[ ] Integrate into lib/config.sh:write_config()
[ ] Add tests: tests/unit/test_config_validator.sh
[ ] Test with invalid configs
[ ] Commit: "feat: add configuration validation pipeline"
```

#### Day 17-18 (10小时)
```bash
# Task 3.3: Dependency Injection
[ ] Update get_public_ip() to support CUSTOM_IP_SERVICES
[ ] Update download functions to support mock URLs
[ ] Create environment variable documentation
[ ] Create tests/unit/test_dependency_injection.sh
[ ] Set up mock HTTP server for testing
[ ] Test with custom service endpoints
[ ] Commit: "feat: implement dependency injection for testability"
```

#### Day 19 (4小时)
```bash
# Phase 3 Testing & Integration
[ ] Run: make check
[ ] Run: bash tests/test-runner.sh
[ ] Test backward compatibility
[ ] Test with custom injected dependencies
[ ] Verify module loading performance
[ ] Update CHANGELOG.md
[ ] Create PR: "Phase 3: Architecture refinements"
```

---

### Week 6: Phase 4 Implementation

#### Day 20-21 (8小时)
```bash
# Task 4.1: Code Coverage
[ ] Create tests/coverage.sh
[ ] Implement track_coverage() function
[ ] Implement generate_coverage_report()
[ ] Add to Makefile as 'coverage' target
[ ] Run coverage on all modules
[ ] Document uncovered functions
[ ] Commit: "test: add code coverage tracking"

# Task 4.2: Enhanced Testing
[ ] Create tests/test_framework.sh
[ ] Implement assert_equals()
[ ] Implement assert_not_empty()
[ ] Implement assert_file_exists()
[ ] Implement print_test_summary()
[ ] Refactor existing tests to use new framework
[ ] Add 20+ new unit tests for uncovered functions
[ ] Commit: "test: enhance unit testing framework"
```

#### Day 22 (4小时)
```bash
# Task 4.3: Benchmarks
[ ] Create tests/benchmark.sh
[ ] Implement benchmark() function
[ ] Add benchmarks for: UUID gen, validation, JSON parsing
[ ] Add to Makefile as 'benchmark' target
[ ] Record baseline performance metrics
[ ] Commit: "test: add performance benchmarking"
```

#### Day 23-24 (6小时)
```bash
# Task 4.4: Documentation
[ ] Update CLAUDE.md with v2.2.0 changes
[ ] Create docs/UPGRADE_v2.2.md
[ ] Update README.md if needed
[ ] Document all new environment variables
[ ] Update module dependency diagram
[ ] Review all inline documentation
[ ] Commit: "docs: update for v2.2.0 release"
```

#### Day 25 (6小时)
```bash
# Final Integration & Release
[ ] Run: make check (should pass 100%)
[ ] Run: make coverage (target: ≥70%)
[ ] Run: make benchmark (record results)
[ ] Full integration test on clean VM
[ ] Test one-liner install: bash <(curl -fsSL ...)
[ ] Test all management commands
[ ] Update version in install_multi.sh
[ ] Create release notes
[ ] Merge all PRs to main branch
[ ] Tag release: git tag v2.2.0
```

---

## ✅ Verification Commands

### After Each Phase
```bash
# Syntax check all files
find lib bin -name "*.sh" -exec bash -n {} \;

# Run ShellCheck
make lint

# Run all tests
make check

# Coverage check (Phase 4+)
make coverage

# Integration test
DEBUG=1 bash install_multi.sh
```

### Before Final Release
```bash
# Clean environment test
docker run -it --rm ubuntu:22.04 bash
apt update && apt install -y curl
bash <(curl -fsSL https://raw.githubusercontent.com/.../install_multi.sh)

# Test all protocols
DOMAIN=test.example.com bash install_multi.sh

# Test management commands
sbx status
sbx info
sbx backup create
sbx export uri all
```

---

## 📊 Progress Tracking

### Completion Metrics
- **Phase 1**: ⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜ 0% (0/4 tasks)
- **Phase 2**: ⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜ 0% (0/3 tasks)
- **Phase 3**: ⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜ 0% (0/3 tasks)
- **Phase 4**: ⬜⬜⬜⬜⬜⬜⬜⬜⬜⬜ 0% (0/4 tasks)

**Overall Progress**: 0% (0/14 tasks completed)

### Quality Gates
- [ ] ShellCheck: 0 warnings
- [ ] Test Coverage: ≥70%
- [ ] Code Duplication: <2%
- [ ] All Tests: 100% pass rate
- [ ] Performance: No regression

---

## 🚨 Blockers & Issues

| Issue | Severity | Status | Resolution |
|-------|----------|--------|------------|
| - | - | - | - |

---

## 📝 Notes & Decisions

### Design Decisions
- **Module Splitting**: Decided to keep backward compatibility by maintaining deprecated functions for one version cycle
- **Tool Abstraction**: Using environment variables for dependency injection instead of complex DI framework
- **Testing**: Focusing on function-level coverage rather than line coverage for bash scripts

### Open Questions
- [ ] Should we support Python 2 fallbacks? (Decision: No, EOL since 2020)
- [ ] Minimum bash version? (Decision: 4.3+, released 2014)
- [ ] Should we add optional emoji in logs? (Decision: No, CLAUDE.md prohibits)

---

*Last Updated*: 2025-11-10
*Next Review*: After each phase completion
