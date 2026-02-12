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

## Daemon Mode Testing

The query runner includes a persistent daemon mode for optimizing consecutive queries. This section covers testing the daemon functionality.

### Daemon Overview

The daemon runs as a persistent Java process that:
- Maintains database connections in a connection pool
- Listens on a Unix domain socket (`~/.query_runner/daemon.sock`)
- Automatically starts on first query (unless `--no-daemon` is specified)
- Times out after 5 minutes of inactivity

### Quick Start

```bash
# Start daemon explicitly
./query_runner --daemon-start

# Check daemon status
./query_runner --daemon-status

# Stop daemon
./query_runner --daemon-stop

# Restart daemon
./query_runner --daemon-restart

# Run query (auto-starts daemon if not running)
./query_runner "SELECT * FROM users"

# Disable daemon mode
./query_runner --no-daemon "SELECT * FROM users"
```

### Running Daemon Tests

```bash
# Install test dependencies
apt-get install socat sqlite3

# Run all daemon tests
./test_daemon/test_daemon.sh

# Run specific test categories
./test_daemon/test_daemon.sh lifecycle    # Daemon lifecycle tests
./test_daemon/test_daemon.sh protocol    # JSON protocol tests
./test_daemon/test_daemon.sh fallback    # Fallback to single-query mode
./test_daemon/test_daemon.sh pooling     # Connection pool tests
./test_daemon/test_daemon.sh security    # Security validation tests
./test_daemon/test_daemon.sh concurrency # Concurrent query tests
./test_daemon/test_daemon.sh performance # Performance benchmarks
```

### Test Categories

#### Lifecycle Tests (`test_daemon_lifecycle.sh`)

Tests daemon start, stop, restart, auto-start, and socket cleanup:

```bash
./test_daemon/test_daemon.sh lifecycle
```

| Test | Description |
|------|-------------|
| `daemon_start_fresh` | Start daemon when not running |
| `daemon_already_running` | Handle duplicate start gracefully |
| `daemon_query_execution` | Execute queries through daemon |
| `daemon_status_running` | Report running status correctly |
| `daemon_stop` | Stop daemon and cleanup socket |
| `daemon_stop_not_running` | Handle stop when not running |
| `daemon_restart` | Restart with new PID |
| `daemon_auto_start` | Auto-start on first query |
| `daemon_socket_cleanup` | Clean stale socket on start |
| `daemon_multiple_queries` | Handle multiple queries |
| `daemon_query_different_formats` | Support all output formats |

#### Protocol Tests (`test_daemon_protocol.sh`)

Tests the JSON protocol over Unix socket:

```bash
./test_daemon/test_daemon.sh protocol
```

| Test | Description |
|------|-------------|
| `protocol_ping` | Ping/pong health check |
| `protocol_query_valid` | Execute valid SQL queries |
| `protocol_query_invalid_sql` | Return errors for bad SQL |
| `protocol_query_blocked` | Block write operations |
| `protocol_status` | Report daemon status |
| `protocol_shutdown` | Graceful shutdown |
| `protocol_malformed_json` | Handle invalid JSON |
| `protocol_missing_type` | Require type field |
| `protocol_unknown_type` | Reject unknown types |
| `protocol_large_result` | Handle large result sets |
| `protocol_special_chars` | Proper JSON escaping |
| `protocol_null_values` | Handle NULL correctly |
| `protocol_format_*` | Support all formats |

#### Fallback Tests (`test_daemon_fallback.sh`)

Tests graceful fallback to single-query mode:

```bash
./test_daemon/test_daemon.sh fallback
```

| Test | Description |
|------|-------------|
| `fallback_socket_missing` | Work when daemon unavailable |
| `fallback_socket_busy` | Recover from stale socket |
| `fallback_explicit_flag` | Honor `--no-daemon` |
| `fallback_daemon_crash` | Recover from crash |
| `fallback_connection_refused` | Handle connection errors |

#### Connection Pooling Tests (`test_daemon_pooling.sh`)

Tests connection pool behavior:

```bash
./test_daemon/test_daemon.sh pooling
```

| Test | Description |
|------|-------------|
| `pool_connection_reuse` | Reuse connections |
| `pool_max_connections` | Handle pool exhaustion |
| `pool_connection_validity` | Validate connections |
| `pool_query_uses_pool` | Queries benefit from pool |
| `pool_multiple_queries` | Multiple queries share pool |
| `pool_sequential_queries` | Sequential queries reuse |

