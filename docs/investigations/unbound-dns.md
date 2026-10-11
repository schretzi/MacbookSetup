## DNS — unbound

I need different DNS routing depending on where I am: home network, local
compose services, VMs, VPN. A local resolver answers all of them at once
instead of rewriting resolver settings per network. unbound has done that job
for years; it briefly got replaced by AdGuard Home for the extra ad/tracker
filtering, but running two resolvers (one at home via Pi-hole, enterprise
proxies at the office) made filtering redundant everywhere else, so this
machine is back to unbound as the only local resolver, full stop.

The role (`roles/unbound`) runs the full chain:

1. **Loopback alias** — _its own role, `localhost_alias`._ unbound binds to
   `127.0.0.2`, one of several loopback aliases that role creates and keeps
   across reboots (macOS drops them on every boot). Separate from the
   resolver role on purpose: the addresses outlive whichever resolver uses
   them.
2. **The daemon.** Unlike AdGuard Home, unbound has a Homebrew formula
   (`brew "unbound"`, `Brewfiles/60_security.brew`) and brew already manages
   its LaunchDaemon (`sh.brew.unbound`). `brew bundle install` only ever
   installs the receipt, never starts the service, so the role's job is just
   making sure it is actually running — no release pinning, no checksum
   verification, no accounts to seed.
