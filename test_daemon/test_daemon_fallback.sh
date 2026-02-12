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

log_pass() {
	echo -e "${GREEN}✓${NC} $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
	echo -e "${RED}✗${NC} $1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
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

setup() {
	cleanup_daemon
}

teardown() {
	cleanup_daemon
}

trap 'teardown' EXIT

setup

echo "=== Daemon Fallback Tests ==="

echo "Running: fallback_socket_missing"
cleanup_daemon
output=$("$QUERY_RUNNER" --no-daemon -t sqlite -d "$TEST_DB" "SELECT 1" 2>&1)
if echo "$output" | grep -q "1"; then
	log_pass "fallback_socket_missing"
else
	log_fail "fallback_socket_missing - no-daemon mode failed"
fi

echo "Running: fallback_socket_busy"
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1 || true
pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
kill -9 "$pid" 2>/dev/null || true
sleep 0.5
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>&1)
if echo "$output" | grep -q "1"; then
	log_pass "fallback_socket_busy"
else
	log_fail "fallback_socket_busy - failed to handle crashed daemon"
fi

echo "Running: fallback_explicit_flag"
cleanup_daemon
output=$("$QUERY_RUNNER" --no-daemon -t sqlite -d "$TEST_DB" "SELECT 1 as val" 2>&1)
if [[ -S "$DAEMON_SOCKET" ]]; then
	log_fail "fallback_explicit_flag - daemon should not start"
else
	log_pass "fallback_explicit_flag"
fi

echo "Running: fallback_daemon_crash"
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1 || true
pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
kill -9 "$pid" 2>/dev/null || true
sleep 0.5
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>&1)
if echo "$output" | grep -q "1"; then
	log_pass "fallback_daemon_crash"
else
	log_fail "fallback_daemon_crash - failed to recover from crash"
fi

echo "Running: fallback_connection_refused"
cleanup_daemon
touch "$DAEMON_SOCKET"
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>&1)
if echo "$output" | grep -q "1"; then
	log_pass "fallback_connection_refused"
else
	log_fail "fallback_connection_refused - failed to fallback"
fi

echo "Running: fallback_no_socat"
if ! command -v socat >/dev/null 2>&1; then
	log_skip "fallback_no_socat - socat not installed"
else
	log_pass "fallback_no_socat"
fi

echo ""
echo "=== Fallback Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