#### Security Tests (`test_daemon_security.sh`)

Tests daemon security controls:

```bash
./test_daemon/test_daemon.sh security
```

| Test | Description |
|------|-------------|
| `socket_file_permissions` | Socket has restricted perms |
| `socket_directory_permissions` | Socket dir has restricted perms |
| `query_injection_blocked` | Block SQL injection |
| `query_union_detection` | Detect cross-table UNIONs |
| `query_dangerous_keywords` | Block dangerous keywords |
| `error_no_credentials` | No credentials in errors |
| `query_length_limit` | Reject oversized queries |
| `null_byte_blocked` | Reject null bytes |
| `read_only_enforced` | Enforce read-only |

#### Concurrency Tests (`test_daemon_concurrency.sh`)

Tests parallel query execution:

```bash
./test_daemon/test_daemon.sh concurrency
```

| Test | Description |
|------|-------------|
| `concurrent_queries_5` | 5 parallel queries |
| `concurrent_queries_10` | 10 parallel queries |
| `concurrent_queries_20` | 20 parallel queries |
| `concurrent_mixed_formats` | Different formats concurrently |
| `concurrent_same_table` | Multiple queries on same table |
| `concurrent_error_isolation` | Errors don't cascade |
| `concurrent_daemon_stable` | Daemon remains stable |

#### Performance Tests (`test_daemon_performance.sh`)

Benchmarks daemon performance:

```bash
./test_daemon/test_daemon.sh performance
```

| Test | Target |
|------|--------|
| `perf_daemon_startup` | < 5 seconds |
| `perf_first_query` | < 500ms |
| `perf_subsequent_queries` | < 100ms avg |
| `perf_cold_vs_warm` | > 2x speedup |
| `perf_throughput` | > 5 QPS |
| `perf_memory_baseline` | < 200MB |
| `perf_query_latency_p50_p99` | p99 < 500ms |

### Docker-Based Database Testing

For multi-database testing, use Docker:

```bash
# Start test databases
cd test_daemon/docker
docker-compose up -d

# Wait for databases to be ready
sleep 10

# Run tests with MySQL
DB_TYPE=mysql DB_HOST=localhost DB_PORT=3307 \
  DB_DATABASE=testdb DB_USER=root DB_PASSWORD=testpass123 \
  ../../test_daemon.sh all

# Run tests with PostgreSQL
DB_TYPE=postgresql DB_HOST=localhost DB_PORT=5433 \
  DB_DATABASE=testdb DB_USER=postgres DB_PASSWORD=testpass123 \
  ../../test_daemon.sh all

# Cleanup
docker-compose down
```

### Test Fixtures

Test database schema and data are in `test_daemon/fixtures/test_schema.sql`:

```sql
CREATE TABLE users (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    age INTEGER,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id INTEGER PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    amount REAL NOT NULL,
    status TEXT DEFAULT 'pending'
);

CREATE TABLE products (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    stock INTEGER DEFAULT 0
);
```

### Troubleshooting Tests

**socat not found:**
```bash
apt-get install socat          # Debian/Ubuntu
brew install socat              # macOS
```

**SQLite not found:**
```bash
apt-get install sqlite3         # Debian/Ubuntu
brew install sqlite3            # macOS
```

**Daemon won't start:**
```bash
# Check logs
cat ~/.query_runner/daemon.log

# Manual start with debug
DEBUG=1 ./query_runner --daemon-start
```

**Socket permission denied:**
```bash
# Remove stale socket
rm -f ~/.query_runner/daemon.sock

# Fix permissions
chmod 700 ~/.query_runner
```

### Continuous Integration

Example CI configuration for GitHub Actions:

```yaml
name: Daemon Tests

on: [push, pull_request]

jobs:
  daemon-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: |
          apt-get update
          apt-get install -y socat sqlite3 default-jdk
      - name: Run daemon tests
        run: ./test_daemon/test_daemon.sh all
```

## Conclusion

This testing framework provides comprehensive validation of the query runner daemon mode:

- **63 tests** across 7 categories
- **SQLite** for fast local testing
- **Docker** support for MySQL/PostgreSQL
- **Automated** performance benchmarks
- **Security** validation for all entry points
- **Concurrency** testing up to 20 parallel queries

All tests validate both the daemon functionality and maintain backward compatibility with single-query mode through robust fallback mechanisms.