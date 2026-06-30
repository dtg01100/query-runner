#!/bin/bash
# Sourced by every test_daemon_*.sh script. Sources set up the test database
# (test_daemon.db) if it's missing or empty so individual sub-suites are
# runnable standalone (not just through the test_daemon.sh harness).
#
# The harness's setup_test_db() does the same work; this is a no-op when
# the DB is already populated.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$TEST_DB"  # may be inherited from caller
TEST_DB="${TEST_DB:-$SCRIPT_DIR/test_daemon.db}"

if [[ ! -s "$TEST_DB" ]]; then
	if [[ -f "$SCRIPT_DIR/fixtures/test_schema.sql" ]] && command -v sqlite3 >/dev/null 2>&1; then
		sqlite3 "$TEST_DB" <"$SCRIPT_DIR/fixtures/test_schema.sql"
	fi
fi