3. **`unbound.conf`**, rendered from a small template: loopback-only
   interface, no privilege drop (macOS has no `unbound` system user), logs to
   stderr instead of syslog (so `observe`'s log view sees them), and a single
   `include: "conf.d/*.conf"` glob.
4. **Zones and forwarders**, below — everything local lives in `conf.d/`,
   picked up by that glob with no edit to `unbound.conf` itself.
5. **Verification.** The role waits for the port, resolves a name through
   `127.0.0.2`, and on failure prints the last lines of the log rather than
   pointing at it.

### conf.d/ — one file per owner

| file              | owned by                       | holds                                            |
| ----------------- | ------------------------------- | ------------------------------------------------- |
| `forwarders.conf` | macswitcher                     | the default (root `.`) forward-zone; rewritten on every network context switch |
| `kiac.conf`        | LocalKubernetes, at runtime     | `.kiac` + the `kiac.schretzi.net` OAuth-alias names, rendered from live compose service addresses |
| `schretzi.conf`    | `MacbookSetup-Private` overlay  | home LAN names, private k3d addresses              |
| `work.conf`        | `MacbookSetup-Work` overlay     | one pinned name + the corporate intranet forward-zones |

The overlays declare theirs in `overlay.yml`, and the role installs them from
`<root>/Dotfiles/unbound/zones.d/<file>` into `conf.d/`:

```yaml
unbound_zones_overlay:
  - { file: schretzi.conf, enabled: true, root: "{{ private_repo_root }}" }
```

### Zone syntax — plain unbound, no filter-list translation

A zone file is native unbound config, wrapped in its own `server:` clause
(unbound merges every `server:` block across every included file):

```
server:
  local-zone: "schretzi.local" transparent
  local-data: "mb.schretzi.local A 127.0.0.1"

  local-zone: "infra.k3d.schretzi" redirect
  local-data: "infra.k3d.schretzi A 127.0.0.100"
```

Three zone types cover everything this setup needs:

- **`static`** — anything under the zone with no matching `local-data` answers
  NXDOMAIN. Used for `.kiac`, which is owned entirely: unlike AdGuard Home's
  `||kiac^$dnsrewrite=NXDOMAIN` + a mandatory `@@` exception per name (a
  two-list invariant that had to be asserted so a missing exception didn't
  silently NXDOMAIN a real name), `static` makes "no entry = not answered"
  the default with nothing else to keep in sync.
- **`transparent`** — a name not listed under the zone falls through to the
  upstream resolvers, instead of NXDOMAIN. Used for `schretzi.local` and
  `kiac.schretzi.net`: only the names actually listed are overridden,
  everything else under them resolves normally (real public DNS, in the
  `kiac.schretzi.net` case, since `schretzi.net` is a real domain this
  machine's owner controls).
- **`redirect`** — every name under the zone, subdomains included, answers
  the single `local-data` line. One line covers what AdGuard Home's
  `||name^` matched-and-everything-under-it trick needed a full rule for.

### Forwarding, and the DNSSEC trap it opens

Per-domain forwarding (the work intranet) is a `forward-zone:` stanza per
domain — a top-level clause, not nested in `server:`:

```
forward-zone:
  name: "1tld.biz."
  forward-addr: 172.30.242.106
  forward-addr: 172.30.242.107
```

**A forwarded answer still has to pass DNSSEC validation**, and that breaks
for internal names: `*.internal`/`*.intranet`/`*.local` are not real TLDs, so
the root proves they don't exist while the internal resolver answers anyway
→ bogus. Each forwarded intranet domain needs a matching
`domain-insecure: "domain"` line (see `work.conf`) — the standard
split-horizon exemption, trust the internal resolver for internal names,
keep full validation everywhere else. AdGuard Home never had this trap
because it does not validate locally; it's the one real piece of complexity
unbound adds back.

### Adding private domains

Private names belong in the **private overlay**, not here — that is what
keeps this repository publishable. Add them to
`MacbookSetup-Private/Dotfiles/unbound/zones.d/schretzi.conf`:

```
server:
  local-zone: "home.internal" transparent
  local-data: "nas.home.internal A 192.168.1.10"
  local-data: "printer.home.internal A 192.168.1.11"
```

Then `ansible-playbook site.yml --tags unbound --ask-become-pass`. Editing the
file alone changes nothing — see the next section.

### The one real trap, measured differently than AdGuard Home's

**Writing a conf.d file changes nothing on its own.** unbound only reads
`conf.d/` at startup, so "write the file, do nothing else" leaves it serving
whatever it already had, with nothing in any log to say so.

Unlike AdGuard Home — which kept its own cached copy of every rule list under
`data/filters/<id>.txt` and needed either an API refresh call or a restart
plus a served-answer verification pass to close that gap — unbound re-reads
`conf.d/*.conf` directly on every restart. So `unbound_zones_refresh`
(`/usr/local/bin/unbound_zones_refresh`, NOPASSWD sudoers rule
`unbound-zones-refresh`) only has three steps:

1. `unbound-checkconf` — validate the whole merged config (every included
   file) before touching the running daemon, so a broken render fails loudly
   here rather than crash-looping it.
2. `launchctl kickstart -k system/sh.brew.unbound` — restart.
3. Wait for port 53, then `dig` every `local-data` name found across the
   changed file(s) and confirm it answers the address the file declares.

No cache-rewrite dance, no fallback-to-restart-when-the-API-is-unusable logic
— the restart-not-API-call design means there's only ever one path.

### The other real trap: a VPN client can shadow unbound entirely

`macswitcher` points a network service at unbound with
`networksetup -setdnsservers <service> 127.0.0.2` — but that only sets *that
service's* resolver, which is one of several candidates macOS's resolver
picks among by lowest `order` (`scutil --dns` shows all of them). A VPN
client that overrides DNS system-wide (Tailscale with "Override local DNS" /
`CorpDNS` turned on, in particular) typically registers its own resolver
with a lower order than the per-service one macswitcher sets, and wins for
every name that resolver doesn't explicitly recognize — including domains
unbound alone knows about, like `kiac.schretzi.net`. The symptom: `dig
@127.0.0.2 gtt.kiac.schretzi.net` answers correctly, but `dig
gtt.kiac.schretzi.net` (no explicit server — i.e. what every real
application does) returns NXDOMAIN/no-answer from the VPN's resolver
instead.

The fix is a domain-scoped resolver, which macOS always prefers over an
unscoped one regardless of `order`: an `/etc/resolver/<domain>` file
containing `nameserver 127.0.0.2`. `roles/unbound` manages this for every
domain listed in `unbound_resolver_domains` (`group_vars/all.yml` sets it to
`[schretzi.net]`, which also covers `kiac.schretzi.net`) plus
`unbound_resolver_domains_overlay` (the work overlay lists every domain
`work.conf` forwards to the internal resolvers — otherwise a VPN that
overrides DNS globally, like Tailscale with "Override local DNS" on, wins
for those too, even though unbound alone has the forward-zone for them; the
private overlay lists `infra.k3d.schretzi` the same way, but deliberately
not `schretzi.local` — `.local` is mDNS/Bonjour's reserved namespace and
resolves via multicast ahead of `/etc/resolver` regardless). Add a domain to
whichever list owns it — not to `unbound.conf` — if some other VPN/profile
ever starts shadowing it too.

### kiac and compose services

kiac/apple-container host-side DNS (per-VM addresses on the vmnet, the
`com.schretzi.adguardhome-bind` dance for serving it from a non-loopback
address) is gone along with kiac/apple-container themselves — everything that
survived the move to Docker Compose is a `compose/` container behind the
single edge Caddy on `127.0.0.1:443`, so `.kiac` now answers one address
(`127.0.0.1`) for every name, rendered by LocalKubernetes' `roles/host_dns`.
See that repository's `README.md` and `PLAN.md` §5 for the current design;
there is no vmnet-bind trap to repeat here anymore.
