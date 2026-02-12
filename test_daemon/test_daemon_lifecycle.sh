#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/../query_runner"
TEST_DB="$SCRIPT_DIR/test_daemon.db"
DAEMON_SOCKET="$HOME/.query_runner/daemon.sock"
DAEMON_PORT_FILE="$HOME/.query_runner/daemon.port"
DAEMON_PID_FILE="$HOME/.query_runner/daemon.pid"
DAEMON_CLASS_DIR="$HOME/.query_runner/daemon_class"

RED='\033[0;31m'
GREEN='\033[0;32m'
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
	if [[ -f "$DAEMON_PORT_FILE" ]]; then
		port=$(cat "$DAEMON_PORT_FILE" 2>/dev/null || echo "")
		if [[ -n "$port" ]]; then
			echo '{"type":"shutdown"}' | timeout 2 nc localhost "$port" 2>/dev/null || true
		fi
	fi
	if [[ -f "$DAEMON_PID_FILE" ]]; then
		pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
			sleep 0.5
		fi
	fi
	rm -f "$DAEMON_SOCKET" "$DAEMON_PORT_FILE" "$DAEMON_PID_FILE" 2>/dev/null || true
	rm -rf "$DAEMON_CLASS_DIR" 2>/dev/null || true
}

wait_for_daemon() {
	local max_attempts="${1:-10}"
	local attempt=0
	while [[ $attempt -lt $max_attempts ]]; do
		if [[ -S "$DAEMON_SOCKET" ]] || [[ -f "$DAEMON_PORT_FILE" ]]; then
			if [[ -f "$DAEMON_PID_FILE" ]]; then
				pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
				if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
					return 0
				fi
			fi
		fi
		sleep 0.5
		attempt=$((attempt + 1))
	done
	return 1
}

daemon_query() {
	"$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$@" 2>/dev/null
}

daemon_send() {
	local message="$1"
	if [[ -S "$DAEMON_SOCKET" ]]; then
		echo "$message" | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null
	elif [[ -f "$DAEMON_PORT_FILE" ]]; then
		port=$(cat "$DAEMON_PORT_FILE" 2>/dev/null || echo "")
		if [[ -n "$port" ]]; then
			echo "$message" | timeout 2 nc localhost "$port" 2>/dev/null
		fi
	fi
}

setup() {
	cleanup_daemon
	"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1 || true
	wait_for_daemon 15
}

teardown() {
	cleanup_daemon
}

trap 'teardown' EXIT

setup

echo "=== Daemon Lifecycle Tests ==="

echo "Running: daemon_start_fresh"
cleanup_daemon
if "$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1; then
	if wait_for_daemon 10; then
		log_pass "daemon_start_fresh"
	else
		log_fail "daemon_start_fresh - daemon not ready"
	fi
else
	log_fail "daemon_start_fresh - failed to start"
fi

echo "Running: daemon_already_running"
if daemon_query "SELECT 1" >/dev/null 2>&1; then
	log_pass "daemon_already_running"
else
	log_fail "daemon_already_running"
fi

echo "Running: daemon_query_execution"
output=$(daemon_query "SELECT * FROM users LIMIT 2" 2>/dev/null)
if echo "$output" | grep -q "Alice"; then
	log_pass "daemon_query_execution"
else
	log_fail "daemon_query_execution - query did not return expected results"
fi

echo "Running: daemon_status_running"
output=$(daemon_send '{"type":"status"}' 2>/dev/null || echo '{}')
if echo "$output" | grep -q '"status":"ok"'; then
	log_pass "daemon_status_running"
else
	log_fail "daemon_status_running - status not detected"
fi

echo "Running: daemon_stop"
if "$QUERY_RUNNER" --daemon-stop -t sqlite -d "$TEST_DB" 2>/dev/null; then
	sleep 1
	if [[ ! -S "$DAEMON_SOCKET" ]] && [[ ! -f "$DAEMON_PORT_FILE" ]]; then
		log_pass "daemon_stop"
	else
		log_fail "daemon_stop - socket/port still exists"
	fi
else
	log_fail "daemon_stop - stop command failed"
fi

echo "Running: daemon_stop_not_running"
cleanup_daemon
if "$QUERY_RUNNER" --daemon-stop -t sqlite -d "$TEST_DB" 2>/dev/null; then
	log_pass "daemon_stop_not_running"
else
	log_fail "daemon_stop_not_running - should not fail"
fi

echo "Running: daemon_restart"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1
wait_for_daemon 10
first_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
sleep 2
if "$QUERY_RUNNER" --daemon-restart -t sqlite -d "$TEST_DB" 2>/dev/null; then
	wait_for_daemon 10
	second_pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
	if [[ -n "$second_pid" ]] && [[ "$first_pid" != "$second_pid" ]]; then
		log_pass "daemon_restart"
	else
		log_fail "daemon_restart - PID did not change"
	fi
else
	log_fail "daemon_restart - restart command failed"
fi

echo "Running: daemon_auto_start"
cleanup_daemon
if ! [[ -S "$DAEMON_SOCKET" ]] && [[ ! -f "$DAEMON_PORT_FILE" ]]; then
	if daemon_query "SELECT 1" >/dev/null 2>&1; then
		if wait_for_daemon 10; then
			log_pass "daemon_auto_start"
		else
			log_fail "daemon_auto_start - daemon not auto-started"
		fi
	else
		log_fail "daemon_auto_start - query failed"
	fi
else
	log_fail "daemon_auto_start - daemon already running"
fi

echo "Running: daemon_socket_cleanup"
cleanup_daemon
touch "$DAEMON_SOCKET" 2>/dev/null || true
if "$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1; then
	if wait_for_daemon 10; then
		log_pass "daemon_socket_cleanup"
	else
		log_fail "daemon_socket_cleanup - start failed"
	fi
else
	log_fail "daemon_socket_cleanup - start failed"
fi

echo "Running: daemon_multiple_queries"
daemon_query "SELECT 1" >/dev/null 2>&1 || true
daemon_query "SELECT 2" >/dev/null 2>&1 || true
daemon_query "SELECT 3" >/dev/null 2>&1 || true
if wait_for_daemon 5; then
	log_pass "daemon_multiple_queries"
else
	log_fail "daemon_multiple_queries - daemon died"
fi

echo "Running: daemon_query_different_formats"
output_json=$(daemon_query -f json "SELECT 1 as val" 2>/dev/null)
output_csv=$(daemon_query -f csv "SELECT 1 as val" 2>/dev/null)
output_text=$(daemon_query -f text "SELECT 1 as val" 2>/dev/null)
if echo "$output_json" | grep -q '"val"' && echo "$output_csv" | grep -q 'val' && echo "$output_text" | grep -q 'val'; then
	log_pass "daemon_query_different_formats"
else
	log_fail "daemon_query_different_formats - format output incorrect"
fi

echo "Running: daemon_idle_timeout_detection"
if grep -q "IDLE_TIMEOUT_MS" "$SCRIPT_DIR/../query_runner" 2>/dev/null; then
	log_pass "daemon_idle_timeout_detection"
else
	log_fail "daemon_idle_timeout_detection - idle timeout not implemented"
fi

echo ""
echo "=== Lifecycle Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
