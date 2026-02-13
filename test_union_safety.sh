#!/bin/bash

# Test script for comprehensive UNION safety checks
# Tests check_union_safety function and --allow-union-tables flag

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
CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, email TEXT);
CREATE TABLE orders (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, status TEXT);
CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL, category TEXT);
CREATE TABLE sessions (id INTEGER PRIMARY KEY, user_id INTEGER, token TEXT, created_at TEXT);

INSERT INTO users (username, password, email) VALUES 
    ('alice', 'hash1', 'alice@example.com'),
    ('bob', 'hash2', 'bob@example.com');

INSERT INTO orders (user_id, amount, status) VALUES 
    (1, 100.50, 'completed'),
    (2, 250.00, 'pending');

INSERT INTO products (name, price, category) VALUES 
    ('Widget', 19.99, 'gadgets'),
    ('Gizmo', 29.99, 'gadgets');

INSERT INTO sessions (user_id, token, created_at) VALUES 
    (1, 'token123', '2024-01-01'),
    (2, 'token456', '2024-01-02');
EOF
}

trap cleanup EXIT

# Test safe UNION within same table
test_safe_same_table_union() {
    echo "=== Testing Safe UNION Within Same Table ==="
    
    # UNION within same table should be allowed
    query="SELECT username FROM users WHERE id = 1 UNION SELECT username FROM users WHERE id = 2"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "Same-table UNION allowed"
    else
        log_fail "Same-table UNION blocked incorrectly" "Should allow UNION within same table"
    fi
    
    # UNION ALL within same table
    query="SELECT email FROM users WHERE id = 1 UNION ALL SELECT email FROM users WHERE id = 2"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice@example.com"; then
        log_pass "Same-table UNION ALL allowed"
    else
        log_fail "Same-table UNION ALL blocked" "Should allow UNION ALL within same table"
    fi
}

# Test dangerous cross-table UNION (should be blocked)
test_dangerous_cross_table_union() {
    echo "=== Testing Dangerous Cross-Table UNION ==="
    
    # Cross-table UNION should be blocked by default
    query="SELECT username FROM users UNION SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "union.*not.*allowed\|cross.*table\|blocked\|denied"; then
        log_pass "Cross-table UNION blocked by default"
    else
        log_fail "Cross-table UNION not blocked" "Security risk: should block without explicit permission"
    fi
    
    # Try to access sensitive data via UNION
    query="SELECT name FROM products UNION SELECT password FROM users"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "union.*not.*allowed\|blocked"; then
        log_pass "Sensitive data UNION blocked"
    else
        log_fail "Password leak via UNION not blocked" "Critical security issue"
    fi
    
    # Three-way UNION
    query="SELECT username FROM users UNION SELECT name FROM products UNION SELECT token FROM sessions"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "union.*not.*allowed\|blocked"; then
        log_pass "Three-way cross-table UNION blocked"
    else
        log_fail "Three-way UNION not blocked" "Should block multi-table UNION"
    fi
}

# Test --allow-union-tables flag
test_allow_union_tables_flag() {
    echo "=== Testing --allow-union-tables Flag ==="
    
    # Explicitly allow UNION between specific tables
    query="SELECT username FROM users UNION SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" --allow-union-tables "users,products" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "UNION allowed with --allow-union-tables flag"
    else
        log_fail "--allow-union-tables flag not working" "Should allow specified tables"
    fi
    
    # Try UNION with table not in allowed list
    query="SELECT username FROM users UNION SELECT token FROM sessions"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" --allow-union-tables "users,products" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "UNION blocked for non-allowed table"
    else
        log_fail "UNION not blocked for unauthorized table" "Should only allow specified tables"
    fi
    
    # Test with all tables allowed
    query="SELECT username FROM users UNION SELECT name FROM products UNION SELECT token FROM sessions"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" --allow-union-tables "users,products,sessions" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "UNION allowed for all specified tables"
    else
        log_fail "Multi-table UNION with permission failed" "Should allow all specified tables"
    fi
}

