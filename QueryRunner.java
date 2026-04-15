import java.sql.*;
import java.util.*;
import java.util.regex.*;

public class QueryRunner {

    private static final int MAX_ROWS = 10000;
    private static final int MAX_VALUE_LENGTH = 10000;

    private static boolean isDebug() {
        String v = System.getenv("QUERY_RUNNER_DEBUG");
        return v != null && (v.equals("1") || v.equalsIgnoreCase("true"));
    }

    private static void debug(String msg) {
        if (isDebug()) System.err.println("DEBUG: " + msg);
    }

    private static String maskJdbcUrl(String url) {
        if (url == null) return null;
        try {
            return url.replaceAll("(?i)(password=)([^&;]+)", "$1******");
        } catch (Exception e) {
            return url;
        }
    }

    private static String sanitizeJdbcUrl(String url) {
        if (url == null) return null;
        url = url.replaceAll("[\\p{Cntrl}\\\\<>\"'&|;]", "");
        if (!url.startsWith("jdbc:")) {
            return url;
        }
        return url;
    }

    private static String sanitizeOutput(String str) {
        if (str == null) return null;
        return str.replaceAll("[\\p{Cntrl}<>\"'&`$|;]", "");
    }

    private static List<Object> parseJsonArray(String json) {
        if (json == null || json.trim().isEmpty()) {
            return Collections.emptyList();
        }
        String trimmed = json.trim();
        if (!trimmed.startsWith("[") || !trimmed.endsWith("]")) {
            throw new IllegalArgumentException("Invalid JSON array");
        }
        List<Object> result = new ArrayList<>();
        String content = trimmed.substring(1, trimmed.length() - 1);
        int depth = 0;
        boolean inString = false;
        boolean escaped = false;
        int start = 0;

        for (int i = 0; i <= content.length(); i++) {
            char c = i < content.length() ? content.charAt(i) : ',';
            if (escaped) {
                escaped = false;
                continue;
            }
            if (c == '\\') {
                escaped = true;
                continue;
            }
            if (c == '"') {
                inString = !inString;
                continue;
            }
            if (inString) continue;
            if (c == '{' || c == '[') depth++;
            if (c == '}' || c == ']') depth--;
            if (depth == 0 && (c == ',' || i == content.length())) {
                String item = content.substring(start, i).trim();
                start = i + 1;
                if (item.isEmpty()) continue;
                result.add(parseJsonValue(item));
            }
        }
        return result;
    }

    private static Object parseJsonValue(String value) {
        if (value.startsWith("\"")) {
            return parseJsonString(value);
        }
        if (value.startsWith("{")) {
            throw new IllegalArgumentException("JSON objects are not supported in SQL_PARAMS");
        }
        if (value.startsWith("[")) {
            return parseJsonArray(value);
        }
        if (value.equals("true")) return Boolean.TRUE;
        if (value.equals("false")) return Boolean.FALSE;
        if (value.equals("null")) return null;
        try {
            if (value.contains(".")) {
                return Double.parseDouble(value);
            }
            return Long.parseLong(value);
        } catch (NumberFormatException e) {
            return value;
        }
    }

    private static String parseJsonString(String value) {
        if (value.startsWith("\"") && value.endsWith("\"") && value.length() >= 2) {
            return value.substring(1, value.length() - 1)
                .replace("\\\"", "\"")
                .replace("\\\\", "\\")
                .replace("\\n", "\n")
                .replace("\\r", "\r")
                .replace("\\t", "\t")
                .replace("\\b", "\b")
                .replace("\\f", "\f");
        }
        return value;
    }

    private static void bindParameters(PreparedStatement stmt, List<Object> params) throws SQLException {
        for (int i = 0; i < params.size(); i++) {
            Object value = params.get(i);
            if (value == null) {
                stmt.setObject(i + 1, null);
            } else if (value instanceof Boolean) {
                stmt.setBoolean(i + 1, (Boolean) value);
            } else if (value instanceof Long) {
                stmt.setLong(i + 1, (Long) value);
            } else if (value instanceof Integer) {
                stmt.setInt(i + 1, (Integer) value);
            } else if (value instanceof Double) {
                stmt.setDouble(i + 1, (Double) value);
            } else if (value instanceof Float) {
                stmt.setFloat(i + 1, (Float) value);
            } else if (value instanceof Number) {
                stmt.setObject(i + 1, value);
            } else {
                stmt.setString(i + 1, value.toString());
            }
        }
    }

