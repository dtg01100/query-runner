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

echo "=== Daemon Security Tests ==="

echo "Running: socket_file_permissions"
if [[ -S "$DAEMON_SOCKET" ]]; then
	perms=$(stat -c "%a" "$DAEMON_SOCKET" 2>/dev/null || stat -f "%OLp" "$DAEMON_SOCKET" 2>/dev/null || echo "unknown")
	if [[ "$perms" == "600" ]] || [[ "$perms" == "660" ]]; then
		log_pass "socket_file_permissions"
	else
		log_fail "socket_file_permissions - permissions are $perms, expected 600 or 660"
	fi
else
	log_fail "socket_file_permissions - socket not found"
fi

echo "Running: socket_directory_permissions"
dir_perms=$(stat -c "%a" "$HOME/.query_runner" 2>/dev/null || stat -f "%OLp" "$HOME/.query_runner" 2>/dev/null || echo "unknown")
if [[ "$dir_perms" == "700" ]] || [[ "$dir_perms" == "755" ]]; then
	log_pass "socket_directory_permissions"
else
	log_fail "socket_directory_permissions - directory permissions are $dir_perms"
fi

echo "Running: query_injection_blocked"
response=$(echo '{"type":"query","sql":"SELECT * FROM users; DROP TABLE users;","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "query_injection_blocked"
else
	log_fail "query_injection_blocked - should block multiple statements"
fi

echo "Running: query_union_detection"
response=$(echo '{"type":"query","sql":"SELECT * FROM users UNION SELECT * FROM orders","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"' || [[ $(echo "$response" | grep -c "users\|orders" 2>/dev/null || echo "0") -ge 2 ]]; then
	log_pass "query_union_detection"
else
	log_fail "query_union_detection - should detect UNION across tables"
fi

echo "running: query_dangerous_keywords"
for keyword in "DROP TABLE" "DELETE FROM" "INSERT INTO" "UPDATE users"; do
	response=$(echo "{\"type\":\"query\",\"sql\":\"$keyword\",\"format\":\"json\"}" | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
	if echo "$response" | grep -q '"status":"error"'; then
		log_pass "query_dangerous_keyword_$keyword"
	else
		log_fail "query_dangerous_keyword_$keyword"
	fi
done

echo "Running: error_no_credentials"
response=$(echo '{"type":"query","sql":"SELECT * FROM sqlite_master","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if ! echo "$response" | grep -qiE "password|passwd|secret|token"; then
	log_pass "error_no_credentials"
else
	log_fail "error_no_credentials - credentials leaked in response"
fi

echo "Running: query_length_limit"
long_query="SELECT * FROM users WHERE name='$(head -c 2000000 /dev/zero | tr '\0' 'a')'"
response=$(echo "{\"type\":\"query\",\"sql\":\"$long_query\",\"format\":\"json\"}" | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -qi "too long\|limit\|max"; then
	log_pass "query_length_limit"
else
	log_fail "query_length_limit - should reject oversized queries"
fi

echo "Running: null_byte_blocked"
response=$(echo $'{"type":"query","sql":"SELECT 1\x00DROP TABLE users","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "null_byte_blocked"
else
	log_fail "null_byte_blocked - should reject null bytes"
fi

echo "Running: read_only_enforced"
response=$(echo '{"type":"query","sql":"CREATE TABLE test_table (id INT)","format":"json"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"error"'; then
	log_pass "read_only_enforced"
else
	log_fail "read_only_enforced - should block CREATE TABLE"
fi

echo ""
echo "=== Security Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
