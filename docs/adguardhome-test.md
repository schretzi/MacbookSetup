# AdGuard Home, the resolver

unbound was the local resolver here for years (Setup.md → DNS). AdGuard Home
replaced it. This file is the record of that: it started as a side-by-side
trial and the sections below are still written in that order, because the
comparison is what the decision rests on — but the trial is over.

**Where things stand now:**

| | |
| --- | --- |
| serving DNS | AdGuard Home, on `127.0.0.1/.2/.3` and, while the vmnet is up, `192.168.64.1` |
| unbound | `bootout` + `launchctl disable`, `enable_unbound: false` |
| unbound's `conf.d` | still the single source of truth for zones, *translated* into AdGuard Home's inputs |
| in `site.yml` | the `adguardhome` role — the runtime glue only, **not** the install |
| the install | still `Scripts/MacOS/adguardhome-test-install.sh`; there is no Homebrew formula |
| rollback | `Scripts/MacOS/adguardhome-cutover.sh --revert` |

The reason to make the switch was the half unbound does not do: ad and tracker
blocking, malware/phishing filtering, a query log and per-client stats. The
reason to be careful about it is in [What is actually
worse](#what-is-actually-worse) — it is not a strict upgrade, and the open
DNSSEC question in `BACKLOG.md` is still open.

Two things the cutover broke that are worth reading before anything else,
because neither was predicted and both took the machine's containers down:
[Serving the vmnet](#serving-the-vmnet-why-bind_hosts-is-a-list-and-not-0000)
and the web UI's port, at the end of [Pointing something at
it](#pointing-something-at-it).

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

`dns.local_resolver` in `~/.config/macswitcher/config.yaml` is **not** the one
place that decides this, which is easy to get wrong: a context's own
`dns.resolvers` overrides it, and every context except `work` pinned
`127.0.0.2` explicitly. Switching the machine over means changing
`local_resolver` *and* each context:

```go
resolvers := []string{strings.TrimSpace(cfg.DNS.LocalResolver)}
if ctx, ok := cfg.Contexts[cfg.CurrentContext]; ok && len(ctx.DNS.Resolvers) > 0 {
    resolvers = ctx.DNS.Resolvers   // context wins
}
```

### Tailscale sits in front of the resolver

Setup.md describes Tailscale as registering a split-DNS resolver for the
tailnet domain only. That is not what it does here. With `--accept-dns` on it
becomes the *system* resolver — `/etc/resolv.conf` says `100.100.100.100`, and
`scutil --dns` puts it at order 103400, ahead of the loopback resolver at
200000:

```
resolver #1  nameserver[0] : 100.100.100.100   order : 103400   (utun4)
resolver #2  nameserver[0] : 127.0.0.3         order : 200000
```

This is harmless *as long as* the tailnet has no global nameservers configured:
`tailscale dns status` then reports "no resolvers configured, system default
will be used", and MagicDNS forwards everything that is not a tailnet name to
whatever `networksetup` has set — so AdGuard Home stays in the path. Confirmed
end to end: `dscacheutil -q host -a name doubleclick.net` returns `0.0.0.0`
while `github.com` resolves normally, and `mbm5.tail3c0f6.ts.net` still works.

Two consequences worth knowing:

- Tailscale caches what it believes the system default is. After changing
  `networksetup -setdnsservers`, check `tailscale dns status` really shows the
  new address before concluding anything from a test.
- If the tailnet ever gets a global nameserver in the admin console, or
  "Override Local DNS" is turned on, **every local resolver is bypassed** —
  unbound included. That would have been silently true for the old setup too.

So a test through `dig @127.0.0.3` proves what AdGuard Home does; only
`dscacheutil` (or an actual browser) proves what the machine does.

Web UI: <http://127.0.0.3:3053> (user `admin`, password set at install).

**Not 3000, and this is not cosmetic.** gitea publishes `0.0.0.0:3000` on the
host, and a wildcard bind fails outright when a specific address on that port
is already taken — so AdGuard Home holding `127.0.0.3:3000` stopped the gitea
container from starting at all, with nothing but `bind(...): Address already
in use (errno: 48)` to go on. AdGuard Home is the newcomer, so it moved.

---

## Serving the vmnet: why `bind_hosts` is a list and not `0.0.0.0`

The cutover script set `bind_hosts: [0.0.0.0]`, mirroring unbound's
`interface: 0.0.0.0`, on the reasoning that the wildcard covers the vmnet
gateway `192.168.64.1` whenever it happens to exist. It does cover it — the
socket accepts the query. It just never answers it.

Measured on this machine, AdGuard Home v0.107.79, with a container running:

| from | to | proto | result |
| --- | --- | --- | --- |
| host | `127.0.0.3:53` | UDP | answers |
| host | `192.168.64.1:53` | TCP | answers |
| container `192.168.64.2` | `192.168.64.1:53` | TCP | full answer |
| container `192.168.64.2` | `192.168.64.1:53` | **UDP** | **silence** |
| container `192.168.64.2` | `192.168.64.1:5354` (test echo server, wildcard bind) | UDP | answers |

The last row is the one that rules everything else out: a plain wildcard UDP
socket on the host replies to the container fine, so this is neither pf, nor
Little Snitch, nor `allowed_clients` — the TCP rows come from the same client
and are answered.

What is left is visible in `lsof`. `bind_hosts: [0.0.0.0]` is a wildcard
address, so Go opens **one AF_INET6 dual-stack socket**:

```
AdGuardHo  root  101u  IPv6  UDP *:53
AdGuardHo  root  102u  IPv6  TCP *:53 (LISTEN)
```

TCP is connection-oriented and needs no help with the reply's source address.
For UDP, dnsproxy reads the query's local address out of the socket's control
messages and sets it explicitly on the reply — and for an IPv4-mapped client
that is not on loopback, that reply does not leave the host. Every container
and every kiac node VM gets `nameserver 192.168.64.1` from the runtime and asks
over UDP, so the entire vmnet had no resolver: `kiac resume` could not pull an
image, and containers could not resolve each other.

Naming the addresses instead gives each one its own AF_INET socket:

```
AdGuardHo  root   96u  IPv4  UDP 127.0.0.1:53
AdGuardHo  root  103u  IPv4  UDP 127.0.0.2:53
AdGuardHo  root  104u  IPv4  UDP 127.0.0.3:53
AdGuardHo  root  105u  IPv4  UDP 192.168.64.1:53
```

and the reply source is simply what the socket is bound to.

### Which is why the bind list moves

`192.168.64.1` exists only while the vmnet bridge is up, i.e. while at least
one container runs — and AdGuard Home refuses to start on an address it cannot
bind. A fixed list containing it would mean: boot with no containers, no
resolver at all, launchd respawn-looping. So the list follows the interface:

| | `bind_hosts` |
| --- | --- |
| vmnet up | `127.0.0.1 127.0.0.2 127.0.0.3 192.168.64.1` |
| vmnet down | `127.0.0.1 127.0.0.2 127.0.0.3` |

`Scripts/MacOS/adguardhome_bind_refresh.sh` owns that, installed as
`/usr/local/bin/adguardhome_bind_refresh` by the `adguardhome` role and run by
`com.schretzi.adguardhome-bind`. It restarts AdGuard Home only when the list
really changes, and if the daemon does not come back it restores a byte-exact
backup rather than leaving the machine without DNS.

The plist polls every 60s rather than the 300s its sibling
`com.schretzi.vmnet-nat-refresh` uses, because the trigger here is a container
starting — which is not a system network change and touches neither watched
file, so the poll is the primary mechanism and not the safety net. Anything
that cannot wait a minute calls the script directly; it has a NOPASSWD rule.

Two loopback addresses are in the list purely because the wildcard used to
cover them: `127.0.0.1`, and `127.0.0.2` because that is the address unbound
served for years and things still point at it.

### Editing the config without PyYAML

`adguardhome_bind_hosts.py` does the actual edit with the standard library
only. That is not purity: the refresh script runs as root from a LaunchDaemon
at boot and from Ansible's `become`, and PyYAML on this machine lives in
`~/Library/Python/*/site-packages` — user site-packages, invisible to root. The
first version imported `yaml` and died with `ModuleNotFoundError` the moment it
left an interactive shell.

It is a structural edit rather than a `sed`: it finds the top-level `dns:`
mapping, then `bind_hosts:` inside it, and replaces exactly that key's list,
copying every other byte through untouched — because AdGuard Home rewrites this
file itself whenever anything changes in the web UI, so its formatting is not
ours to predict. It reads block style at either indentation and flow style, and
always writes block style.

---

## Keeping `.kiac` current

The vmnet hands out addresses by DHCP in start order, so container and node-VM
IPs drift on every reboot — `gitea.kiac` was `192.168.64.2` before this
session's restart and `192.168.64.10` after it. Nothing here is static.

LocalKubernetes' `roles/host_dns` is what tracks that: it looks up every
container's live IP and each cluster's Gateway address, then re-renders
`/opt/homebrew/etc/unbound/conf.d/kiac.conf`. That file is still the single
source of truth — the whole point of migrating by translation rather than by
copying — and it now has to be translated before anything reads it:

```
host_dns  ->  conf.d/kiac.conf  ->  adguardhome_zones_refresh
                                    ->  /etc/adguardhome/zones/kiac.txt
```

`roles/host_dns` used to end with `launchctl kickstart -k system/net.unbound`.
After the cutover that is a no-op — the job is booted out and `disable`d — so
the render would be written and never served. It now calls
`/usr/local/bin/adguardhome_zones_refresh` (and the bind refresh) instead, both
through NOPASSWD rules so a non-interactive play can do it.

### Restarting AdGuard Home does not reload a local rule list

This is the trap, and it has no symptom other than wrong answers.

A filter whose `url` is an absolute path is still a *filter list*: AdGuard Home
keeps its own copy under `data/filters/<id>.txt`, and **that copy is what it
loads**. It does not read the configured path at startup at all. So "write the
file, kickstart the daemon" leaves it serving the previous addresses.

Measured, in this session: gitea moved from `192.168.64.2` to `.10`, the zone
file on disk said `.10`, AdGuard Home was restarted 12 seconds *after* the file
was written — and `dig @127.0.0.3 gitea.kiac` still answered `.2`, with
`blocked_response_ttl` as the TTL, i.e. straight out of a stale rewrite rule.
Eleven of the nineteen names were wrong that way.

The obvious guess — "drop the cached copy and it will re-read the source" — is
wrong, and worth recording because it fails *silently in the right direction*.
With `data/filters/1001.txt` moved aside and the daemon restarted:

```
gitea.kiac      -> (no answer)     the file was not recreated
registry.kiac   -> (no answer)     nothing was read from zones/kiac.txt
```

A refresh from the `url` happens on the update interval or through the HTTP
API, and the API needs the admin password — not something a non-interactive
root script has.

### The supported way: the API, live, no restart

`POST /control/filtering/refresh` makes AdGuard Home re-read the local path and
rewrite its cached copy — no restart, so the DNS cache survives. Measured, with
the source file changed and nothing restarted:

```
{"updated":1}                              exactly the one list that changed
data/filters/1001.txt                      rewritten, new mtime, new content
gitea.kiac  192.168.64.10 -> 10.99.99.99   answered, without a restart
```

That is what `adguardhome_zones_refresh` does now.

Beware how easy it is to mis-measure this. The first attempt queried the canary
name *before* changing the zone, which cached the NXDOMAIN for
`blocked_response_ttl` = 10s, then re-queried 2s later and read "no change"
as "the API does not work". The second attempt used a name never queried
before — and still got nothing, because a bare `A` rule in a `static` zone is
swallowed by the `||kiac^$dnsrewrite=NXDOMAIN` catch-all unless it also gets
its `@@` exception. The proof is the `gitea.kiac` row: an existing name, whose
exception the generator already emits, changing address with no restart.

### The credential

The API needs one, and **AdGuard Home has no permission model**: every account
under `users:` is a full admin. There is no read-only account and no way to
scope one to `filtering/refresh`. A separate account is therefore credential
isolation, not privilege isolation — worth having so a root script does not
carry your own password and can be rotated on its own, but it is not a
sandbox.

Created once, by hand. `htpasswd` ships with macOS and produces the bcrypt
hash AdGuard Home wants:

```bash
PASS="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32)"
HASH="$(htpasswd -bnBC 10 '' "$PASS" | tr -d ':\n')"
# add {name: zonesync, password: $HASH} to users: in AdGuardHome.yaml, restart
sudo security add-generic-password -U -s "adguardhome api" -a zonesync \
     -w "$PASS" /Library/Keychains/System.keychain
```

The System keychain rather than the login keychain, because the reader is a
root script with no login session. `adguardhome_zones_refresh` looks it up
there and says so plainly when it is missing.

### The fallback

Without a credential — or with the API unreachable — the script writes the
cached copy itself and restarts: each generated zone is copied over its
`data/filters/<id>.txt` (`!` comment lines are valid in a rule list, so nothing
is stripped). The `id` → source mapping comes out of AdGuard Home's own
`filters:` block, so no ID is hardcoded. The source under
`/etc/adguardhome/zones` is kept current either way — otherwise the next
scheduled refresh would quietly revert everything.

The previous cached copy is kept aside until the zone verifies, and put back if
it does not, so a failed attempt never leaves the machine with no `.kiac` zone
at all — which is worse than a stale one.

### Why the zones show up under "Blocklists" in the web UI

Because AdGuard Home has exactly two list categories, `filters` and
`whitelist_filters`, and a rule list full of `$dnsrewrite` rules belongs to the
first. There is no "local zones" category to put them in. Cosmetic; the `name`
field (`local zones - kiac`) is what tells them apart.

And it verifies unconditionally, not just when the generated files changed —
checking only on change would miss precisely this bug, where the files are
current on disk and the served answers are not. Every
`||name^$dnsrewrite=NOERROR;A;addr` rule in `zones/kiac.txt` is queried and
compared; a disagreement is printed and exits non-zero.

A restart is still only issued when something actually needs it: it costs the
whole DNS cache, and there is no `unbound-control reload` equivalent.

By hand, after any zone change:

```bash
cd ~/Workspace/Schretzi/LocalKubernetes
ansible-playbook playbooks/dns-update.yml     # re-render conf.d from live IPs
sudo -n /usr/local/bin/adguardhome_zones_refresh
```

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

2. **The kiac VMs need a moving bind list.** They take their nameserver from
   the vmnet gateway `192.168.64.1`, which exists only while a container runs.
   unbound served that address from a single `interface: 0.0.0.0` line and
   needed nothing further; AdGuard Home cannot (see [Serving the
   vmnet](#serving-the-vmnet-why-bind_hosts-is-a-list-and-not-0000)), so it
   takes a script, a LaunchDaemon and two sudo rules to do what one line of
   unbound config did. That is a real cost of the switch, not a footnote.

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
| `Scripts/MacOS/adguardhome-cutover.sh`     | hand DNS over from unbound, and `--revert`     |
| `Scripts/MacOS/unbound_to_adguard.py`      | the migration itself                           |
| `Scripts/MacOS/adguardhome-compare.sh`     | diff the two resolvers                         |
| `Scripts/MacOS/adguardhome_bind_refresh.sh`| keeps `bind_hosts` following the vmnet gateway |
| `Scripts/MacOS/adguardhome_bind_hosts.py`  | the config edit, standard library only         |
| `Scripts/MacOS/adguardhome_zones_refresh.sh`| re-translates `conf.d`, restarts only on a real change |
| `Ansible/roles/adguardhome/`               | installs the three above, the daemon and the rotation |
| `Dotfiles/adguardhome/AdGuardHome.yaml.seed`| base config, seeded once then runtime-owned   |
| `plists/LaunchDaemon/com.schretzi.adguardhome.plist` | the resolver daemon                 |
| `plists/LaunchDaemon/com.schretzi.adguardhome-bind.plist` | the bind refresh job          |
| `etc/newsyslog.d/adguardhome.conf`         | rotation for the resolver's err log only       |
| `etc/newsyslog.d/adguardhome-bind.conf`    | rotation for the bind refresh job              |
| `/opt/adguardhome/`                        | binary, live config (not in git)               |
| `/etc/adguardhome/`                        | generated upstreams and zones (not in git)     |
| System keychain, `adguardhome api`         | the `zonesync` API password (not in git)       |
| `LocalKubernetes/roles/host_dns/`          | renders `conf.d/kiac.conf` from live IPs, then calls the two refreshes |
