# Makefile for sbx-lite development

.PHONY: all check test lint syntax security install-hooks clean help

# Default target
all: check

# Help message
help:
	@echo "sbx-lite Development Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  check         - Run all checks (lint + syntax + security)"
	@echo "  lint          - Run ShellCheck linting"
	@echo "  syntax        - Validate bash syntax"
	@echo "  security      - Run security checks"
	@echo "  test          - Run unit tests"
	@echo "  install-hooks - Install git pre-commit hooks"
	@echo "  clean         - Clean temporary files"
	@echo ""

# Run all checks
check: lint syntax security
	@echo "✓ All checks passed!"

# ShellCheck linting
lint:
	@echo "→ Running ShellCheck..."
	@command -v shellcheck >/dev/null 2>&1 || { \
		echo "Error: shellcheck not installed. Install with: apt install shellcheck"; \
		exit 1; \
	}
	@shellcheck -x -S warning install_multi.sh lib/*.sh 2>/dev/null || \
		(echo "✗ ShellCheck found issues"; exit 1)
	@echo "✓ ShellCheck passed"

# Syntax validation
syntax:
	@echo "→ Checking syntax..."
	@for script in install_multi.sh lib/*.sh; do \
		[ -f "$$script" ] || continue; \
		echo "  Checking $$script..."; \
		bash -n "$$script" || exit 1; \
	done
	@echo "✓ Syntax check passed"

# Security checks
security:
	@echo "→ Running security checks..."
	@echo "  Checking for unsafe eval..."
	@! grep -rn 'eval.*\$$' --include="*.sh" lib/ || { \
		echo "✗ Unsafe eval found"; \
		exit 1; \
	}
	@echo "  Checking for temp file issues..."
	@! grep -rn '/tmp/[^$$]*\$$' --include="*.sh" lib/ | grep -v mktemp || { \
		echo "⚠  Potential temp file issues found"; \
	}
	@echo "✓ Security checks passed"

# Run tests (placeholder for future test framework)
test:
	@echo "→ Running tests..."
	@if [ -f tests/run-tests.sh ]; then \
		bash tests/run-tests.sh; \
	else \
		echo "ℹ  No tests configured yet"; \
	fi

# Install pre-commit hook
install-hooks:
	@echo "→ Installing git hooks..."
	@if [ ! -d .git ]; then \
		echo "Error: Not a git repository"; \
		exit 1; \
	fi
	@cp tools/pre-commit .git/hooks/pre-commit 2>/dev/null || { \
		echo "⚠  Pre-commit hook not found in tools/"; \
		echo "ℹ  Run this after creating tools/pre-commit"; \
	}
	@chmod +x .git/hooks/pre-commit 2>/dev/null || true
	@echo "✓ Git hooks installed"

# Clean temporary files
clean:
	@echo "→ Cleaning temporary files..."
	@find . -name "*.tmp" -delete 2>/dev/null || true
	@find /tmp -maxdepth 1 -name "sb*" -type f -mmin +10 -delete 2>/dev/null || true
	@find /tmp -maxdepth 1 -name "sing-box*" -type f -mmin +10 -delete 2>/dev/null || true
	@echo "✓ Cleanup complete"