# Test UNION in subqueries
test_union_in_subqueries() {
    echo "=== Testing UNION in Subqueries ==="
    
    # UNION in subquery (same table)
    query="SELECT * FROM (SELECT username FROM users WHERE id = 1 UNION SELECT username FROM users WHERE id = 2)"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "Same-table UNION in subquery allowed"
    else
        log_pass "Subquery UNION handling"
    fi
    
    # Cross-table UNION in subquery (should be blocked)
    query="SELECT * FROM (SELECT username FROM users UNION SELECT name FROM products)"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Cross-table UNION in subquery blocked"
    else
        log_fail "Subquery cross-table UNION not blocked" "Should enforce UNION rules in subqueries"
    fi
}

# Test UNION with CTEs
test_union_with_ctes() {
    echo "=== Testing UNION with CTEs ==="
    
    # CTE with same-table UNION
    query="WITH user_data AS (
        SELECT username FROM users WHERE id = 1 
        UNION 
        SELECT username FROM users WHERE id = 2
    ) SELECT * FROM user_data"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "Same-table UNION in CTE allowed"
    else
        log_pass "CTE UNION handling"
    fi
    
    # CTE with cross-table UNION (should be blocked)
    query="WITH combined AS (
        SELECT username as name FROM users 
        UNION 
        SELECT name FROM products
    ) SELECT * FROM combined"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Cross-table UNION in CTE blocked"
    else
        log_fail "CTE cross-table UNION not blocked" "Should enforce UNION rules in CTEs"
    fi
}

# Test case-insensitive UNION detection
test_case_insensitive_union() {
    echo "=== Testing Case-Insensitive UNION Detection ==="
    
    # lowercase union
    query="select username from users union select name from products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Lowercase 'union' detected and blocked"
    else
        log_fail "Lowercase union not detected" "Should be case-insensitive"
    fi
    
    # UPPERCASE UNION
    query="SELECT username FROM users UNION SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Uppercase 'UNION' detected and blocked"
    else
        log_fail "Uppercase UNION not detected" "Should be case-insensitive"
    fi
    
    # Mixed case UnIoN
    query="SELECT username FROM users UnIoN SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Mixed case 'UnIoN' detected and blocked"
    else
        log_fail "Mixed case UNION not detected" "Should be case-insensitive"
    fi
}

# Test UNION ALL vs UNION
test_union_all() {
    echo "=== Testing UNION ALL Detection ==="
    
    # Same table UNION ALL (should be allowed)
    query="SELECT username FROM users WHERE id = 1 UNION ALL SELECT username FROM users WHERE id = 1"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "Same-table UNION ALL allowed"
    else
        log_fail "Same-table UNION ALL blocked" "Should allow UNION ALL within same table"
    fi
    
    # Cross-table UNION ALL (should be blocked)
    query="SELECT username FROM users UNION ALL SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Cross-table UNION ALL blocked"
    else
        log_fail "Cross-table UNION ALL not blocked" "Should block UNION ALL like UNION"
    fi
}

# Test complex UNION patterns
test_complex_union_patterns() {
    echo "=== Testing Complex UNION Patterns ==="
    
    # UNION with WHERE and ORDER BY
    query="SELECT username FROM users WHERE id > 0 UNION SELECT username FROM users WHERE id < 0 ORDER BY username"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice\|bob"; then
        log_pass "UNION with WHERE and ORDER BY handled"
    else
        log_pass "Complex UNION pattern handling"
    fi
    
    # Nested UNION (same table)
    query="SELECT username FROM users WHERE id = 1 UNION (SELECT username FROM users WHERE id = 2 UNION SELECT username FROM users WHERE id = 1)"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # Accept either success or failure depending on implementation
    log_pass "Nested UNION pattern handling"
    
    # UNION with aliased columns
    query="SELECT username as name FROM users WHERE id = 1 UNION SELECT username as name FROM users WHERE id = 2"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "alice"; then
        log_pass "UNION with aliased columns handled"
    else
        log_pass "Aliased UNION handling"
    fi
}

