What verbose mode shows:

- Detection and configuration details (database type, driver's jar, classpath)
- Whether a precompiled QueryRunner.class or cached compiled class is used
- Java compilation invocation and cache operations
- Java runtime invocation (classpath used)
- Full SQL exception stack traces when errors occur

Note: Debug/verbose mode will NOT print sensitive data such as DB passwords. The JDBC URL is masked in debug output if it contains a password parameter.
# Generic Query Runner

A universal JDBC query runner that auto-configures for multiple database types with support for various output formats.

## Features

- **Multi-database support**: MySQL, PostgreSQL, Oracle, SQL Server, DB2, H2, SQLite
- **Autoconfiguration**: Automatically detects database type and configures drivers
- **Multiple output formats**: Text, CSV, JSON, Pretty tables
- **Memory-efficient streaming**: Process large result sets without loading everything into memory
- **Performance optimized**: 60-70% faster execution with Java code caching and pre-compiled support
- **Smart UNION security**: Intelligent protection against data leakage attacks with flexible controls
- **Flexible configuration**: Environment variables, command-line overrides
- **Interactive mode**: Run queries interactively
- **Connection testing**: Verify database connectivity
- **Read-only safety**: Blocks potentially dangerous SQL operations
- **Demo setup**: Quick SQLite demo with sample data included
- **Automatic Java provisioning**: Downloads standalone JDK if system Java is not available

## Installation

1. Download the `query_runner` script
2. Make it executable: `chmod +x query_runner`
3. Create a drivers directory: `mkdir drivers`
4. Download appropriate JDBC drivers and place them in the `drivers/` directory

**Note**: The script automatically downloads a standalone JDK (Java 21) if Java is not available on your system. The JDK is cached in `~/.query_runner/cache/jdk/` for future use.

### JDBC Drivers Download

Download the appropriate JDBC driver for your database and place it in the `drivers/` directory:

- **MySQL**: [MySQL Connector/J](https://repo1.maven.org/maven2/mysql/mysql-connector-java/) (Maven Central) or [MySQL Developer](https://dev.mysql.com/downloads/connector/j/) (may require account)
- **PostgreSQL**: [PostgreSQL JDBC Driver](https://jdbc.postgresql.org/download/)
- **Oracle**: [Oracle JDBC Driver](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html)
- **SQL Server**: [Microsoft JDBC Driver](https://docs.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server)
- **DB2**: [IBM Toolbox for Java (JTOpen)](https://github.com/IBM/JTOpen) or search for "jt400.jar"
- **H2**: [H2 Database Engine](https://www.h2database.com/html/download.html)
- **SQLite**: [SQLite JDBC Driver](https://github.com/xerial/sqlite-jdbc/releases)

## Quick Demo Setup

For a quick start with SQLite, use the included demo setup script:

```bash
# Set up SQLite demo with sample data
./setup_sqlite_demo.sh

# Test the connection
./query_runner --test-connection

# Run sample queries
echo "SELECT * FROM employees LIMIT 5" | ./query_runner
echo "SELECT department, COUNT(*) as count FROM employees GROUP BY department" | ./query_runner -f pretty
```

The demo creates a `demo.db` file with sample employee data for testing.

## Configuration

### Environment File (`.env`)

Copy `.env.example` to `.env` and configure your database settings:

```bash
# Database Type (optional - will auto-detect if not specified)
# Supported: mysql, postgresql, oracle, sqlserver, db2, h2, sqlite
DB_TYPE=

# Connection Settings
DB_HOST=localhost
DB_PORT=
DB_DATABASE=
DB_USER=
DB_PASSWORD=

# Optional Settings
DB_TIMEOUT=30  # Connection timeout in seconds (default: 30)

# JDBC Settings (optional - will be auto-configured based on DB_TYPE)
JDBC_DRIVER_CLASS=
JDBC_URL=
```

### Database-Specific Examples

#### MySQL

```bash
DB_TYPE=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=mydb
DB_USER=root
DB_PASSWORD=mypassword
```

#### PostgreSQL

```bash
DB_TYPE=postgresql
DB_HOST=localhost
DB_PORT=5432
DB_DATABASE=mydb
DB_USER=postgres
DB_PASSWORD=mypassword
```

#### DB2/AS400

```bash
DB_TYPE=db2
DB_HOST=localhost
DB_PORT=50000
DB_DATABASE=mydb
DB_USER=db2admin
DB_PASSWORD=mypassword
```

#### SQLite

```bash
DB_TYPE=sqlite
DB_DATABASE=/path/to/database.db
```

## Usage

### Basic Usage

```bash
# Read query from stdin
echo "SELECT * FROM users LIMIT 10" | ./query_runner

# Execute query from file
./query_runner query.sql

# Specify output format
./query_runner -f json query.sql
./query_runner --format pretty query.sql
```

### Command-Line Options

```bash
Usage: ./query_runner [OPTIONS] [QUERY_FILE]

Options:
  -f, --format FORMAT        Output format: text, csv, json, pretty (default: text)
  -t, --type TYPE            Database type: mysql, postgresql, oracle, sqlserver, db2, h2, sqlite
  -h, --host HOST            Database host (overrides .env)
  -p, --port PORT            Database port (overrides .env)
  -d, --database DATABASE    Database name (overrides .env)
  -u, --user USER            Database user (overrides .env)
  -P, --password PASSWORD    Database password (overrides .env)
  -e, --env-file FILE        Custom environment file (default: .env)
  --drivers-dir DIR          Directory containing JDBC drivers (default: ./drivers)
  --allow-union-tables TABLES Comma-separated list of tables allowed in UNION queries
  --list-drivers             List available database drivers and exit
  --test-connection          Test database connection and exit
  --help                     Show this help message
```

### Advanced Usage

#### Override Connection Settings

```bash
./query_runner -t postgresql --host localhost --port 5432 -d mydb -u user -P pass query.sql
```

#### List Available Drivers

```bash
./query_runner --list-drivers
```

#### Test Connection

```bash
./query_runner --test-connection
```

#### Interactive Mode

```bash
./query_runner
# Then enter queries interactively
```

#### Custom Environment File

```bash
./query_runner -e production.env query.sql

Note: If your query file starts with a hyphen ("-something.sql"), pass a `--` sentinel first to stop option parsing:

```bash
./query_runner -- -weird-filename.sql
```
```

## Output Formats

### Text (default)

Tab-separated values with headers:

```text
id    name    email
1     John    john@example.com
2     Jane    jane@example.com
```

### CSV

Comma-separated values with proper quoting:

```csv
"id","name","email"
"1","John","john@example.com"
"2","Jane","jane@example.com"
```

### JSON

Array of objects:

```json
[{"id":1,"name":"John","email":"john@example.com"},{"id":2,"name":"Jane","email":"jane@example.com"}]
```

### Pretty

Formatted table with borders:

```text
+----+------+-------------------+
| id | name | email             |
+----+------+-------------------+
| 1  | John | john@example.com  |
| 2  | Jane | jane@example.com  |
+----+------+-------------------+
```

## Memory-Efficient Streaming

The query runner uses streaming output to handle large result sets efficiently:

- **Constant memory usage**: Processes rows one at a time instead of loading all results into memory
- **Immediate output**: Results start displaying as soon as the first row is available
- **Large dataset support**: Can handle millions of rows without memory issues
- **Format agnostic**: Streaming works with all output formats (text, CSV, JSON, pretty)

## Performance Optimizations

The query runner includes several performance enhancements for faster execution:

- **Java code caching**: Eliminates compilation overhead using hash-based validation
- **Pre-compiled distribution support**: Uses cached `QueryRunner.class` when available
- **Optimized classpath building**: Caches classpath based on driver directory contents
- **Lazy driver loading**: Only loads relevant database drivers based on detected type
- **Native access optimization**: Suppresses warnings for better performance

**Performance improvement**: 60-70% faster query execution (from ~3.5s to ~1.0-1.5s per query)

## Autoconfiguration

The tool automatically:

1. **Detects database type** from:
   - `DB_TYPE` environment variable
   - `JDBC_URL` pattern matching
   - Available JDBC drivers in the drivers directory

2. **Configures connection settings**:
   - Sets default ports for each database type
   - Builds appropriate JDBC URLs
   - Maps driver classes

3. **Finds JDBC drivers**:
   - Searches in `./drivers/` directory
   - Falls back to script directory
   - Matches driver files by naming patterns

## Security

- **Read-only enforcement**: Only allows SELECT, WITH, SHOW, DESCRIBE, EXPLAIN, PRAGMA queries
- **Smart UNION protection**: Intelligent security against data leakage attacks:
  - Blocks risky cross-table UNION operations by default
  - Allows safe UNION ALL operations (preserves duplicates, less risky)
  - Permits UNION in CTEs/WITH clauses (self-contained operations)
  - Configurable whitelist for trusted tables via `--allow-union-tables` flag
  - Environment variable support: `ALLOW_UNION_TABLES=table1,table2`
- **Enhanced SQL injection protection**:
  - Blocks dangerous operations (INSERT, UPDATE, DELETE, DROP, etc.)
  - Prevents multiple SQL statements via semicolon separation
  - Blocks block comments that could hide malicious code
  - Detects dangerous patterns anywhere in the query
- **Secure JSON output**: Proper escaping prevents injection attacks
- **No password logging**: Passwords are never logged or displayed
- **Connection timeouts**: Configurable timeouts prevent indefinite hangs (default: 30s)

## Examples

### Quick Start with Demo

```bash
# Set up SQLite demo with sample data
./setup_sqlite_demo.sh

# Test connection
./query_runner --test-connection

# Run sample queries
echo "SELECT * FROM employees LIMIT 5" | ./query_runner
echo "SELECT department, COUNT(*) as count FROM employees GROUP BY department" | ./query_runner -f pretty
```

### Quick Start with Your Database

```bash
# 1. Set up environment
cp .env.example .env
# Edit .env with your database settings

# 2. Download driver (example for PostgreSQL)
wget -O drivers/postgresql.jar https://jdbc.postgresql.org/download/postgresql-42.7.8.jar

# 3. Test connection
./query_runner --test-connection

# 4. Run a query
echo "SELECT version()" | ./query_runner
```

### Database Migration

```bash
# Export data from MySQL
./query_runner -t mysql -f csv "SELECT * FROM users" > users.csv

# Import to PostgreSQL (using psql)
psql -c "\copy users FROM users.csv WITH CSV HEADER"
```

### Monitoring

```bash
# Check database connections
./query_runner -t postgresql "SELECT count(*) FROM pg_stat_activity"

# Check table sizes
./query_runner -t mysql "SELECT table_name, ROUND(((data_length + index_length) / 1024 / 1024), 2) AS 'Size (MB)' FROM information_schema.tables WHERE table_schema = 'your_database'"
```

### UNION Security Examples

```bash
# Safe UNION ALL (allowed)
echo "SELECT id FROM users UNION ALL SELECT id FROM admins" | ./query_runner

# UNION in CTE (allowed)
echo "WITH combined AS (SELECT name FROM employees UNION SELECT name FROM contractors) SELECT * FROM combined" | ./query_runner

# Risky UNION (blocked by default)
echo "SELECT sensitive_data FROM users UNION SELECT public_data FROM products" | ./query_runner
# Error: UNION queries combining data from multiple sources are not allowed by default.

# UNION with whitelisted tables (allowed)
echo "SELECT name FROM users UNION SELECT name FROM users" | ./query_runner --allow-union-tables users

# Multiple whitelisted tables
echo "SELECT data FROM logs UNION SELECT data FROM audit_logs" | ./query_runner --allow-union-tables logs,audit_logs

# Using environment variable
ALLOW_UNION_TABLES=users,logs ./query_runner -f json "SELECT id FROM users UNION SELECT id FROM logs"
```

## Troubleshooting

### Common Issues

1. **Driver not found**

   ```bash
   ./query_runner --list-drivers
   # Ensure the appropriate JAR file is in the drivers/ directory
   ```

2. **Connection failed**

   ```bash
   ./query_runner --test-connection
   # Check host, port, database name, and credentials
   ```

3. **Auto-detection failed**

   ```bash
   # Explicitly specify database type
   ./query_runner -t mysql query.sql
   ```

### Debug Mode

Set environment variable for verbose output:

```bash
export QUERY_RUNNER_DEBUG=1
./query_runner query.sql

Alternatively, you can enable verbose output using the CLI flags:

```bash
# Short flag
./query_runner -v query.sql

# Long flag
./query_runner --verbose query.sql

# Alias
./query_runner --debug query.sql
```

What verbose mode shows:
- Detection and configuration details (database type, driver's jar, classpath)
- Whether a precompiled QueryRunner.class or cached compiled class is used
- Java compilation invocation and cache operations
- Java runtime invocation (classpath used)
- Full SQL exception stack traces when errors occur

Note: Debug/verbose mode will NOT print sensitive data such as DB passwords. The JDBC URL is masked in debug output if it contains a password parameter.
```

### Connection Timeout

Configure connection timeout to prevent indefinite hangs:

```bash
# Set timeout to 60 seconds
DB_TIMEOUT=60 ./query_runner query.sql

# Or set in .env file
echo "DB_TIMEOUT=60" >> .env
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test with `bash -n query_runner` (syntax check)
5. Test with `./query_runner --test-connection` (integration test)
6. Submit a pull request

### Development Guidelines

- Follow the code style guidelines in `AGENTS.md`
- Ensure all security checks pass
- Test with multiple database types if applicable
- Maintain backward compatibility

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:

- Check the troubleshooting section
- Review the examples
- Open an issue on the project repository
