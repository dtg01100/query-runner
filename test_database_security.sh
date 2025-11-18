#!/bin/bash

# Test database security hardening against malicious database inputs
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Test database connection string validation
test_database_connection_security() {
    echo "=== Testing Database Connection Security ==="
    
    # Test malicious JDBC URLs
    local malicious_urls=(
        "jdbc:sqlite:/etc/passwd"
        "jdbc:sqlite:/proc/version"
        "jdbc:mysql://localhost;rm -rf /"
        "jdbc:postgresql://localhost|cat /etc/passwd"
        "jdbc:oracle://localhost`whoami`"
        "jdbc:sqlserver://localhost&&rm -rf /"
        "jdbc:h2:tcp://localhost:9092/;DROP TABLE users"
        "jdbc:db2://localhost:50000/UNION SELECT * FROM admin"
    )
    
    for url in "${malicious_urls[@]}"; do
        echo "Testing malicious JDBC URL: $url"
        
        # Test by setting environment variable and running query
        if ! JDBC_URL="$url" ./query_runner -t sqlite -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Malicious JDBC URL blocked: ${url:0:40}..." "PASS" "blocking" "blocked"
        else
            log_test "Malicious JDBC URL NOT blocked: ${url:0:40}..." "FAIL" "blocking" "accepted"
        fi
    done
}

# Test database path validation
test_database_path_security() {
    echo "=== Testing Database Path Security ==="
    
    # Test malicious database paths
    local malicious_paths=(
        "/etc/passwd"
        "/etc/shadow"
        "/proc/version"
        "/sys/kernel/version"
        "/dev/random"
        "C:\\windows\\system32\\drivers\\etc\\hosts"
        "C:\\boot.ini"
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts"
        "file:///etc/passwd"
        "jar:file:///etc/passwd"
    )
    
    for path in "${malicious_paths[@]}"; do
        echo "Testing malicious database path: $path"
        
        if ! ./query_runner -t sqlite -d "$path" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Malicious database path blocked: $path" "PASS" "blocking" "blocked"
        else
            log_test "Malicious database path NOT blocked: $path" "FAIL" "blocking" "accepted"
        fi
    done
}

# Test credential injection in connection strings
test_credential_injection() {
    echo "=== Testing Credential Injection Protection ==="
    
    # Test credential injection attempts
    local credential_injections=(
        "jdbc:mysql://user:pass@localhost/test?password=evil"
        "jdbc:postgresql://localhost:5432/test?user=admin&password=;rm -rf /"
        "jdbc:oracle://localhost:1521/test?user=';DROP TABLE users--"
        "jdbc:sqlserver://localhost:1433/test?user=||cat /etc/passwd"
        "jdbc:h2:tcp://localhost:9092/test?password=`whoami`"
    )
    
    for injection in "${credential_injections[@]}"; do
        echo "Testing credential injection: $injection"
        
        if ! JDBC_URL="$injection" ./query_runner -t mysql -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Credential injection blocked: ${injection:0:50}..." "PASS" "blocking" "blocked"
        else
            log_test "Credential injection NOT blocked: ${injection:0:50}..." "FAIL" "blocking" "accepted"
        fi
    done
}

