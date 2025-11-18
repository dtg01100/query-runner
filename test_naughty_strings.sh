#!/bin/bash

# Test script for input validation against naughty strings
# This script tests various potentially problematic strings to ensure they are properly handled

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/naughty_test.db"
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

# Clean up test database
cleanup() {
    if [[ -f "$TEST_DB" ]]; then
        rm -f "$TEST_DB"
    fi
}

# Set up cleanup trap
trap cleanup EXIT

# Create test SQLite database
create_test_db() {
    echo "Creating test SQLite database for naughty strings..."
    
    # Create database with test tables
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    username TEXT NOT NULL,
    email TEXT NOT NULL
);

INSERT INTO users (username, email) VALUES 
    ('alice', 'alice@example.com'),
    ('bob', 'bob@example.com');
EOF
}

# Test CLI parameter validation with naughty strings
test_cli_parameters() {
    echo "=== Testing CLI Parameter Validation ==="
    
    # Read naughty strings and test each one
    while IFS= read -r naughty_string || [[ -n "$naughty_string" ]]; do
        # Skip empty lines and comments
        [[ -z "$naughty_string" || "$naughty_string" =~ ^# ]] && continue
        
        # Escape the string for shell usage
        escaped_string=$(printf '%q' "$naughty_string")
        
        # Test host parameter
        if ! ./query_runner -t sqlite -h "$naughty_string" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Host validation: $naughty_string" "PASS" "rejection" "rejected"
        else
            log_test "Host validation: $naughty_string" "FAIL" "rejection" "accepted"
        fi
        
        # Test database parameter  
        if ! ./query_runner -t sqlite -d "$naughty_string" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Database validation: $naughty_string" "PASS" "rejection" "rejected"
        else
            log_test "Database validation: $naughty_string" "FAIL" "rejection" "accepted"
        fi
        
        # Test user parameter
        if ! ./query_runner -t sqlite -u "$naughty_string" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "User validation: $naughty_string" "PASS" "rejection" "rejected"
        else
            log_test "User validation: $naughty_string" "FAIL" "rejection" "accepted"
        fi
        
    done < naughty_strings.txt
}

# Test SQL query validation with naughty strings
test_sql_queries() {
    echo "=== Testing SQL Query Validation ==="
    
    # Test basic SELECT with naughty strings in WHERE clauses
    while IFS= read -r naughty_string || [[ -n "$naughty_string" ]]; do
        # Skip empty lines and comments
        [[ -z "$naughty_string" || "$naughty_string" =~ ^# ]] && continue
        
        # Escape single quotes for SQL
        escaped_string=$(echo "$naughty_string" | sed "s/'/''/g")
        
        # Test SELECT with naughty string in WHERE clause
        query="SELECT * FROM users WHERE username = '$escaped_string'"
        
        if ./query_runner -t sqlite -d "$TEST_DB" -f text "$query" >/dev/null 2>&1; then
            log_test "SQL query with naughty string: ${naughty_string:0:50}..." "PASS" "acceptance" "accepted"
        else
            log_test "SQL query with naughty string: ${naughty_string:0:50}..." "FAIL" "acceptance" "rejected"
        fi
        
        # Test for SQL injection attempts
        injection_query="SELECT * FROM users WHERE username = '$naughty_string'; DROP TABLE users;"
        
        if ! ./query_runner -t sqlite -d "$TEST_DB" -f text "$injection_query" >/dev/null 2>&1; then
            log_test "SQL injection attempt blocked: ${naughty_string:0:50}..." "PASS" "rejection" "rejected"
        else
            log_test "SQL injection attempt NOT blocked: ${naughty_string:0:50}..." "FAIL" "rejection" "accepted"
        fi
        
    done < naughty_strings.txt
}

# Test environment file parsing with naughty strings
test_env_file() {
    echo "=== Testing Environment File Parsing ==="
    
    local test_count=0
    
    while IFS= read -r naughty_string || [[ -n "$naughty_string" ]]; do
        # Skip empty lines and comments
        [[ -z "$naughty_string" || "$naughty_string" =~ ^# ]] && continue
        
        test_count=$((test_count + 1))
        
        # Skip if we've tested enough to keep the test reasonable
        if [[ $test_count -gt 20 ]]; then
            break
        fi
        
        # Create environment file with naughty string
        cat > /tmp/naughty_env.env << EOF
DB_HOST=$naughty_string
DB_USER=$naughty_string
DB_PASSWORD=$naughty_string
DB_DATABASE=$naughty_string
EOF
        
        # Test environment file parsing
        if ! ./query_runner --env-file /tmp/naughty_env.env -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Env file with naughty string: ${naughty_string:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "Env file with naughty string: ${naughty_string:0:30}..." "FAIL" "rejection" "accepted"
        fi
        
    done < naughty_strings.txt
    
    rm -f /tmp/naughty_env.env
}

# Test query file content with naughty strings
test_query_files() {
    echo "=== Testing Query File Content ==="
    
    local test_count=0
    
    while IFS= read -r naughty_string || [[ -n "$naughty_string" ]]; do
        # Skip empty lines and comments
        [[ -z "$naughty_string" || "$naughty_string" =~ ^# ]] && continue
        
        test_count=$((test_count + 1))
        
        # Skip if we've tested enough to keep the test reasonable
        if [[ $test_count -gt 10 ]]; then
            break
        fi
        
        # Test valid query with naughty string content
        echo "SELECT * FROM users WHERE username = '$naughty_string'" > /tmp/naughty_query.sql
        
        if ./query_runner -t sqlite -d "$TEST_DB" -f text "/tmp/naughty_query.sql" >/dev/null 2>&1; then
            log_test "Query file with naughty string: ${naughty_string:0:30}..." "PASS" "acceptance" "accepted"
        else
            log_test "Query file with naughty string: ${naughty_string:0:30}..." "FAIL" "acceptance" "rejected"
        fi
        
        # Test malicious query in file
        echo "SELECT * FROM users WHERE username = '$naughty_string'; DROP TABLE users;" > /tmp/malicious_query.sql
        
        if ! ./query_runner -t sqlite -d "$TEST_DB" -f text "/tmp/malicious_query.sql" >/dev/null 2>&1; then
            log_test "Malicious query file blocked: ${naughty_string:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "Malicious query file NOT blocked: ${naughty_string:0:30}..." "FAIL" "rejection" "accepted"
        fi
        
    done < naughty_strings.txt
    
    rm -f /tmp/naughty_query.sql /tmp/malicious_query.sql
}

# Download and set up naughty strings list
setup_naughty_strings() {
    echo "Setting up naughty strings test data..."
    
    if [[ ! -f "naughty_strings.txt" ]]; then
        echo "Downloading naughty strings list..."
        if command -v curl >/dev/null 2>&1; then
            curl -s -o naughty_strings.txt "https://raw.githubusercontent.com/minimaxir/big-list-of-naughty-strings/master/blns.csv" || {
                echo "Failed to download naughty strings, creating minimal test set..."
                create_minimal_naughty_strings
            }
        elif command -v wget >/dev/null 2>&1; then
            wget -q -O naughty_strings.txt "https://raw.githubusercontent.com/minimaxir/big-list-of-naughty-strings/master/blns.csv" || {
                echo "Failed to download naughty strings, creating minimal test set..."
                create_minimal_naughty_strings
            }
        else
            echo "No download tool available, creating minimal test set..."
            create_minimal_naughty_strings
        fi
    fi
}

# Create a minimal set of naughty strings for testing
create_minimal_naughty_strings() {
    cat > naughty_strings.txt << 'EOF'
# Basic injection attempts
'; DROP TABLE users; --
" OR 1=1 --
' OR '1'='1
admin'--

# Path traversal
../../../etc/passwd
..\\..\\..\\windows\\system32\\drivers\\etc\\hosts

# XSS attempts
<script>alert('xss')</script>
javascript:alert('xss')

# Command injection
; rm -rf /
| rm -rf /
`rm -rf /`

# Special characters
"<>|&*()'
\n\r\t\b\f

# Unicode and encoding issues
%C0%AF
%2e%2e%2f
../../../etc/passwd

# Null bytes and binary
test\0string
test\x00string

# Long strings
aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa

# SQL keywords
UNION SELECT
INSERT INTO
UPDATE SET
DELETE FROM
DROP TABLE

# Format strings
%s%s%s%s%s%s%s%s%s%s
%d%d%d%d%d%d%d%d%d%d

# JavaScript
function(){alert('test')}
eval('alert("test")')

# XML/HTML
<?xml version="1.0"?>
<!DOCTYPE test [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>

# JSON
{"malicious": "code"}
[[[[]]]]

# Base64 encoded attempts
Li4vLi4vLi4vZXRjL3Bhc3N3ZAA=
cGluZyAtbmMgMTI3LjAuMC4xIDk5OTk=

# Time-based attempts
'; WAITFOR DELAY '00:00:05'--

# Comments
/* DROP TABLE users */
-- DROP TABLE users
# DROP TABLE users

# Encoded payloads
%3B%20DROP%20TABLE%20users%3B%20--
; DROP TABLE users; --

# Nested attempts
'"; DROP TABLE users; --"
"'; DROP TABLE users; --'
EOF
}

# Main test execution
main() {
    echo "=== Query Runner Naughty Strings Input Validation Tests ==="
    echo
    
    # Setup
    setup_naughty_strings
    
    # Create test database
    create_test_db
    
    # Run tests
    test_cli_parameters
    test_sql_queries  
    test_env_file
    test_query_files
    
    # Print test summary
    echo "=== Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All naughty string tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED naughty string tests failed!${NC}"
        return 1
    fi
}

# Run the tests
main "$@"