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

echo "=== Daemon Protocol Tests ==="

echo "Running: protocol_ping"
response=$(echo '{"type":"ping"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{"status":"error"}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q '"pong":true'; then
	log_pass "protocol_ping"
else
	log_fail "protocol_ping - unexpected response: $response"
fi

echo "Running: protocol_query_valid"
response=$(echo '{"type":"query","sql":"SELECT 1 as val","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q '"val"'; then
	log_pass "protocol_query_valid"
else
	log_fail "protocol_query_valid - unexpected response"
fi

echo "Running: protocol_query_invalid_sql"
response=$(echo '{"type":"query","sql":"SELECT * FROM nonexistent_table","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "protocol_query_invalid_sql"
else
	log_fail "protocol_query_invalid_sql - should return error"
fi

echo "Running: protocol_query_blocked"
response=$(echo '{"type":"query","sql":"INSERT INTO users (name) VALUES (\"test\")","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"' && echo "$response" | grep -qi "read-only\|only.*read\|allowed"; then
	log_pass "protocol_query_blocked"
else
	log_fail "protocol_query_blocked - should block write operations"
fi

echo "Running: protocol_status"
response=$(echo '{"type":"status"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q 'uptime_ms'; then
	log_pass "protocol_status"
else
	log_fail "protocol_status - unexpected response: $response"
fi

echo "Running: protocol_shutdown"
response=$(echo '{"type":"shutdown"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
sleep 1
if [[ ! -S "$DAEMON_SOCKET" ]]; then
	log_pass "protocol_shutdown"
else
	log_fail "protocol_shutdown - socket still exists"
fi

setup

echo "Running: protocol_malformed_json"
response=$(echo 'not valid json at all' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "protocol_malformed_json"
else
	log_fail "protocol_malformed_json - should return error"
fi

echo "Running: protocol_missing_type"
response=$(echo '{"sql":"SELECT 1"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "protocol_missing_type"
else
	log_fail "protocol_missing_type - should return error"
fi

echo "Running: protocol_unknown_type"
response=$(echo '{"type":"unknown_type"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"' && echo "$response" | grep -q "Unknown\|unknown"; then
	log_pass "protocol_unknown_type"
else
	log_fail "protocol_unknown_type - should return unknown type error"
fi

echo "Running: protocol_large_result"
response=$(echo '{"type":"query","sql":"WITH RECURSIVE cnt(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM cnt WHERE x<100) SELECT * FROM cnt","format":"json"}' | timeout 5 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q '"x"'; then
	log_pass "protocol_large_result"
else
	log_fail "protocol_large_result - failed to handle large result set"
fi

echo "Running: protocol_special_chars"
response=$(echo '{"type":"query","sql":"SELECT '\''hello\nworld\tspecial\rchars'\'' as txt","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q '\\n'; then
	log_pass "protocol_special_chars"
else
	log_fail "protocol_special_chars - special chars not properly escaped"
fi

echo "Running: protocol_null_values"
response=$(echo '{"type":"query","sql":"SELECT NULL as null_val, 1 as num_val","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"' && echo "$response" | grep -q 'null'; then
	log_pass "protocol_null_values"
else
	log_fail "protocol_null_values - null values not properly handled"
fi

echo "Running: protocol_all_formats"
for fmt in json csv text; do
	response=$(echo "{\"type\":\"query\",\"sql\":\"SELECT 1 as val\",\"format\":\"$fmt\"}" | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
	if echo "$response" | grep -q '"status":"ok"'; then
		log_pass "protocol_format_$fmt"
	else
		log_fail "protocol_format_$fmt"
	fi
done

echo ""
echo "=== Protocol Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
