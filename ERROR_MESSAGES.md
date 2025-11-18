# Query Runner Input Validation Error Messages

## Summary of Improvements

All user input validation now provides **clear, helpful error messages** instead of exposing system internals or cryptic errors like `xargs: unmatched single quote`.

## Before vs After Examples

### ❌ Before (Poor Error Messages)
```
xargs: unmatched single quote; by default quotes are special to xargs unless you use the -0 option
```

### ✅ After (User-Friendly Error Messages)

#### **SQL Query Errors**
```bash
# Invalid SQL operation
Error: Query must start with a read-only operation
Supported operations: SELECT, WITH, SHOW, DESCRIBE, EXPLAIN, PRAGMA
Example: SELECT * FROM users WHERE id = 1

# Multiple statements
Error: Multiple SQL statements are not allowed
Each query must be a single SQL statement without semicolons.

# Empty query
Error: No query provided
Usage: ./query_runner [OPTIONS] [QUERY_FILE]
   or: echo 'SELECT * FROM table' | ./query_runner [OPTIONS]
```

#### **File Input Errors**
```bash
# Non-existent file
Error: Query file not found: /path/to/file.sql
Please check the file path and ensure the file exists.

# Unreadable file
Error: Cannot read query file: /path/to/file.sql
Please check file permissions.

# Invalid file path
Error: Invalid path for env-file: ../../../etc/passwd
Please provide a valid file system path.
Paths should not contain control characters or binary data.
```

#### **Command-Line Parameter Errors**
```bash
# Invalid database type
Error: Invalid database type. Supported: mysql, postgresql, oracle, sqlserver, db2, h2, sqlite
Please choose one of the supported database types.

# Invalid format
Error: Invalid format. Supported: text, csv, json, pretty
Please choose one of the supported output formats.

# Invalid host
Error: Invalid characters in host name
Host names should contain only letters, numbers, dots, and hyphens.

# Port out of range
Error: Invalid port number: 99999
Port numbers must be between 1 and 65535.

# Too long input
Error: Query too long (maximum 1MB)
Please reduce the query size and try again.
```

#### **Java Runtime Errors**
```bash
# Database not found
Database connection failed: Database not found or inaccessible
Please check your database path/URL and ensure the database exists.

# Access denied
Database connection failed: Access denied
Please check your database permissions and credentials.

# Invalid SQL syntax
Query execution failed: Invalid SQL syntax
Please check your SQL query for syntax errors.

# Missing JDBC driver
Database connection failed: JDBC driver issue
Please ensure the appropriate JDBC driver is available in the drivers directory.
```

## Key Improvements

1. **Clear Problem Description**: Users understand what went wrong
2. **Actionable Guidance**: Specific steps to fix the issue
3. **Examples Provided**: Show correct usage patterns
4. **No Information Leakage**: Sensitive system details are not exposed
5. **Consistent Format**: All error messages follow the same pattern
6. **Context-Aware**: Different messages for different error types

## Error Message Pattern

All error messages follow this pattern:
```
Error: [Brief problem description]
[Detailed explanation if needed]
[Specific guidance or example]
```

This ensures users can quickly understand and resolve issues while maintaining security by not exposing system internals.