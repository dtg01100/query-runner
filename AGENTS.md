# Agent Guidelines for Query Runner

## Build/Test Commands

### Canonical: drive everything through `make` (or `./run_all_tests.sh` directly)

| Command | What it runs |
|---|---|
| `make test` | daemon-mode tests (the daily-driver path; same as `make test-daemon`) |
| `make test-all` | full integration suite (core + security + formats + daemon) |
| `make test-core` | cache / error / path / query normalization |
| `make test-security` | input validation + db security + union safety |
| `make test-formats` | CLI / env-files / output formats |
| `make test-daemon` | daemon suite alone (8 sub-suites) |
| `make test-coverage` | just the coverage-gap daemon sub-suite |
| `make lint` | shellcheck on `query_runner` + `run_all_tests.sh` |
| `make preflight` | kill any running daemon + clear `~/.query_runner/` |

All test commands run `make preflight` first to clear stale daemon
state. If a test is failing, run `make preflight` between attempts.

Each daemon sub-suite is also runnable on its own (useful when
debugging a single failure): `bash test_daemon/test_daemon_lifecycle.sh`
et al. The `test_daemon/.test_setup.sh` helper bootstraps a fresh
sqlite fixture (test_daemon.db) if missing so standalone runs work.

The integration suite aggregates everything via `run_all_tests.sh
integration`. See TESTING.md for the canonical doc on what each
suite covers and the per-test inventory.

### Lint

- `make lint` (uses shellcheck on the two scripts the suite points at)
- Direct: `shellcheck query_runner run_all_tests.sh`

### One-off checks (when iterating on a single script)

- `bash -n test_daemon/test_daemon_*.sh` — syntax-check a sub-suite
- `./query_runner --test-connection` — confirms JDBC handshake
- `./query_runner -q "SELECT 1"` — minimal smoke against AS/400
- Manual test: `echo "SELECT 1" | ./query_runner -f json`

## Code Style Guidelines

- Bash: Use `set -euo pipefail`, quote variables, prefer `[[ ]]` over `[ ]`
- Java generation: Use try-with-resources, proper exception handling, secure JSON escaping
- Functions: Use lowercase with underscores, local variables with `local`
- Security: Validate all inputs, use parameterized queries, never log passwords
- Error handling: Check return codes, provide meaningful error messages
- Temp files: Use `mktemp`, cleanup with `trap`, avoid shell injection
- Output: Support text/csv/json/pretty formats, handle null values consistently
- Performance: Use caching for Java compilation, optimize classpath building, lazy load drivers
- UNION Security: Implement smart detection, allow safe patterns, block risky cross-table operations
