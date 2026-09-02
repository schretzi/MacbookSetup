# Networking tools — install and use

Three macOS CLIs that handle network contexts, corporate proxy auth, Kerberos
tickets and OAuth2 mail tokens, plus the filtering proxy one of them chains
into, and the launchd agents that keep them all running in the background.

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
| **privoxy** | A filtering HTTP proxy. Not one of mine — third-party, from a tap formula. macswitcher points Alpaca at it in contexts that reach the internet directly, so URLs are filtered on networks where no corporate proxy does it. |

They are independent. Install only what you need — except privoxy, which is
only useful with macswitcher in front of it.

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

### Contexts on this machine

Seven named contexts cover every network situation this machine actually sees.
`no-filter`, `full-direct`, `remote-vpn` and `home-alone` live in
`~/.config/macswitcher/contexts/` (the personal/private overlay);
`home-vpn`, `office` and `vpn-debug` are symlinked from the `MacbookSetup-Work`
overlay, because they carry the corporate `forwarder_proxy` block or the
corporate upstream resolvers.

| Context | DNS | proxy_mode | privoxy | alpaca | adguard | VPN | kka |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `no-filter` | public (bypass adguard) | direct | stopped (fail-open) | ✅ | running, unused | stopped | — |
| `full-direct` | DHCP | off | stopped | ❌ | unused | stopped | — |
| `remote-vpn` | OEBB → adguard fallback | direct | started | ✅ | opportunistic | started (**needs field-testing**) | — |
| `home-alone` | adguard | direct | started | ✅ | ✅ | stopped | — |
| `home-vpn` | adguard | forward → corp | stopped | ✅ | ✅ | started | started |
| `office` | adguard | forward → corp | stopped | ✅ | ✅ | stopped | started |
| `vpn-debug` | adguard → corp upstreams | off | stopped | ❌ | ✅ | started | started |

`no-filter` and `full-direct` are diagnostic/fallback contexts — the former
bypasses AdGuard Home's DNS filtering and lets privoxy fail open while
leaving both daemons running as a pass-thru; the latter turns everything off
(including the system proxy itself) for the case where the network is
misbehaving and the only goal is *some* connectivity.

`remote-vpn` targets OEBB train WiFi, whose captive portal only completes
against its own DNS servers — resolvers list OEBB's servers first and
AdGuard Home as a last-resort fallback. The VPN start in this context is
unverified: a captive portal intercepts the VPN handshake too, and once the
tunnel is up its routing may fight the OEBB-first resolver order. Confirm on
an actual train before trusting the automatic VPN start.

`home-vpn` and `office` both forward through the corporate proxy (Alpaca
never talks to privoxy in `forward` mode, and privoxy is stopped outright to
match), and both need `kerberoskeepalive` for Kerberos tickets. The only
difference is the VPN: `office` assumes the corporate network is already
reachable directly; `home-vpn` brings the tunnel up first.

`vpn-debug` is `home-vpn` with both proxies taken out of the path — the
tunnel, AdGuard Home and Kerberos, nothing else. It exists because those
three contexts stack the tunnel, Alpaca and the corporate PAC on top of each
other, so a failure could belong to any of them and the error usually names
the last one rather than the one at fault. Anything that still fails in
`vpn-debug` fails without a proxy involved; anything that works here but not
in `home-vpn` is the proxy layer. Not a daily driver: no ad filtering and no
HTTPS inspection. Pair it with `Scripts/MacOS/net_probe.sh`, which separates
a name that does not resolve from a port that does not answer:

```sh
net_probe.sh www-proxy.corp.example 8080
net_probe.sh --realm CORP.EXAMPLE.COM   # KDC discovery + reachability
```

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

## privoxy

A filtering HTTP proxy between Alpaca and the internet:

```
browser / CLI  ->  alpaca 127.0.0.1:3128  ->  privoxy 127.0.0.1:8118  ->  internet
```

Only in contexts whose `proxy_mode` is `direct`. In a `forward` context Alpaca
talks to the corporate proxy, which filters already, and privoxy stays out of
the path.

### Install — from the tap, not from homebrew-core

```sh
brew install schretzi/tap/privoxy
```

**`brew install privoxy` from homebrew-core is not equivalent.** That formula
configures without `--with-openssl`, so `FEATURE_HTTPS_INSPECTION` is compiled
out — `otool -L` on the bottle links no TLS library at all. privoxy then
answers every `ca-*` directive with

```
Error: Ignoring unrecognized directive 'ca-directory ...'
```

and runs happily, filtering nothing but plain HTTP. A proxy that silently does
not inspect looks exactly like one that does, which is the whole reason the tap
formula exists.

### The CA it signs with

Without HTTPS inspection privoxy sees only `CONNECT host:443` and can block
whole hosts — which a DNS-level blocker already does. Filtering by URL *path*
on HTTPS means privoxy terminates TLS with a certificate it mints per site,
from a CA the machine trusts.

