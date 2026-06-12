# systemd integration for query_runner

Single-user, single-machine. No remote access, no socket activation — the
JVM is supervised by systemd as a long-running service, and the JVM's
own idle self-shutdown handles lazy unload within a session.

## Install (user mode)

```sh
mkdir -p ~/.config/systemd/user
cp packaging/systemd/query_runner.service ~/.config/systemd/user/

# Optional: copy your .env to a user-owned env file
# (the unit loads ~/.config/query_runner/env)
mkdir -p ~/.config/query_runner
cp .env ~/.config/query_runner/env
chmod 600 ~/.config/query_runner/env

systemctl --user daemon-reload
systemctl --user enable --now query_runner.service
```

## Verify

```sh
systemctl --user status query_runner
journalctl --user -u query_runner -f
query_runner -t sqlite -d ~/path/to/test.db -q "SELECT 1"
```

## How it works

- `query_runner.service` runs `query_runner --daemon-systemd` in foreground.
  systemd sees the JVM as the supervised process.
- journald captures the daemon's stdout/stderr.
- The JVM's `IDLE_TIMEOUT_MS` (default 120s, override via
  `QUERY_RUNNER_DAEMON_IDLE_SECS` in the env file) self-shuts the daemon
  after N seconds of inactivity.
- On session logout, systemd stops the service; the JVM exits on SIGTERM
  within `TimeoutStopSec=15`.

## Why no `.socket` unit?

Socket activation (systemd listening on the socket, spawning the daemon
on first connect) requires the JVM to inherit a file descriptor from
systemd. Java's `System.inheritedChannel()` doesn't honor systemd's
`LISTEN_FDS` mechanism for Unix-domain sockets on current JDKs. Working
around it requires either JNI/JNA (fragile across JDK versions) or
`Accept=yes` (defeats the lazy-pool intent by spawning a fresh daemon
per connection).

For a single-user desktop tool, the .service approach is simpler and
covers the actual use case (start on login, stop on logout, idle-shut
within a session) without the FD-3 problem.

## Tuning the idle timeout

```sh
# In ~/.config/query_runner/env
QUERY_RUNNER_DAEMON_IDLE_SECS=300   # 5 min idle before self-shutdown
QUERY_RUNNER_DAEMON_IDLE_SECS=0     # never auto-shutdown (daemon stays warm)
```

Then `systemctl --user restart query_runner.service`.
