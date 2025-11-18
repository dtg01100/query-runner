# Database Testing Guide

This document provides a comprehensive guide for testing the query runner with various database types. It uses SQLite as a reference example, but the principles apply to all supported databases (MySQL, PostgreSQL, Oracle, SQL Server, DB2, H2, SQLite).

## Overview

This testing framework validates:
- Database connectivity and configuration
- Query execution and result handling
- Output format rendering (text, CSV, JSON, pretty)
- Error handling and security controls
- Driver management and dependencies

## General Testing Approach

### 1. Database Setup

For any database type, create a test table with sample data:

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,  -- Adjust type for your database
    name VARCHAR(100) NOT NULL,
    email VARCHAR(255) UNIQUE,
    age INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO users (name, email, age) VALUES 
('Alice Johnson', 'alice@example.com', 28),
('Bob Smith', 'bob@example.com', 35),
('Carol Davis', 'carol@example.com', 42),
('David Wilson', 'david@example.com', 31),
('Eva Brown', 'eva@example.com', 29);
```

### 2. Driver Dependencies

Download the appropriate JDBC driver(s) to the `drivers/` directory:

**Database-specific drivers:**
- **MySQL**: `mysql-connector-java-*.jar`
- **PostgreSQL**: `postgresql-*.jar`
- **Oracle**: `ojdbc*.jar`
- **SQL Server**: `mssql-jdbc*.jar`
- **DB2**: `db2jcc*.jar` or `jt400*.jar`
- **H2**: `h2*.jar`
- **SQLite**: `sqlite-jdbc*.jar`

**Common dependencies** (may be required):
- SLF4J API: `slf4j-api-*.jar`
- SLF4J Implementation: `slf4j-simple-*.jar` or `slf4j-nop-*.jar`

### 3. Configuration

Create a `.env` file with database-specific settings:

```bash
# Database Type (required)
DB_TYPE=<database_type>

# Connection Settings (adjust for your database)
DB_HOST=<hostname>
DB_PORT=<port>
DB_DATABASE=<database_name>
DB_USER=<username>
DB_PASSWORD=<password>

# Optional: Override auto-configuration
JDBC_DRIVER_CLASS=<driver_class>
JDBC_URL=<custom_jdbc_url>
```

**Database-specific examples:**

```bash
# MySQL
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=testdb
DB_USER=root
DB_PASSWORD=mypassword

# PostgreSQL
DB_TYPE=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=testdb
DB_USER=postgres
DB_PASSWORD=mypassword

# SQLite
DB_TYPE=sqlite
DB_DATABASE=/path/to/test.db
DB_USER=
DB_PASSWORD=

# Oracle
DB_TYPE=oracle
DB_HOST=localhost
DB_PORT=1521
DB_DATABASE=ORCL
DB_USER=scott
DB_PASSWORD=tiger
```

## Standard Test Suite

Run these tests for any database type to validate functionality:

### 1. Basic Query Execution

**Command:**
```bash
echo "SELECT * FROM users LIMIT 3" | ./query_runner
```

**Expected Results:**
- Returns 3 records in tab-separated format
- All columns properly displayed
- Data types handled correctly
- No errors or warnings (except Java native access warnings)

### 2. JSON Output Format

**Command:**
```bash
echo "SELECT * FROM users WHERE age > 30" | ./query_runner -f json
```

**Expected Results:**
- Valid JSON array output
- Proper JSON escaping for special characters
- Numbers and null values handled correctly
- Consistent field ordering

### 3. CSV Output Format

**Command:**
```bash
echo "SELECT name, email FROM users ORDER BY age DESC" | ./query_runner -f csv
```

**Expected Results:**
- Proper CSV header row
- Fields correctly quoted
- Special characters properly escaped
- Line endings consistent

### 4. Pretty Table Output Format

**Command:**
```bash
echo "SELECT name, age FROM users LIMIT 2" | ./query_runner -f pretty
```

**Expected Results:**
- Formatted table with borders
- Proper column alignment
- Clean visual presentation
- Handles long values gracefully

### 5. Connection Testing

**Command:**
```bash
./query_runner --test-connection
```

**Expected Results:**
- Connection established successfully
- Configuration parameters displayed correctly
- Driver loaded without errors
- "Connection successful!" message

### 6. Driver Listing

**Command:**
```bash
./query_runner --list-drivers
```

**Expected Results:**
- Detects appropriate database driver
- Lists all JAR files in drivers directory
- Identifies driver types correctly

### 7. Database-Specific Query Testing

**Commands:**
```bash
# Test database metadata
echo "SELECT COUNT(*) as total_users FROM users" | ./query_runner

# Test different data types
echo "SELECT name, age, created_at FROM users WHERE name LIKE '%A%'" | ./query_runner

