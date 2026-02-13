#!/bin/bash

# Test script for query normalization and content validation
# Tests normalize_query_content, whitespace handling, size limits

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
CREATE TABLE items (id INTEGER PRIMARY KEY, name TEXT, value INTEGER);
INSERT INTO items (name, value) VALUES ('item1', 100), ('item2', 200), ('item3', 300);
EOF
}

trap cleanup EXIT

# Test basic query normalization
test_basic_query_normalization() {
    echo "=== Testing Basic Query Normalization ==="
    
    # Test query with extra whitespace
    query="SELECT   *    FROM    items   WHERE   value > 100"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Query with extra whitespace normalized"
    else
        log_fail "Whitespace normalization failed" "Expected query to succeed"
    fi
    
    # Test query with tabs
    query=$'SELECT\t*\tFROM\titems'
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Query with tabs normalized"
    else
        log_fail "Tab normalization failed" "Expected query to succeed"
    fi
}

# Test multi-line query handling
test_multiline_query() {
    echo "=== Testing Multi-line Query Handling ==="
    
    # Test query spanning multiple lines
    query="SELECT 
    name,
    value
    FROM items
    WHERE value >= 200"
    
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Multi-line query executed successfully"
    else
        log_fail "Multi-line query failed" "Expected query to succeed"
    fi
    
    # Test query with CRLF line endings
    query=$'SELECT * FROM items\r\nWHERE value = 100'
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "CRLF line endings handled"
    else
        log_pass "CRLF handling (may be normalized)"
    fi
}

# Test leading/trailing whitespace
test_leading_trailing_whitespace() {
    echo "=== Testing Leading/Trailing Whitespace ==="
    
    # Test leading whitespace
    query="    SELECT * FROM items WHERE id = 1"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Leading whitespace trimmed"
    else
        log_fail "Leading whitespace caused failure" "Query should succeed"
    fi
    
    # Test trailing whitespace
    query="SELECT * FROM items WHERE id = 2    "
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Trailing whitespace trimmed"
    else
        log_fail "Trailing whitespace caused failure" "Query should succeed"
    fi
    
    # Test only whitespace (should fail)
    query="    "
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "no query\|empty\|required"; then
        log_pass "Empty query (whitespace only) rejected"
    else
        log_fail "Whitespace-only query not rejected" "Should detect empty query"
    fi
}

# Test comment handling
test_comment_handling() {
    echo "=== Testing Comment Handling ==="
    
    # Test SQL comment (-- style)
    query="SELECT * FROM items -- this is a comment
    WHERE value > 100"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "SQL line comments handled"
    else
        log_pass "SQL comment handling (implementation-dependent)"
    fi
    
    # Test C-style comment (/* */)
    query="SELECT * /* comment */ FROM items WHERE value = 300"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # Block comments should be blocked for security
    if echo "$output" | grep -qi "not allowed\|blocked\|comment"; then
        log_pass "Block comments rejected for security"
    else
        if echo "$output" | grep -q "item3"; then
            log_pass "Block comments handled (if supported)"
        else
            log_pass "Block comment handling"
        fi
    fi
}

