#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QUERY_RUNNER="$SCRIPT_DIR/../query_runner"
TEST_DB="$SCRIPT_DIR/test_daemon.db"
DAEMON_SOCKET="$HOME/.query_runner/daemon.sock"
DAEMON_PID_FILE="$HOME/.query_runner/daemon.pid"
DAEMON_CLASS_DIR="$HOME/.query_runner/daemon_class"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_pass() {
	echo -e "${GREEN}✓${NC} $1"
	TESTS_PASSED=$((TESTS_PASSED + 1))
}

log_fail() {
	echo -e "${RED}✗${NC} $1"
	TESTS_FAILED=$((TESTS_FAILED + 1))
}

log_perf() {
	echo -e "${YELLOW}⚡${NC} $1"
}

cleanup_daemon() {
	if [[ -S "$DAEMON_SOCKET" ]]; then
		echo '{"type":"shutdown"}' | timeout 2 socat - UNIX-CONNECT:"$DAEMON_SOCKET" - 2>/dev/null || true
	fi
	if [[ -f "$DAEMON_PID_FILE" ]]; then
		local pid
		pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
		if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
			kill "$pid" 2>/dev/null || true
			sleep 0.5
		fi
	fi
	rm -f "$DAEMON_SOCKET" "$DAEMON_PID_FILE" 2>/dev/null || true
	rm -rf "$DAEMON_CLASS_DIR" 2>/dev/null || true
}

setup() {
	cleanup_daemon
}

teardown() {
	cleanup_daemon
}

trap 'teardown' EXIT

setup

echo "=== Performance Tests ==="

echo "Running: perf_daemon_startup"
start=$(date +%s%3N)
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1
end=$(date +%s%3N)
duration=$((end - start))
log_perf "Daemon startup time: ${duration}ms"
if [[ $duration -lt 5000 ]]; then
	log_pass "perf_daemon_startup"
else
	log_fail "perf_daemon_startup - startup took ${duration}ms (>5000ms)"
fi
sleep 1

echo "Running: perf_first_query"
start=$(date +%s%3N)
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>/dev/null)
end=$(date +%s%3N)
duration=$((end - start))
log_perf "First query time: ${duration}ms"
if [[ $duration -lt 500 ]]; then
	log_pass "perf_first_query"
else
	log_fail "perf_first_query - first query took ${duration}ms (>500ms)"
fi

echo "Running: perf_subsequent_queries"
total_time=0
for i in {1..10}; do
	start=$(date +%s%3N)
	output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1 as val" 2>/dev/null)
	end=$(date +%s%3N)
	total_time=$((total_time + (end - start)))
done
avg_time=$((total_time / 10))
log_perf "Average subsequent query time: ${avg_time}ms"
if [[ $avg_time -lt 100 ]]; then
	log_pass "perf_subsequent_queries"
else
	log_fail "perf_subsequent_queries - avg query took ${avg_time}ms (>100ms)"
fi

echo "Running: perf_cold_vs_warm"
"$QUERY_RUNNER" --daemon-stop -t sqlite -d "$TEST_DB" >/dev/null 2>&1 || true
rm -rf "$DAEMON_CLASS_DIR" 2>/dev/null || true
rm -rf "$HOME/.query_runner/cache" 2>/dev/null || true
sleep 1

start=$(date +%s%3N)
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>/dev/null)
end=$(date +%s%3N)
cold_time=$((end - start))

"$QUERY_RUNNER" --daemon-stop -t sqlite -d "$TEST_DB" >/dev/null 2>&1 || true
sleep 1

start=$(date +%s%3N)
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1
sleep 1
start=$(date +%s%3N)
output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" 2>/dev/null)
end=$(date +%s%3N)
warm_time=$((end - start))

speedup=$(echo "scale=2; $cold_time / $warm_time" | bc 2>/dev/null || echo "0")
log_perf "Cold query: ${cold_time}ms, Warm query: ${warm_time}ms, Speedup: ${speedup}x"
if [[ $(echo "$speedup > 2" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
	log_pass "perf_cold_vs_warm"
else
	log_fail "perf_cold_vs_warm - insufficient speedup (${speedup}x, expected >2x)"
fi

echo "Running: perf_throughput"
"$QUERY_RUNNER" --daemon-stop -t sqlite -d "$TEST_DB" >/dev/null 2>&1 || true
"$QUERY_RUNNER" --daemon-start -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1 || true
sleep 1

start=$(date +%s%3N)
for i in {1..50}; do
	"$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1" >/dev/null 2>&1
done
end=$(date +%s%3N)
duration=$((end - start))
qps=$(echo "scale=2; 50 / ($duration / 1000)" | bc 2>/dev/null || echo "0")
log_perf "Throughput: ${qps} queries/second"
if [[ $(echo "$qps > 5" | bc -l 2>/dev/null || echo "0") -eq 1 ]]; then
	log_pass "perf_throughput"
else
	log_fail "perf_throughput - throughput ${qps} qps (<5 qps)"
fi

echo "Running: perf_memory_baseline"
pid=$(cat "$DAEMON_PID_FILE" 2>/dev/null || echo "")
if [[ -n "$pid" ]]; then
	mem=$(ps -o rss= -p "$pid" 2>/dev/null || echo "0")
	log_perf "Memory usage: ${mem}KB"
	if [[ $mem -lt 200000 ]]; then
		log_pass "perf_memory_baseline"
	else
		log_fail "perf_memory_baseline - memory ${mem}KB (>200MB)"
	fi
else
	log_fail "perf_memory_baseline - daemon not running"
fi

echo "Running: perf_query_latency_p50_p99"
latencies=()
for i in {1..100}; do
	start=$(date +%s%3N)
	output=$("$QUERY_RUNNER" -t sqlite -d "$TEST_DB" "SELECT 1 as val" 2>/dev/null)
	end=$(date +%s%3N)
	latencies+=($((end - start)))
done
IFS=$'\n' sorted=($(sort -n <<<"${latencies[*]}"))
unset IFS
p50=${sorted[50]}
p99=${sorted[99]}
log_perf "Latency p50: ${p50}ms, p99: ${p99}ms"
if [[ $p99 -lt 500 ]]; then
	log_pass "perf_query_latency_p50_p99"
else
	log_fail "perf_query_latency_p50_p99 - p99 latency ${p99}ms (>500ms)"
fi

echo ""
echo "=== Performance Test Results ==="
echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed: ${RED}$TESTS_FAILED${NC}"

if [[ $TESTS_FAILED -eq 0 ]]; then
	exit 0
else
	exit 1
fi
