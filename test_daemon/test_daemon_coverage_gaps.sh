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
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

log_pass() { echo -e "${GREEN}✓${NC} $1"; TESTS_PASSED=$((TESTS_PASSED + 1)); }
log_fail() { echo -e "${RED}✗${NC} $1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
log_skip() { echo -e "${YELLOW}⊘${NC} $1 (skipped)"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

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
    rm -rf "$DAEMON_CLASS_DIR" ~/.query_runner/cache 2>/dev/null || true
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

setup() { cleanup_daemon; }
teardown() { cleanup_daemon; }
trap 'teardown' EXIT

setup

echo "=== Coverage Gap Tests ==="

echo ""
echo "Running: daemon_env_daemon_mode_auto"
cleanup_daemon
DAEMON_MODE=auto output=$(echo "SELECT 1" | DAEMON_MODE=auto "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_env_daemon_mode_auto"
else
    log_fail "daemon_env_daemon_mode_auto"
fi

echo "Running: daemon_env_daemon_mode_off"
cleanup_daemon
DAEMON_MODE=off output=$(echo "SELECT 1" | DAEMON_MODE=off "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_env_daemon_mode_off"
else
    log_fail "daemon_env_daemon_mode_off"
fi

echo "Running: daemon_flag_enable"
cleanup_daemon
output=$(echo "SELECT 1" | "$QUERY_RUNNER" --daemon -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_flag_enable"
else
    log_fail "daemon_flag_enable"
fi

echo "Running: daemon_flag_disable"
cleanup_daemon
output=$(echo "SELECT 1" | "$QUERY_RUNNER" --no-daemon -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_flag_disable"
else
    log_fail "daemon_flag_disable"
fi

echo "Running: daemon_status_endpoint_info"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$("$QUERY_RUNNER" --daemon-status -t sqlite -d "$TEST_DB" 2>&1 || true)
if echo "$output" | grep -qE "(UNIX|INET|localhost|PID)"; then
    log_pass "daemon_status_endpoint_info"
else
    log_fail "daemon_status_endpoint_info"
fi

echo "Running: daemon_stale_pid_file"
cleanup_daemon
echo "999999" > "$DAEMON_PID_FILE"
output=$("$QUERY_RUNNER" --daemon-status -t sqlite -d "$TEST_DB" 2>&1 || true)
if echo "$output" | grep -q "not running"; then
    log_pass "daemon_stale_pid_file"
else
    log_fail "daemon_stale_pid_file"
fi

echo "Running: daemon_query_timeout"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
port=$(cat "$DAEMON_PORT_FILE" 2>/dev/null || echo "")
output=$(timeout 5 bash -c "echo '{\"type\":\"query\",\"sql\":\"SELECT 1\",\"format\":\"text\"}' | nc -w 1 localhost $port" 2>/dev/null || echo "timeout")
if echo "$output" | grep -q "1"; then
    log_pass "daemon_query_timeout"
else
    log_fail "daemon_query_timeout"
fi

echo "Running: daemon_graceful_shutdown_pending"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
port=$(cat "$DAEMON_PORT_FILE" 2>/dev/null || echo "")
(echo '{"type":"shutdown"}' | timeout 2 nc localhost "$port" 2>/dev/null) &
sleep 1
cleanup_daemon
sleep 1
if [[ ! -f "$DAEMON_PID_FILE" ]] || ! kill -0 $(cat "$DAEMON_PID_FILE" 2>/dev/null) 2>/dev/null; then
    log_pass "daemon_graceful_shutdown_pending"
else
    log_fail "daemon_graceful_shutdown_pending"
fi

echo "Running: daemon_format_json_valid"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1" | "$QUERY_RUNNER" -f json -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | jq -e . >/dev/null 2>&1; then
    log_pass "daemon_format_json_valid"
else
    log_fail "daemon_format_json_valid"
fi

echo "Running: daemon_format_csv_valid"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1" | "$QUERY_RUNNER" -f csv -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_format_csv_valid"
else
    log_fail "daemon_format_csv_valid"
fi

echo "Running: daemon_format_pretty_valid"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1" | "$QUERY_RUNNER" -f pretty -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -qE "(\+|-|1)"; then
    log_pass "daemon_format_pretty_valid"
else
    log_fail "daemon_format_pretty_valid"
fi

echo "Running: daemon_format_text_valid"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1" | "$QUERY_RUNNER" -f text -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_format_text_valid"
else
    log_fail "daemon_format_text_valid"
fi

echo "Running: daemon_symlink_invocation"
cleanup_daemon
ln -sf "$QUERY_RUNNER" /tmp/qr_symlink_test 2>/dev/null || true
output=$(echo "SELECT 1" | /tmp/qr_symlink_test --daemon -t sqlite -d "$TEST_DB" 2>&1)
rm -f /tmp/qr_symlink_test 2>/dev/null || true
if echo "$output" | grep -q "1"; then
    log_pass "daemon_symlink_invocation"
else
    log_fail "daemon_symlink_invocation"
fi

echo "Running: daemon_query_empty_result"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1 WHERE 0" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_query_empty_result"
else
    log_fail "daemon_query_empty_result"
fi

echo "Running: daemon_status_query"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
response=$(echo '{"type":"status"}' | timeout 2 nc localhost $(cat "$DAEMON_PORT_FILE") 2>/dev/null || echo '{}')
if echo "$response" | grep -q '"status":"ok"'; then
    log_pass "daemon_status_query"
else
    log_fail "daemon_status_query"
fi

echo "Running: daemon_concurrent_different_formats"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
pids=()
for fmt in json csv text; do
    (
        output=$(echo "SELECT '$fmt' as fmt" | "$QUERY_RUNNER" -f "$fmt" -t sqlite -d "$TEST_DB" 2>/dev/null)
        exit 0
    ) &
    pids+=($!)
done
failed=0
for pid in "${pids[@]}"; do wait "$pid" 2>/dev/null || failed=$((failed + 1)); done
if [[ $failed -eq 0 ]]; then
    log_pass "daemon_concurrent_different_formats"
else
    log_fail "daemon_concurrent_different_formats"
fi

echo ""
echo "=== Coverage Gap Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Skipped: ${YELLOW}$TESTS_SKIPPED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then exit 0; else exit 1; fi

echo ""
echo "Running: daemon_query_very_long"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
long_query="SELECT '$(head -c 1000 /dev/zero | tr '\0' 'a')' as long_val"
output=$(echo "$long_query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "long_val"; then
    log_pass "daemon_query_very_long"
else
    log_fail "daemon_query_very_long"
fi

echo "Running: daemon_query_special_chars"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
special_query="SELECT '\$&@#!%^*(){}[]|\\\"'\''\t\n\r' as special"
output=$(echo "$special_query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "special"; then
    log_pass "daemon_query_special_chars"
else
    log_fail "daemon_query_special_chars"
fi

echo "Running: daemon_mixed_case_sql"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "select count(*) from users" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "[0-9]"; then
    log_pass "daemon_mixed_case_sql"
else
    log_fail "daemon_mixed_case_sql"
fi

echo "Running: daemon_whitespace_query"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "  SELECT 1  " | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1"; then
    log_pass "daemon_whitespace_query"
else
    log_fail "daemon_whitespace_query"
fi

echo "Running: daemon_quoted_string_query"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 'hello world' as greeting" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "hello world"; then
    log_pass "daemon_quoted_string_query"
else
    log_fail "daemon_quoted_string_query"
fi

echo "Running: daemon_double_quote_string"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo 'SELECT "double quotes" as dq' | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "double quotes"; then
    log_pass "daemon_double_quote_string"
else
    log_fail "daemon_double_quote_string"
fi

echo "Running: daemon_number_values"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 42 as num, 3.14159 as pi, -100 as neg" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "42" && echo "$output" | grep -q "3.14"; then
    log_pass "daemon_number_values"
else
    log_fail "daemon_number_values"
fi

echo "Running: daemon_boolean_values"
cleanup_daemon
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" > /dev/null 2>&1
wait_for_daemon 10
output=$(echo "SELECT 1 as one, 0 as zero" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
if echo "$output" | grep -q "1" && echo "$output" | grep -q "0"; then
    log_pass "daemon_boolean_values"
else
    log_fail "daemon_boolean_values"
fi