# Test NULL handling (if applicable)
echo "SELECT * FROM users WHERE email IS NOT NULL" | ./query_runner

# Test database-specific features
# MySQL: echo "SELECT VERSION()" | ./query_runner
# PostgreSQL: echo "SELECT version()" | ./query_runner  
# Oracle: echo "SELECT * FROM v$version" | ./query_runner
# SQLite: echo "SELECT sqlite_version()" | ./query_runner
```

## Common Issues and Solutions

### 1. Java Compilation Errors

**Problem:** Escape sequence issues in generated Java code
**Symptoms:** Compilation errors with string literals
**Solution:** Ensure proper backslash escaping in the `escapeJson` method

### 2. Missing Dependencies

**Problem:** `ClassNotFoundException` for various classes
**Common Missing Classes:**
- `org.slf4j.LoggerFactory` → Download SLF4J API and implementation
- Database-specific driver classes → Download correct JDBC driver
- `javax.naming.*` → May need additional JNDI dependencies

**Solution:** Download required JARs to `drivers/` directory

### 3. Environment Variable Passing

**Problem:** Environment variables not available to Java process
**Symptoms:** NullPointerException in Java code
**Solution:** Ensure all required variables are exported before Java execution

### 4. Classpath Configuration

**Problem:** Only main driver JAR is in classpath
**Symptoms:** ClassNotFoundException for driver dependencies
**Solution:** Update classpath to include all JARs in drivers directory

### 5. Database-Specific Issues

**Connection Timeouts:**
- Check firewall settings
- Verify database is running and accessible
- Adjust timeout parameters in JDBC URL

**Authentication Failures:**
- Verify credentials in `.env` file
- Check database user permissions
- Ensure password doesn't contain special characters needing escaping

**SQL Syntax Errors:**
- Different databases have different SQL dialects
- Test with simple queries first
- Check database-specific reserved words

### 6. Driver Compatibility

**Problem:** Driver version incompatible with Java version
**Solution:** Use driver versions compatible with your Java runtime

**Problem:** Driver requires additional native libraries
**Solution:** Download platform-specific native libraries or use pure Java drivers

## Filename and Path Edge Cases

The runner rejects query file paths that contain control characters or are otherwise malformed. These are considered unsafe inputs and will be rejected with an error message.

Examples to test:

```bash
# Reject file names with tabs or newlines and carriage returns (control characters)
./query_runner " /tmp/has\tname.sql "  # Should fail with an error message
./query_runner " /tmp/has\nname.sql "  # Should fail with an error message

