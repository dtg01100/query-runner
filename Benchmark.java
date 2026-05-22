import java.util.*;

/**
 * Benchmark harness for result parsing and returning.
 * Uses synthetic data to measure throughput of different output formats.
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

        // Generate test data
        Random rng = new Random(seed);
        List<String> colNames = new ArrayList<>();
        for (int i = 0; i < cols; i++) {
            colNames.add(COL_NAMES[i % COL_NAMES.length] + (i >= COL_NAMES.length ? "_" + (i / COL_NAMES.length) : ""));
        }

        // Generate all row data upfront to ensure deterministic timing
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
            outputBenchmark(colNames, rowsData, format, 100);
        }

        // Measure
        long totalNanos = 0;
        int measuredRows = 0;

        for (int i = 0; i < MEASURE_ITERATIONS; i++) {
            long start = System.nanoTime();
            int count = outputBenchmark(colNames, rowsData, format, rows);
            long end = System.nanoTime();
            totalNanos += (end - start);
            measuredRows += count;
        }

        double avgNanosPerRow = (double) totalNanos / measuredRows;

        // Output metrics
        System.out.println("METRIC throughput=" + String.format("%.2f", measuredRows * 1e9 / totalNanos));
        System.out.println("METRIC ns_per_row=" + String.format("%.2f", avgNanosPerRow));
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

    private static int outputBenchmark(List<String> colNames, List<Object[]> rowsData,
                                        String format, int maxRows) {
        int count = 0;
        StringBuilder sb = new StringBuilder();
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
                Object val = row[i];
                if (val == null) {
                    sb.append("null");
                } else if (val instanceof Number) {
                    sb.append(val);
                } else {
                    sb.append("\"").append(escapeJson(val.toString())).append("\"");
                }
            }
            sb.append("}");
            count++;
        }
        sb.append("]");

        // Write to stdout to simulate actual work
        System.out.print(sb.toString());

        return count;
    }

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
}