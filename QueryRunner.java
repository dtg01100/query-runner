import java.sql.*;
import java.util.*;
import java.util.regex.*;

public class QueryRunner {

    private static final int MAX_ROWS = 10000;
    private static final int MAX_VALUE_LENGTH = 10000;

    // Pre-compiled pattern for number detection (avoids regex compilation per value)
    private static final Pattern NUMBER_PATTERN = Pattern.compile("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$");

    private static boolean isDebug() {
        String v = System.getenv("QUERY_RUNNER_DEBUG");
        return v != null && (v.equals("1") || v.equalsIgnoreCase("true"));
    }

    // Suppress WARN lines on stderr when the wrapper (or the env) sets
    // QUERY_RUNNER_NO_WARNINGS=1 (mirrors the bash --quiet / --no-warnings
    // decision). Errors still print.
    private static boolean isWarningsSuppressed() {
        String v = System.getenv("QUERY_RUNNER_NO_WARNINGS");
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
        int len = str.length();
        // Fast path: scan for any char that would be stripped. Most AS/400 values
        // are plain ASCII (item codes, vendor numbers, names) and skip the copy.
        boolean needsStrip = false;
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            if (c < 0x20 || c == '<' || c == '>' || c == '"' || c == '\''
                || c == '&' || c == '`' || c == '$' || c == '|' || c == ';') {
                needsStrip = true;
                break;
            }
        }
        if (!needsStrip) return str;
        StringBuilder sb = new StringBuilder(len);
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            if (c >= 0x20 && c != '<' && c != '>' && c != '"' && c != '\''
                && c != '&' && c != '`' && c != '$' && c != '|' && c != ';') {
                sb.append(c);
            }
        }
        return sb.toString();
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
            // Stable exit code for SQL errors so callers can branch on it.
            // 4 matches the bash wrapper's EXIT_SQL constant.
            System.exit(4);
        } catch (Exception e) {
            System.err.println("Error: " + sanitizeOutput(e.getMessage() != null ? e.getMessage() : "An error occurred"));
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(4);
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
                if (rowCount >= MAX_ROWS && !isWarningsSuppressed()) {
                    System.err.println("WARN: Result set truncated at " + MAX_ROWS + " rows for security");
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
        int colCount = columnNames.size();
        // Pre-compute JSON key prefixes to avoid repeated escapeJson calls
        String[] keyPrefixes = new String[colCount];
        for (int i = 0; i < colCount; i++) {
            keyPrefixes[i] = "\"" + JsonUtil.escapeJson(columnNames.get(i)) + "\":";
        }

        // When the wrapper sets QUERY_RUNNER_JSON_ENVELOPE=1, wrap the array
        // in a metadata envelope so agents can detect truncation, row
        // counts, and per-call timing without re-parsing the array. The
        // bare-array form remains the default for backward compatibility.
        boolean envelope = "1".equals(System.getenv("QUERY_RUNNER_JSON_ENVELOPE"));
        int rowCount = 0;
        boolean truncated = false;

        StringBuilder sb = new StringBuilder(8192);
        if (envelope) {
            sb.append("{\"status\":\"ok\",\"row_count\":");
        }
        sb.append('[');
        boolean first = true;
        while (rs.next()) {
            if (rowCount >= MAX_ROWS) {
                truncated = true;
                break;
            }
            if (!first) sb.append(',');
            first = false;
            sb.append('{');
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append(',');
                sb.append(keyPrefixes[i]);
                Object value = rs.getObject(i + 1);
                if (value == null) {
                    sb.append("null");
                } else if (value instanceof Number) {
                    sb.append(value);
                } else if (value instanceof Boolean) {
                    sb.append(value);
                } else {
                    sb.append('"').append(JsonUtil.escapeJson(value.toString())).append('"');
                }
            }
            sb.append('}');
            rowCount++;
        }
        sb.append(']');
        if (envelope) {
            sb.append(",\"truncated\":").append(truncated ? "true" : "false");
            sb.append(",\"columns\":[");
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append(',');
                sb.append('"').append(JsonUtil.escapeJson(columnNames.get(i))).append('"');
            }
            sb.append("]}");
        }
        System.out.print(sb.toString());
        if (truncated && !isWarningsSuppressed()) {
            // Stable, greppable prefix on stderr. Suppressed when the wrapper
            // exports QUERY_RUNNER_NO_WARNINGS=1 (--quiet / --no-warnings).
            System.err.println("WARN: Result set truncated at " + MAX_ROWS + " rows for security");
        }
    }

    private static void outputCsvStream(List<String> columnNames, ResultSet rs) throws SQLException {
        int colCount = columnNames.size();
        // Pre-compute header row with sanitized and escaped column names
        StringBuilder header = new StringBuilder(colCount * 24);
        for (int i = 0; i < colCount; i++) {
            if (i > 0) header.append(',');
            String columnName = sanitizeOutput(columnNames.get(i));
            header.append('"').append(columnName.replace("\"", "\"\"")).append('"');
        }
        header.append('\n');
        
        StringBuilder sb = new StringBuilder(8192);
        sb.append(header);
        while (rs.next()) {
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append(',');
                // getString skips the type-inference dance of getObject; faster
                // for text output. Caveat: getString on a numeric type returns
                // the driver's toString which is stable for jt400/sqlite.
                String strValue = rs.getString(i + 1);
                if (strValue != null) {
                    strValue = sanitizeOutput(strValue);
                    sb.append('"').append(strValue.replace("\"", "\"\"")).append('"');
                }
            }
            sb.append('\n');
        }
        System.out.print(sb.toString());
    }

    private static void outputTextStream(List<String> columnNames, ResultSet rs) throws SQLException {
        int colCount = columnNames.size();
        // Pre-compute header row
        StringBuilder header = new StringBuilder(colCount * 16);
        for (int i = 0; i < colCount; i++) {
            if (i > 0) header.append('\t');
            header.append(sanitizeOutput(columnNames.get(i)));
        }
        header.append('\n');

        StringBuilder sb = new StringBuilder(8192);
        sb.append(header);
        while (rs.next()) {
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append('\t');
                // getString is faster than getObject().toString() for text output.
                String strValue = rs.getString(i + 1);
                if (strValue == null) {
                    sb.append("NULL");
                } else {
                    sb.append(sanitizeOutput(strValue));
                }
            }
            sb.append('\n');
        }
        System.out.print(sb.toString());
    }

    private static void outputPretty(List<String> columnNames, List<Map<String, Object>> rows) {
        int colCount = columnNames.size();
        List<String> sanitizedNames = new ArrayList<>(colCount);
        for (String name : columnNames) {
            sanitizedNames.add(sanitizeOutput(name));
        }

        int[] maxWidths = new int[colCount];
        for (int i = 0; i < colCount; i++) {
            maxWidths[i] = sanitizedNames.get(i).length();
        }
        for (Map<String, Object> row : rows) {
            for (int i = 0; i < colCount; i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? sanitizeOutput(value.toString()) : "NULL";
                if (strValue.length() > maxWidths[i]) maxWidths[i] = strValue.length();
            }
        }

        StringBuilder sb = new StringBuilder(8192);
        // Top border
        sb.append('+');
        for (int w : maxWidths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        // Header row
        sb.append('|');
        for (int i = 0; i < colCount; i++) {
            sb.append(' ').append(String.format("%-" + maxWidths[i] + "s", sanitizedNames.get(i))).append(" |");
        }
        sb.append('\n');

        // Header border
        sb.append('+');
        for (int w : maxWidths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        // Data rows
        for (Map<String, Object> row : rows) {
            sb.append('|');
            for (int i = 0; i < colCount; i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? sanitizeOutput(value.toString()) : "NULL";
                sb.append(' ').append(String.format("%-" + maxWidths[i] + "s", strValue)).append(" |");
            }
            sb.append('\n');
        }

        // Bottom border
        sb.append('+');
        for (int w : maxWidths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        System.out.print(sb.toString());
    }
}