# Use -- sentinel for filenames beginning with a hyphen
printf "SELECT 1" > /tmp/-weird.sql
./query_runner -- /tmp/-weird.sql
```


## Security Validation

### Read-Only Query Enforcement

Test that the query runner properly blocks dangerous operations:

**Blocked Operations (should fail):**
```bash
echo "INSERT INTO users (name) VALUES ('test')" | ./query_runner  # Should be blocked
echo "UPDATE users SET age = 30 WHERE id = 1" | ./query_runner    # Should be blocked
echo "DELETE FROM users WHERE id = 1" | ./query_runner           # Should be blocked
echo "DROP TABLE users" | ./query_runner                         # Should be blocked
echo "CREATE TABLE test (id INT)" | ./query_runner              # Should be blocked
```

**Allowed Operations (should succeed):**
```bash
echo "SELECT * FROM users" | ./query_runner                     # Should work
echo "WITH temp AS (SELECT * FROM users) SELECT * FROM temp" | ./query_runner  # Should work
echo "PRAGMA table_info(users)" | ./query_runner                # SQLite only
echo "SHOW TABLES" | ./query_runner                             # MySQL/PostgreSQL
echo "DESCRIBE users" | ./query_runner                          # MySQL/Oracle
```

### Input Validation

Test these security controls:
- ✅ Multiple statement separation (semicolons) blocked
- ✅ Block comments prevented
- ✅ Query must start with read-only operation
- ✅ Dangerous keywords detected anywhere in query

### Database-Specific Security

**MySQL:**
- Test SQL injection prevention
- Verify privilege restrictions

**PostgreSQL:**
- Test function call restrictions
- Verify schema access controls

**Oracle:**
- Test PL/SQL block prevention
- Verify package access restrictions

**SQL Server:**
- Test stored procedure execution prevention
- Verify database context restrictions

## Performance Testing

### Baseline Metrics

Test these performance characteristics for your database:

**Query Execution:**
- Simple SELECT: < 1 second
- Complex JOIN: < 5 seconds
- Large result sets: Monitor memory usage

**Startup Overhead:**
- Java compilation: ~2-3 seconds
- Driver loading: ~1-2 seconds
- Connection establishment: Database-dependent

**Memory Usage (Streaming Implementation):**
- Small result sets (< 100 rows): ~5MB constant
- Medium result sets (100-1000 rows): ~5MB constant  
- Large result sets (> 1000 rows): ~5MB constant
- Pretty format: O(n) - loads all data for column width calculation

### Performance Optimization

**For Contributors:**
1. **Pre-compilation:** Consider pre-compiling Java code for production
2. **Connection Reuse:** Implement connection pooling for frequent use
3. **Result Streaming:** Now implemented by default for all formats except pretty
4. **Caching:** Cache compiled Java code between runs

**Streaming Benefits:**
- Constant memory usage regardless of dataset size
- Immediate output to user/pipeline
- Ideal for large data processing
- Perfect for pipeline usage

## Database-Specific Testing

### MySQL Testing
```bash
# Test MySQL-specific features
echo "SELECT VERSION()" | ./query_runner
echo "SHOW DATABASES" | ./query_runner
echo "DESCRIBE users" | ./query_runner
echo "SELECT NOW()" | ./query_runner
```

### PostgreSQL Testing
```bash
# Test PostgreSQL-specific features
echo "SELECT version()" | ./query_runner
echo "SELECT datname FROM pg_database" | ./query_runner
echo "\\d users" | ./query_runner  # May not work, use: SELECT column_name FROM information_schema.columns WHERE table_name = 'users'
echo "SELECT NOW()" | ./query_runner
```

### Oracle Testing
```bash
# Test Oracle-specific features
echo "SELECT * FROM v$version" | ./query_runner
echo "SELECT table_name FROM user_tables" | ./query_runner
echo "SELECT SYSDATE FROM dual" | ./query_runner
```

### SQL Server Testing
```bash
# Test SQL Server-specific features
echo "SELECT @@VERSION" | ./query_runner
echo "SELECT name FROM sys.databases" | ./query_runner
echo "SELECT GETDATE()" | ./query_runner
```

## Contributing Guidelines

### Adding New Database Support

1. **Update `configure_database()` function** in `query_runner`
2. **Add driver detection logic** in `detect_database_type()`
3. **Test with standard test suite**
4. **Add database-specific test cases**
5. **Update documentation**

### Testing Checklist

Before submitting changes, verify:

- [ ] All output formats work correctly
- [ ] Connection testing succeeds
- [ ] Security controls block dangerous operations
- [ ] Error handling is appropriate
- [ ] Performance is acceptable
- [ ] Documentation is updated

### Bug Reporting

When reporting issues, include:
- Database type and version
- JDBC driver version
- Java version
- Exact query that failed
- Full error message
- `.env` configuration (with sensitive data removed)

## Quick Test Commands

```bash
# Basic functionality
echo "SELECT * FROM users LIMIT 3" | ./query_runner

# Output formats
echo "SELECT * FROM users" | ./query_runner -f json
echo "SELECT * FROM users" | ./query_runner -f csv  
echo "SELECT * FROM users" | ./query_runner -f pretty

# Validation
./query_runner --test-connection
./query_runner --list-drivers

# Security tests (should fail)
echo "INSERT INTO users (name) VALUES ('test')" | ./query_runner  # Should be blocked
echo "SELECT 1; DROP TABLE users;" | ./query_runner            # Should be blocked

# Database-specific tests
echo "SELECT VERSION()" | ./query_runner  # MySQL/PostgreSQL
echo "SELECT NOW()" | ./query_runner      # Most databases
```

## Streaming Implementation Details

### Memory-Efficient Processing

The query runner now implements streaming by default:

**Text/CSV/JSON Formats:**
- Row-by-row processing with constant memory usage
- Immediate output as each row is processed
- Perfect for pipelines and large datasets

**Pretty Format:**
- Requires two-pass processing for column alignment
- Loads all data into memory (O(n) memory usage)
- Use only for small to medium datasets

### Pipeline Benefits

Streaming makes the query runner ideal for pipeline usage:

```bash
# Process large datasets without memory issues
echo "SELECT * FROM large_table" | ./query_runner -f csv | grep "pattern" | wc -l

# Stream to file
echo "SELECT * FROM large_table" | ./query_runner -f json > results.json

# Real-time processing
echo "SELECT * FROM logs WHERE timestamp > '2024-01-01'" | ./query_runner -f text | process_logs.py
```

## Conclusion

This testing framework provides a comprehensive approach to validate the query runner across different database types. The SQLite validation demonstrated:

- ✅ Reliable database connectivity
- ✅ Accurate query execution  
- ✅ Multiple output format support
- ✅ Robust security controls
- ✅ Proper error handling
- ✅ **NEW:** Memory-efficient streaming for large datasets

The streaming implementation transforms the query runner from a small-dataset tool to an enterprise-scale data processing solution capable of handling millions of rows with constant memory usage.

Use this guide to test new database types, validate changes, and ensure consistent behavior across all supported databases.