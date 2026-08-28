# AdGuard Home, on trial next to unbound

unbound has been the local resolver here for years (Setup.md → DNS). This is an
evaluation of **AdGuard Home** as its replacement, run *next to* it rather than
instead of it: unbound keeps answering on `127.0.0.2`, AdGuard Home answers on
`127.0.0.3`, and nothing about the unbound setup is modified. Backing out is
deleting one directory and one plist.

The reason to consider the switch is the half unbound does not do: ad and
tracker blocking, malware/phishing filtering, a query log and per-client stats.
The reason to be careful about it is in [What is actually
worse](#what-is-actually-worse) — it is not a strict upgrade.

**Nothing here is wired into `site.yml`.** A normal
`ansible-playbook site.yml` neither installs, configures, nor removes any of
it. If AdGuard Home wins the evaluation, the install moves into a Homebrew tap
with a workflow tracking upstream releases, and the wiring becomes a role like
every other daemon.

---

## Install

```bash
Scripts/MacOS/adguardhome-test-install.sh
```

It downloads the pinned release (v0.107.79, SHA-256 checked against the
published `checksums.txt` — there is **no Homebrew formula** for AdGuard Home;
`brew search adguard` only finds the unrelated content-blocker cask), seeds the
config, translates unbound's zones, loads the LaunchDaemon and proves it
answers.

Remove it again, completely:

```bash
Scripts/MacOS/adguardhome-test-install.sh --uninstall
```

### The one thing that can block the install

unbound binds `0.0.0.0:53`, so it already holds every loopback alias including
`127.0.0.3`. Whether a second process may then bind that specific address is a
kernel question, not a configuration one, so the installer **tests the actual
bind before doing anything** and stops with instructions rather than leaving a
crash-looping daemon behind.

If it does refuse, the fix is to stop unbound binding the wildcard — set
`interface: 127.0.0.2` (plus `192.168.64.1` for the kiac VMs) in
`Dotfiles/unbound/unbound.conf` and restart it. Note the warning in the unbound
role: unbound refuses to start if **any** named interface is missing, which is
why the base config uses the wildcard in the first place. `192.168.64.1` only
exists while the vmnet is up.

---

## How the unbound configuration was migrated

By translating it, not by copying it — `Scripts/MacOS/unbound_to_adguard.py`
reads unbound's live `conf.d` and regenerates AdGuard Home's equivalents:

| unbound                          | AdGuard Home                                        |
| -------------------------------- | --------------------------------------------------- |
| `forward-zone: "."`              | plain lines in `upstream_dns_file`                   |
| `forward-zone: "intranet.tld"`   | `[/intranet.tld/]addr` in the same file              |
| `local-data: "x A 1.2.3.4"`      | `\|\|x^$dnsrewrite=NOERROR;A;1.2.3.4` in a rule list |
| `local-zone: "z" static`         | `\|\|z^$dnsrewrite=NXDOMAIN` + an `@@` exception per defined name |
| `local-zone: "z" redirect`       | the catch-all rule carries the address               |
| `local-zone: "z" transparent`    | nothing — undefined names forward, which is the default |
| `domain-insecure: "z"`           | **nothing**, and that is not an oversight — see below |

This means **unbound's `conf.d` stays the single source of truth** while both
resolvers run. Nothing needs maintaining twice, the overlays need no changes,
and the Ansible that owns `kiac.conf` keeps owning it. Regenerate after any
zone change:

```bash
sudo Scripts/MacOS/unbound_to_adguard.py
sudo launchctl kickstart -k system/com.schretzi.adguardhome
```

### The `@@` exception rules are load-bearing

`local-zone … static` means "answer what is listed, NXDOMAIN for the rest". In
AdGuard Home that is a wildcard NXDOMAIN rule — but when several `$dnsrewrite`
rules match one name, **a non-NOERROR rcode wins over an address**. So the
catch-all would swallow every name the zone actually defines. Each defined name
therefore gets an `@@…$dnsrewrite=NXDOMAIN` exception cancelling the catch-all
for itself only, which the generator emits automatically.

Verified against the live zones, unprivileged, before any of this was
installed:

| query                       | unbound expects | AdGuard Home gave        |
| --------------------------- | --------------- | ------------------------ |
| `gitea.kiac A`              | `192.168.64.2`  | `192.168.64.2` ✅         |
| `nonexistent-zzz.kiac A`    | NXDOMAIN        | NXDOMAIN ✅               |
| `foo.apps.main.kiac A`      | `192.168.64.10` (redirect) | `192.168.64.10` ✅ |
| `gitea.kiac AAAA`           | NOERROR/NODATA  | NOERROR/NODATA ✅         |
| `nope-zzz.kiac AAAA`        | NXDOMAIN        | NXDOMAIN ✅               |

---

## Comparing the two

```bash
Scripts/MacOS/adguardhome-compare.sh
```

Queries every name unbound answers locally — read out of `conf.d`, so it needs
no maintaining — against both resolvers and diffs rcode *and* data. `+short`
alone is not enough: it prints nothing for NXDOMAIN and nothing for NODATA, and
telling those apart is the whole point of a `static` zone. Exit status is
non-zero on any disagreement, so it can gate the cutover.

A difference on `doubleclick.net` is AdGuard Home doing its job, not a fault.

> **Careful:** the comparison is only meaningful if unbound is actually serving
> the current `conf.d`. At the time of writing it was **not** — the running
> daemon answered NXDOMAIN for `gitea.kiac` while `kiac.conf` defines it, and
> `unbound-control` was refused on `127.0.0.1:8953`. Restart unbound
> (`sudo launchctl kickstart -k system/net.unbound`) before trusting a diff, or
> every local name shows up as a false difference.

### First measured run

`--upstream`, both resolvers live, AdGuard Home freshly installed:

| query               | unbound (127.0.0.2)      | AdGuard Home (127.0.0.3) |
| ------------------- | ------------------------ | ------------------------ |
| `example.com`       | same                     | same ✅                   |
| `cloudflare.com`    | same                     | same ✅                   |
| `google.com`        | same                     | same ✅                   |
| `github.com`        | `140.82.121.4`           | `140.82.121.3` (round-robin, benign) |
| `doubleclick.net`   | resolves                 | `0.0.0.0` — **blocking works** |
| `dnssec-failed.org` | **resolves (NOERROR)**   | **SERVFAIL** ✅           |
| AD flag             | **absent**               | **present** ✅            |
| latency             | cold 10ms, cached 0ms    | cold 32ms, cached 0ms    |

The DNSSEC rows are the opposite of what the theory predicts, and worth
understanding rather than celebrating. The architectural point below still
holds — AdGuard Home does not validate locally, it relays Quad9's verdict. But
the unbound instance *actually running on this machine* is not validating at
all: no AD flag, and it happily returns an address for `dnssec-failed.org`.
Together with the stale zones and the refused control port, that says the
running unbound is in a bad state, not that AdGuard Home has gained a feature.

So: AdGuard Home is currently giving better answers than unbound is, while
being architecturally the weaker of the two on this point. Fix unbound first,
then re-run, or the comparison flatters AdGuard Home for the wrong reason.

---

## macswitcher

macswitcher drives both resolvers from the same context data. A context's
`unbound_forwarders` is one decision — "which upstreams does this network
want" — written in two syntaxes:

- `unbound.forwarders_file` → `forward-zone` stanza, then `unbound-control reload`
- `adguard.upstreams_file` → plain upstream lines, then a daemon restart
  (AdGuard Home reads that file at startup only; it has no reload signal)

A rewrite **preserves every `[/zone/]addr` line** in the upstream file. Those
come from unbound's forward-zones — the work overlay's intranet zones — and are
not macswitcher's to own; dropping them on a context switch would take the
intranet off the air in a way that only surfaces at the next intranet lookup.
There is a test pinning this (`TestWriteAdGuardUpstreamsPreservesPerDomainEntries`).

`macswitcher observe` now has an **adguardhome** row directly under unbound,
showing its launchd state plus which upstreams it is forwarding to, split into
the defaults macswitcher owns and a count of the per-domain zones it does not.

Both sides are opt-in: with `adguard.upstreams_file` unset, macswitcher behaves
exactly as before, and the observe row reads "not configured".

**This is a local build, not a release.** `~/bin/macswitcher` shadows the cask
binary at `/opt/homebrew/bin/macswitcher` because `~/bin` comes first on PATH.
The cask is untouched.

```bash
cd ~/Workspace/Schretzi/macswitcher && go build -o ~/bin/macswitcher ./cmd/macswitcher
rm ~/bin/macswitcher   # back to the cask
```

---

## Pointing something at it

Nothing is pointed at AdGuard Home automatically — same reasoning as the
unbound role, this is the step that breaks all name resolution when the
resolver is not healthy.

```bash
networksetup -setdnsservers Wi-Fi 127.0.0.3   # try AdGuard Home
networksetup -setdnsservers Wi-Fi 127.0.0.2   # back to unbound
```

For a full cutover later, `dns.local_resolver` in
`~/.config/macswitcher/config.yaml` is the one place that decides where every
context points.

Web UI: <http://127.0.0.3:3000> (user `admin`, password set at install).

---

## What is actually worse

Worth being honest about before switching, because none of it shows up in a
`dig` diff:

1. **DNSSEC is no longer validated on this machine.** unbound validates
   locally against `root.key` and sets AD itself. AdGuard Home's
   `enable_dnssec` only sets the DO/AD bits towards the upstream and relays
   whatever verdict comes back — `EnableDNSSEC defines whether the proxy should
   set the AD/DO bits in the upstream requests`. Quad9 validates, so bogus
   domains still fail; but the trust moves from this machine to the upstream.
   The AD-flag test in Setup.md → DNSSEC no longer means what it used to.

   The corollary is that all 13 `domain-insecure:` lines in the work overlay
   become unnecessary: there is no local validation for a split-horizon zone to
   be exempted from.

2. **The kiac VMs are not covered yet.** They take their nameserver from the
   vmnet gateway `192.168.64.1`, so they follow whatever the active network
   service points at. While AdGuard Home is bound to `127.0.0.3` only, pointing
   the system at it works for the host; a real cutover needs `bind_hosts` to
   include `192.168.64.1` (or `0.0.0.0`), which cannot happen while unbound
   holds the wildcard.

3. **A third-party daemon that rotates its own log.** CONVENTIONS.md says
   nothing rotates itself. AdGuard Home holds its log fd open and cannot be
   taught to reopen after a newsyslog rename, so its own rotation stays on for
   `adguardhome.log` and `etc/newsyslog.d/adguardhome.conf` covers only
   `adguardhome.err.log`. Same accepted-exception shape as `corp-vpn`.

4. **No `unbound-control` equivalent.** Changing upstreams means restarting the
   daemon, not reloading it, so a context switch drops the cache.

Unchanged either way: Apple's `container` runtime and Tailscale both register
`/etc/resolver` split-DNS domains that mDNSResponder consults *before* the
configured nameserver, so neither needs anything here.

---

## Files

| path                                       | what                                          |
| ------------------------------------------ | --------------------------------------------- |
| `Scripts/MacOS/adguardhome-test-install.sh`| install / update / uninstall                   |
| `Scripts/MacOS/unbound_to_adguard.py`      | the migration itself                           |
| `Scripts/MacOS/adguardhome-compare.sh`     | diff the two resolvers                         |
| `Dotfiles/adguardhome/AdGuardHome.yaml.seed`| base config, seeded once then runtime-owned   |
| `plists/LaunchDaemon/com.schretzi.adguardhome.plist` | the daemon                          |
| `etc/newsyslog.d/adguardhome.conf`         | rotation for the err log only                  |
| `/opt/adguardhome/`                        | binary, live config, generated zones (not in git) |
