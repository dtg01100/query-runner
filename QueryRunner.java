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
        String url = System.getenv("JDBC_URL");
        String driver = System.getenv("JDBC_DRIVER_CLASS");
        String user = System.getenv("DB_USER");
        String password = System.getenv("DB_PASSWORD");
        String format = System.getenv("OUTPUT_FORMAT");
        if (format == null) format = "text";
        debug("JDBC driver class: " + driver);
        debug("JDBC URL: " + maskJdbcUrl(url));
        debug("DB user: " + (user == null ? "(none)" : user));
        try {
            Class.forName(driver);
            Connection conn = DriverManager.getConnection(url, user, password);
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery(query);
            ResultSetMetaData meta = rs.getMetaData();
            int columnCount = meta.getColumnCount();
            List<String> columnNames = new ArrayList<>();
            for (int i = 1; i <= columnCount; i++) {
                columnNames.add(meta.getColumnName(i));
            }
            if ("pretty".equals(format)) {
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
            } else {
                // Stream
                switch (format) {
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
            rs.close();
            stmt.close();
            conn.close();
        } catch (SQLException e) {
            System.err.println("SQL Error: " + e.getMessage());
            System.err.println("SQL State: " + e.getSQLState());
            System.err.println("Error Code: " + e.getErrorCode());
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        } catch (ClassNotFoundException e) {
            System.err.println("Error: JDBC driver not found: " + e.getMessage());
            if (isDebug()) {
                e.printStackTrace(System.err);
            }
            System.exit(1);
        }
    }

    private static String escapeJson(String str) {
        if (str == null) return null;
        return str.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t");
    }

    private static String repeatString(String str, int count) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < count; i++) {
            sb.append(str);
        }
        return sb.toString();
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
                    System.out.print(value.toString());
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
            System.out.print("\"" + columnNames.get(i).replace("\"", "\"\"") + "\"");
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
            System.out.print(columnNames.get(i));
        }
        System.out.println();
        // Stream rows
        while (rs.next()) {
            for (int i = 0; i < columnNames.size(); i++) {
                if (i > 0) System.out.print("\t");
                Object value = rs.getObject(i + 1);
                System.out.print(value != null ? value.toString() : "NULL");
            }
            System.out.println();
        }
    }

    private static void outputPretty(List<String> columnNames, List<Map<String, Object>> rows) {
        int[] maxWidths = new int[columnNames.size()];
        for (int i = 0; i < columnNames.size(); i++) {
            maxWidths[i] = columnNames.get(i).length();
        }
        for (Map<String, Object> row : rows) {
            for (int i = 0; i < columnNames.size(); i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? value.toString() : "NULL";
                maxWidths[i] = Math.max(maxWidths[i], strValue.length());
            }
        }
        String separator = "+";
        for (int width : maxWidths) {
            separator += repeatString("-", width + 2) + "+";
        }
        System.out.println(separator);
        System.out.print("|");
        for (int i = 0; i < columnNames.size(); i++) {
            System.out.print(" " + String.format("%-" + maxWidths[i] + "s", columnNames.get(i)) + " |");
        }
        System.out.println();
        System.out.println(separator);
        for (Map<String, Object> row : rows) {
            System.out.print("|");
            for (int i = 0; i < columnNames.size(); i++) {
                Object value = row.get(columnNames.get(i));
                String strValue = value != null ? value.toString() : "NULL";
                System.out.print(" " + String.format("%-" + maxWidths[i] + "s", strValue) + " |");
            }
            System.out.println();
        }
        System.out.println(separator);
    }
}
