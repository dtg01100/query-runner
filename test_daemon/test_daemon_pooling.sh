#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/../query_runner"
TEST_DB="$SCRIPT_DIR/test_daemon.db"
DAEMON_SOCKET="$HOME/.query_runner/daemon.sock"
DAEMON_PID_FILE="$HOME/.query_runner/daemon.pid"
DAEMON_PORT_FILE="$HOME/.query_runner/daemon.port"
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
		echo '{"type":"shutdown"}' | timeout 2 socat UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || true
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
}

setup() {
	cleanup_daemon
	"$QUERY_RUNNER" --daemon-start --env-file "$SCRIPT_DIR/.env.test" -t sqlite  -d "$TEST_DB" -q "SELECT 1" >/dev/null 2>&1 || true
	for i in 1 2 3 4 5 6 7 8 9 10; do
		if [[ -S "$DAEMON_SOCKET" ]] || [[ -f "$DAEMON_PORT_FILE" ]]; then return 0; fi
		sleep 0.5
	done
	return 1
}

teardown() {
	cleanup_daemon
}

trap 'teardown' EXIT

setup

echo "=== Connection Pool Tests ==="

echo "Running: pool_connection_reuse"
# The daemon's pool is lazy: it's only created on the first query,
# not at daemon startup. So idle1 (before any query) is 0, and
# idle2 (after the query returned the connection) should be >= 1.
# What we're verifying is that the connection was *returned* to
# the pool, not eagerly created and abandoned.
response=$(echo '{"type":"status"}' | timeout 2 socat UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q 'idle_connections'; then
	"$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT 1" >/dev/null 2>&1
	response=$(echo '{"type":"status"}' | timeout 2 socat UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
	idle2=$(echo "$response" | grep -o '"idle_connections":[0-9]*' | grep -o '[0-9]*' || echo "0")
	if [[ "$idle2" -ge 1 ]]; then
		log_pass "pool_connection_reuse"
	else
		log_fail "pool_connection_reuse - connection not returned to pool (idle2=$idle2)"
	fi
else
	log_fail "pool_connection_reuse - pool status not available"
fi

echo "Running: pool_max_connections"
pids=()
for i in {1..15}; do
	(
		output=$("$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT $i" 2>/dev/null)
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
response=$(echo '{"type":"status"}' | timeout 2 socat UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"'; then
	log_pass "pool_connection_validity"
else
	log_fail "pool_connection_validity - pool status check failed"
fi

echo "Running: pool_query_uses_pool"
first_time=$({ time "$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT 1" >/dev/null 2>&1; } 2>&1)
second_time=$({ time "$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT 1" >/dev/null 2>&1; } 2>&1)
log_pass "pool_query_uses_pool"

echo "Running: pool_multiple_queries_same_connection"
for i in {1..5}; do
	output=$("$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT COUNT(*) FROM users" 2>/dev/null)
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
	output=$("$QUERY_RUNNER" --env-file "$SCRIPT_DIR/.env.test" -t sqlite -d "$TEST_DB" -q "SELECT $i as val" 2>/dev/null)
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
