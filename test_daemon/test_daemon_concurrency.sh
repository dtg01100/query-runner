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

echo "=== Daemon Concurrency Tests ==="

echo "Running: concurrent_queries_5"
pids=()
for i in {1..5}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i as val" 2>/dev/null)
		if echo "$output" | grep -q "$i"; then
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
if [[ $failed -eq 0 ]]; then
	log_pass "concurrent_queries_5"
else
	log_fail "concurrent_queries_5 - $failed queries failed"
fi

echo "Running: concurrent_queries_10"
pids=()
for i in {1..10}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i as val" 2>/dev/null)
		if echo "$output" | grep -q "$i"; then
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
if [[ $failed -eq 0 ]]; then
	log_pass "concurrent_queries_10"
else
	log_fail "concurrent_queries_10 - $failed queries failed"
fi

echo "Running: concurrent_queries_20"
pids=()
for i in {1..20}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i as val" 2>/dev/null)
		if echo "$output" | grep -q "$i"; then
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
if [[ $failed -eq 0 ]]; then
	log_pass "concurrent_queries_20"
else
	log_fail "concurrent_queries_20 - $failed queries failed"
fi

echo "Running: concurrent_mixed_formats"
pids=()
for i in {1..5}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json "SELECT $i as val" 2>/dev/null)
		if echo "$output" | grep -q '"val"'; then
			exit 0
		else
			exit 1
		fi
	) &
	pids+=($!)
done
for i in {6..10}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv "SELECT $i as val" 2>/dev/null)
		if echo "$output" | grep -q "val"; then
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
if [[ $failed -eq 0 ]]; then
	log_pass "concurrent_mixed_formats"
else
	log_fail "concurrent_mixed_formats - $failed queries failed"
fi

echo "Running: concurrent_same_table"
pids=()
for i in {1..10}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT * FROM users WHERE id = $((i % 5 + 1))" 2>/dev/null)
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
if [[ $failed -eq 0 ]]; then
	log_pass "concurrent_same_table"
else
	log_fail "concurrent_same_table - $failed queries failed"
fi

echo "Running: concurrent_error_isolation"
"$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT * FROM nonexistent" >/dev/null 2>&1 &
error_pid=$!
"$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1 as val" >/dev/null 2>&1 &
valid_pid=$!
wait "$error_pid" 2>/dev/null || true
wait "$valid_pid" 2>/dev/null
if [[ $? -eq 0 ]]; then
	log_pass "concurrent_error_isolation"
else
	log_fail "concurrent_error_isolation - valid query failed due to error"
fi

echo "Running: concurrent_daemon_stable"
pids=()
for i in {1..10}; do
	(
		output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT $i" 2>/dev/null)
		exit 0
	) &
	pids+=($!)
done
for pid in "${pids[@]}"; do
	wait "$pid" 2>/dev/null || true
done
if [[ -S "$DAEMON_SOCKET" ]]; then
	log_pass "concurrent_daemon_stable"
else
	log_fail "concurrent_daemon_stable - daemon crashed"
fi

echo ""
echo "=== Concurrency Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
