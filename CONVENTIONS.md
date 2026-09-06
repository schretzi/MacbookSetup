
# Daemon, log and CLI conventions

Every background job I run on this machine — whether it comes from one of my
Go CLIs (KerberosKeepAlive, OauthMailToken, macswitcher, tunneling) or from a
plist in this repo — follows the rules below. The point is not that these are the only
sensible names, it is that there is exactly **one** name for each thing.

**This file is the machine-specific instance.** The general, reusable version —
with the reasoning, the failure modes and working code for the reopening log
writer and the `service` command tree — lives in the
[`macos-launchd-services`](../schretzi-skills/skills/macos-launchd-services)
skill. Change the skill first; this file records only what is specific to _this_
machine (my owner prefix, my job list, my paths).

The migration onto these conventions is complete: every job below already
carries its final name. Setting up a machine now needs only
`ansible-playbook site.yml --ask-become-pass`.

Third-party jobs are out of scope: `com.google.*`, `homebrew.mxcl.*`,
`org.pqrs.karabiner-daemon`, `com.koekeishiya.skhd`, `com.asmvik.yabai` and
`com.kanata.daemon` keep whatever their upstream chose.

## 1. Naming

`<name>` is the binary name for a Go CLI, or a short kebab-case job name for a
script (`offlineimap-sync`, `vmnet-nat-refresh`).

| thing              | convention                                         |
| ------------------ | -------------------------------------------------- |
| launchd label      | `com.schretzi.<name>`                              |
| LaunchAgent plist  | `~/Library/LaunchAgents/com.schretzi.<name>.plist` |
| LaunchDaemon plist | `/Library/LaunchDaemons/com.schretzi.<name>.plist` |
| config file        | `~/.config/<name>/config.yaml`                     |
| env var prefix     | `<NAME>_` (upper-cased, `-` → `_`)                 |

No `org.` prefix, no per-user labels (`com.$USER.…` changes between machines),
no bare `com.<appname>.…` without an owner.

## 2. Logs

Flat in `~/Library/Logs` for LaunchAgents, `/Library/Logs` for LaunchDaemons.
No per-project subdirectories.

| file             | written by | contains                                      |
| ---------------- | ---------- | --------------------------------------------- |
| `<name>.log`     | the job    | everything the job intends to log             |
| `<name>.err.log` | launchd    | panics, and anything before logging is set up |

For a **Go daemon**, `<name>.log` is opened by the process itself through
`internal/logfile`, and the plist sets only `StandardErrorPath`. Go panics go
to stderr, so `<name>.err.log` catches them; stdout goes to `/dev/null`.

For a **script**, the plist sets `StandardOutPath` → `<name>.log` and
`StandardErrorPath` → `<name>.err.log`.

## 2a. State

Machine-written state that a tool republishes — not config, not logs — goes in
`~/.local/state/<name>/`, matching the XDG-style `~/.config/<name>/` in §1.

|          |                                                |
| -------- | ---------------------------------------------- |
| path     | `~/.local/state/<name>/<thing>.json`           |
| mode     | `0600`, `0700` on the directory                |
| lifetime | safe to delete; the owning process rewrites it |

It is deliberately none of the other three places: `~/Library/Logs` is for
append-only history, `~/.config` is for files a human edits, and
`~/Library/Application Support` is for data whose loss is a problem. State is
a cache of what a running process knows.

Two rules that matter for anything reading it:

- **Write atomically** — temp file in the same directory, then `rename`. A
  reader must never see a half-written file.
- **Stamp the PID**, and have readers check it is still alive. A file left
  behind by a dead daemon describes the past; treating it as current is how a
  stopped service keeps reporting healthy. `tunneling status` does exactly
  this: the state file says what the daemon observed, a live port probe says
  whether anything is listening, and the two together are what it reports.

## 3. Rotation

`newsyslog` rotates everything. One committed conf per job in
`etc/newsyslog.d/<name>.conf`, installed by the `newsyslog` Ansible role.
Nothing rotates itself — no lumberjack, no `logrotate`, no manual truncation.

```
# logfilename          [owner:group]  mode count size(KB) when flags
/Users/me/Library/Logs/foo.log  me:staff  640  5    5120     *    NJ
```

`N` because there is no process to signal — **without it newsyslog sends
SIGHUP to syslogd on every rotation**. `J` compresses the archive with bzip2.

### The rename problem

`newsyslog` rotates by **renaming**. It has no copy-truncate mode. launchd does
_not_ reopen `StandardOutPath`/`StandardErrorPath` when that happens: the job
keeps its original fd and goes on writing into the renamed — then compressed —
inode, while the new log file stays empty forever.

This is measured behaviour, not theory. It is what silently killed kanata's
logging: after its first rotation, `kanata.out.log` never grew again.

Two consequences:

- **Short-lived jobs are safe.** `StartInterval`/`WatchPaths` jobs that exit
  between runs get a fresh fd on every launch, so a rename between runs is
  invisible to them.
- **Long-running jobs must reopen.** Any job that stays resident and holds its
  fd needs to notice the rename. Go daemons do this in `internal/logfile`,
  which re-stats the path (at most once a second) and reopens when the inode
  it holds is no longer the one at that path.

The one accepted exception is the work overlay's VPN agent: it ends in
`exec sudo openconnect`, so the fd belongs to a third-party binary that cannot
be taught to reopen. Its logs are a few KB after weeks and the job restarts on
every network flap, so size-based rotation realistically never fires.
Documented, not fixed.

## 4. CLI surface

Every Go CLI that installs a background job exposes the same tree:

```
<binary> service install      # write the plist and load it
<binary> service uninstall    # unload it and remove the plist
<binary> service start
<binary> service stop
<binary> service restart
<binary> service status
```

`service` always means _this tool's own launchd job_. The foreground process
that the job runs is a separate, non-`service` command (`daemon`, `proxy run`).
Never use "daemon" for both.

Other shared commands:

| command                    | meaning                                          |
| -------------------------- | ------------------------------------------------ |
| `<binary> version`         | version, commit, build date, Go version, licence |
| `<binary> status`          | what the tool manages right now                  |
| `<binary> config init`     | write a starter `~/.config/<name>/config.yaml`   |
| `<binary> config validate` | check the config and exit non-zero if bad        |

`config init` writes the _embedded_ starter config, not a file read from disk
at runtime — the example a reader sees in the repo and the file the command
writes have to be the same bytes, or the documented example quietly stops
parsing. tunneling does this via `internal/config/config.example.yaml` plus a
`//go:embed`; goreleaser flattens it into the archive with `src`/`dst`.

## 5. Plist shape

Long-running jobs:

```xml
<key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Background</string>
<key>ThrottleInterval</key><integer>10</integer>
```

`KeepAlive: true` restarts a job even after it exits cleanly, which makes a
deliberate `stop` impossible without `bootout`. Use the `SuccessfulExit: false`
form unless the job genuinely must never exit.

The binary path must **not** be version-pinned. `/opt/homebrew/bin/<name>`,
never `/opt/homebrew/Caskroom/<name>/0.1.0/<name>` — the latter breaks on the
next `brew upgrade`.

## 6. Repo baseline

Every Go CLI repo carries: `.golangci.yml`, `lefthook.yml` (gitleaks
pre-commit + `make pipeline` pre-push), `.github/workflows/{ci,release}.yml`,
`.github/dependabot.yml`, a `Makefile` exposing
`fmt lint security test build docs pipeline hooks clean`, and `tools/gendocs`
regenerating `docs/` from the cobra tree.
