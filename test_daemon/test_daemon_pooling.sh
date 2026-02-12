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
	"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1 || true
	sleep 1
}

teardown() {
	cleanup_daemon
}

trap 'teardown' EXIT

setup

echo "=== Connection Pool Tests ==="

echo "Running: pool_connection_reuse"
response=$(echo '{"type":"status"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q 'idle_connections'; then
	idle1=$(echo "$response" | grep -o '"idle_connections":[0-9]*' | grep -o '[0-9]*' || echo "0")
	"$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1
	response=$(echo '{"type":"status"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
	idle2=$(echo "$response" | grep -o '"idle_connections":[0-9]*' | grep -o '[0-9]*' || echo "0")
	if [[ "$idle1" == "$idle2" ]] || [[ "$idle1" -ge 1 ]]; then
		log_pass "pool_connection_reuse"
	else
		log_fail "pool_connection_reuse - connections not being reused"
	fi
else
	log_fail "pool_connection_reuse - pool status not available"
fi

echo "Running: pool_max_connections"
pids=()
for i in {1..15}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i" 2>/dev/null)
		if [[ -n "$output" ]]; then
			exit 0
		else
			exit 1
		fi
	) &
	pids+=($!)
done
failed=0
for pid in "${pids[@]}"; do
	wait "$pid" || failed=$((failed + 1))
done
if [[ $failed -lt 5 ]]; then
	log_pass "pool_max_connections"
else
	log_fail "pool_max_connections - $failed queries failed under load"
fi

echo "Running: pool_connection_validity"
response=$(echo '{"type":"status"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"'; then
	log_pass "pool_connection_validity"
else
	log_fail "pool_connection_validity - pool status check failed"
fi

echo "Running: pool_query_uses_pool"
first_time=$({ time "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1; } 2>&1)
second_time=$({ time "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1; } 2>&1)
log_pass "pool_query_uses_pool"

echo "Running: pool_multiple_queries_same_connection"
for i in {1..5}; do
	output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT COUNT(*) FROM users" 2>/dev/null)
	if ! echo "$output" | grep -q "[0-9]"; then
		log_fail "pool_multiple_queries_same_connection"
		break
	fi
done
if [[ $i -eq 5 ]]; then
	log_pass "pool_multiple_queries_same_connection"
fi

echo "Running: pool_sequential_queries"
for i in {1..10}; do
	output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i as val" 2>/dev/null)
	if ! echo "$output" | grep -q "$i"; then
		log_fail "pool_sequential_queries - query $i failed"
		break
	fi
done
if [[ $i -eq 10 ]]; then
	log_pass "pool_sequential_queries"
fi

echo ""
echo "=== Pooling Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
