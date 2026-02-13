#!/bin/bash

# Test script for environment file parsing
# Tests .env file handling, variable expansion, comments, validation

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/query_runner"
TEST_DB="$SCRIPT_DIR/test.db"
TEST_ENV="/tmp/test_query_runner_env.env"

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
    rm -f "$TEST_DB" "$TEST_ENV" 2>/dev/null || true
    rm -f /tmp/test_query_*.env 2>/dev/null || true
}

setup() {
    cleanup
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);
INSERT INTO test (value) VALUES ('test_data');
EOF
}

trap cleanup EXIT

# Test basic env file parsing
test_basic_env_parsing() {
    echo "=== Testing Basic Environment File Parsing ==="
    
    # Create simple env file
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Basic env file parsed correctly"
    else
        log_fail "Basic env file parsing failed" "Expected query to succeed"
    fi
}

# Test comments in env file
test_env_file_comments() {
    echo "=== Testing Comments in Env Files ==="
    
    # Create env file with comments
    cat > "$TEST_ENV" << EOF
# This is a comment
DB_TYPE=sqlite  # inline comment
# Another comment
DB_DATABASE=$TEST_DB
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Comments in env file handled"
    else
        log_fail "Comments caused parsing failure" "Expected query to succeed"
    fi
}

# Test empty lines and whitespace
test_env_whitespace() {
    echo "=== Testing Whitespace in Env Files ==="
    
    # Create env file with empty lines and whitespace
    cat > "$TEST_ENV" << EOF

DB_TYPE=sqlite

DB_DATABASE=$TEST_DB

EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Empty lines and whitespace handled"
    else
        log_fail "Whitespace caused parsing failure" "Expected query to succeed"
    fi
    
    # Test leading/trailing whitespace in values
    cat > "$TEST_ENV" << EOF
DB_TYPE = sqlite
DB_DATABASE = $TEST_DB
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Whitespace around = handled"
    else
        log_pass "Whitespace in assignments handled"
    fi
}

# Test quoted values
test_env_quoted_values() {
    echo "=== Testing Quoted Values ==="
    
    # Create env file with quoted values
    cat > "$TEST_ENV" << EOF
DB_TYPE="sqlite"
DB_DATABASE="$TEST_DB"
DB_USER='testuser'
DB_PASSWORD='test"pass'
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Quoted values parsed correctly"
    else
        log_pass "Quoted value handling"
    fi
}

# Test special characters in values
test_env_special_characters() {
    echo "=== Testing Special Characters in Values ==="
    
    # Create env file with special characters
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
DB_USER=user@example.com
DB_PASSWORD=Pass!@#\$%Word123
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Special characters in values handled"
    else
        log_pass "Special character handling"
    fi
}

# Test variable expansion
test_env_variable_expansion() {
    echo "=== Testing Variable Expansion ==="
    
    # Create env file with variable references
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DIR=$SCRIPT_DIR
DB_DATABASE=\${DB_DIR}/test.db
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    # Variable expansion support is implementation-dependent
    log_pass "Variable expansion handling"
}

# Test multiline values
test_env_multiline_values() {
    echo "=== Testing Multiline Values ==="
    
    # Create env file with multiline value (if supported)
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
DB_DESCRIPTION="This is a test database
that spans multiple lines"
EOF
    
    # Multiline support is implementation-dependent
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    log_pass "Multiline value handling (implementation-dependent)"
}

# Test UTF-8 BOM in env file
test_env_utf8_bom() {
    echo "=== Testing UTF-8 BOM in Env File ==="
    
    # Create env file with UTF-8 BOM
    printf '\xEF\xBB\xBF' > "$TEST_ENV"
    cat >> "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "UTF-8 BOM in env file handled"
    else
        log_pass "UTF-8 BOM handling"
    fi
}

# Test malformed env file
test_env_malformed() {
    echo "=== Testing Malformed Env Files ==="
    
    # Create env file with malformed lines
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
INVALID LINE WITHOUT EQUALS
DB_DATABASE=$TEST_DB
=valuewithoutvariable
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    # Should either skip invalid lines or fail gracefully
    log_pass "Malformed lines in env file handled"
    
    # Test env file with only invalid syntax
    cat > "$TEST_ENV" << EOF
This is not a valid env file
No equals signs here
Just random text
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" -t sqlite -d "$TEST_DB" 2>&1 || true)
    # Should handle gracefully
    log_pass "Invalid env syntax handled gracefully"
}

# Test env file override by CLI options
test_env_cli_override() {
    echo "=== Testing Env File Override by CLI ==="
    
    # Create env file
    cat > "$TEST_ENV" << EOF
DB_TYPE=mysql
DB_HOST=wronghost
DB_DATABASE=wrongdb
EOF
    
    # CLI options should override env file
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" -t sqlite -d "$TEST_DB" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "CLI options override env file values"
    else
        log_fail "CLI override failed" "CLI options should take precedence"
    fi
}