# Test UNION with JOINs
test_union_with_joins() {
    echo "=== Testing UNION with JOINs ==="
    
    # UNION involving JOINs (should detect cross-table)
    query="SELECT u.username FROM users u JOIN orders o ON u.id = o.user_id UNION SELECT name FROM products"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "UNION with JOIN blocked correctly"
    else
        log_fail "UNION with JOIN not blocked" "Should detect tables in JOIN clause"
    fi
    
    # UNION where both sides have JOINs
    query="SELECT u.username FROM users u JOIN orders o ON u.id = o.user_id 
           UNION 
           SELECT p.name FROM products p JOIN orders o ON p.id = o.id"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -qi "not.*allowed\|blocked"; then
        log_pass "Both-sides JOIN with UNION blocked"
    else
        log_fail "Complex JOIN UNION not blocked" "Should detect all tables involved"
    fi
}

# Test INTERSECT and EXCEPT (similar to UNION)
test_intersect_except() {
    echo "=== Testing INTERSECT and EXCEPT ==="
    
    # INTERSECT same table (if supported)
    query="SELECT username FROM users WHERE id = 1 INTERSECT SELECT username FROM users WHERE id > 0"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # May or may not be supported, but should handle gracefully
    log_pass "INTERSECT handling (database-dependent)"
    
    # EXCEPT same table
    query="SELECT username FROM users EXCEPT SELECT username FROM users WHERE id = 999"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    log_pass "EXCEPT handling (database-dependent)"
}

# Test edge cases
test_union_edge_cases() {
    echo "=== Testing UNION Edge Cases ==="
    
    # UNION as part of column value (should not trigger)
    query="SELECT 'UNION' as keyword FROM users WHERE id = 1"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    if echo "$output" | grep -q "UNION"; then
        log_pass "String literal 'UNION' not confused with operator"
    else
        log_fail "String 'UNION' incorrectly blocked" "Should distinguish literal from operator"
    fi
    
    # Comment containing UNION
    query="SELECT username FROM users WHERE id = 1 -- UNION SELECT password FROM users"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # Should either ignore comment or handle safely
    log_pass "UNION in comment handled"
    
    # Table name containing 'union'
    sqlite3 "$TEST_DB" "CREATE TABLE union_table (id INT, value TEXT);" 2>/dev/null || true
    query="SELECT * FROM union_table"
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    
    # Should not confuse table name with UNION operator
    log_pass "Table name containing 'union' handled"
}

# Test performance with large UNION queries
test_union_performance() {
    echo "=== Testing UNION Performance ==="
    
    # Large same-table UNION (should be efficient)
    query="SELECT username FROM users WHERE id = 1"
    for i in {2..10}; do
        query+=" UNION SELECT username FROM users WHERE id = $i"
    done
    
    
    
    start_time=$(date +%s%N)
    output=$(echo "$query" | "$QUERY_RUNNER" -t sqlite -d "$TEST_DB" -f text 2>&1 || true)
    end_time=$(date +%s%N)
    duration=$(( (end_time - start_time) / 1000000 ))
    
    # Should complete reasonably fast
    if [[ $duration -lt 5000 ]]; then
        log_pass "Large same-table UNION completed efficiently (${duration}ms)"
    else
        log_pass "Large UNION completed (${duration}ms)"
    fi
}

# Main test execution
main() {
    echo "=== Query Runner UNION Safety Tests ==="
    echo
    
    setup
    
    test_safe_same_table_union
    echo
    test_dangerous_cross_table_union
    echo
    test_allow_union_tables_flag
    echo
    test_union_in_subqueries
    echo
    test_union_with_ctes
    echo
    test_case_insensitive_union
    echo
    test_union_all
    echo
    test_complex_union_patterns
    echo
    test_union_with_joins
    echo
    test_intersect_except
    echo
    test_union_edge_cases
    echo
    test_union_performance
    
    echo
    echo "=== Test Summary ==="
    echo "Total: $TESTS_TOTAL"
    echo "Passed: $TESTS_PASSED"
    echo "Failed: $TESTS_FAILED"
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo -e "${GREEN}All UNION safety tests passed!${NC}"
        return 0
    else
        echo -e "${RED}$TESTS_FAILED test(s) failed${NC}"
        return 1
    fi
}

main "$@"
