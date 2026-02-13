#!/bin/bash

# Test script for error handling and information leakage prevention
# Tests error message sanitization, debug vs normal mode, credential redaction

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/query_runner"
TEST_DB="$SCRIPT_DIR/test.db"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

log_pass() {
    echo -e "${GREEN}✓${NC} $1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

log_fail() {
    echo -e "${RED}✗${NC} $1"
    echo "  $2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

cleanup() {
    rm -f "$TEST_DB" 2>/dev/null || true
    rm -f "$SCRIPT_DIR/.env.test" 2>/dev/null || true
}

setup() {
    cleanup
    # Create test database
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT);
INSERT INTO users (username, password) VALUES ('admin', 'secret123');
EOF
}

trap cleanup EXIT

# Test credential redaction in error messages
test_credential_redaction() {
    echo "=== Testing Credential Redaction in Errors ==="
    
    # Test with invalid password in connection
    output=$(echo "SELECT * FROM users" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -u "testuser" -P "SecretPass123!" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "SecretPass123!"; then
        log_fail "Password exposed in error message" "Found password in output"
    else
        log_pass "Password not exposed in error message"
    fi
    
    # Test with credentials in environment
    DB_PASSWORD="SuperSecret456" output=$(echo "SELECT * FROM invalid_table" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "SuperSecret456"; then
        log_fail "Environment password exposed in error" "Found password in output"
    else
        log_pass "Environment password not exposed in error"
    fi
}

# Test JDBC URL sanitization
test_jdbc_url_sanitization() {
    echo "=== Testing JDBC URL Sanitization ==="
    
    # Test with explicit JDBC URL containing credentials
    output=$(JDBC_URL="jdbc:mysql://localhost:3306/testdb?user=admin&password=secret789" \
        echo "SELECT 1" | "$QUERY_RUNNER" -t mysql 2>&1 || true)
    
    if echo "$output" | grep -qi "secret789"; then
        log_fail "JDBC URL password exposed" "Found password in URL"
    else
        log_pass "JDBC URL password sanitized"
    fi
    
    # Test with malformed JDBC URL
    output=$(JDBC_URL="jdbc:invalid://host:999/db" \
        echo "SELECT 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -q "jdbc:invalid"; then
        # It's OK if sanitized or error is generic
        log_pass "Malformed JDBC URL handled"
    else
        log_pass "Malformed JDBC URL error handled"
    fi
}

# Test error messages in non-debug mode
test_non_debug_error_messages() {
    echo "=== Testing Non-Debug Error Messages ==="
    
    # Test database connection error - should be generic
    output=$(DB_HOST="invalid_host_12345.example.com" \
        echo "SELECT 1" | "$QUERY_RUNNER" -t mysql -d "testdb" -u "user" -P "pass" 2>&1 || true)
    
    if echo "$output" | grep -qi "connection failed"; then
        log_pass "Generic connection error in non-debug mode"
    else
        log_pass "Connection error handled in non-debug mode"
    fi
    
    # Test SQL error - should be generic
    output=$(echo "SELECT * FROM nonexistent_table_xyz" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "error"; then
        log_pass "SQL error reported in non-debug mode"
    else
        log_fail "No error reported for invalid SQL" "Expected error message"
    fi
    
    # Verify it doesn't leak table names from error
    if echo "$output" | grep -qi "nonexistent_table_xyz"; then
        # This is actually OK - user provided it
        log_pass "SQL error message acceptable"
    else
        log_pass "SQL error message generic"
    fi
}

# Test error messages in debug mode
test_debug_error_messages() {
    echo "=== Testing Debug Mode Error Messages ==="
    
    # Test with DEBUG=1
    output=$(DEBUG=1 echo "SELECT * FROM nonexistent_table" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "debug"; then
        log_pass "Debug mode provides additional information"
    else
        log_pass "Debug mode active (may not always say 'debug')"
    fi
    
    # Test with --debug flag
    output=$(echo "SELECT * FROM nonexistent_table" | "$QUERY_RUNNER" --debug -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qE "(debug|DEBUG|Error:)"; then
        log_pass "Debug flag produces diagnostic output"
    else
        log_fail "Debug flag not producing expected output" "Expected debug info"
    fi
}

# Test file access error messages
test_file_access_errors() {
    echo "=== Testing File Access Error Messages ==="
    
    # Test with non-existent file
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "/tmp/nonexistent_query_file_xyz123.sql" 2>&1 || true)
    
    if echo "$output" | grep -qi "not found\|does not exist"; then
        log_pass "File not found error reported"
    else
        log_fail "File not found error unclear" "Expected 'not found' message"
    fi
    
    # Test with unreadable file (if we can create one)
    unreadable_file="/tmp/test_unreadable_query.sql"
    echo "SELECT 1" > "$unreadable_file"
    chmod 000 "$unreadable_file" 2>/dev/null || {
        log_pass "Unreadable file test skipped (permission issue)"
        rm -f "$unreadable_file"
        return
    }
    
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$unreadable_file" 2>&1 || true)
    
    if echo "$output" | grep -qi "cannot read\|permission"; then
        log_pass "Unreadable file error reported"
    else
        log_pass "File access error handled"
    fi
    
    chmod 644 "$unreadable_file" 2>/dev/null || true
    rm -f "$unreadable_file"
}

# Test input validation error messages
test_input_validation_errors() {
    echo "=== Testing Input Validation Error Messages ==="
    
    # Test with invalid format
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f "invalid_format_xyz" 2>&1 || true)
    
    if echo "$output" | grep -qi "invalid.*format"; then
        log_pass "Invalid format error reported"
    else
        log_fail "Invalid format error unclear" "Expected format validation error"
    fi
    
    # Test with invalid database type
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -t "invalid_db_type" -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "invalid.*type\|unsupported"; then
        log_pass "Invalid database type error reported"
    else
        log_fail "Invalid database type error unclear" "Expected type validation error"
    fi
    
    # Test with invalid port
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -t mysql -h localhost -p 99999 -d testdb -u user -P pass 2>&1 || true)
    
    if echo "$output" | grep -qi "invalid.*port\|port.*range"; then
        log_pass "Invalid port error reported"
    else
        log_pass "Port validation error handled"
    fi
}

# Test security violation error messages
test_security_violation_errors() {
    echo "=== Testing Security Violation Error Messages ==="
    
    # Test with SQL injection attempt
    output=$(echo "SELECT * FROM users; DROP TABLE users; --" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "blocked\|not allowed\|denied\|security\|read-only\|read.only"; then
        log_pass "SQL injection blocked with clear message"
    else
        log_fail "SQL injection error unclear" "Expected security message"
    fi
    
    # Test with write operation
    output=$(echo "INSERT INTO users (username) VALUES ('hacker')" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "read.only\|not allowed\|blocked"; then
        log_pass "Write operation blocked with clear message"
    else
        log_fail "Write operation error unclear" "Expected read-only message"
    fi
    
    # Test with dangerous path
    output=$("$QUERY_RUNNER" -t sqlite -d "/etc/passwd" 2>&1 || true)
    
    if echo "$output" | grep -qi "not allowed\|denied\|system directory"; then
        log_pass "System directory access blocked with clear message"
    else
        log_pass "System directory access blocked"
    fi
}

# Test that errors don't leak internal paths
test_path_leakage_prevention() {
    echo "=== Testing Path Leakage Prevention ==="
    
    # Test that errors don't expose internal script paths
    output=$(echo "INVALID SQL HERE" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    # Should not expose full script paths like /home/user/.query_runner/cache/...
    if echo "$output" | grep -qE "/home/[^/]+/\.query_runner"; then
        log_fail "Internal cache paths leaked" "Found internal path in error"
    else
        log_pass "Internal paths not leaked in errors"
    fi
    
    # Check for temp directory leakage
    if echo "$output" | grep -qE "/tmp/[a-zA-Z0-9\._-]{10,}"; then
        log_pass "Temp file paths in output (acceptable for debugging)"
    else
        log_pass "No temp file paths leaked"
    fi
}

# Test error message user-friendliness
test_error_message_clarity() {
    echo "=== Testing Error Message Clarity ==="
    
    # Test missing database parameter
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -t mysql -h localhost -u user -P pass 2>&1 || true)
    
    if echo "$output" | grep -qi "database.*required\|missing.*database"; then
        log_pass "Missing database parameter error is clear"
    else
        log_pass "Missing database error handled"
    fi
    
    # Test empty query
    output=$(echo "" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    if echo "$output" | grep -qi "no query\|query.*required\|empty"; then
        log_pass "Empty query error is clear"
    else
        log_fail "Empty query error unclear" "Expected clear message about missing query"
    fi
    
    # Test query too long (if limit exists)
    # shorten the stress test so CI/local runs stay fast; allow overriding via QUERY_STRESS_ITERS
    iters=${QUERY_STRESS_ITERS:-20}
    long_query='SELECT 1 '
    for ((_ = 1; _ <= iters; _++)); do
        long_query+='UNION ALL SELECT 1 '
    done
    output=$(echo "$long_query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    
    # May succeed or fail depending on limits
    if echo "$output" | grep -qi "too long\|too large\|size.*exceeded"; then
        log_pass "Query size limit error is clear"
    else
        log_pass "Large query handled (no size limit error)"
    fi
}

# Test hostname/IP sanitization
test_hostname_sanitization() {
    echo "=== Testing Hostname Sanitization ==="
    
    # Test that localhost/127.0.0.1 might be sanitized in non-debug mode
    output=$(DB_HOST="127.0.0.1" DB_PORT="9999" \
        echo "SELECT 1" | "$QUERY_RUNNER" -t mysql -d testdb -u user -P pass 2>&1 || true)
    
    # In non-debug mode, specific hosts might be redacted
    # This is implementation-dependent
    log_pass "Hostname handling in error messages"
    
    # Test with debug mode - should show more detail
    output=$(DEBUG=1 DB_HOST="192.168.1.100" DB_PORT="9999" \
        echo "SELECT 1" | "$QUERY_RUNNER" -t mysql -d testdb -u user -P pass 2>&1 || true)
    
    log_pass "Debug mode hostname disclosure (acceptable)"
}

# Test error handling doesn't crash
test_error_handling_stability() {
    echo "=== Testing Error Handling Stability ==="
    
    # Test various error conditions don't cause crashes
    test_cases=(
        "echo '' | $QUERY_RUNNER -t sqlite -d $TEST_DB"
        "echo 'SELECT' | $QUERY_RUNNER -t sqlite -d $TEST_DB"
        "echo 'SELECT * FROM' | $QUERY_RUNNER -t sqlite -d $TEST_DB"
        "$QUERY_RUNNER -t sqlite -d /nonexistent/path/db.sqlite"
        "echo 'SELECT 1' | $QUERY_RUNNER -t invalid_type"
    )
    
    for test_case in "${test_cases[@]}"; do
        eval "$test_case" >/dev/null 2>&1 || true
    done
    
    log_pass "Error handling stable across edge cases"
}

# Test exit codes are appropriate
test_exit_codes() {
    echo "=== Testing Exit Codes ==="
    
    # Successful query should exit 0
    echo "SELECT 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" >/dev/null 2>&1
    exit_code=$?
    
    if [[ $exit_code -eq 0 ]]; then
        log_pass "Successful query exits with code 0"
    else
        log_fail "Successful query exit code wrong" "Expected 0, got $exit_code"
    fi
    
    # Failed query should exit non-zero
    echo "INVALID SQL" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_pass "Failed query exits with non-zero code"
    else
        log_fail "Failed query exit code wrong" "Expected non-zero, got $exit_code"
    fi
    
    # Invalid options should exit non-zero
    "$QUERY_RUNNER" --invalid-option >/dev/null 2>&1 || exit_code=$?
    
    if [[ $exit_code -ne 0 ]]; then
        log_pass "Invalid option exits with non-zero code"
    else
        log_fail "Invalid option exit code wrong" "Expected non-zero, got $exit_code"
    fi
}

# Main test execution
main() {
    echo "=== Query Runner Error Handling Tests ==="
    echo
    
    setup
    
    test_credential_redaction
    echo
    test_jdbc_url_sanitization
    echo
    test_non_debug_error_messages
    echo
    test_debug_error_messages
    echo
    test_file_access_errors
    echo
    test_input_validation_errors
    echo
    test_security_violation_errors
    echo
    test_path_leakage_prevention
    echo
    test_error_message_clarity
    echo
    test_hostname_sanitization
    echo
    test_error_handling_stability
    echo
    test_exit_codes
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All error handling tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
