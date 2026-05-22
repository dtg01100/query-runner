#!/bin/bash
# Benchmark harness for result parsing and returning optimization
# Measures throughput for JSON, CSV, text, and pretty output formats

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Compile benchmark if needed
Benchmark_class="Benchmark"

if [[ ! -f "Benchmark.class" ]] || \
   [[ "Benchmark.java" -nt "Benchmark.class" ]] || \
   [[ "QueryRunner.java" -nt "Benchmark.class" ]] || \
   [[ "JsonUtil.java" -nt "Benchmark.class" ]]; then
    echo "Compiling benchmark..." >&2
    javac -O -d . Benchmark.java QueryRunner.java JsonUtil.java 2>/dev/null || \
    javac -d . Benchmark.java QueryRunner.java JsonUtil.java
fi

# Run benchmark with different row counts and formats
# Output format: METRIC name=value (nanoseconds per row)

exec java -Xmx256m -cp . Benchmark "$@"
