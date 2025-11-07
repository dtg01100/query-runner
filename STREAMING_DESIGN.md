# Streaming Large Result Sets - Design Document

## Current Limitation

The current implementation loads all query results into memory before outputting:

```java
List<Map<String, Object>> rows = new ArrayList<>();
while (rs.next()) {
    Map<String, Object> row = new HashMap<>();
    // ... load row into memory
    rows.add(row);
}
// Then process all rows at once
outputJson(columnNames, rows);
```

This causes memory issues with large datasets (millions of rows).

## Streaming Solutions

### Option 1: Row-by-Row Streaming (Recommended)

**Approach:** Process and output each row immediately as it's read from the ResultSet.

**Benefits:**
- Constant memory usage regardless of result size
- Immediate output to user
- Simple implementation
- Works with all output formats

**Implementation:**

```java
// Instead of loading all rows:
switch (format) {
    case "json":
        outputJsonStream(columnNames, rs);
        break;
    case "csv":
        outputCsvStream(columnNames, rs);
        break;
    case "pretty":
        outputPrettyStream(columnNames, rs);
        break;
    case "text":
    default:
        outputTextStream(columnNames, rs);
        break;
}

// Streaming implementations:
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
```

### Option 2: Batch Streaming

**Approach:** Process rows in configurable batches (e.g., 1000 rows at a time).

**Benefits:**
- Balance between memory usage and performance
- Allows for some optimizations (bulk formatting)
- Configurable memory footprint

**Implementation:**

```java
private static final int BATCH_SIZE = 1000;

private static void outputJsonBatch(List<String> columnNames, ResultSet rs) throws SQLException {
    System.out.print("[");
    boolean firstRow = true;
    List<Map<String, Object>> batch = new ArrayList<>(BATCH_SIZE);
    
    while (rs.next()) {
        Map<String, Object> row = new HashMap<>();
        for (int i = 1; i <= columnNames.size(); i++) {
            row.put(columnNames.get(i-1), rs.getObject(i));
        }
        batch.add(row);
        
        if (batch.size() >= BATCH_SIZE) {
            if (!firstRow) System.out.print(",");
            firstRow = false;
            outputJsonBatch(columnNames, batch, false); // false = don't close array
            batch.clear();
        }
    }
    
    // Output remaining rows
    if (!batch.isEmpty()) {
        if (!firstRow) System.out.print(",");
        outputJsonBatch(columnNames, batch, false);
    }
    
    System.out.println("]");
}
```

### Option 3: Cursor-Based Streaming

**Approach:** Use database-specific cursor features for true streaming.

**Benefits:**
- Most memory efficient
- Database-level optimization
- Can handle billions of rows

**Implementation:**

```java
// Configure connection for streaming
Properties props = new Properties();
props.setProperty("defaultRowFetchSize", "1000");
props.setProperty("useCursorFetch", "true"); // MySQL
Connection conn = DriverManager.getConnection(url, props);

// Or use server-side cursor
Statement stmt = conn.createStatement(
    ResultSet.TYPE_FORWARD_ONLY, 
    ResultSet.CONCUR_READ_ONLY
);
stmt.setFetchSize(1000); // Database-specific
```

## Format-Specific Streaming Challenges

### JSON Format
**Challenge:** Need to handle array structure properly
**Solution:** Track first row to manage commas, close array at end

### CSV Format  
**Challenge:** Simple - just output header then stream rows
**Solution:** Header first, then stream each row

### Pretty Format
**Challenge:** Need column widths for alignment
**Solution:** Two-pass approach:
1. First pass: calculate column widths (sample or full scan)
2. Second pass: stream formatted output

### Text Format
**Challenge:** Simple - tab-separated streaming
**Solution:** Stream each row immediately

## Implementation Plan

### Phase 1: Basic Streaming
1. Implement row-by-row streaming for text and CSV formats
2. Implement streaming for JSON format
3. Add configuration option for streaming mode

### Phase 2: Advanced Features
1. Implement pretty format streaming with two-pass approach
2. Add batch size configuration
3. Add progress reporting for large queries

### Phase 3: Database Optimization
1. Implement cursor-based streaming
2. Add database-specific optimizations
3. Add connection pooling for repeated queries

## Configuration Options

```bash
# Enable streaming mode
./query_runner --stream

# Set batch size (for batch streaming)
./query_runner --batch-size 5000

# Enable progress reporting
./query_runner --progress

# Auto-enable streaming for result sets > N rows
./query_runner --stream-threshold 10000
```

## Memory Usage Comparison

| Approach | Memory Usage | 1M Rows | 10M Rows | 100M Rows |
|----------|--------------|---------|----------|-----------|
| Current  | O(n)         | ~500MB  | ~5GB     | ~50GB     |
| Streaming| O(1)         | ~5MB    | ~5MB     | ~5MB      |
| Batch    | O(batch)     | ~50MB   | ~50MB    | ~50MB     |

## Backward Compatibility

- Default behavior remains unchanged (load all into memory)
- Streaming is opt-in via command line flag
- All existing tests continue to work
- Output format remains identical

## Testing Strategy

### Unit Tests
- Test streaming with various result sizes
- Test memory usage doesn't grow with row count
- Test output format consistency

### Integration Tests
- Test with different databases
- Test with large datasets (1M+ rows)
- Test error handling during streaming

### Performance Tests
- Benchmark memory usage
- Measure throughput (rows/second)
- Compare with current implementation

## Recommendation

**Start with Option 1 (Row-by-Row Streaming)** because:
- Simplest to implement
- Solves the core memory problem
- Works with all output formats
- Provides immediate benefits
- Can be enhanced later with batching if needed

This approach will transform the query runner from being limited to small datasets to being able to handle enterprise-scale data processing.