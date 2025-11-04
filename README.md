# Generic Query Runner

A universal JDBC query runner that auto-configures for multiple database types with support for various output formats.

## Features

- **Multi-database support**: MySQL, PostgreSQL, Oracle, SQL Server, DB2, H2, SQLite
- **Autoconfiguration**: Automatically detects database type and configures drivers
- **Multiple output formats**: Text, CSV, JSON, Pretty tables
- **Flexible configuration**: Environment variables, command-line overrides
- **Interactive mode**: Run queries interactively
- **Connection testing**: Verify database connectivity
- **Read-only safety**: Blocks potentially dangerous SQL operations

## Installation

1. Download the `query_runner` script
2. Make it executable: `chmod +x query_runner`
3. Create a drivers directory: `mkdir drivers`
4. Download appropriate JDBC drivers and place them in the `drivers/` directory

### JDBC Drivers Download

Download the appropriate JDBC driver for your database and place it in the `drivers/` directory:

- **MySQL**: [MySQL Connector/J](https://repo1.maven.org/maven2/mysql/mysql-connector-java/) (Maven Central) or [MySQL Developer](https://dev.mysql.com/downloads/connector/j/) (may require account)
- **PostgreSQL**: [PostgreSQL JDBC Driver](https://jdbc.postgresql.org/download/)
- **Oracle**: [Oracle JDBC Driver](https://www.oracle.com/database/technologies/appdev/jdbc-downloads.html)
- **SQL Server**: [Microsoft JDBC Driver](https://docs.microsoft.com/en-us/sql/connect/jdbc/download-microsoft-jdbc-driver-for-sql-server)
- **DB2**: [IBM Toolbox for Java (JTOpen)](https://github.com/IBM/JTOpen) or search for "jt400.jar"
- **H2**: [H2 Database Engine](https://www.h2database.com/html/download.html)
- **SQLite**: [SQLite JDBC Driver](https://github.com/xerial/sqlite-jdbc/releases)

## Configuration

### Environment File (`.env`)

Copy `.env.example` to `.env` and configure your database settings:

```bash
# Database Type (optional - will auto-detect)
DB_TYPE=mysql

# Connection Settings
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=mydb
DB_USER=myuser
DB_PASSWORD=mypassword
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
```

## Output Formats

### Text (default)
Tab-separated values with headers:
```
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
```
+----+------+-------------------+
| id | name | email             |
+----+------+-------------------+
| 1  | John | john@example.com  |
| 2  | Jane | jane@example.com  |
+----+------+-------------------+
```

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

- **Read-only enforcement**: Only allows SELECT, WITH, SHOW, DESCRIBE, EXPLAIN queries
- **SQL injection protection**: Blocks dangerous operations (INSERT, UPDATE, DELETE, DROP, etc.)
- **No password logging**: Passwords are never logged or displayed

## Examples

### Quick Start
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
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the troubleshooting section
- Review the examples
- Open an issue on the project repository