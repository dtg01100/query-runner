#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/test_daemon.db"

mock_slow_query() {
	echo "WITH RECURSIVE slow(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM slow WHERE x<1000) SELECT * FROM slow LIMIT 1"
}

mock_disconnect_db() {
	if [[ -f "$TEST_DB" ]]; then
		mv "$TEST_DB" "${TEST_DB}.bak"
	fi
}

mock_reconnect_db() {
	if [[ -f "${TEST_DB}.bak" ]]; then
		mv "${TEST_DB}.bak" "$TEST_DB"
	fi
}

mock_large_result_query() {
	echo "SELECT * FROM ("
	for i in $(seq 1 100); do
		echo "SELECT $i as id, 'Item $i' as name UNION ALL"
	done
	echo "SELECT 1, 'Item 1' LIMIT 1"
}

mock_permission_denied_socket() {
	local socket_dir="$HOME/.query_runner"
	chmod 000 "$socket_dir/daemon.sock" 2>/dev/null || true
}

mock_restore_socket() {
	local socket_dir="$HOME/.query_runner"
	chmod 600 "$socket_dir/daemon.sock" 2>/dev/null || true
}

mock_db_corruption() {
	echo "This is not a valid SQLite database" >"$TEST_DB"
}

mock_valid_db() {
	sqlite3 "$TEST_DB" <"$SCRIPT_DIR/fixtures/test_schema.sql" 2>/dev/null || true
}

wait_for_daemon() {
	local max_attempts="${1:-10}"
	local attempt=0
	while [[ $attempt -lt $max_attempts ]]; do
		if [[ -S "$HOME/.query_runner/daemon.sock" ]]; then
			return 0
		fi
		sleep 0.5
		attempt=$((attempt + 1))
	done
	return 1
}

wait_for_daemon_status() {
	local expected_status="$1"
	local max_attempts="${2:-10}"
	local attempt=0

	while [[ $attempt -lt $max_attempts ]]; do
		local response
		response=$("$SCRIPT_DIR/../query_runner" --daemon-status -t sqlite -d "$TEST_DB" 2>/dev/null || echo "")
		if echo "$response" | grep -q "$expected_status"; then
			return 0
		fi
		sleep 0.5
		attempt=$((attempt + 1))
	done
	return 1
}
