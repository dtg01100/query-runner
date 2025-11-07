# Agent Guidelines for Query Runner

## Build/Test Commands
- Test script: `bash -n query_runner` (syntax check)
- Integration test: `./query_runner --test-connection`
- Manual test: `echo "SELECT 1" | ./query_runner -f json`
- Driver check: `./query_runner --list-drivers`

## Code Style Guidelines
- Bash: Use `set -euo pipefail`, quote variables, prefer `[[ ]]` over `[ ]`
- Java generation: Use try-with-resources, proper exception handling, secure JSON escaping
- Functions: Use lowercase with underscores, local variables with `local`
- Security: Validate all inputs, use parameterized queries, never log passwords
- Error handling: Check return codes, provide meaningful error messages
- Temp files: Use `mktemp`, cleanup with `trap`, avoid shell injection
- Output: Support text/csv/json/pretty formats, handle null values consistently