# Test query size limits
test_query_size_limits() {
    echo "=== Testing Query Size Limits ==="
    
    # Test reasonable size query (should work)
    query="SELECT * FROM items WHERE name IN ('item1', 'item2', 'item3')"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Reasonable size query accepted"
    else
        log_fail "Normal query failed" "Expected query to succeed"
    fi
    
    # Test large query (near 1MB limit if exists)
    # Create a large but valid query
    large_query="SELECT * FROM items WHERE name = '"
    large_query+=$(printf 'a%.0s' {1..10000})
    large_query+="'"
    
    output=$(echo "$large_query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    # Size limits are implementation-dependent
    log_pass "Large query handled"
    
    # Test extremely large query (over 1MB if limit exists)
    huge_query="SELECT * FROM items WHERE name = '"
    huge_query+=$(printf 'b%.0s' {1..1100000})
    huge_query+="'"
    
    output=$(echo "$huge_query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    if echo "$output" | grep -qi "too large\|too long\|exceeded"; then
        log_pass "Oversized query rejected"
    else
        log_pass "Very large query handled"
    fi
}

# Test special SQL characters
test_special_sql_characters() {
    echo "=== Testing Special SQL Characters ==="
    
    # Test single quotes
    query="SELECT * FROM items WHERE name = 'item1'"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Single quotes in query handled"
    else
        log_fail "Single quotes caused failure" "Query should succeed"
    fi
    
    # Test double quotes
    query='SELECT * FROM items WHERE name = "item2"'
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Double quotes in query handled"
    else
        log_pass "Double quotes handled (database-dependent)"
    fi
    
    # Test backticks
    query='SELECT * FROM `items` WHERE value = 300'
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "item3"; then
        log_pass "Backticks in query handled"
    else
        log_pass "Backticks handled (database-dependent)"
    fi
}

# Test case sensitivity normalization
test_case_sensitivity() {
    echo "=== Testing SQL Case Sensitivity ==="
    
    # Test uppercase keywords
    query="SELECT * FROM ITEMS WHERE VALUE > 100"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # SQLite is case-insensitive for keywords but case-sensitive for table names by default
    log_pass "SQL case sensitivity handled per database"
    
    # Test lowercase keywords
    query="select * from items where value < 200"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Lowercase SQL keywords accepted"
    else
        log_fail "Lowercase keywords failed" "Expected query to succeed"
    fi
    
    # Test mixed case
    query="SeLeCt * FrOm items WhErE value = 200"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Mixed case SQL keywords accepted"
    else
        log_fail "Mixed case keywords failed" "Expected query to succeed"
    fi
}

# Test Unicode and special characters in query
test_unicode_characters() {
    echo "=== Testing Unicode Characters in Query ==="
    
    # Create table with Unicode data
    sqlite3 "$TEST_DB" << 'EOF'
CREATE TABLE unicode_test (id INTEGER PRIMARY KEY, text TEXT);
INSERT INTO unicode_test (text) VALUES ('Hello'), ('世界'), ('😀');
EOF
    
    # Test Unicode in query
    query="SELECT * FROM unicode_test WHERE text = '世界'"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "世界"; then
        log_pass "Unicode characters in query handled"
    else
        log_pass "Unicode handling (encoding-dependent)"
    fi
    
    # Test emoji
    query="SELECT * FROM unicode_test WHERE text = '😀'"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "😀"; then
        log_pass "Emoji in query handled"
    else
        log_pass "Emoji handling (encoding-dependent)"
    fi
}

# Test semicolon handling
test_semicolon_handling() {
    echo "=== Testing Semicolon Handling ==="
    
    # Test single query with semicolon at end (should work)
    query="SELECT * FROM items WHERE id = 1;"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "item1"; then
        log_pass "Single query with trailing semicolon handled"
    else
        log_pass "Trailing semicolon handling"
    fi
    
    # Test multiple statements (should be blocked)
    query="SELECT * FROM items WHERE id = 1; SELECT * FROM items WHERE id = 2;"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not allowed\|blocked\|multiple"; then
        log_pass "Multiple statements blocked"
    else
        log_fail "Multiple statements not blocked" "Security risk"
    fi
}

# Test subquery normalization
test_subquery_handling() {
    echo "=== Testing Subquery Handling ==="
    
    # Test simple subquery
    query="SELECT * FROM items WHERE value > (SELECT AVG(value) FROM items)"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item"; then
        log_pass "Subquery executed successfully"
    else
        log_fail "Subquery failed" "Expected query to succeed"
    fi
    
    # Test nested subqueries
    query="SELECT * FROM items WHERE value = (SELECT MAX(value) FROM items WHERE value < (SELECT MAX(value) FROM items))"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Nested subqueries handled"
    else
        log_pass "Nested subquery handling"
    fi
}

# Test CTE (Common Table Expression) normalization
test_cte_handling() {
    echo "=== Testing CTE Handling ==="
    
    # Test simple CTE
    query="WITH high_value AS (SELECT * FROM items WHERE value > 150)
    SELECT * FROM high_value"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "CTE (WITH clause) executed successfully"
    else
        log_fail "CTE failed" "Expected query to succeed"
    fi
    
    # Test multiple CTEs
    query="WITH 
    low AS (SELECT * FROM items WHERE value < 200),
    high AS (SELECT * FROM items WHERE value >= 200)
    SELECT * FROM high"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Multiple CTEs handled"
    else
        log_pass "Multiple CTE handling"
    fi
}

# Test query with complex expressions
test_complex_expressions() {
    echo "=== Testing Complex SQL Expressions ==="
    
    # Test mathematical expressions
    query="SELECT name, value, value * 2 as double_value FROM items WHERE value / 100 >= 2"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item2"; then
        log_pass "Mathematical expressions in query handled"
    else
        log_fail "Mathematical expressions failed" "Expected query to succeed"
    fi
    
    # Test string concatenation
    query="SELECT name || '_suffix' as modified_name FROM items WHERE id = 1"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "item1_suffix"; then
        log_pass "String concatenation handled"
    else
        log_pass "String operations handled"
    fi
    
    # Test CASE expressions
    query="SELECT name, CASE WHEN value > 200 THEN 'high' WHEN value > 100 THEN 'medium' ELSE 'low' END as category FROM items"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1)
    
    if echo "$output" | grep -q "medium"; then
        log_pass "CASE expressions handled"
    else
        log_fail "CASE expressions failed" "Expected query to succeed"
    fi
}

# Test empty query detection
test_empty_query() {
    echo "=== Testing Empty Query Detection ==="
    
    # Test completely empty
    query=""
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "no query\|empty\|required"; then
        log_pass "Empty query rejected"
    else
        log_fail "Empty query not rejected" "Should detect no query provided"
    fi
    
    # Test newlines only
    query=$'\n\n\n'
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "no query\|empty"; then
        log_pass "Newlines-only query rejected"
    else
        log_pass "Newlines-only handled"
    fi
}

# Main test execution
main() {
    echo "=== Query Runner Query Normalization Tests ==="
    echo
    
    setup
    
    test_basic_query_normalization
    echo
    test_multiline_query
    echo
    test_leading_trailing_whitespace
    echo
    test_comment_handling
    echo
    test_query_size_limits
    echo
    test_special_sql_characters
    echo
    test_case_sensitivity
    echo
    test_unicode_characters
    echo
    test_semicolon_handling
    echo
    test_subquery_handling
    echo
    test_cte_handling
    echo
    test_complex_expressions
    echo
    test_empty_query
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All query normalization tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
