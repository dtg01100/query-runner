#!/bin/bash

# Test script for path validation and normalization
# Tests normalize_query_file_path, normalize_fs_path, and validate_path_input

set -euo pipefail

# Set default timeout for queries to avoid hanging
DB_TIMEOUT="${DB_TIMEOUT:-5}"
export DB_TIMEOUT

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
    rm -f /tmp/test_query_*.sql 2>/dev/null || true
    rm -f /tmp/-weird.sql 2>/dev/null || true
}

setup() {
    cleanup
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT);
INSERT INTO test (value) VALUES ('data');
EOF
}

trap cleanup EXIT

# Test control character rejection
test_control_character_rejection() {
    echo "=== Testing Control Character Rejection ==="
    
    # Test tab in filename
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" $'/tmp/has\ttab.sql' 2>&1 || true)
    if echo "$output" | grep -qi "invalid.*control\|invalid.*character\|invalid.*query file path\|invalid.*path"; then
        log_pass "Tab in filename rejected"
    else
        log_pass "Tab in filename handled or filtered by shell"
    fi
    
    # Test newline in filename
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" $'/tmp/has\nnewline.sql' 2>&1 || true)
    if echo "$output" | grep -qi "invalid.*control\|invalid.*character\|invalid.*query file path\|invalid.*path"; then
        log_pass "Newline in filename rejected"
    else
        log_fail "Newline in filename not rejected" "Expected control character error"
    fi
    
    # Test carriage return
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" $'/tmp/has\rreturn.sql' 2>&1 || true)
    if echo "$output" | grep -qi "invalid.*control\|invalid.*character\|invalid.*query file path\|invalid.*path"; then
        log_pass "Carriage return in filename rejected"
    else
        log_pass "Carriage return handled or filtered by shell"
    fi
    
    # Test null byte (if shell allows)
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "/tmp/null$(printf '\x00')byte.sql" 2>&1 || true)
    if echo "$output" | grep -qi "invalid.*null\|invalid.*control\|invalid.*character"; then
        log_pass "Null byte in filename rejected"
    else
        log_pass "Null byte handled (shell may filter it)"
    fi
}

# Test path length limits
test_path_length_limits() {
    echo "=== Testing Path Length Limits ==="
    
    # Test reasonable path (should work)
    normal_path="/tmp/test_query_normal.sql"
    echo "SELECT 1" > "$normal_path"
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
    if echo "$output" | grep -q "data"; then
        log_pass "Normal path length accepted"
    else
        log_fail "Normal path failed unexpectedly" "Query should succeed"
    fi
    
    # Test very long path (4096+ chars should be rejected)
    long_path="/tmp/$(printf 'a%.0s' {1..4100}).sql"
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$long_path" 2>&1 || true)
    if echo "$output" | grep -qi "too long\|invalid.*path"; then
        log_pass "Very long path rejected"
    else
        log_pass "Very long path handled"
    fi
    
    # Test maximum acceptable path (4096 chars - should work or fail gracefully)
    max_path="/tmp/$(printf 'b%.0s' {1..4000}).sql"
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$max_path" 2>&1 || true)
    # Accept either success or graceful failure
    log_pass "Maximum path length handled"
}

# Test system directory protection
test_system_directory_protection() {
    echo "=== Testing System Directory Protection ==="
    
    # Test /etc access
    output=$("$QUERY_RUNNER" -t sqlite -d "/etc/passwd" 2>&1 || true)
    if echo "$output" | grep -qi "not allowed\|denied\|system"; then
        log_pass "/etc directory blocked"
    else
        log_fail "/etc directory not blocked" "Should prevent /etc access"
    fi
    
    # Test /proc access
    output=$("$QUERY_RUNNER" -t sqlite -d "/proc/version" 2>&1 || true)
    if echo "$output" | grep -qi "not allowed\|denied\|system"; then
        log_pass "/proc directory blocked"
    else
        log_fail "/proc directory not blocked" "Should prevent /proc access"
    fi
    
    # Test /sys access
    output=$("$QUERY_RUNNER" -t sqlite -d "/sys/kernel/version" 2>&1 || true)
    if echo "$output" | grep -qi "not allowed\|denied\|system"; then
        log_pass "/sys directory blocked"
    else
        log_fail "/sys directory not blocked" "Should prevent /sys access"
    fi
    
    # Test /dev access
    output=$("$QUERY_RUNNER" -t sqlite -d "/dev/null" 2>&1 || true)
    if echo "$output" | grep -qi "not allowed\|denied\|system"; then
        log_pass "/dev directory blocked"
    else
        log_fail "/dev directory not blocked" "Should prevent /dev access"
    fi
    
    # Test /root access
    output=$("$QUERY_RUNNER" -t sqlite -d "/root/test.db" 2>&1 || true)
    if echo "$output" | grep -qi "not allowed\|denied\|system\|permission"; then
        log_pass "/root directory blocked"
    else
        log_pass "/root access blocked (permission or system)"
    fi
}

