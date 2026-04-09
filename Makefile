# Fleet management scripts — linting, testing and coverage targets
# Requires: shellcheck (https://github.com/koalaman/shellcheck)
#           bats       (https://github.com/bats-core/bats-core)
#           kcov       (https://github.com/SimonKagstrom/kcov) — for coverage
#           docker     (optional, for Docker-based test targets)
#
# Usage:
#   make lint              Run ShellCheck on all .sh scripts
#   make lint-verbose      Run ShellCheck with full explanations
#   make check             Alias for lint (CI-friendly name)
#   make test              Run all bats tests (unit + integration) via Docker
#   make test-unit         Run unit tests only
#   make test-integration  Run integration tests only
#   make coverage          Run tests under kcov and open the HTML report

SHELL := /bin/bash
SCRIPTS := $(shell find scripts/ -name "*.sh" ! -path "*/old/*" | sort) install.sh
SCRIPTS_NOEXT := scripts/bin/fleetman
BATS_JOBS ?= $(shell nproc 2>/dev/null || echo 4)
COVERAGE_DIR := reports/coverage
TEST_REPORT_DIR := reports/tests

.PHONY: lint lint-verbose check test test-unit test-integration coverage

lint:
	@echo "=== ShellCheck ==="
	@shellcheck --format=gcc $(SCRIPTS) $(SCRIPTS_NOEXT)
	@echo "  All scripts passed."

lint-verbose:
	@echo "=== ShellCheck (verbose) ==="
	@shellcheck $(SCRIPTS) $(SCRIPTS_NOEXT)

check: lint

test:
	@echo "=== Bats (all tests, $(BATS_JOBS) jobs) ==="
	@mkdir -p $(TEST_REPORT_DIR)
	@bats --jobs $(BATS_JOBS) --recursive --report-formatter junit --output $(TEST_REPORT_DIR)  tests/

test-unit:
	@echo "=== Bats (unit, $(BATS_JOBS) jobs) ==="
	@bats --jobs $(BATS_JOBS) --recursive tests/unit/

test-integration:
	@echo "=== Bats (integration, $(BATS_JOBS) jobs) ==="
	@bats --jobs $(BATS_JOBS) --recursive tests/integration/

coverage:
	@echo "=== Coverage (kcov + bats) ==="
	@rm -rf $(COVERAGE_DIR)/
	@kcov \
		--include-path=scripts/,install.sh \
		--bash-parse-files-in-dir=scripts/ \
		--exclude-path=old/,scripts/internal/migrations/ \
		$(COVERAGE_DIR)/ \
		bats --jobs $(BATS_JOBS) --recursive tests/
	@echo ""
	@echo "  Report → $(COVERAGE_DIR)/index.html"
