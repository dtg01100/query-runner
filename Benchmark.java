import java.sql.*;
import java.util.*;
import java.util.regex.*;

/**
 * Benchmark harness for result parsing and returning.
 * Simulates QueryRunner's result set output with synthetic data.
 */
public class Benchmark {
    private static final int DEFAULT_ROWS = 10000;
    private static final int DEFAULT_COLS = 10;
    private static final int WARMUP_ITERATIONS = 2;
    private static final int MEASURE_ITERATIONS = 5;

    // Column names
    private static final String[] COL_NAMES = {
        "id", "name", "email", "age", "salary", "department",
        "joined_date", "active", "balance", "rating"
    };

    // Sample data for generating rows
    private static final String[] NAMES = {
        "Alice Smith", "Bob Johnson", "Carol White", "David Brown",
        "Emma Davis", "Frank Miller", "Grace Wilson", "Henry Moore",
        "Ivy Taylor", "Jack Anderson", "Kate Thomas", "Leo Jackson"
    };
    private static final String[] DEPTS = {
        "Engineering", "Sales", "Marketing", "Finance",
        "HR", "Operations", "Support", "Legal"
    };

    // Pre-compiled pattern for number detection (same as QueryRunner)
    private static final Pattern NUMBER_PATTERN = Pattern.compile("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$");

    public static void main(String[] args) {
        String format = "json";
        int rows = DEFAULT_ROWS;
        int cols = DEFAULT_COLS;
        long seed = 42;

        // Parse args
        for (int i = 0; i < args.length; i++) {
            switch (args[i]) {
                case "-f":
                case "--format":
                    if (i + 1 < args.length) format = args[++i];
                    break;
                case "-r":
                case "--rows":
                    if (i + 1 < args.length) rows = Integer.parseInt(args[++i]);
                    break;
                case "-c":
                case "--cols":
                    if (i + 1 < args.length) cols = Integer.parseInt(args[++i]);
                    break;
                case "-s":
                case "--seed":
                    if (i + 1 < args.length) seed = Long.parseLong(args[++i]);
                    break;
                case "-h":
                case "--help":
                    System.out.println("Usage: Benchmark [-f format] [-r rows] [-c cols] [-s seed]");
                    System.out.println("  format: json, csv, text, pretty (default: json)");
                    System.out.println("  rows: row count (default: 10000)");
                    System.out.println("  cols: column count (default: 10)");
                    System.exit(0);
            }
        }

        // Generate column names
        List<String> colNames = new ArrayList<>();
        for (int i = 0; i < cols; i++) {
            colNames.add(COL_NAMES[i % COL_NAMES.length] + (i >= COL_NAMES.length ? "_" + (i / COL_NAMES.length) : ""));
        }

        // Generate all row data upfront to ensure deterministic timing
        Random rng = new Random(seed);
        List<Object[]> rowsData = new ArrayList<>(rows);
        for (int r = 0; r < rows; r++) {
            Object[] row = new Object[cols];
            for (int c = 0; c < cols; c++) {
                row[c] = generateValue(c, r, rng);
            }
            rowsData.add(row);
        }

        // Warmup
        for (int i = 0; i < WARMUP_ITERATIONS; i++) {
            runBenchmark(colNames, rowsData, format, 100);
        }

        // Measure
        long totalNanos = 0;
        int measuredRows = 0;

        for (int i = 0; i < MEASURE_ITERATIONS; i++) {
            // Force GC before measurement
            System.gc();
            long start = System.nanoTime();
            int count = runBenchmark(colNames, rowsData, format, rows);
            long end = System.nanoTime();
            totalNanos += (end - start);
            measuredRows += count;
        }

        double throughput = measuredRows * 1e9 / totalNanos;
        double nsPerRow = (double) totalNanos / measuredRows;

        // Output metrics
        System.out.println("METRIC throughput=" + String.format("%.2f", throughput));
        System.out.println("METRIC ns_per_row=" + String.format("%.2f", nsPerRow));
        System.out.println("METRIC total_rows=" + measuredRows);
        System.out.println("METRIC total_ns=" + totalNanos);
        System.out.println("METRIC format=" + format);
        System.out.println("METRIC columns=" + cols);
    }