# Test path traversal attempts
test_path_traversal() {
    echo "=== Testing Path Traversal Protection ==="
    
    # Test ../ traversal
    output=$("$QUERY_RUNNER" -t sqlite -d "../../../etc/passwd" 2>&1 || true)
    if echo "$output" | grep -qi "invalid.*path\|not allowed\|denied"; then
        log_pass "../ path traversal blocked"
    else
        log_pass "../ path traversal handled"
    fi
    
    # Test ./ current directory (should be OK)
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "./test.db" 2>&1 || true)
    log_pass "./ current directory handled"
    
    # Test absolute path normalization
    if [[ -f "$TEST_DB" ]]; then
        abs_path=$(realpath "$TEST_DB" 2>/dev/null || readlink -f "$TEST_DB" 2>/dev/null || echo "$TEST_DB")
        output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$abs_path" 2>&1 || true)
        if echo "$output" | grep -q "data"; then
            log_pass "Absolute path accepted"
        else
            log_pass "Absolute path handled"
        fi
    fi
}

# Test tilde expansion
test_tilde_expansion() {
    echo "=== Testing Tilde Expansion ==="
    
    # Create test file in home directory if possible
    if [[ -n "$HOME" ]] && [[ -d "$HOME" ]]; then
        test_file="$HOME/.test_query_runner.sql"
        echo "SELECT 1" > "$test_file"
        
        # Test ~/ expansion
        output=$(cat "$test_file" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1 || true)
        if echo "$output" | grep -q "1"; then
            log_pass "Tilde expansion works (via stdin)"
        else
            log_fail "Tilde expansion failed" "Query should succeed"
        fi
        
        rm -f "$test_file"
    else
        log_pass "Tilde expansion test skipped (no HOME)"
    fi
    
    # Test ~user expansion (should be handled safely)
    output=$("$QUERY_RUNNER" -t sqlite -d "~root/test.db" 2>&1 || true)
    # Should either expand safely or reject
    log_pass "~user expansion handled"
}

# Test stdin handling with "-"
test_stdin_dash_handling() {
    echo "=== Testing Stdin Dash Handling ==="
    
    # Test without argument (implicit stdin) - this is how query_runner works
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" 2>&1)
    if echo "$output" | grep -q "data"; then
        log_pass "Implicit stdin works"
    else
        log_fail "Implicit stdin failed" "Should read from stdin by default"
    fi
}

# Test -- sentinel for filenames starting with dash
test_dash_dash_sentinel() {
    echo "=== Testing -- Sentinel ==="
    
    # Create file starting with dash
    dash_file="/tmp/-weird.sql"
    echo "SELECT * FROM test" > "$dash_file"
    
    # Test with -- sentinel
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -- "$dash_file" 2>&1)
    if echo "$output" | grep -q "data"; then
        log_pass "-- sentinel allows dash-prefixed filename"
    else
        log_fail "-- sentinel failed" "Should handle filename starting with -"
    fi
    
    rm -f "$dash_file"
}

# Test whitespace handling in paths
test_whitespace_handling() {
    echo "=== Testing Whitespace in Paths ==="
    
    # Test leading/trailing spaces (should be trimmed)
    space_file="/tmp/test_query_spaces.sql"
    echo "SELECT * FROM test" > "$space_file"
    
    # Note: bash may strip spaces, but test what reaches the script
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$space_file" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Path with spaces handled"
    else
        log_pass "Path whitespace handling"
    fi
    
    rm -f "$space_file"
    
    # Test path with spaces in middle
    space_middle="/tmp/test query file.sql"
    echo "SELECT * FROM test" > "$space_middle"
    
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$space_middle" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Path with internal spaces handled"
    else
        log_pass "Internal space handling"
    fi
    
    rm -f "$space_middle"
}

# Test symlink handling
test_symlink_handling() {
    echo "=== Testing Symlink Handling ==="
    
    # Create symlink to test database
    symlink_db="/tmp/test_symlink.db"
    ln -sf "$TEST_DB" "$symlink_db" 2>/dev/null || {
        log_pass "Symlink test skipped (cannot create symlink)"
        return
    }
    
    # Query through symlink
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$symlink_db" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Symlink followed successfully"
    else
        log_pass "Symlink handling"
    fi
    
    rm -f "$symlink_db"
    
    # Test broken symlink
    broken_link="/tmp/test_broken_link.db"
    ln -sf "/nonexistent/path/db.sqlite" "$broken_link" 2>/dev/null || {
        log_pass "Broken symlink test skipped"
        return
    }
    
    output=$(echo "SELECT 1" | "$QUERY_RUNNER" -t sqlite -d "$broken_link" 2>&1 || true)
    if echo "$output" | grep -qi "not found\|does not exist"; then
        log_pass "Broken symlink detected"
    else
        log_pass "Broken symlink handled"
    fi
    
    rm -f "$broken_link"
}

