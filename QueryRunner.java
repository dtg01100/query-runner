import java.sql.*;
import java.util.*;
import java.util.regex.*;

public class QueryRunner {

    private static boolean isDebug() {
        String v = System.getenv("QUERY_RUNNER_DEBUG");
        return v != null && (v.equals("1") || v.equalsIgnoreCase("true"));
    }

    private static void debug(String msg) {
        if (isDebug()) System.err.println("DEBUG: " + msg);
    }

    private static String maskJdbcUrl(String url) {
        if (url == null) return null;
        // Mask password= param in JDBC URL if present
        try {
            return url.replaceAll("(?i)(password=)([^&;]+)", "$1******");
        } catch (Exception e) {
            return url;
        }
    }

public static void main(String[] args) {
        String query = "";
        Scanner scanner = new Scanner(System.in);
        if (scanner.hasNextLine()) {
            query = scanner.useDelimiter("\\A").next();
        }
        
        // Input validation and sanitization
        if (query == null || query.trim().isEmpty()) {
            System.err.println("Error: Query cannot be empty");
            System.exit(1);
        }
        
        // Check for maximum query length
        if (query.length() > 1048576) { // 1MB limit
            System.err.println("Error: Query too long (maximum 1MB)");
            System.exit(1);
        }
        
        // Remove any potential null bytes or control characters
        query = query.replaceAll("\\u0000|\\p{Cntrl}", "");
        
        String url = System.getenv("JDBC_URL");
        String driver = System.getenv("JDBC_DRIVER_CLASS");
        String user = System.getenv("DB_USER");
        String password = System.getenv("DB_PASSWORD");
        String format = System.getenv("OUTPUT_FORMAT");
        if (format == null) format = "text";
        
        // Validate required parameters
        if (url == null || url.trim().isEmpty()) {
            System.err.println("Error: JDBC URL not provided");
            System.exit(1);
        }
        
        if (driver == null || driver.trim().isEmpty()) {
            System.err.println("Error: JDBC driver class not provided");
            System.exit(1);
        }
        
        // Sanitize JDBC URL
        url = sanitizeJdbcUrl(url);
        
        debug("JDBC driver class: " + driver);
        debug("JDBC URL: " + maskJdbcUrl(url));
        debug("DB user: " + (user == null ? "(none)" : user));
        
        try {
            Class.forName(driver);
        } catch (ClassNotFoundException e) {
            System.err.println("Error: JDBC driver not found: " + sanitizeOutput(e.getMessage()));
            System.exit(1);
        }

        try (Connection conn = DriverManager.getConnection(url, user, password);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {

            ResultSetMetaData meta = rs.getMetaData();
            int columnCount = meta.getColumnCount();
            List<String> columnNames = new ArrayList<>();
            for (int i = 1; i <= columnCount; i++) {
                String columnName = meta.getColumnName(i);
                // Sanitize column names to prevent malicious content
                columnName = sanitizeOutput(columnName);
                columnNames.add(columnName);
            }

            switch (format) {
                case "pretty":
                    // For pretty format, load all rows to calculate widths
                    List<Map<String, Object>> rows = new ArrayList<>();
                    int rowCount = 0;
                    final int MAX_ROWS = 10000; // Prevent DoS from huge result sets
                    
                    while (rs.next() && rowCount < MAX_ROWS) {
                        Map<String, Object> row = new HashMap<>();
                        for (int i = 1; i <= columnCount; i++) {
                            Object value = rs.getObject(i);
                            // Sanitize values to prevent malicious content in output
                            if (value != null) {
                                String stringValue = value.toString();
                                // Limit value length to prevent DoS
                                if (stringValue.length() > 10000) {
                                    stringValue = stringValue.substring(0, 10000) + "...";
                                }
                                value = sanitizeOutput(stringValue);
                            }
                            row.put(columnNames.get(i-1), value);
                        }
                        rows.add(row);
                        rowCount++;
                    }
                    
                    if (rowCount >= MAX_ROWS) {
                        System.err.println("Warning: Result set truncated at " + MAX_ROWS + " rows for security");
                    }
                    
                    outputPretty(columnNames, rows);
                    break;
                case "json":
                    outputJsonStream(columnNames, rs);
                    break;
                case "csv":
                    outputCsvStream(columnNames, rs);
                    break;
                case "text":
                default:
                    outputTextStream(columnNames, rs);
                    break;
            }
        } catch (SQLException e) {
            // Sanitize error messages to prevent information leakage
            String errorMessage = e.getMessage();
            if (errorMessage != null) {
                // Remove potentially sensitive information from error messages
                errorMessage = errorMessage.replaceAll("(?i)(password|passwd|pwd)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(user|username|uid)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(host|server)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
            }
            
            // Provide more helpful error messages for common issues
            if (errorMessage != null) {
                if (errorMessage.contains("database") && errorMessage.contains("not found")) {
                    System.err.println("Database connection failed: Database not found or inaccessible");
                    System.err.println("Please check your database path/URL and ensure the database exists.");
                } else if (errorMessage.contains("access") || errorMessage.contains("permission")) {
                    System.err.println("Database connection failed: Access denied");
                    System.err.println("Please check your database permissions and credentials.");
                } else if (errorMessage.contains("driver")) {
                    System.err.println("Database connection failed: JDBC driver issue");
                    System.err.println("Please ensure the appropriate JDBC driver is available in the drivers directory.");
                } else if (errorMessage.contains("table") && errorMessage.contains("not found")) {
                    System.err.println("Query execution failed: Table not found");
                    System.err.println("Please check your table names and database schema.");
                } else if (errorMessage.contains("syntax") || errorMessage.contains("SQL")) {
                    System.err.println("Query execution failed: Invalid SQL syntax");
                    System.err.println("Please check your SQL query for syntax errors.");
                } else {
                    System.err.println("SQL Error: " + sanitizeOutput(errorMessage));
                    System.err.println("Please check your query and database connection.");
                }
            } else {
                System.err.println("SQL Error: Database operation failed");
                System.err.println("Please check your query and database connection.");
            }
            
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        } catch (Exception e) {
            // Generic error handling for other exceptions
            System.err.println("Error: " + sanitizeOutput(e.getMessage() != null ? e.getMessage() : "An error occurred"));
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        }
    }
        
        // Input validation and sanitization
        if (query == null || query.trim().isEmpty()) {
            System.err.println("Error: Query cannot be empty");
            System.exit(1);
        }
        
        // Check for maximum query length
        if (query.length() > 1048576) { // 1MB limit
            System.err.println("Error: Query too long (maximum 1MB)");
            System.exit(1);
        }
        
        // Remove any potential null bytes or control characters
        query = query.replaceAll("\\u0000|\\p{Cntrl}", "");
        
        String url = System.getenv("JDBC_URL");
        String driver = System.getenv("JDBC_DRIVER_CLASS");
        String user = System.getenv("DB_USER");
        String password = System.getenv("DB_PASSWORD");
        String format = System.getenv("OUTPUT_FORMAT");
        if (format == null) format = "text";
        
        // Validate required parameters
        if (url == null || url.trim().isEmpty()) {
            System.err.println("Error: JDBC URL not provided");
            System.exit(1);
        }
        
        if (driver == null || driver.trim().isEmpty()) {
            System.err.println("Error: JDBC driver class not provided");
            System.exit(1);
        }
        
        // Sanitize JDBC URL
        url = sanitizeJdbcUrl(url);
        
        debug("JDBC driver class: " + driver);
        debug("JDBC URL: " + maskJdbcUrl(url));
        debug("DB user: " + (user == null ? "(none)" : user));
        
        try {
            Class.forName(driver);
        } catch (ClassNotFoundException e) {
            System.err.println("Error: JDBC driver not found: " + e.getMessage());
            System.exit(1);
        }

        try (Connection conn = DriverManager.getConnection(url, user, password);
             Statement stmt = conn.createStatement();
             ResultSet rs = stmt.executeQuery(query)) {

            ResultSetMetaData meta = rs.getMetaData();
            int columnCount = meta.getColumnCount();
            List<String> columnNames = new ArrayList<>();
            for (int i = 1; i <= columnCount; i++) {
                columnNames.add(meta.getColumnName(i));
            }

            switch (format) {
                case "pretty":
                    // For pretty format, load all rows to calculate widths
                    List<Map<String, Object>> rows = new ArrayList<>();
                    while (rs.next()) {
                        Map<String, Object> row = new HashMap<>();
                        for (int i = 1; i <= columnCount; i++) {
                            row.put(columnNames.get(i-1), rs.getObject(i));
                        }
                        rows.add(row);
                    }
                    outputPretty(columnNames, rows);
                    break;
                case "json":
                    outputJsonStream(columnNames, rs);
                    break;
                case "csv":
                    outputCsvStream(columnNames, rs);
                    break;
                case "text":
                default:
                    outputTextStream(columnNames, rs);
                    break;
            }
        } catch (SQLException e) {
            // Sanitize error messages to prevent information leakage
            String errorMessage = e.getMessage();
            if (errorMessage != null) {
                // Remove potentially sensitive information from error messages
                errorMessage = errorMessage.replaceAll("(?i)(password|passwd|pwd)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(user|username|uid)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(host|server)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
            }
            
            // Provide more helpful error messages for common issues
            if (errorMessage != null) {
                if (errorMessage.contains("database") && errorMessage.contains("not found")) {
                    System.err.println("Database connection failed: Database not found or inaccessible");
                    System.err.println("Please check your database path/URL and ensure the database exists.");
                } else if (errorMessage.contains("access") || errorMessage.contains("permission")) {
                    System.err.println("Database connection failed: Access denied");
                    System.err.println("Please check your database permissions and credentials.");
                } else if (errorMessage.contains("driver")) {
                    System.err.println("Database connection failed: JDBC driver issue");
                    System.err.println("Please ensure the appropriate JDBC driver is available in the drivers directory.");
                } else if (errorMessage.contains("table") && errorMessage.contains("not found")) {
                    System.err.println("Query execution failed: Table not found");
                    System.err.println("Please check your table names and database schema.");
                } else if (errorMessage.contains("syntax") || errorMessage.contains("SQL")) {
                    System.err.println("Query execution failed: Invalid SQL syntax");
                    System.err.println("Please check your SQL query for syntax errors.");
                } else {
                    System.err.println("SQL Error: " + sanitizeOutput(errorMessage));
                    System.err.println("Please check your query and database connection.");
                }
            } else {
                System.err.println("SQL Error: Database operation failed");
                System.err.println("Please check your query and database connection.");
            }
            
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        } catch (Exception e) {
            // Generic error handling for other exceptions
            System.err.println("Error: " + sanitizeOutput(e.getMessage() != null ? e.getMessage() : "An error occurred"));
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        }
    }
    
    // Sanitize JDBC URL to prevent injection
    private static String sanitizeJdbcUrl(String url) {
        if (url == null) return null;
        
        // Remove potentially dangerous characters
        url = url.replaceAll("[\\p{Cntrl}\\\\<>\"'&|;]", "");
        
        // Validate JDBC URL format
        if (!url.startsWith("jdbc:")) {
            return url; // Let the JDBC driver handle invalid URLs
        }
        
        return url;
    }
    
    // Enhanced JSON escaping to prevent XSS and injection
    private static String escapeJson(String str) {
        if (str == null) return null;
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            switch (c) {
                case '\\':
                case '"':
                    sb.append('\\').append(c);
                    break;
                case '\b':
                    sb.append("\\b");
                    break;
                case '\t':
                    sb.append("\\t");
                    break;
                case '\n':
                    sb.append("\\n");
                    break;
                case '\f':
                    sb.append("\\f");
                    break;
                case '\r':
                    sb.append("\\r");
                    break;
                default:
                    if (c < ' ') {
                        String t = "000" + Integer.toHexString(c);
                        sb.append("\\u").append(t.substring(t.length() - 4));
                    } else {
                        // Additional sanitization for potentially dangerous characters
                        if (c == '<' || c == '>' || c == '&' || c == '\'' || c == '"') {
                            sb.append(String.format("\\u%04x", (int) c));
                        } else {
                            sb.append(c);
                        }
                    }
                    break;
            }
        }
        return sb.toString();
    }

    private static String repeatString(String str, int count) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < count; i++) {
            sb.append(str);
        }
        return sb.toString();
    }
    
    // Sanitize output to prevent XSS and command injection
    private static String sanitizeOutput(String str) {
        if (str == null) return null;
        
        // Remove or escape potentially dangerous characters
        return str.replaceAll("[\\p{Cntrl}<>\"'&`$|;]", "");
    }

    private static void outputJsonStream(List<String> columnNames, ResultSet rs) throws SQLException {
        System.out.print("[");
        boolean first = true;
        while (rs.next()) {
            if (!first) System.out.print(",");
            first = false;
            System.out.print("{");
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print(",");
                System.out.print("\"" + escapeJson(columnNames.get(i)) + "\":");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("null");
                } else if (value instanceof Number || value instanceof Boolean) {
                    // For numbers and booleans, ensure they're properly formatted
                    String numStr = value.toString();
                    if (numStr.matches("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$")) {
                        System.out.print(numStr);
                    } else {
                        // If it looks like a number but contains suspicious characters, treat as string
                        System.out.print("\"" + escapeJson(numStr) + "\"");
                    }
                } else {
                    System.out.print("\"" + escapeJson(value.toString()) + "\"");
                }
            }
            System.out.print("}");
        }
        System.out.println("]");
    }

    private static void outputCsvStream(List<String> columnNames, ResultSet rs) throws SQLException {
        // Output header
        for (int i = 0; i < columnNames.size(); i++) {
            if (i > 0) System.out.print(",");
            String columnName = columnNames.get(i);
            // Sanitize column names for CSV
            columnName = sanitizeOutput(columnName);
            System.out.print("\"" + columnName.replace("\"", "\"\"") + "\"");
        }
        System.out.println();
        // Stream rows
        while (rs.next()) {
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print(",");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("");
                } else {
                    String strValue = value.toString();
                    // Sanitize values for CSV
                    strValue = sanitizeOutput(strValue);
                    System.out.print("\"" + strValue.replace("\"", "\"\"") + "\"");
                }
            }
            System.out.println();
        }
    }

    private static void outputTextStream(List<String> columnNames, ResultSet rs) throws SQLException {
        // Output header
        for (int i = 0; i < columnNames.size(); i++) {
            if (i > 0) System.out.print("\t");
            // Sanitize column names for text output
            String columnName = sanitizeOutput(columnNames.get(i));
            System.out.print(columnName);
        }
        System.out.println();
        // Stream rows
        while (rs.next()) {
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print("\t");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("NULL");
                } else {
                    String strValue = value.toString();
                    // Sanitize values for text output
                    strValue = sanitizeOutput(strValue);
                    System.out.print(strValue);
                }
            }
            System.out.println();
        }
    }

    private static void outputPretty(List<String> columnNames, List<Map<String, Object>> rows) {
        // Sanitize column names
        List<String> sanitizedNames = new ArrayList<>();
        for (String name : columnNames) {
            sanitizedNames.add(sanitizeOutput(name));
        }
        
        int[] maxWidths = new int[sanitizedNames.size()];
        for (int i = 0; i < sanitizedNames.size(); i++) {
            maxWidths[i] = sanitizedNames.get(i).length();
        }
        for (Map<String, Object> row : rows) {
            for (int i = 0; i < sanitizedNames.size(); i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? sanitizeOutput(value.toString()) : "NULL";
                maxWidths[i] = Math.max(maxWidths[i], strValue.length());
            }
        }
        String separator = "+";
        for (int width : maxWidths) {
            separator += repeatString("-", width + 2) + "+";
        }
        System.out.println(separator);
        System.out.print("|");
        for (int i = 0; i < sanitizedNames.size(); i++) {
            System.out.print(" " + String.format("%-" + maxWidths[i] + "s", sanitizedNames.get(i)) + " |");
        }
        System.out.println();
        System.out.println(separator);
        for (Map<String, Object> row : rows) {
            System.out.print("|");
            for (int i = 0; i < sanitizedNames.size(); i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? sanitizeOutput(value.toString()) : "NULL";
                System.out.print(" " + String.format("%-" + maxWidths[i] + "s", strValue) + " |");
            }
            System.out.println();
        }
        System.out.println(separator);
    }
}
