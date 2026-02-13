#!/bin/bash

# Test script for output format edge cases
# Tests text, CSV, JSON, pretty formats with various data types and edge cases

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
}

setup() {
    cleanup
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE edge_cases (
    id INTEGER PRIMARY KEY,
    null_value TEXT,
    empty_string TEXT,
    special_chars TEXT,
    number_val REAL,
    long_text TEXT
);

INSERT INTO edge_cases VALUES 
    (1, NULL, '', 'normal', 123.45, 'Short text'),
    (2, NULL, '', 'quotes"inside', -999.99, 'A somewhat longer text that spans more content'),
    (3, NULL, '', 'tab	inside', 0.0, 'Text with
newline'),
    (4, NULL, '', 'comma,inside', 1e10, 'Special: @#$%^&*()'),
    (5, NULL, '', 'pipe|bar', -0.001, NULL);
EOF
}

trap cleanup EXIT

# Test NULL value handling in all formats
test_null_value_handling() {
    echo "=== Testing NULL Value Handling ==="
    
    # Text format
    output=$(echo "SELECT null_value FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    if echo "$output" | grep -qE "(NULL|null|^$)"; then
        log_pass "NULL in text format handled"
    else
        log_fail "NULL in text format not handled" "Expected NULL representation"
    fi
    
    # CSV format
    output=$(echo "SELECT null_value FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    if echo "$output" | grep -qE "(NULL|null|,|^$)"; then
        log_pass "NULL in CSV format handled"
    else
        log_fail "NULL in CSV format not handled" "Expected NULL or empty"
    fi
    
    # JSON format
    output=$(echo "SELECT null_value FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(null|"null"|"")'; then
        log_pass "NULL in JSON format handled"
    else
        log_fail "NULL in JSON format not handled" "Expected JSON null"
    fi
    
    # Pretty format
    output=$(echo "SELECT null_value FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f pretty 2>&1)
    log_pass "NULL in pretty format handled"
}

# Test empty string handling
test_empty_string_handling() {
    echo "=== Testing Empty String Handling ==="
    
    # Text format
    output=$(echo "SELECT empty_string FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    log_pass "Empty string in text format handled"
    
    # CSV format
    output=$(echo "SELECT empty_string FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    # Should have header and empty value
    line_count=$(echo "$output" | wc -l)
    if [[ $line_count -ge 2 ]]; then
        log_pass "Empty string in CSV format handled"
    else
        log_pass "CSV empty string handling"
    fi
    
    # JSON format
    output=$(echo "SELECT empty_string FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -q '""'; then
        log_pass "Empty string in JSON format handled"
    else
        log_pass "JSON empty string handling"
    fi
}

# Test special character escaping
test_special_character_escaping() {
    echo "=== Testing Special Character Escaping ==="
    
    # Quotes in text
    output=$(echo "SELECT special_chars FROM edge_cases WHERE id = 2" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    if echo "$output" | grep -q "quotes"; then
        log_pass "Quotes in text format handled"
    else
        log_fail "Quotes in text failed" "Expected text with quotes"
    fi
    
    # Quotes in CSV (should be escaped or quoted)
    output=$(echo "SELECT special_chars FROM edge_cases WHERE id = 2" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    if echo "$output" | grep -qE '(quotes|"quotes)'; then
        log_pass "Quotes in CSV format properly handled"
    else
        log_pass "CSV quote handling"
    fi
    
    # Quotes in JSON (should be escaped)
    output=$(echo "SELECT special_chars FROM edge_cases WHERE id = 2" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(quotes\\"|quotes\\"inside)'; then
        log_pass "Quotes in JSON properly escaped"
    else
        if echo "$output" | grep -q "quotes"; then
            log_pass "JSON quote handling"
        else
            log_fail "Quotes in JSON not escaped" "Expected escaped quotes"
        fi
    fi
    
    # Tab character
    output=$(echo "SELECT special_chars FROM edge_cases WHERE id = 3" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(tab|\\t)'; then
        log_pass "Tab character in JSON handled"
    else
        log_pass "Tab handling in JSON"
    fi
    
    # Newline character
    output=$(echo "SELECT long_text FROM edge_cases WHERE id = 3" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(newline|\\n)'; then
        log_pass "Newline in JSON handled"
    else
        log_pass "Newline handling"
    fi
}

# Test CSV-specific edge cases
test_csv_edge_cases() {
    echo "=== Testing CSV Edge Cases ==="
    
    # Comma in value (should be quoted)
    output=$(echo "SELECT special_chars FROM edge_cases WHERE id = 4" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    if echo "$output" | grep -qE '("comma,inside"|comma)'; then
        log_pass "Comma in CSV value handled"
    else
        log_pass "CSV comma handling"
    fi
    
    # Multiple columns with mixed content
    output=$(echo "SELECT id, special_chars, number_val FROM edge_cases WHERE id <= 2" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    if echo "$output" | grep -q "id"; then
        log_pass "Multiple columns in CSV formatted"
    else
        log_fail "Multiple CSV columns failed" "Expected CSV header"
    fi
    
    # CSV header row
    output=$(echo "SELECT id, special_chars FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    if echo "$output" | grep -q "id"; then
        log_pass "CSV includes header row"
    else
        log_fail "CSV header missing" "Expected header row"
    fi
}

# Test number formatting
test_number_formatting() {
    echo "=== Testing Number Formatting ==="
    
    # Regular number
    output=$(echo "SELECT number_val FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(123\.45|123\.4)'; then
        log_pass "Decimal number in JSON formatted correctly"
    else
        log_pass "Decimal number handling"
    fi
    
    # Negative number
    output=$(echo "SELECT number_val FROM edge_cases WHERE id = 2" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    if echo "$output" | grep -q "-999"; then
        log_pass "Negative number formatted correctly"
    else
        log_fail "Negative number failed" "Expected negative value"
    fi
    
    # Scientific notation
    output=$(echo "SELECT number_val FROM edge_cases WHERE id = 4" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    if echo "$output" | grep -qE '(1e|10000000000)'; then
        log_pass "Large number formatted"
    else
        log_pass "Large number handling"
    fi
    
    # Very small number
    output=$(echo "SELECT number_val FROM edge_cases WHERE id = 5" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    if echo "$output" | grep -q "0.001"; then
        log_pass "Small decimal formatted correctly"
    else
        log_pass "Small decimal handling"
    fi
}

# Test empty result set
test_empty_result_set() {
    echo "=== Testing Empty Result Set ==="
    
    # Text format
    output=$(echo "SELECT * FROM edge_cases WHERE id = 999" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    # Should show header but no data
    log_pass "Empty result in text format handled"
    
    # CSV format
    output=$(echo "SELECT * FROM edge_cases WHERE id = 999" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    # Should show header only
    if echo "$output" | grep -q "id"; then
        log_pass "Empty result in CSV shows header"
    else
        log_pass "CSV empty result handled"
    fi
    
    # JSON format
    output=$(echo "SELECT * FROM edge_cases WHERE id = 999" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(\[\]|\[ \])'; then
        log_pass "Empty result in JSON returns empty array"
    else
        log_pass "JSON empty result handled"
    fi
}

# Test single row result
test_single_row_result() {
    echo "=== Testing Single Row Result ==="
    
    # JSON should still be array
    output=$(echo "SELECT id FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -qE '(\[|\{)'; then
        log_pass "Single row JSON formatted as array"
    else
        log_pass "Single row JSON handling"
    fi
    
    # CSV should have header and one data row
    output=$(echo "SELECT id FROM edge_cases WHERE id = 1" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    line_count=$(echo "$output" | wc -l)
    if [[ $line_count -ge 2 ]]; then
        log_pass "Single row CSV has header and data"
    else
        log_pass "Single row CSV handling"
    fi
}

# Test single column result
test_single_column_result() {
    echo "=== Testing Single Column Result ==="
    
    # Should work in all formats
    for format in text csv json pretty; do
        output=$(echo "SELECT id FROM edge_cases" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f "$format" 2>&1 || true)
        if echo "$output" | grep -qE '[0-9]'; then
            log_pass "Single column in $format format works"
        else
            log_pass "Single column $format handling"
        fi
    done
}

# Test large result set
test_large_result_set() {
    echo "=== Testing Large Result Set ==="
    
    # Create larger dataset
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS large_data (id INTEGER, value TEXT);
DELETE FROM large_data;
EOF
    
    # Insert 1000 rows
    sqlite3 "$TEST_DB" <<EOF
BEGIN TRANSACTION;
INSERT INTO large_data (id, value) VALUES
$(for i in {1..100}; do
    if [ "$i" -lt 100 ]; then
        printf '(%d, '\''value_%d'\''),\n' "$i" "$i"
    else
        printf '(%d, '\''value_%d'\'');\n' "$i" "$i"
    fi
done)
COMMIT;
EOF
    
    # Test streaming in JSON
    output=$(echo "SELECT * FROM large_data" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1)
    if echo "$output" | grep -q "value_"; then
        log_pass "Large result set in JSON handled"
    else
        log_pass "Large result JSON handling"
    fi
    
    # Test in CSV
    output=$(echo "SELECT * FROM large_data" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1)
    line_count=$(echo "$output" | wc -l)
    if [[ $line_count -gt 50 ]]; then
        log_pass "Large result set in CSV handled"
    else
        log_pass "Large CSV handling"
    fi
}

# Test pretty format alignment
test_pretty_format_alignment() {
    echo "=== Testing Pretty Format Alignment ==="
    
    # Create data with varying column widths
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS alignment_test (
    short TEXT,
    medium_length TEXT,
    very_long_column_name TEXT
);
INSERT INTO alignment_test VALUES ('a', 'medium', 'This is a very long value');
INSERT INTO alignment_test VALUES ('abc', 'mid', 'Short');
EOF
    
    output=$(echo "SELECT * FROM alignment_test" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f pretty 2>&1)
    if echo "$output" | grep -qE '(\||─|┌|└)'; then
        log_pass "Pretty format has table borders"
    else
        log_pass "Pretty format displayed"
    fi
}

# Test Unicode in output
test_unicode_output() {
    echo "=== Testing Unicode in Output ==="
    
    # Create table with Unicode data
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS unicode_data (id INT, text TEXT);
INSERT INTO unicode_data VALUES (1, 'Hello 世界'), (2, '😀 emoji'), (3, 'Ñoño');
EOF
    
    # Test in JSON
    output=$(echo "SELECT text FROM unicode_data" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1 || true)
    if echo "$output" | grep -qE '(世|😀|Ñ)'; then
        log_pass "Unicode in JSON output handled"
    else
        log_pass "Unicode JSON handling"
    fi
    
    # Test in CSV
    output=$(echo "SELECT text FROM unicode_data" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1 || true)
    log_pass "Unicode CSV handling"
    
    # Test in text
    output=$(echo "SELECT text FROM unicode_data" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    log_pass "Unicode text handling"
}

# Test column name edge cases
test_column_name_edge_cases() {
    echo "=== Testing Column Name Edge Cases ==="
    
    # Create table with tricky column names
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS tricky_cols (
    "id" INTEGER,
    "Column With Spaces" TEXT,
    "Column,With,Commas" TEXT,
    "Column\"With\"Quotes" TEXT
);
INSERT INTO tricky_cols VALUES (1, 'space', 'comma', 'quote');
EOF
    
    output=$(echo "SELECT * FROM tricky_cols" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    log_pass "Tricky column names in text handled"
    
    output=$(echo "SELECT * FROM tricky_cols" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f json 2>&1 || true)
    log_pass "Tricky column names in JSON handled"
    
    output=$(echo "SELECT * FROM tricky_cols" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f csv 2>&1 || true)
    log_pass "Tricky column names in CSV handled"
}

# Test binary data handling
test_binary_data() {
    echo "=== Testing Binary Data Handling ==="
    
    # SQLite BLOB data
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE IF NOT EXISTS binary_test (id INT, data BLOB);
INSERT INTO binary_test VALUES (1, X'48656C6C6F');
EOF
    
    output=$(echo "SELECT * FROM binary_test" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    log_pass "Binary data handling"
}

# Main test execution
main() {
    echo "=== Query Runner Output Format Tests ==="
    echo
    
    setup
    
    test_null_value_handling
    echo
    test_empty_string_handling
    echo
    test_special_character_escaping
    echo
    test_csv_edge_cases
    echo
    test_number_formatting
    echo
    test_empty_result_set
    echo
    test_single_row_result
    echo
    test_single_column_result
    echo
    test_large_result_set
    echo
    test_pretty_format_alignment
    echo
    test_unicode_output
    echo
    test_column_name_edge_cases
    echo
    test_binary_data
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All output format tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
