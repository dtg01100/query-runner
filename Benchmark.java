import java.util.*;

/**
 * Benchmark harness for result parsing and returning.
 * Uses synthetic data to measure throughput of output format implementations.
 * Tests actual QueryRunner-style code patterns.
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
    private static final java.util.regex.Pattern NUMBER_PATTERN =
        java.util.regex.Pattern.compile("^-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?$");

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
     * Run benchmark with specified format
     */
    private static int runBenchmark(List<String> colNames, List<Object[]> rowsData,
                                     String format, int maxRows) {
        switch (format) {
            case "json":
                return outputJson(colNames, rowsData, maxRows);
            case "csv":
                return outputCsv(colNames, rowsData, maxRows);
            case "text":
                return outputText(colNames, rowsData, maxRows);
            case "pretty":
                return outputPretty(colNames, rowsData, maxRows);
            default:
                return outputJson(colNames, rowsData, maxRows);
        }
    }

    /**
     * Optimized JSON output - matches QueryRunner's optimized implementation
     * Uses StringBuilder for batched output, direct number append, pre-computed key prefixes
     */
    private static int outputJson(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int colCount = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        // Pre-compute JSON key prefixes
        String[] keyPrefixes = new String[colCount];
        for (int i = 0; i < colCount; i++) {
            keyPrefixes[i] = "\"" + escapeJson(colNames.get(i)) + "\":";
        }

        StringBuilder sb = new StringBuilder(16384);
        sb.append('[');
        boolean first = true;

        for (int r = 0; r < rows; r++) {
            if (!first) sb.append(',');
            first = false;
            sb.append('{');
            Object[] row = rowsData.get(r);
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append(',');
                sb.append(keyPrefixes[i]);
                Object value = row[i];
                if (value == null) {
                    sb.append("null");
                } else if (value instanceof Number) {
                    sb.append(value);
                } else if (value instanceof Boolean) {
                    sb.append(value);
                } else {
                    sb.append('"').append(escapeJson(value.toString())).append('"');
                }
            }
            sb.append('}');
        }
        sb.append(']');
        System.out.print(sb.toString());
        return rows;
    }

    /**
     * CSV output - StringBuilder based
     */
    private static int outputCsv(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        int colCount = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        StringBuilder sb = new StringBuilder(8192);
        // Header
        for (int i = 0; i < colCount; i++) {
            if (i > 0) sb.append(',');
            sb.append('"').append(colNames.get(i).replace("\"", "\"\"")).append('"');
        }
        sb.append('\n');

        // Data rows
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append(',');
                Object value = row[i];
                if (value != null) {
                    sb.append('"').append(value.toString().replace("\"", "\"\"")).append('"');
                }
            }
            sb.append('\n');
            count++;
        }

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Text output - tab-separated
     */
    private static int outputText(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        int colCount = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        StringBuilder sb = new StringBuilder(8192);
        // Header
        for (int i = 0; i < colCount; i++) {
            if (i > 0) sb.append('\t');
            sb.append(colNames.get(i));
        }
        sb.append('\n');

        // Data rows
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            for (int i = 0; i < colCount; i++) {
                if (i > 0) sb.append('\t');
                Object value = row[i];
                if (value == null) {
                    sb.append("NULL");
                } else {
                    sb.append(value.toString());
                }
            }
            sb.append('\n');
            count++;
        }

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Pretty output - table format
     */
    private static int outputPretty(List<String> colNames, List<Object[]> rowsData, int maxRows) {
        int count = 0;
        int colCount = colNames.size();
        int rows = Math.min(rowsData.size(), maxRows);

        // Calculate column widths
        int[] widths = new int[colCount];
        for (int i = 0; i < colCount; i++) {
            widths[i] = colNames.get(i).length();
        }

        // Scan data for max widths
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            for (int i = 0; i < colCount; i++) {
                String str = row[i] != null ? row[i].toString() : "NULL";
                if (str.length() > widths[i]) widths[i] = str.length();
            }
        }

        StringBuilder sb = new StringBuilder(8192);
        // Top border
        sb.append('+');
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        // Header row
        sb.append('|');
        for (int i = 0; i < colCount; i++) {
            sb.append(' ').append(String.format("%-" + widths[i] + "s", colNames.get(i))).append(" |");
        }
        sb.append('\n');

        // Header border
        sb.append('+');
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        // Data rows
        for (int r = 0; r < rows; r++) {
            Object[] row = rowsData.get(r);
            sb.append('|');
            for (int i = 0; i < colCount; i++) {
                String str = row[i] != null ? row[i].toString() : "NULL";
                sb.append(' ').append(String.format("%-" + widths[i] + "s", str)).append(" |");
            }
            sb.append('\n');
            count++;
        }

        // Bottom border
        sb.append('+');
        for (int w : widths) {
            for (int i = 0; i < w + 2; i++) sb.append('-');
            sb.append('+');
        }
        sb.append('\n');

        System.out.print(sb.toString());
        return count;
    }

    /**
     * Escape JSON string - optimized with fast path
     */
    private static String escapeJson(String str) {
        if (str == null) return "";
        int len = str.length();
        // Fast path: no special chars (common case)
        boolean needsEscape = false;
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            if (c == '\\' || c == '"' || c < ' ' || c > 127) {
                needsEscape = true;
                break;
            }
        }
        if (!needsEscape) return str;

        // Slow path: escape needed
        StringBuilder sb = new StringBuilder(len + 16);
        for (int i = 0; i < len; i++) {
            char c = str.charAt(i);
            switch (c) {
                case '\\': sb.append("\\\\"); break;
                case '"': sb.append("\\\""); break;
                case '\n': sb.append("\\n"); break;
                case '\r': sb.append("\\r"); break;
                case '\t': sb.append("\\t"); break;
                default:
                    if (c < ' ' || c > 127) {
                        // Inline hex encoding - avoid String.format overhead
                        sb.append("\\u00");
                        sb.append(Integer.toHexString(c >> 4 & 0xF));
                        sb.append(Integer.toHexString(c & 0xF));
                    } else {
                        sb.append(c);
                    }
            }
        }
        return sb.toString();
    }
}