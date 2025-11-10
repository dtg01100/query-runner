#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
DRIVERS_DIR="$SCRIPT_DIR/drivers"
DEMO_DB="$SCRIPT_DIR/demo.db"
SQLITE_JDBC_URL="https://github.com/xerial/sqlite-jdbc/releases/download/3.51.0.0/sqlite-jdbc-3.51.0.0.jar"
SQLITE_JDBC_JAR="$DRIVERS_DIR/sqlite-jdbc-3.51.0.0.jar"

echo "Setting up SQLite demo database..."
echo

# Create drivers directory if it doesn't exist
if [[ ! -d "$DRIVERS_DIR" ]]; then
    echo "Creating drivers directory..."
    mkdir -p "$DRIVERS_DIR"
fi

# Download SQLite JDBC driver if it doesn't exist
if [[ ! -f "$SQLITE_JDBC_JAR" ]]; then
    echo "Downloading SQLite JDBC driver..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$SQLITE_JDBC_JAR" "$SQLITE_JDBC_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$SQLITE_JDBC_JAR" "$SQLITE_JDBC_URL"
    else
        echo "Error: Neither curl nor wget found. Please install one of them." >&2
        exit 1
    fi
    echo "Downloaded SQLite JDBC driver to $SQLITE_JDBC_JAR"
else
    echo "SQLite JDBC driver already exists at $SQLITE_JDBC_JAR"
fi

echo

# Create demo database
echo "Creating demo SQLite database..."

# Remove existing demo database if it exists
if [[ -f "$DEMO_DB" ]]; then
    rm "$DEMO_DB"
fi

# Create tables and insert sample data
sqlite3 "$DEMO_DB" << 'EOF'
-- Create employees table
CREATE TABLE employees (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    department TEXT,
    salary REAL,
    hire_date DATE,
    active BOOLEAN DEFAULT 1
);

-- Create departments table
CREATE TABLE departments (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    location TEXT,
    budget REAL
);

-- Insert sample departments
INSERT INTO departments (name, location, budget) VALUES
('Engineering', 'Building A', 500000.00),
('Sales', 'Building B', 300000.00),
('Marketing', 'Building C', 200000.00),
('HR', 'Building A', 150000.00);

-- Insert sample employees
INSERT INTO employees (name, department, salary, hire_date) VALUES
('Alice Johnson', 'Engineering', 85000.00, '2023-01-15'),
('Bob Smith', 'Engineering', 78000.00, '2023-03-20'),
('Carol Williams', 'Sales', 65000.00, '2022-11-10'),
('David Brown', 'Sales', 70000.00, '2023-05-05'),
('Eve Davis', 'Marketing', 60000.00, '2023-02-28'),
('Frank Miller', 'Engineering', 95000.00, '2021-08-15'),
('Grace Wilson', 'HR', 55000.00, '2022-09-01'),
('Henry Taylor', 'Sales', 68000.00, '2023-07-12');

-- Create a view for active employees with department info
CREATE VIEW employee_details AS
SELECT
    e.id,
    e.name,
    e.department,
    d.location,
    e.salary,
    e.hire_date
FROM employees e
JOIN departments d ON e.department = d.name
WHERE e.active = 1;

-- Create an index for faster queries
CREATE INDEX idx_employee_department ON employees(department);
CREATE INDEX idx_employee_salary ON employees(salary);
EOF

echo "Created demo database with sample data at $DEMO_DB"
echo

# Show database contents
echo "Demo database contents:"
echo "======================"
echo
echo "Departments:"
sqlite3 "$DEMO_DB" "SELECT * FROM departments;" | cat
echo
echo "Employees:"
sqlite3 "$DEMO_DB" "SELECT * FROM employees;" | cat
echo

echo "Setup complete! You can now use the query runner with SQLite:"
echo
echo "Examples:"
echo "---------"
echo "# List all employees"
echo "echo \"SELECT * FROM employees\" | ./query_runner -t sqlite -d demo.db"
echo
echo "# Show employee details with department info"
echo "echo \"SELECT * FROM employee_details\" | ./query_runner -t sqlite -d demo.db"
echo
echo "# Get employees by department"
echo "echo \"SELECT name, salary FROM employees WHERE department = 'Engineering'\" | ./query_runner -t sqlite -d demo.db"
echo
echo "# Export to CSV"
echo "echo \"SELECT * FROM employees\" | ./query_runner -t sqlite -d demo.db -f csv > employees.csv"
echo
echo "# Interactive mode"
echo "./query_runner -t sqlite -d demo.db"
echo
echo "Note: You may see Java warnings about restricted methods - these are harmless"