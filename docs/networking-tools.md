# Networking tools — install and use

Three macOS CLIs that handle network contexts, corporate proxy auth, Kerberos
tickets and OAuth2 mail tokens, plus the launchd agents that keep them running
in the background.

**This page is self-contained.** It assumes nothing from the rest of this
repository — no Ansible, no overlays, no clone required. Everything here is a
`brew install` and a handful of files under your own home directory. If you do
run the Ansible play, it performs these same steps for you and you can skip to
[Verifying](#verifying).

| Tool | What it does |
| --- | --- |
| **macswitcher** | Switches between named network contexts (home / office / VPN): macOS network location, DNS resolvers, system proxy settings, and a local [Alpaca](https://github.com/samuong/alpaca) proxy that handles PAC files and corporate proxy authentication. |
| **kerberoskeepalive** | Keeps Kerberos tickets alive by re-acquiring them from a password stored in your login Keychain, before they expire. |
| **omt** | Obtains and refreshes OAuth2 access tokens for IMAP/POP/SMTP, so a mail client that only speaks "password" can authenticate against Microsoft 365 or Gmail. |

They are independent. Install only what you need.

---

## Prerequisites

- macOS on Apple Silicon or Intel, with [Homebrew](https://brew.sh).
- The tools are macOS-only: they use launchd, the Keychain and `networksetup`.

```sh
brew tap schretzi/tap
```

---

## macswitcher

### Install

```sh
brew install schretzi/tap/macswitcher
brew install alpaca          # required: macswitcher runs it as the local proxy
```

`alpaca` must be on your `PATH` **before** you install the launch agent —
macswitcher records its absolute path in the plist, because launchd starts jobs
with a minimal `PATH` and would not find it otherwise.

### Configure

```sh
macswitcher config init          # writes ~/.config/macswitcher/config.yaml
$EDITOR ~/.config/macswitcher/config.yaml
macswitcher config validate
```

A context is one named network situation. At minimum give each one a
`mac_network_location`, DNS resolvers, and a `proxy_mode` of `off`, `direct`
or `forward`. `forward` additionally needs a `forwarder_proxy` block naming
your upstream proxy and where its credentials live in the Keychain.

`config validate` exits non-zero and explains what is wrong. Run it until it
passes — the launch agent refuses to install against an invalid config, which
is deliberate: a job that cannot start just becomes a background crash-loop.

### Run it in the background

```sh
macswitcher service install
```

That writes `~/Library/LaunchAgents/com.schretzi.macswitcher.plist` and loads
it. From then on the local proxy starts at login.

### Daily use

```sh
macswitcher switch office        # apply a context
macswitcher status               # what is active right now
macswitcher observe              # TUI: this agent plus the resolver, kerberos, omt, vpn
```

---

## kerberoskeepalive

### Install

```sh
brew install schretzi/tap/kerberoskeepalive
```

### Configure

The tool reads your password from an **existing** Keychain item. It never
creates or modifies Keychain entries, so make one yourself first:

```sh
security add-generic-password -a "$USER" -s KerberosKeepAlive-corp -w
```

Then write the config:

```sh
mkdir -p ~/.config/kerberoskeepalive
$EDITOR ~/.config/kerberoskeepalive/config.yaml
```

Each profile needs a Kerberos principal, the Keychain `service` + `account`
you just used, and a ccache destination. A minimal one:

```yaml
profiles:
  - name: corp
    principal: you@CORP.EXAMPLE.COM
    keychain:
      service: KerberosKeepAlive-corp
      account: you
    ccache: API
    ticket_lifetime: 3h
    refresh_threshold: 30m
```

`ccache: API` stores the ticket in Apple's in-memory GSSCred cache rather than
a file on disk. Prefer it: a file ccache is a bearer credential at rest that
survives logout and lands in backups.

### First run, then background

```sh
kerberoskeepalive init           # run this interactively FIRST
kerberoskeepalive service install
```

`init` acquires the first ticket while you are at the keyboard, so you can
answer the macOS Keychain access prompt. The daemon runs unattended and cannot
answer it — install the agent before granting access and it will simply fail
in the background.

```sh
kerberoskeepalive status         # ticket state and expiry
```

---

## omt

### Install

```sh
brew install schretzi/tap/omt
```

### Configure

omt has no `config init`. Copy the annotated example from the
[OauthMailToken repository](https://github.com/schretzi/OauthMailToken) to
`~/.config/omt/config.yaml` and edit it. It searches `$XDG_CONFIG_HOME`
(default `~/.config`) for `omt/config.yaml`.

The file has two sections: `providers` (OAuth2 endpoints and client
credentials for Microsoft/Google) and `accounts` (your mail addresses, each
naming a provider). Tokens are kept in the OS keyring, not in the config.

### Authorize, then background

```sh
omt authorize you@example.com    # interactive, opens a browser
omt status                       # confirm it worked
omt service install
```

The daemon refreshes tokens before they expire. It exists because an external
timer does not fire while the machine is asleep and does not catch up missed
ticks — the daemon checks expiry itself on every tick instead.

### Use from a mail client

```sh
omt you@example.com              # prints only the token, nothing else
```

That is what you put in mutt's `imap_pass_cmd` or equivalent. stdout carries
the token and nothing else, so it is safe to use directly as a password
command.

---

## Log rotation

**This is a manual step, and skipping it means logs grow without bound.**

Each tool writes `~/Library/Logs/<name>.log`. Rotation is macOS's built-in
`newsyslog`, which reads every file in `/etc/newsyslog.d/` once an hour. Copy
the configs from this repository:

```sh
sudo install -o root -g wheel -m 0644 \
  etc/newsyslog.d/macswitcher.conf \
  etc/newsyslog.d/kerberoskeepalive.conf \
  etc/newsyslog.d/omt.conf \
  /etc/newsyslog.d/
```

Not cloning this repo? Each file is two lines. Replace `me` with your username:

```
# /etc/newsyslog.d/macswitcher.conf
# logfilename                          owner:group    mode count size(KB) when flags
/Users/me/Library/Logs/macswitcher.log     me:staff   600  5    5120     *    NJ
/Users/me/Library/Logs/macswitcher.err.log me:staff   600  5    5120     *    NJ
```

Three details that are easy to get wrong:

- `size` is in **kilobytes**, not bytes and not MB.
- The `N` flag means "no process to signal". **Without it, newsyslog sends
  `SIGHUP` to `syslogd` after every rotation.** Most hand-written configs
  miss this.
- `owner:group` is required for files you own, because newsyslog runs as root
  and would otherwise recreate the log as `root:admin` — which the tool can
  then no longer write to.

Test a config without waiting an hour:

```sh
sudo newsyslog -nvv -f /etc/newsyslog.d/macswitcher.conf   # dry run
sudo newsyslog -F   -f /etc/newsyslog.d/macswitcher.conf   # force one now
```

### Why the tool version matters

`newsyslog` rotates by **renaming**, and launchd does **not** reopen a job's
log file when that happens. A long-running daemon that simply inherits the fd
keeps writing into the renamed — then compressed — archive, while the new log
file stays empty forever. Logging stops silently; nothing errors.

All three tools handle this from **v0.2.0** onward: they open their own log and
re-check, at most once a second, whether the file at that path is still the one
they hold. Older builds do not. If you are pinned to 0.1.x, do not add a
newsyslog config for them.

---

## Verifying

```sh
# every agent should be listed, and none should be crash-looping
launchctl list | grep com.schretzi

# per tool
macswitcher service status
kerberoskeepalive service status
omt service status

# logs exist and are being written
ls -la ~/Library/Logs/{macswitcher,kerberoskeepalive,omt}.log
```

`service status` prints the label, whether the plist is installed, whether
launchd has it loaded, whether it is running, and both log paths. All three
tools print the same shape, so the output is greppable across them.

A `-` in the PID column of `launchctl list` is normal for a job that runs
periodically and exits between runs. A non-zero status column next to a live
PID means it exited at least once and was restarted — check `<tool> service
status` and the `.err.log`.

---

## Conventions

Every background job on this machine follows the same rules, so you always
know where to look:

| | |
| --- | --- |
| launchd label | `com.schretzi.<name>` |
| plist | `~/Library/LaunchAgents/com.schretzi.<name>.plist` |
| config | `~/.config/<name>/config.yaml` |
| log | `~/Library/Logs/<name>.log` |
| launchd stderr | `~/Library/Logs/<name>.err.log` (panics only; normally empty) |
| control | `<tool> service install\|uninstall\|start\|stop\|restart\|status` |

`service` always means *that tool's own launchd job*. The foreground process
the job runs is a separate command (`daemon`, `proxy run`) — the two are never
the same word.

Full reasoning in [CONVENTIONS.md](../CONVENTIONS.md).

---

## Troubleshooting

**`error: accepts 1 arg(s), received 2` from `omt service install`**
An old omt without the `service` command. `brew upgrade --cask omt` and check
`omt version` reports 0.2.0 or later.

**`service install` succeeded but the label is wrong**
You are on an old macswitcher. 0.1.x had a `service` command that installed
`com.macswitcher.proxy`. It reports success while leaving you unmigrated.
Confirm with `macswitcher service status` — the label must read
`com.schretzi.macswitcher`.

**`alpaca executable not found in PATH`**
`brew install alpaca`, then re-run `macswitcher service install`. The path is
baked into the plist at install time.

**`Bootstrap failed: 5: Input/output error`**
`launchctl bootout` is asynchronous — it returns once the unload has been
*requested*, not once launchd has finished. Wait a second and retry, or just
use `<tool> service restart`, which handles the wait.

**The log stopped and never resumed**
Rotation caught you out — see [Why the tool version
matters](#why-the-tool-version-matters). The signature is a live log whose
mtime is frozen at exactly the moment the archive was created:

```sh
ls -li ~/Library/Logs/macswitcher.log*
```

**The job is not running after a `brew upgrade`**
Older plists could point at a version-pinned Caskroom path that the upgrade
deleted. Re-run `<tool> service install` — current versions record the stable
`/opt/homebrew/bin/<name>` path instead.

---

## Uninstall

```sh
<tool> service uninstall                 # unload the agent, remove its plist
brew uninstall --cask <tool>
sudo rm /etc/newsyslog.d/<tool>.conf
```

`service uninstall` leaves your logs and config alone. `brew uninstall --zap`
removes the config too.

---

## Not covered here

- **DNS**, network locations and the pf NAT rules — machine-specific,
  see [Setup.md](../Setup.md).
- **The script-based launch agents** (mail sync, VPN). Those have no CLI to
  install them; their plists live in `plists/` in this repository and are
  copied into place by the Ansible play.
- **Employer-specific configuration**, which lives in a private overlay
  repository and is not distributable.
