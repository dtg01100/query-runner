#!/bin/bash

# Test script for input validation hardening with SQLite
# This script tests various malicious inputs to ensure they are properly handled

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/test_input_validation.db"
QUERY_RUNNER="$SCRIPT_DIR/query_runner"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Log test results
log_test() {
    local test_name="$1"
    local result="$2"
    local expected="$3"
    local actual="$4"
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    
    if [[ "$result" == "PASS" ]]; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} $test_name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} $test_name"
        echo "  Expected: $expected"
        echo "  Actual: $actual"
    fi
}

# Run a test command and capture output
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    local expected_exit_code="${4:-0}"
    
    echo "Running: $test_name"
    
    # Run the command and capture output and exit code
    local output
    local exit_code
    output=$(eval "$test_command" 2>&1) || exit_code=$?
    
    # Check if the test passed
    if [[ "$expected_result" == "should_fail" ]]; then
        if [[ $exit_code -ne 0 ]]; then
            log_test "$test_name" "PASS" "failure" "failure (exit code: $exit_code)"
        else
            log_test "$test_name" "FAIL" "failure" "success"
        fi
    else
        if [[ $exit_code -eq 0 ]]; then
            log_test "$test_name" "PASS" "success" "success"
        else
            log_test "$test_name" "FAIL" "success" "failure (exit code: $exit_code)"
        fi
    fi
    
    # Show output for debugging if needed
    if [[ -n "$output" ]]; then
        echo "  Output: $output"
    fi
    echo
}

# Create test SQLite database
create_test_db() {
    echo "Creating test SQLite database..."
    
    # Create database with test tables
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL
);

CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL
);

-- Insert test data
INSERT INTO users (username, email) VALUES 
    ('alice', 'alice@example.com'),
    ('bob', 'bob@example.com'),
    ('charlie', 'charlie@example.com');

INSERT INTO products (name, price) VALUES
    ('Laptop', 999.99),
    ('Mouse', 25.50),
    ('Keyboard', 75.00);
EOF
}

# Clean up test database
cleanup() {
    if [[ -f "$TEST_DB" ]]; then
        rm -f "$TEST_DB"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Main test execution
main() {
    echo "=== Query Runner Input Validation Tests ==="
    echo "Testing with SQLite database..."
    echo
    
    # Create test database
    create_test_db
    
    # Test 1: Valid SELECT query
    run_test "Valid SELECT query" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'SELECT * FROM users LIMIT 2'" \
        "should_pass"
    
    # Test 2: SQL injection attempt with UNION
    run_test "SQL injection attempt with UNION" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'SELECT * FROM users UNION SELECT * FROM products'" \
        "should_fail"
    
    # Test 3: INSERT statement (should be blocked)
    run_test "INSERT statement (should be blocked)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'INSERT INTO users (username, email) VALUES (\"test\", \"test@test.com\")'" \
        "should_fail"
    
    # Test 4: UPDATE statement (should be blocked)
    run_test "UPDATE statement (should be blocked)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'UPDATE users SET email = \"hacker@evil.com\" WHERE username = \"alice\"'" \
        "should_fail"
    
    # Test 5: DELETE statement (should be blocked)
    run_test "DELETE statement (should be blocked)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'DELETE FROM users WHERE username = \"alice\"'" \
        "should_fail"
    
    # Test 6: DROP statement (should be blocked)
    run_test "DROP statement (should be blocked)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'DROP TABLE users'" \
        "should_fail"
    
    # Test 7: Multiple statements (should be blocked)
    run_test "Multiple statements (should be blocked)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'SELECT * FROM users; DROP TABLE users'" \
        "should_fail"
    
    # Test 8: Path traversal attempt in database path
    run_test "Path traversal attempt in database path" \
        "$QUERY_RUNNER -t sqlite -d '../../../etc/passwd' -f text 'SELECT 1'" \
        "should_fail"
    
    # Test 9: Command injection in host parameter
    run_test "Command injection in host parameter" \
        "$QUERY_RUNNER -t sqlite -h 'localhost; rm -rf /' -d '$TEST_DB' -f text 'SELECT 1'" \
        "should_fail"
    
    # Test 10: Invalid format parameter
    run_test "Invalid format parameter" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f 'invalid_format' 'SELECT 1'" \
        "should_fail"
    
    # Test 11: Very long query (DoS attempt)
    run_test "Very long query (DoS attempt)" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'SELECT * FROM users WHERE username = \"$(head -c 2000000 /dev/zero | tr '\0' 'a')\"'" \
        "should_fail"
    
    # Test 12: Null byte injection
    run_test "Null byte injection" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text $'SELECT * FROM users WHERE username = \"test\\0; DROP TABLE products\"'" \
        "should_fail"
    
    # Test 13: Valid UNION with same table (should be allowed)
    run_test "Valid UNION with same table" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'SELECT username FROM users WHERE id = 1 UNION ALL SELECT username FROM users WHERE id = 2'" \
        "should_pass"
    
    # Test 14: Valid WITH clause with UNION (should be allowed)
    run_test "Valid WITH clause with UNION" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text 'WITH cte AS (SELECT username FROM users UNION ALL SELECT name FROM products) SELECT * FROM cte'" \
        "should_pass"
    
    # Test 15: Environment file with malicious content
    echo "Creating malicious environment file..."
    cat > /tmp/malicious.env << 'EOF'
DB_HOST=localhost; rm -rf /
DB_USER=admin' OR '1'='1
DB_PASSWORD=test
DB_DATABASE=/etc/passwd
EOF
    run_test "Environment file with malicious content" \
        "$QUERY_RUNNER --env-file /tmp/malicious.env -f text 'SELECT 1'" \
        "should_fail"
    rm -f /tmp/malicious.env
    
    # Test 16: Query file with path traversal
    echo "Creating query file with path traversal..."
    echo 'SELECT * FROM users' > /tmp/test_query.sql
    run_test "Query file with valid content" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text '/tmp/test_query.sql'" \
        "should_pass"
    rm -f /tmp/test_query.sql
    
    # Test 17: Query file with path traversal attempt
    echo "Creating query file with path traversal attempt..."
    echo '../../../etc/passwd' > /tmp/path_traversal.sql
    run_test "Query file with path traversal attempt" \
        "$QUERY_RUNNER -t sqlite -d '$TEST_DB' -f text '/tmp/path_traversal.sql'" \
        "should_fail"
    rm -f /tmp/path_traversal.sql
    
    # Print test summary
    echo "=== Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED tests failed!${NC}"
        return 1
    fi
}

# Run the tests
main "$@"