```sh
mkdir -p ~/.config/privoxy/ca && chmod 700 ~/.config/privoxy/ca
cd ~/.config/privoxy/ca
openssl req -x509 -newkey rsa:4096 -nodes \
    -keyout cakey.pem -out cacert.crt -days 3650 \
    -subj "/CN=Privoxy HTTPS Inspection CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
chmod 600 cakey.pem

sudo security add-trusted-cert -d -r trustRoot \
    -k /Library/Keychains/System.keychain cacert.crt
```

The key is unencrypted because privoxy reads it unattended at every start; an
encrypted one would need `ca-password` in the config, i.e. the passphrase next
to the key. Keep the directory `0700` — that key can impersonate any site to
this machine.

Firefox-based browsers ignore the keychain unless the `ImportEnterpriseRoots`
policy is set; Safari, Chrome and macOS `curl` (SecureTransport) follow it
directly.

### Configure

`~/.config/privoxy/config`:

```
listen-address  127.0.0.1:8118
confdir         /opt/homebrew/etc/privoxy

debug           1024        # blocks
debug           4096        # startup
debug           8192        # errors

actionsfile     match-all.action
actionsfile     default.action
actionsfile     /Users/me/.config/privoxy/user.action
filterfile      default.filter

permit-access   127.0.0.1
permit-access   ::1

ca-directory           /Users/me/.config/privoxy/ca
ca-cert-file           cacert.crt
ca-key-file            cakey.pem
certificate-directory  /Users/me/.local/state/privoxy/certs
trusted-cas-file       /opt/homebrew/etc/ca-certificates/cert.pem
```

Three of those are easy to get wrong:

- **`debug 1` is deliberately absent.** It logs the destination of every
  request, which turns the log into a browsing history on disk. `1024` logs
  what was blocked, which is what a filtering proxy is actually asked to
  account for.
- **`trusted-cas-file` is not optional.** privoxy becomes the TLS *client*
  once inspecting and never consults the macOS keychain. With no bundle at
  all, `SSL_CTX_load_verify_locations(NULL, NULL)` fails and every HTTPS
  connection dies. Hosts signed by a private CA need that CA appended to the
  bundle, or they stop verifying.
- **`certificate-directory` fills up and privoxy never cleans it.** One
  certificate per inspected site, forever. It is safe to delete; each site
  costs one regeneration.

Then `~/.config/privoxy/user.action`:

```
{+https-inspection}
/

{-https-inspection}
.apple.com
.icloud.com
.microsoft.com
.cloud.microsoft
.microsoftonline.com
.dropbox.com
.signal.org
.tailscale.com
```

Everything that pins its certificates belongs in the second list: a pinned
client compares against the key it shipped with, sees privoxy's, and fails —
usually with a misleading error. Endpoint security agents belong there too,
and not because of breakage: decrypting the tool that watches the machine is
wrong regardless of whether it would work.

The list is never finished. `.microsoft.com` does **not** match
`login.microsoftonline.com`, which is the kind of gap you only find by
watching `~/Library/Logs/privoxy.log` for `unknown ca` handshake failures.

### Run it in the background

privoxy has no `service` subcommand — it is not one of mine — so the launch
agent is written by hand. `~/Library/LaunchAgents/com.schretzi.privoxy.plist`:

```xml
<key>Label</key>
<string>com.schretzi.privoxy</string>
<key>ProgramArguments</key>
<array>
    <string>/opt/homebrew/sbin/privoxy</string>
    <string>--no-daemon</string>
    <string>--pidfile</string>
    <string>/Users/me/.local/state/privoxy/privoxy.pid</string>
    <string>/Users/me/.config/privoxy/config</string>
</array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>/dev/null</string>
<key>StandardErrorPath</key><string>/Users/me/Library/Logs/privoxy.log</string>
```

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.schretzi.privoxy.plist
```

`StandardErrorPath` is the *main* log, not an error log, and there is no
`privoxy.err.log`. privoxy writes everything to stderr, and its own `logfile`
directive is honoured only when it daemonises — which it cannot do under
launchd. Splitting the paths would leave an empty `privoxy.log` next to an
`err.log` holding everything.

### Wire Alpaca into it

macswitcher's `config.yaml`:

```yaml
filter_proxy:
  enabled: true
  host: 127.0.0.1
  port: 8118
  fail_open: true
  direct: [.kiac, .ts.net]
```

Alpaca has no "always use this upstream" flag — a PAC file is its only way to
name one — so macswitcher generates one into
`~/.local/state/macswitcher/filter.pac` and starts Alpaca with `-C file://…`.
Do not hand-write a PAC and name it through a context's `alpaca.command`:
`macswitcher config validate` warns about exactly that, because the
local-network exceptions then exist in two places and drift apart.

`fail_open: true` adds a `DIRECT` fallback, so a filter that is down costs
filtering rather than connectivity. That is silent by nature, which is why:

```sh
macswitcher status | grep filter_proxy
# filter_proxy: 127.0.0.1:8118, in path, listening
# filter_proxy: 127.0.0.1:8118 NOT LISTENING - traffic is going out unfiltered (fail_open)
```

The shell mirrors it too: `PROXY_STATE` in `~/.zsh/rcs/proxy` reads `filtered`
rather than `on` while privoxy is in the path.

### Daily use

```sh
curl -x 127.0.0.1:8118 -o /dev/null -w '%{http_code}\n' http://example.com/
tail -f ~/Library/Logs/privoxy.log         # "Crunch: Blocked:" is a block
open http://config.privoxy.org/show-status # through the proxy: compiled-in features, loaded action files
```

`FEATURE_HTTPS_INSPECTION  Yes` on that page is the direct answer to "did I
install the right build".

**A per-application firewall needs one rule, and loses something for it.**
privoxy runs under launchd and connects as itself, so a single allow rule
covers it — but that rule then replaces the per-app decision for everything
proxied, because outbound traffic no longer carries the identity of the app
that caused it. Until privoxy is allowed out, requests sit for 30 s and fail
with `No server or forwarder response received`, which reads like a network
fault rather than a firewall decision. That timeout is hardcoded and not
configurable.

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
  etc/newsyslog.d/privoxy.conf \
  /etc/newsyslog.d/
```

Not cloning this repo? Each file is two lines. Replace `me` with your username:

```
# /etc/newsyslog.d/macswitcher.conf
# logfilename                          owner:group    mode count size(KB) when flags
/Users/me/Library/Logs/macswitcher.log     me:staff   600  5    5120     *    NJ
/Users/me/Library/Logs/macswitcher.err.log me:staff   600  5    5120     *    NJ
```

privoxy's conf is the odd one out, because it is a third-party binary that
cannot reopen its log — so rotation has to restart it instead. The two fields
after the flags are a pidfile and a signal:

```
/Users/me/Library/Logs/privoxy.log  me:staff  600  5  5120  *  J  /Users/me/.local/state/privoxy/privoxy.pid  15
```

Signal 15 with `KeepAlive` in the plist means newsyslog renames the log, stops
privoxy, and launchd brings it back within a second against the new file. And
**no `N` flag here** — `N` means "no process to signal", which is exactly what
this one does.

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

# privoxy has no service subcommand - ask launchd and the port directly
launchctl print gui/$(id -u)/com.schretzi.privoxy | grep -E 'state|last exit'
curl -sx 127.0.0.1:8118 -o /dev/null -w '%{http_code}\n' http://example.com/
macswitcher status | grep filter_proxy

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

privoxy keeps the label and the plist path and departs from the rest, because
it is somebody else's binary:

| | |
| --- | --- |
| config | `~/.config/privoxy/config` — privoxy's own format, not YAML |
| log | `~/Library/Logs/privoxy.log`, written by launchd from **stderr** |
| launchd stderr | none — there is no `privoxy.err.log`; see the plist note above |
| control | `launchctl` directly; there is no `privoxy service …` |

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

**Every request through privoxy takes 30 s and then fails**
`No server or forwarder response received` in `~/Library/Logs/privoxy.log`
means privoxy could not reach the internet, not that the site is down. On a
machine with a per-application firewall, privoxy is a new binary connecting on
behalf of everything else and needs to be allowed once. The 30 s is privoxy's
hardcoded connect timeout — there is no config knob for it.

**HTTPS fails only for one application**
It pins its certificates. Add its domain to the `{-https-inspection}` list in
`user.action` and reload with `pkill -HUP privoxy`. The log line to look for
is a TLS handshake error mentioning `unknown ca`. Note that domain suffixes
are literal: `.microsoft.com` does not cover `login.microsoftonline.com`.

**`macswitcher status` says the filter is not listening**
Then traffic is going out unfiltered (with `fail_open: true`) or failing
(without). Check the agent first: `launchctl print gui/$(id -u)/com.schretzi.privoxy`.

Note that a missing CA does **not** show up here: privoxy starts, listens, and
proxies plain HTTP quite happily, and only HTTPS fails — with
`Error opening certificate file … No such file or directory` followed by
`generate_host_certificate() failed` in its log. The port answers throughout,
so `status` reports it as listening.

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

privoxy again by hand, and with one step the others do not have — the CA it
signs with is trusted machine-wide until you say otherwise:

```sh
launchctl bootout gui/$(id -u)/com.schretzi.privoxy
rm ~/Library/LaunchAgents/com.schretzi.privoxy.plist
brew uninstall privoxy
sudo rm /etc/newsyslog.d/privoxy.conf
sudo security delete-certificate -c "Privoxy HTTPS Inspection CA" /Library/Keychains/System.keychain
rm -rf ~/.config/privoxy ~/.local/state/privoxy
```

Also set `filter_proxy.enabled: false` in macswitcher's config, or the next
context switch generates a PAC pointing at a proxy that is no longer there.
With `fail_open: true` that costs filtering, not connectivity.

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
