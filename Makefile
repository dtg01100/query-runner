# Query Runner — make targets
#
# The canonical entry point is ./query_runner (a bash wrapper). Tests live in
# test_*.sh at the root and in test_daemon/*.sh for daemon-mode tests.
# Driving everything through `make` keeps the AGENTS.md surface small and
# makes the canonical test command obvious to humans and CI alike.
#
# Categories mirror run_all_tests.sh's: all | core | security | formats |
# daemon | lint.
#
# Conventions:
#   - All targets are .PHONY so timestamps don't gate them.
#   - Daemon-state targets (preflight) clear ~/.query_runner/* so the test
#     starts from a known-clean state. Don't run the suite twice in a row
#     without preflight — daemon state can leak between runs.
#   - Coverage tests run last so that any single-suite flake shows up in
#     the final tail rather than getting buried under earlier passes.

SHELL := /usr/bin/env bash

# Force kill any running daemon / test processes before each test run.
# Uses 'pgrep … xargs kill' rather than 'pkill -f test_daemon' to avoid
# killing the bash that's running the Makefile recipe itself (patterns
# like 'test_daemon' can match the process tree when cwd is named
# "test_daemon").
preflight:
	# The daemon runs as a JVM whose process NAME is 'java' (not
	# 'QueryDaemon'), so pkill -x QueryDaemon never matches it. Match the
	# cmdline instead, using the [Q] bracket trick so this Makefile recipe's
	# own argv (which mentions the pattern) is not a match.
	pkill -9 -f 'QueryD[a]emon' 2>/dev/null || true
	# Belt-and-suspenders: kill whatever PID the daemon left behind.
	-if [ -f $${HOME}/.query_runner/daemon.pid ]; then \
		kill -9 $$(cat $${HOME}/.query_runner/daemon.pid) 2>/dev/null || true; \
	fi
	rm -f $${HOME}/.query_runner/daemon.sock \
		$${HOME}/.query_runner/daemon.pid \
		$${HOME}/.query_runner/daemon.port \
		$${HOME}/.query_runner/daemon.config_hash \
		$${HOME}/.query_runner/daemon.log || true
	rm -rf $${HOME}/.query_runner/cache $${HOME}/.query_runner/daemon_class || true

.PHONY: help test test-core test-security test-formats test-daemon test-coverage test-all lint clean preflight install-hooks

help:
	@echo 'make test              - run the core test suites (default)'
	@echo 'make test-core         - cache/error/path/query tests'
	@echo 'make test-security     - input validation + db security + union safety'
	@echo 'make test-formats      - CLI / env files / output formats'
	@echo 'make test-daemon       - daemon mode (8 sub-suites)'
	@echo 'make test-coverage     - coverage gap sub-suite of daemon tests only'
	@echo 'make test-all          - everything above, end to end'
	@echo 'make lint              - shellcheck on query_runner + run_all_tests.sh'
	@echo 'make preflight         - kill daemons + clear ~/.query_runner state'
	@echo 'make install-hooks     - wire .githooks/pre-commit into this repo'

# "make test" defaults to daemon-mode tests because that's the suite most
# affected by daemon-binary changes (the canonical daily-driver path).
test: test-daemon

test-core: preflight
	./run_all_tests.sh core

test-security: preflight
	./run_all_tests.sh security

test-formats: preflight
	./run_all_tests.sh formats

test-daemon: preflight
	./run_all_tests.sh daemon

test-coverage: preflight
	./run_all_tests.sh daemon coverage

test-all: preflight
	./run_all_tests.sh integration

lint:
	./run_all_tests.sh lint

clean: preflight
	rm -f test_daemon/test_daemon.db

# Wire up the pre-commit hook. The hook lives in .githooks/ (not the
# default .git/hooks/) so it can be committed and versioned.
install-hooks:
	chmod +x .githooks/pre-commit
	git config core.hooksPath .githooks
	@echo "Hook installed: .githooks/pre-commit (active via core.hooksPath)"
	@echo "Bypass for one-off: git commit --no-verify"