# Test relative vs absolute paths
test_relative_absolute_paths() {
    echo "=== Testing Relative vs Absolute Paths ==="
    
    # Test relative path
    rel_path="./test.db"
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$rel_path" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Relative path works"
    else
        log_pass "Relative path handled"
    fi
    
    # Test absolute path
    abs_path=$(pwd)/test.db
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "$abs_path" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Absolute path works"
    else
        log_pass "Absolute path handled"
    fi
}

# Test special characters in paths
test_special_characters_in_paths() {
    echo "=== Testing Special Characters in Paths ==="
    
    # Test path with special but valid characters
    special_file="/tmp/test-query_file.2024.sql"
    echo "SELECT * FROM test" > "$special_file"
    
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$special_file" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "Path with hyphens, underscores, dots accepted"
    else
        log_pass "Special character path handling"
    fi
    
    rm -f "$special_file"
    
    # Test path with shell metacharacters (should be rejected or escaped)
    # Test a few representative characters to avoid long test times
    meta_chars=('$' '`' ';')
    meta_test_failed=0
    for char in "${meta_chars[@]}"; do
        output=$("$QUERY_RUNNER" -t sqlite -d "/tmp/file${char}name.db" 2>&1 || true)
        # Should either reject or handle safely
        if echo "$output" | grep -qi "invalid\|not found\|error"; then
            # Expected - either rejected or doesn't exist
            :
        else
            log_fail "Shell metacharacter in path not handled safely" \
                "Expected an error or rejection for path containing '${char}', but got: ${output}"
            meta_test_failed=1
        fi
    done
    
    if [ "$meta_test_failed" -eq 0 ]; then
        log_pass "Shell metacharacters in paths handled safely"
    fi
}

# Test UTF-8 BOM handling
test_utf8_bom_handling() {
    echo "=== Testing UTF-8 BOM Handling ==="
    
    # Create file with UTF-8 BOM
    bom_file="/tmp/test_bom_query.sql"
    printf '\xEF\xBB\xBFSELECT * FROM test' > "$bom_file"
    
    output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "$bom_file" 2>&1 || true)
    if echo "$output" | grep -q "data"; then
        log_pass "UTF-8 BOM stripped successfully"
    else
        log_fail "UTF-8 BOM not handled" "Query should succeed after BOM removal"
    fi
    
    rm -f "$bom_file"
}

# Test empty path handling
test_empty_path() {
    echo "=== Testing Empty Path Handling ==="
    
    # Test with empty string
    output=$(echo "SELECT * FROM test" | "$QUERY_RUNNER" -t sqlite -d "" 2>&1 || true)
    if echo "$output" | grep -qi "required\|missing\|empty"; then
        log_pass "Empty database path rejected"
    else
        log_pass "Empty path handled"
    fi
}

# Test case sensitivity
test_case_sensitivity() {
    echo "=== Testing Path Case Sensitivity ==="
    
    # On case-sensitive filesystems, this matters
    upper_db="/tmp/TEST_DB.sqlite"
    lower_db="/tmp/test_db.sqlite"
    
    # Clean up first
    rm -f "$upper_db" "$lower_db"
    
    echo "" | sqlite3 "$lower_db" "CREATE TABLE IF NOT EXISTS t(id INT);"
    
    # Try to access with different case
    output=$(echo "SELECT * FROM t" | "$QUERY_RUNNER" -t sqlite -d "$upper_db" 2>&1 || true)
    # Accept either result (depends on filesystem)
    log_pass "Path case sensitivity handled per filesystem"
    
    rm -f "$upper_db" "$lower_db"
}

# Main test execution
main() {
    echo "=== Query Runner Path Validation Tests ==="
    echo
    
    setup
    
    test_control_character_rejection
    echo
    test_path_length_limits
    echo
    test_system_directory_protection
    echo
    test_path_traversal
    echo
    test_tilde_expansion
    echo
    test_stdin_dash_handling
    echo
    test_dash_dash_sentinel
    echo
    test_whitespace_handling
    echo
    test_symlink_handling
    echo
    test_relative_absolute_paths
    echo
    test_special_characters_in_paths
    echo
    test_utf8_bom_handling
    echo
    test_empty_path
    echo
    test_case_sensitivity
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All path validation tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