    private static Object generateValue(int col, int rowIdx, Random rng) {
        switch (col % 6) {
            case 0: return rowIdx;  // integer
            case 1: return NAMES[rng.nextInt(NAMES.length)];  // string
            case 2: return "user" + rowIdx + "@example.com";  // email-like
            case 3: return rng.nextInt(100);  // small int
            case 4: return String.format("%.2f", rng.nextDouble() * 100000);  // decimal string
            case 5: return DEPTS[rng.nextInt(DEPTS.length)];  // category
            default: return "value_" + rowIdx;
        }
    }

    /**
     * Run benchmark with specified format - simulates QueryRunner's output methods
     */
    private static int runBenchmark(List<String> colNames, List<Object[]> rowsData,
                                     String format, int maxRows) {
        switch (format) {
            case "json":
                return outputJsonBenchmark(colNames, rowsData, maxRows);
            case "csv":
                return outputCsvBenchmark(colNames, rowsData, maxRows);
            case "text":
                return outputTextBenchmark(colNames, rowsData, maxRows);
            case "pretty":
                return outputPrettyBenchmark(colNames, rowsData, maxRows);
            default:
                return outputJsonBenchmark(colNames, rowsData, maxRows);
        }
    }

    /**
     * Original QueryRunner JSON output - uses System.out.print in loop
     */
    private static int outputJsonBenchmark(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;

        // Pre-allocate StringBuilder with estimated capacity
        // Each row: ~100 chars average, plus overhead
        StringBuilder sb = new StringBuilder(colNames.size() * 20 + rowsData.size() * 100);
        sb.append("[");
        boolean first = true;

        for (Object[] row : rowsData) {
            if (count >= maxRows) break;

            if (!first) sb.append(",");
            first = false;

            sb.append("{");
            for (int i = 0; i < colNames.size(); i++) {
                if (i > 0) sb.append(",");
                sb.append("\"").append(colNames.get(i)).append("\":");
                Object value = row[i];
                if (value == null) {
                    sb.append("null");
                } else if (value instanceof Number || value instanceof Boolean) {
                    String numStr = value.toString();
                    if (NUMBER_PATTERN.matcher(numStr).matches()) {
                        sb.append(numStr);
                    } else {
                        sb.append("\"").append(escapeJson(numStr)).append("\"");
                    }
                } else {
                    sb.append("\"").append(escapeJson(value.toString())).append("\"");
                }
            }
            sb.append("}");
            count++;
        }
        sb.append("]");

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Optimized JSON output - inline escape, pre-compute column names
     */
    private static int outputJsonOptimized(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        int cols = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        // Pre-calculate output size for optimal buffer
        int avgRowSize = cols * 30;  // estimate
        StringBuilder sb = new StringBuilder(rows * avgRowSize + 100);
        sb.append("[");

        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            if (r > 0) sb.append(",");
            sb.append("{");

            for (int i = 0; i < cols; i++) {
                if (i > 0) sb.append(",");
                sb.append("\"").append(colNames.get(i)).append("\":");
                Object value = row[i];

                if (value == null) {
                    sb.append("null");
                } else if (value instanceof Number) {
                    sb.append(value);  // Direct append for numbers
                } else if (value instanceof Boolean) {
                    sb.append(value);
                } else {
                    sb.append("\"").append(escapeJsonInline(value.toString())).append("\"");
                }
            }
            sb.append("}");
            count++;
        }
        sb.append("]");

        System.out.print(sb.toString());
        return count;
    }