    private static String repeatString(String str, int count) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < count; i++) {
            sb.append(str);
        }
        return sb.toString();
    }

    public static void main(String[] args) {
        String query = "";
        Scanner scanner = new Scanner(System.in);
        if (scanner.hasNextLine()) {
            query = scanner.useDelimiter("\\A").next();
        }

        String url = System.getenv("JDBC_URL");
        String driver = System.getenv("JDBC_DRIVER_CLASS");
        String user = System.getenv("DB_USER");
        String password = System.getenv("DB_PASSWORD");
        String format = System.getenv("OUTPUT_FORMAT");
        String paramsJson = System.getenv("SQL_PARAMS");
        List<Object> params = parseJsonArray(paramsJson);
        if (format == null) format = "text";

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

        try (Connection conn = DriverManager.getConnection(url, user, password)) {
            if (params != null && !params.isEmpty()) {
                try (PreparedStatement stmt = conn.prepareStatement(query)) {
                    bindParameters(stmt, params);
                    try (ResultSet rs = stmt.executeQuery()) {
                        outputResultSet(rs, format);
                    }
                }
            } else {
                try (Statement stmt = conn.createStatement();
                     ResultSet rs = stmt.executeQuery(query)) {
                    outputResultSet(rs, format);
                }
            }
        } catch (SQLException e) {
            String errorMessage = e.getMessage();
            if (errorMessage != null) {
                errorMessage = errorMessage.replaceAll("(?i)(password|passwd|pwd)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(user|username|uid)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
                errorMessage = errorMessage.replaceAll("(?i)(host|server)\\s*[:=]\\s*[^\\s,;]+", "$1=******");
            }

            if (errorMessage != null) {
                if (errorMessage.contains("database") && errorMessage.contains("not found")) {
                    System.err.println("Database connection failed: Database not found or inaccessible");
                    System.err.println("Please check your database path/URL and ensure the database exists.");
                } else if (errorMessage.contains("access") || errorMessage.contains("permission")) {
                    System.err.println("Database connection failed: Access denied");
                    System.err.println("Please check your database permissions and credentials.");
                } else if (errorMessage.contains("driver")) {
                    System.err.println("Database connection failed: JDBC driver issue");
                    System.err.println("Please ensure the appropriate JDBC driver is available.");
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
            System.err.println("Error: " + sanitizeOutput(e.getMessage() != null ? e.getMessage() : "An error occurred"));
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        }
    }

    private static void outputResultSet(ResultSet rs, String format) throws SQLException {
        ResultSetMetaData meta = rs.getMetaData();
        int columnCount = meta.getColumnCount();
        List<String> columnNames = new ArrayList<>();
        for (int i = 1; i <= columnCount; i++) {
            String columnName = meta.getColumnName(i);
            columnName = sanitizeOutput(columnName);
            columnNames.add(columnName);
        }

        switch (format) {
            case "pretty":
                List<Map<String, Object>> rows = new ArrayList<>();
                int rowCount = 0;
                while (rs.next() && rowCount < MAX_ROWS) {
                    Map<String, Object> row = new HashMap<>();
                    for (int i = 1; i <= columnCount; i++) {
                        Object value = rs.getObject(i);
                        if (value != null) {
                            String stringValue = value.toString();
                            if (stringValue.length() > MAX_VALUE_LENGTH) {
                                stringValue = stringValue.substring(0, MAX_VALUE_LENGTH) + "...";
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
                System.out.print("\"" + JsonUtil.escapeJson(columnNames.get(i)) + "\":");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("null");
                } else if (value instanceof Number || value instanceof Boolean) {
                    String numStr = value.toString();
                    if (numStr.matches("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$")) {
                        System.out.print(numStr);
                    } else {
                        System.out.print("\"" + JsonUtil.escapeJson(numStr) + "\"");
                    }
                } else {
                    System.out.print("\"" + JsonUtil.escapeJson(value.toString()) + "\"");
                }
            }
            System.out.print("}");
        }
        System.out.println("]");
    }

    private static void outputCsvStream(List<String> columnNames, ResultSet rs) throws SQLException {
        for (int i = 0; i < columnNames.size(); i++) {
            if (i > 0) System.out.print(",");
            String columnName = columnNames.get(i);
            columnName = sanitizeOutput(columnName);
            System.out.print("\"" + columnName.replace("\"", "\"\"") + "\"");
        }
        System.out.println();
        while (rs.next()) {
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print(",");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("");
                } else {
                    String strValue = value.toString();
                    strValue = sanitizeOutput(strValue);
                    System.out.print("\"" + strValue.replace("\"", "\"\"") + "\"");
                }
            }
            System.out.println();
        }
    }

    private static void outputTextStream(List<String> columnNames, ResultSet rs) throws SQLException {
        for (int i = 0; i < columnNames.size(); i++) {
            if (i > 0) System.out.print("\t");
            String columnName = sanitizeOutput(columnNames.get(i));
            System.out.print(columnName);
        }
        System.out.println();
        while (rs.next()) {
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print("\t");
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    System.out.print("NULL");
                } else {
                    String strValue = value.toString();
                    strValue = sanitizeOutput(strValue);
                    System.out.print(strValue);
                }
            }
            System.out.println();
        }
    }

    private static void outputPretty(List<String> columnNames, List<Map<String, Object>> rows) {
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
