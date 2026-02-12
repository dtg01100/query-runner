#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/../query_runner"
TEST_DB="$SCRIPT_DIR/test_daemon.db"
DAEMON_SOCKET="$HOME/.query_runner/daemon.sock"
DAEMON_PID_FILE="$HOME/.query_runner/daemon.pid"
DAEMON_CLASS_DIR="$HOME/.query_runner/daemon_class"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

setup_test_db() {
	echo "Creating test SQLite database..."
	rm -f "$TEST_DB"
	sqlite3 "$TEST_DB" <"$SCRIPT_DIR/fixtures/test_schema.sql"
}

cleanup_daemon() {
	if [[ -S "$DAEMON_SOCKET" ]]; then
		echo '{"type":"shutdown"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || true
	fi
	if [[ -f "$DAEMON_PID_FILE" ]]; then
		local pid
		pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
			sleep 0.5
		fi
	fi
	rm -f "$DAEMON_SOCKET" "$DAEMON_PID_FILE" 2>/dev/null || true
	rm -rf "$DAEMON_CLASS_DIR" 2>/dev/null || true
}

cleanup() {
	cleanup_daemon
	rm -f "$TEST_DB" 2>/dev/null || true
}

trap cleanup EXIT

log_pass() {
	echo -e "${GREEN}✓${NC} $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
	echo -e "${RED}✗${NC} $1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_skip() {
	echo -e "${YELLOW}⊘${NC} $1 (skipped)"
	TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
}

log_info() {
	echo -e "${YELLOW}ℹ${NC} $1"
}

check_socat() {
	if ! command -v socat >/dev/null 2>&1; then
		echo "Error: socat is required for daemon tests"
		echo "Install with: apt-get install socat (Debian/Ubuntu) or brew install socat (macOS)"
		exit 1
	fi
}

check_socat

setup_test_db

if [[ "${1:-all}" == "lifecycle" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Lifecycle Tests ==="
	bash "$SCRIPT_DIR/test_daemon_lifecycle.sh" || true
fi

if [[ "${1:-all}" == "protocol" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Protocol Tests ==="
	bash "$SCRIPT_DIR/test_daemon_protocol.sh" || true
fi

if [[ "${1:-all}" == "fallback" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Fallback Tests ==="
	bash "$SCRIPT_DIR/test_daemon_fallback.sh" || true
fi

if [[ "${1:-all}" == "pooling" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Pooling Tests ==="
	bash "$SCRIPT_DIR/test_daemon_pooling.sh" || true
fi

if [[ "${1:-all}" == "security" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Security Tests ==="
	bash "$SCRIPT_DIR/test_daemon_security.sh" || true
fi

if [[ "${1:-all}" == "concurrency" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Concurrency Tests ==="
	bash "$SCRIPT_DIR/test_daemon_concurrency.sh" || true
fi

if [[ "${1:-all}" == "performance" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Performance Tests ==="
	bash "$SCRIPT_DIR/test_daemon_performance.sh" || true
fi

if [[ "${1:-all}" == "coverage" ]] || [[ "${1:-all}" == "all" ]]; then
	echo ""
	echo "=== Running Coverage Gap Tests ==="
	bash "$SCRIPT_DIR/test_daemon_coverage_gaps.sh" || true
fi

echo ""
echo "=== Test Summary ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
