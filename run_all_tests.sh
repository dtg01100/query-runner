#!/bin/bash

# Master test runner for comprehensive query runner tests
# Runs all test suites and provides summary

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

run_test_suite() {
    local test_script="$1"
    local test_name="$2"
    
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}Running: $test_name${NC}"
    echo -e "${BLUE}========================================${NC}"
    
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
    
    if [[ ! -f "$test_script" ]]; then
        echo -e "${YELLOW}⊘${NC} Test script not found: $test_script"
        TOTAL_SUITES=$((TOTAL_SUITES - 1))
        return
    fi
    
    if bash "$test_script"; then
        echo -e "${GREEN}✓${NC} $test_name passed"
        PASSED_SUITES=$((PASSED_SUITES + 1))
    else
        echo -e "${RED}✗${NC} $test_name failed"
        FAILED_SUITES=$((FAILED_SUITES + 1))
    fi
}

show_usage() {
    cat << 'EOF'
Usage: ./run_all_tests.sh [CATEGORY]

Categories:
    all              Run all test suites (default)
    core             Core functionality tests (cache, error, path, query)
    security         Security-related tests (input validation, naughty strings)
    formats          Output format and CLI tests
    daemon           Daemon mode tests
    integration      All tests in sequence

Individual suites:
    cache            Cache management tests
    error            Error handling tests
    path             Path validation tests
    query            Query normalization tests
    union            UNION safety tests
    cli              CLI option tests
    env              Environment file tests
    output           Output format tests

Examples:
    ./run_all_tests.sh              # Run all tests
    ./run_all_tests.sh core         # Run core tests only
    ./run_all_tests.sh cache        # Run cache tests only
    RUN_EXTENDED_TESTS=1 ./run_all_tests.sh  # Run with extended security tests
EOF
}