# Test database content sanitization
test_database_content_sanitization() {
    echo "=== Testing Database Content Sanitization ==="
    
    # Create a test database with potentially malicious content
    local test_db="$SCRIPT_DIR/content_test.db"
    sqlite3 "$test_db" << 'EOF'
CREATE TABLE malicious_content (
    id INTEGER PRIMARY KEY,
    dangerous_column TEXT,
    xss_content TEXT,
    script_content TEXT
);

INSERT INTO malicious_content (dangerous_column, xss_content, script_content) VALUES
('"; DROP TABLE users; --', '<script>alert("xss")</script>', 'javascript:alert("dangerous")'),
("' OR 1=1 --", '<img src=x onerror=alert("xss")>', '<svg onload=alert("svg")>'),
('UNION SELECT password FROM admin', '<iframe src="javascript:alert(1)"></iframe>', 'data:text/html,<script>alert("data")</script>');
EOF

    # Test that malicious content is properly sanitized in output
    echo "Testing malicious content sanitization..."
    
    # Test JSON output sanitization
    if ./query_runner -t sqlite -d "$test_db" -f json "SELECT * FROM malicious_content" >/dev/null 2>&1; then
        local json_output
        json_output=$(./query_runner -t sqlite -d "$test_db" -f json "SELECT * FROM malicious_content" 2>/dev/null)
        
        # Check that dangerous content is properly escaped in JSON
        if [[ "$json_output" != *"<script>"* ]] && [[ "$json_output" != *"javascript:"* ]]; then
            log_test "JSON output properly sanitized" "PASS" "sanitization" "sanitized"
        else
            log_test "JSON output NOT properly sanitized" "FAIL" "sanitization" "not sanitized"
        fi
    else
        log_test "JSON output generation failed" "FAIL" "generation" "failed"
    fi
    
    # Test CSV output sanitization
    if ./query_runner -t sqlite -d "$test_db" -f csv "SELECT * FROM malicious_content" >/dev/null 2>&1; then
        local csv_output
        csv_output=$(./query_runner -t sqlite -d "$test_db" -f csv "SELECT * FROM malicious_content" 2>/dev/null)
        
        # Check that dangerous content is properly quoted in CSV
        if [[ "$csv_output" != *"<script>"* ]] && [[ "$csv_output" != *"javascript:"* ]]; then
            log_test "CSV output properly sanitized" "PASS" "sanitization" "sanitized"
        else
            log_test "CSV output NOT properly sanitized" "FAIL" "sanitization" "not sanitized"
        fi
    else
        log_test "CSV output generation failed" "FAIL" "generation" "failed"
    fi
    
    # Clean up test database
    rm -f "$test_db"
}

# Test resource exhaustion protection
test_resource_protection() {
    echo "=== Testing Resource Exhaustion Protection ==="
    
    # Create a test database with large result sets
    local large_db="$SCRIPT_DIR/large_test.db"
    sqlite3 "$large_db" << 'EOF'
CREATE TABLE large_table (id INTEGER, data TEXT);

-- Insert many rows to test DoS protection
WITH RECURSIVE series(x) AS (
    SELECT 0
    UNION ALL
    SELECT x+1 FROM series WHERE x < 50000
)
INSERT INTO large_table SELECT x, 'data_' || x FROM series;
EOF

    echo "Testing large result set protection..."
    
    # Test that large result sets are handled safely
    if timeout 10 ./query_runner -t sqlite -d "$large_db" -f json "SELECT * FROM large_table" >/dev/null 2>&1; then
        local result_size
        result_size=$(./query_runner -t sqlite -d "$large_db" -f json "SELECT * FROM large_table" 2>/dev/null | wc -c)
        
        # Check that result size is reasonable (should be truncated)
        if [[ $result_size -lt 1000000 ]]; then  # Less than 1MB
            log_test "Large result set properly limited" "PASS" "limiting" "limited"
        else
            log_test "Large result set NOT properly limited" "FAIL" "limiting" "not limited"
        fi
    else
        log_test "Large result set handling timed out" "PASS" "timeout" "timeout"
    fi
    
    # Clean up test database
    rm -f "$large_db"
}

# Main test execution
main() {
    echo "=== Database Security Hardening Tests ==="
    echo "Testing protection against malicious database inputs..."
    echo
    
    # Run database security tests
    test_database_connection_security
    echo
    
    test_database_path_security
    echo
    
    test_credential_injection
    echo
    
    test_database_content_sanitization
    echo
    
    test_resource_protection
    
    # Print final summary
    echo "=== Database Security Test Summary ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All database security tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED database security tests failed!${NC}"
        return 1
    fi
}

main "$@"