    /**
     * CSV output - original style
     */
    private static int outputCsvBenchmark(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        StringBuilder sb = new StringBuilder();

        // Header
        for (int i = 0; i < colNames.size(); i++) {
            if (i > 0) sb.append(",");
            String colName = colNames.get(i);
            sb.append("\"").append(colName.replace("\"", "\"\"")).append("\"");
        }
        sb.append("\n");

        // Data rows
        for (Object[] row : rowsData) {
            if (count >= maxRows) break;

            for (int i = 0; i < colNames.size(); i++) {
                if (i > 0) sb.append(",");
                Object value = row[i];
                if (value == null) {
                    // empty
                } else {
                    String strValue = value.toString();
                    sb.append("\"").append(strValue.replace("\"", "\"\"")).append("\"");
                }
            }
            sb.append("\n");
            count++;
        }

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Text output - tab-separated
     */
    private static int outputTextBenchmark(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        StringBuilder sb = new StringBuilder();

        // Header
        for (int i = 0; i < colNames.size(); i++) {
            if (i > 0) sb.append("\t");
            sb.append(colNames.get(i));
        }
        sb.append("\n");

        // Data rows
        for (Object[] row : rowsData) {
            if (count >= maxRows) break;

            for (int i = 0; i < colNames.size(); i++) {
                if (i > 0) sb.append("\t");
                Object value = row[i];
                if (value == null) {
                    sb.append("NULL");
                } else {
                    sb.append(value.toString());
                }
            }
            sb.append("\n");
            count++;
        }

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Pretty output - table format
     */
    private static int outputPrettyBenchmark(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        int cols = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        // Calculate column widths
        int[] widths = new int[cols];
        for (int i = 0; i < cols; i++) {
            widths[i] = colNames.get(i).length();
        }

        // Scan data for max widths
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            for (int i = 0; i < cols; i++) {
                Object value = row[i];
                String str = value != null ? value.toString() : "NULL";
                if (str.length() > widths[i]) widths[i] = str.length();
            }
        }

        // Build separator
        StringBuilder sb = new StringBuilder();
        sb.append("+");
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append("-");
            sb.append("+");
        }
        sb.append("\n");

        // Header
        sb.append("|");
        for (int i = 0; i < cols; i++) {
            sb.append(" ").append(String.format("%-" + widths[i] + "s", colNames.get(i))).append(" |");
        }
        sb.append("\n");

        // Separator
        sb.append("+");
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append("-");
            sb.append("+");
        }
        sb.append("\n");

        // Data rows
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            sb.append("|");
            for (int i = 0; i < cols; i++) {
                Object value = row[i];
                String str = value != null ? value.toString() : "NULL";
                sb.append(" ").append(String.format("%-" + widths[i] + "s", str)).append(" |");
            }
            sb.append("\n");
            count++;
        }

        // Footer
        sb.append("+");
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append("-");
            sb.append("+");
        }
        sb.append("\n");

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Escape JSON string - current QueryRunner approach
     */
    private static String escapeJson(String str) {
        if (str == null) return "";
        StringBuilder sb = new StringBuilder(str.length() + 16);
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            switch (c) {
                case '\\': sb.append("\\\\"); break;
                case '"': sb.append("\\\""); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < ' ' || c > 127) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.toString();
    }

    /**
     * Inline escape - avoids StringBuilder allocation
     */
    private static CharSequence escapeJsonInline(String str) {
        if (str == null) return "";
        // Fast path: no special chars
        boolean needsEscape = false;
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            if (c == '\\' || c == '"' || c < ' ' || c > 127) {
                needsEscape = true;
                break;
            }
        }
        if (!needsEscape) return str;

        // Slow path: escape needed
        StringBuilder sb = new StringBuilder(str.length() + 16);
        for (int i = 0; i < str.length(); i++) {
            char c = str.charAt(i);
            switch (c) {
                case '\\': sb.append("\\\\"); break;
                case '"': sb.append("\\\""); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < ' ' || c > 127) {
                        sb.append(String.format("\\u%04x", (int) c));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb;
    }
}