main() {
    local category="${1:-all}"
    
    if [[ "$category" == "--help" ]] || [[ "$category" == "-h" ]]; then
        show_usage
        exit 0
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║   Query Runner Comprehensive Tests    ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    
    case "$category" in
        cache)
            run_test_suite "$SCRIPT_DIR/test_cache_management.sh" "Cache Management"
            ;;
        error)
            run_test_suite "$SCRIPT_DIR/test_error_handling.sh" "Error Handling"
            ;;
        path)
            run_test_suite "$SCRIPT_DIR/test_path_validation.sh" "Path Validation"
            ;;
        query)
            run_test_suite "$SCRIPT_DIR/test_query_normalization.sh" "Query Normalization"
            ;;
        union)
            run_test_suite "$SCRIPT_DIR/test_union_safety.sh" "UNION Safety"
            ;;
        cli)
            run_test_suite "$SCRIPT_DIR/test_cli_options.sh" "CLI Options"
            ;;
        env)
            run_test_suite "$SCRIPT_DIR/test_env_files.sh" "Environment Files"
            ;;
        output)
            run_test_suite "$SCRIPT_DIR/test_output_formats.sh" "Output Formats"
            ;;
        core)
            run_test_suite "$SCRIPT_DIR/test_cache_management.sh" "Cache Management"
            run_test_suite "$SCRIPT_DIR/test_error_handling.sh" "Error Handling"
            run_test_suite "$SCRIPT_DIR/test_path_validation.sh" "Path Validation"
            run_test_suite "$SCRIPT_DIR/test_query_normalization.sh" "Query Normalization"
            ;;
        security)
            run_test_suite "$SCRIPT_DIR/test_input_validation.sh" "Input Validation"
            run_test_suite "$SCRIPT_DIR/test_database_security.sh" "Database Security"
            run_test_suite "$SCRIPT_DIR/test_naughty_strings.sh" "Naughty Strings"
            run_test_suite "$SCRIPT_DIR/test_official_naughty_strings.sh" "Official Naughty Strings"
            run_test_suite "$SCRIPT_DIR/test_focused_naughty.sh" "Focused Naughty"
            run_test_suite "$SCRIPT_DIR/test_real_security_vectors.sh" "Real Security Vectors"
            run_test_suite "$SCRIPT_DIR/test_union_safety.sh" "UNION Safety"
            ;;
        formats)
            run_test_suite "$SCRIPT_DIR/test_cli_options.sh" "CLI Options"
            run_test_suite "$SCRIPT_DIR/test_env_files.sh" "Environment Files"
            run_test_suite "$SCRIPT_DIR/test_output_formats.sh" "Output Formats"
            ;;
        daemon)
            if [[ -f "$SCRIPT_DIR/test_daemon/test_daemon.sh" ]]; then
                run_test_suite "$SCRIPT_DIR/test_daemon/test_daemon.sh" "Daemon Mode (All)"
            else
                echo -e "${YELLOW}Daemon tests not found${NC}"
            fi
            ;;
        integration|all)
            echo "Running comprehensive test suite..."
            
            # Core functionality
            echo ""
            echo -e "${BLUE}=== Core Functionality Tests ===${NC}"
            run_test_suite "$SCRIPT_DIR/test_cache_management.sh" "Cache Management"
            run_test_suite "$SCRIPT_DIR/test_error_handling.sh" "Error Handling"
            run_test_suite "$SCRIPT_DIR/test_path_validation.sh" "Path Validation"
            run_test_suite "$SCRIPT_DIR/test_query_normalization.sh" "Query Normalization"
            
            # Security
            echo ""
            echo -e "${BLUE}=== Security Tests ===${NC}"
            run_test_suite "$SCRIPT_DIR/test_input_validation.sh" "Input Validation"
            run_test_suite "$SCRIPT_DIR/test_database_security.sh" "Database Security"
            run_test_suite "$SCRIPT_DIR/test_union_safety.sh" "UNION Safety"
            
            # Interface
            echo ""
            echo -e "${BLUE}=== Interface Tests ===${NC}"
            run_test_suite "$SCRIPT_DIR/test_cli_options.sh" "CLI Options"
            run_test_suite "$SCRIPT_DIR/test_env_files.sh" "Environment Files"
            run_test_suite "$SCRIPT_DIR/test_output_formats.sh" "Output Formats"
            
            # Extended security (optional - can be slow)
            if [[ "${RUN_EXTENDED_TESTS:-0}" == "1" ]]; then
                echo ""
                echo -e "${BLUE}=== Extended Security Tests ===${NC}"
                run_test_suite "$SCRIPT_DIR/test_naughty_strings.sh" "Naughty Strings"
                run_test_suite "$SCRIPT_DIR/test_official_naughty_strings.sh" "Official Naughty Strings"
                run_test_suite "$SCRIPT_DIR/test_focused_naughty.sh" "Focused Naughty"
                run_test_suite "$SCRIPT_DIR/test_real_security_vectors.sh" "Real Security Vectors"
            fi
            
            # Daemon tests
            if [[ -f "$SCRIPT_DIR/test_daemon/test_daemon.sh" ]]; then
                echo ""
                echo -e "${BLUE}=== Daemon Mode Tests ===${NC}"
                run_test_suite "$SCRIPT_DIR/test_daemon/test_daemon.sh" "Daemon Mode (All)"
            fi
            ;;
        *)
            echo -e "${RED}Unknown category: $category${NC}"
            echo ""
            show_usage
            exit 1
            ;;
    esac
    
    # Summary
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Test Summary                  ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    echo "Total Test Suites: $TOTAL_SUITES"
    echo -e "Passed: ${GREEN}$PASSED_SUITES${NC}"
    echo -e "Failed: ${RED}$FAILED_SUITES${NC}"
    echo ""
    
    if [[ $FAILED_SUITES -eq 0 ]]; then
        echo -e "${GREEN}🎉 All test suites passed!${NC}"
        exit 0
    else
        echo -e "${RED}❌ $FAILED_SUITES test suite(s) failed${NC}"
        exit 1
    fi
}

main "$@"