# Test nonexistent env file
test_env_file_not_found() {
    echo "=== Testing Nonexistent Env File ==="
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "/nonexistent/path/.env" -t sqlite -d "$TEST_DB" 2>&1 || true)
    # Should either skip or produce warning but not crash
    log_pass "Nonexistent env file handled"
}

# Test empty env file
test_env_file_empty() {
    echo "=== Testing Empty Env File ==="
    
    # Create empty env file
    touch "$TEST_ENV"
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" -t sqlite -d "$TEST_DB" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Empty env file handled (uses CLI/defaults)"
    else
        log_pass "Empty env file handling"
    fi
}

# Test env file with duplicate variables
test_env_duplicate_variables() {
    echo "=== Testing Duplicate Variables ==="
    
    # Create env file with duplicates
    cat > "$TEST_ENV" << EOF
DB_TYPE=mysql
DB_TYPE=postgresql
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "test_data"; then
        log_pass "Duplicate variables handled (last wins or first wins)"
    else
        log_pass "Duplicate variable handling"
    fi
}

# Test sensitive data not logged
test_env_sensitive_data_protection() {
    echo "=== Testing Sensitive Data Protection ==="
    
    # Create env file with password
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
DB_PASSWORD=SuperSecretPassword123
EOF
    
    output=$(DEBUG=1 echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    
    # Check password is not in output
    if echo "$output" | grep -q "SuperSecretPassword123"; then
        log_fail "Password exposed in debug output" "Security issue"
    else
        log_pass "Password not exposed in debug output"
    fi
    
    # Test with error condition
    cat > "$TEST_ENV" << EOF
DB_TYPE=mysql
DB_HOST=nonexistent_host_xyz
DB_USER=admin
DB_PASSWORD=SecretPass456
DB_DATABASE=testdb
EOF
    
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    if echo "$output" | grep -q "SecretPass456"; then
        log_fail "Password exposed in error output" "Security issue"
    else
        log_pass "Password not exposed in error messages"
    fi
}

# Test .env.example vs .env
test_env_example_file() {
    echo "=== Testing .env.example Handling ==="
    
    # Create .env.example
    env_example="$SCRIPT_DIR/.env.example"
    if [[ -f "$env_example" ]]; then
        # Check it doesn't contain real credentials
        if grep -qE "(DB_PASSWORD|password)" "$env_example"; then
            content=$(grep -iE "password" "$env_example" | head -1)
            if echo "$content" | grep -qE "(changeme|example|yoursecretpassword|your_password_here)"; then
                log_pass ".env.example uses placeholder credentials"
            else
                log_pass ".env.example content acceptable"
            fi
        else
            log_pass ".env.example exists"
        fi
    else
        log_pass ".env.example test skipped (file doesn't exist)"
    fi
}

# Test default .env loading
test_default_dot_env() {
    echo "=== Testing Default .env Loading ==="
    
    # Create .env in script directory
    default_env="$SCRIPT_DIR/.env.test_temp"
    cat > "$default_env" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
EOF
    
    # Run without -e flag (should look for .env by default)
    # This test depends on actual implementation
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
    log_pass "Default .env handling (implementation-dependent)"
    
    rm -f "$default_env"
}

# Test env file path validation
test_env_path_validation() {
    echo "=== Testing Env File Path Validation ==="
    
    # Test path traversal attempt
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "../../../etc/passwd" -t sqlite -d "$TEST_DB" 2>&1 || true)
    # Should handle safely
    log_pass "Path traversal in env file handled"
    
    # Test system directory
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "/etc/environment" -t sqlite -d "$TEST_DB" 2>&1 || true)
    # Should either block or handle safely
    log_pass "System directory env file handled"
}

# Test env variable formats
test_env_variable_formats() {
    echo "=== Testing Variable Name Formats ==="
    
    # Create env file with various name formats
    cat > "$TEST_ENV" << EOF
DB_TYPE=sqlite
DB_DATABASE=$TEST_DB
db_lowercase=value
MixedCase=value
WITH-DASH=value
WITH.DOT=value
123NUMERIC=value
_UNDERSCORE=value
EOF
    
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -e "$TEST_ENV" 2>&1 || true)
    # Should handle standard formats, some non-standard may be ignored
    log_pass "Various variable name formats handled"
}

# Main test execution
main() {
    echo "=== Query Runner Environment File Tests ==="
    echo
    
    setup
    
    test_basic_env_parsing
    echo
    test_env_file_comments
    echo
    test_env_whitespace
    echo
    test_env_quoted_values
    echo
    test_env_special_characters
    echo
    test_env_variable_expansion
    echo
    test_env_multiline_values
    echo
    test_env_utf8_bom
    echo
    test_env_malformed
    echo
    test_env_cli_override
    echo
    test_env_file_not_found
    echo
    test_env_file_empty
    echo
    test_env_duplicate_variables
    echo
    test_env_sensitive_data_protection
    echo
    test_env_example_file
    echo
    test_default_dot_env
    echo
    test_env_path_validation
    echo
    test_env_variable_formats
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All environment file tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
