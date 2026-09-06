
## DNS — AdGuard Home

I need different DNS routing depending on where I am: home network, local
kubernetes clusters, VMs, VPN. A local resolver answers all of them at once
instead of rewriting resolver settings per network. unbound did that job for
years; AdGuard Home replaced it because it does the same and adds the half
unbound never had — ad, tracker and malware filtering, a query log, per-client
stats.

The role runs the full chain:

1. **Loopback aliases** — _its own role, `localhost_alias`._ The resolver binds to several loopback aliases: `127.0.0.1`, `127.0.0.2`, and `127.0.0.3`. This provides consistent, stable addresses for both DNS and the web UI. `Scripts/MacOS/localhost_alias.sh` is copied to
   `/usr/local/bin/localhost_alias` and run at boot by
   `com.schretzi.localhost-alias`, because macOS drops the aliases on every
   reboot.

   It also adds `.4` to `.12` and `.100`, which I used for separate k3d
   clusters earlier. Apple containers made that unnecessary, but the aliases
   are cheap and the cluster zones still answer with them.

   Separate from the resolver role on purpose: the addresses outlive whichever
   resolver uses them. While they belonged to the unbound role, switching
   unbound off left AdGuard Home's own address unmanaged.

2. **The daemon.** There is no Homebrew formula — `brew search adguard` finds
   only an unrelated content-blocker cask — so the role downloads the pinned
   GitHub release and verifies its SHA-256 **before** anything is unpacked as
   root. Bumping `adguardhome_version` means bumping the matching checksum.
3. **Configuration, seeded once.** `Dotfiles/adguardhome/AdGuardHome.yaml.seed`
   is copied to `/opt/adguardhome/AdGuardHome.yaml` the first time and never
   again — AdGuard Home rewrites that file on every change made through the web
   UI, so the repository seeds it and then keeps its hands off.
4. **Zones and upstreams**, below.
5. **Verification.** The role waits for the port, resolves a name through
   `127.0.0.3`, and on failure prints the last lines of both logs rather than
   pointing at them.

### The two accounts

AdGuard Home has no permission model — every entry in `users:` is a full admin
— so the two accounts are credential isolation, not privilege isolation:

| account    | keychain service    | for                                                                  |
| ---------- | ------------------- | -------------------------------------------------------------------- |
| `admin`    | `adguardhome admin` | the web UI at <http://127.0.0.3:3053>                                |
| `zonesync` | `adguardhome api`   | `POST /control/filtering/refresh`, so a zone change needs no restart |

Neither password is in this repository. The role generates a random one for
whichever has no System keychain entry yet, so a fresh machine converges
unattended:

```bash
sudo security find-generic-password -s "adguardhome admin" -a admin -w \
     /Library/Keychains/System.keychain
```

Changing it there does **not** change it in AdGuard Home — set it in the web UI
too, or delete `AdGuardHome.yaml` and let the role re-seed. On a machine that
already has a config the role never invents a missing entry: a generated
password would not be the one AdGuard Home accepts, and a credential that
silently does not work is worse than an absent one.

### Zones — one rule list per repository

A "zone" here is an AdGuard Home **filtering rule list**, not a zone file in the
DNS sense. Three of them, each owned by whoever owns the names:

| file           | from                        | holds                                        |
| -------------- | --------------------------- | -------------------------------------------- |
| `kiac.txt`     | LocalKubernetes, at runtime | cluster and container addresses on the vmnet |
| `schretzi.txt` | private overlay             | home LAN and private domains                 |
| `work.txt`     | work overlay                | names that needs a fixed answer              |

The overlays declare theirs in `overlay.yml`, and the role installs them from
`<root>/Dotfiles/adguardhome/zones.d/<file>` into `/etc/adguardhome/zones/`:

```yaml
adguardhome_zones_overlay:
  - { file: schretzi.txt, enabled: true, root: "{{ private_repo_root }}" }
```

The syntax is worth three lines:

```
||name^$dnsrewrite=NOERROR;A;10.0.0.1   answer name with that address
||name^                                 matches the name AND everything under it
@@||name^$dnsrewrite=NXDOMAIN           an exception to a rule above
```

Because `||name^` covers subdomains, one line does what unbound needed a
`redirect` zone for. A name that is simply not listed is not answered locally
at all and goes to the upstreams — unbound called that a `transparent` zone.

`.kiac` is the exception: it is owned entirely, so `||kiac^$dnsrewrite=NXDOMAIN`
answers everything under it locally and nothing leaks upstream. Every defined
name then needs an `@@` exception to escape that. **A name with an address but
no exception is not "missing" — it is actively answered NXDOMAIN, and nothing
in any log says so.** LocalKubernetes' template generates both lists from one
loop for exactly that reason, and asserts the property afterwards anyway.

**Adding a zone to a running machine needs one manual step.** AdGuard Home
loads a list because `AdGuardHome.yaml`'s `filters:` block names it with a
fixed id, and that file belongs to the runtime after the first seed. Add the
entry in the web UI, or delete the config and let the role re-seed.

### Adding private domains

Private names belong in the **private overlay**, not here — that is what keeps
this repository publishable. Add them to
`MacbookSetup-Private/Dotfiles/adguardhome/zones.d/schretzi.txt`:

```
||nas.home.internal^$dnsrewrite=NOERROR;A;192.168.1.10
||printer.home.internal^$dnsrewrite=NOERROR;A;192.168.1.11

! covers apps.home.internal and everything under it
||apps.home.internal^$dnsrewrite=NOERROR;A;192.168.1.20
```

Then `ansible-playbook site.yml --tags adguardhome --ask-become-pass`. Editing
the file alone changes nothing — see the next section.

### Upstreams, and why macswitcher owns them

Everything not answered locally goes to `/etc/adguardhome/upstreams.conf`, which
has two kinds of line:

```
9.9.9.9                            default upstreams - macswitcher rewrites
                                   these on every network context switch
[/intranet.example/]10.0.0.1       per-domain - an overlay contributes these,
                                   macswitcher carries them over untouched
```

Dropping the per-domain lines on a context switch would silently take the
intranet off the air, which is the kind of failure that shows up an hour later;
macswitcher preserves any line starting with `[`. The role seeds the file from
`Dotfiles/adguardhome/upstreams.conf` once and ensures each overlay line is
present, so an overlay can add one and have it arrive on the next play.

Comments must be on their own line. AdGuard Home parses a trailing
`9.9.9.9 # note` as a _second_ upstream address and rejects it.

### Two traps, both measured

**Writing a zone file changes nothing.** AdGuard Home keeps its own copy of
every rule list under `data/filters/<id>.txt` and does not re-read the path at
startup. "Write the file, restart the daemon" leaves it serving the previous
addresses, with nothing in any log to say so — measured: gitea moved from
`192.168.64.2` to `.10`, the file on disk said `.10`, the daemon was restarted
twelve seconds later, and `dig @127.0.0.3 gitea.kiac` still answered `.2`.
Eleven of nineteen names were wrong that way.

`sudo -n /usr/local/bin/adguardhome_zones_refresh` is what closes it: it asks
AdGuard Home to re-read its lists over the API (no restart, cache kept), falls
back to rewriting the cached copies and restarting when that is not usable, and
verifies the served answers against the rules afterwards rather than trusting
them. Everything that changes a zone ends there.

**`bind_hosts: 0.0.0.0` does not serve the vmnet.** Go turns a wildcard into a
single dual-stack `AF_INET6` socket, and on Darwin dnsproxy's UDP replies to
IPv4-mapped clients off loopback never leave the host — so every container and
kiac node VM got silence over UDP while TCP worked. The addresses are named
explicitly instead, one `AF_INET` socket each, and
`com.schretzi.adguardhome-bind` adds and removes `192.168.64.1` as the vmnet
comes and goes. unbound did this with one `interface: 0.0.0.0` line; this is
the price of the switch.

### kiac clusters and containers resolve through the host

kiac is a Go tool of its own (`~/Workspace/Schretzi/kiac`); nothing about it is
installed from this repository. Its node VMs — and every `container` the runtime
starts — sit on the `vmnet` network and get `nameserver 192.168.64.1` written
into their `resolv.conf`. That address is the host end of the vmnet bridge, and
the resolver has to be _listening on it_; mDNSResponder does not forward on
their behalf.

The addresses are **not** fixed. The vmnet hands them out by DHCP in start
order, so they move on every reboot. LocalKubernetes' `roles/host_dns` looks up
the live ones, renders `/etc/adguardhome/zones/kiac.txt` and calls the refresh
above. `/etc/adguardhome/zones` is group-writable by `admin` precisely so that
play can do it without `become`.

Two consequences of the VMs asking the host directly:

- A `/etc/resolver` split — the container runtime's, Tailscale's — is host-side
  only. Anything the VMs must resolve needs a real rule here.
- A VPN client that seizes port 53 takes the gateway's resolver with it, and
  every lookup from the VMs is refused. `kiac create cluster --dns 1.1.1.1`
  writes the VM's `resolv.conf` directly and bypasses the gateway, but only at
  creation time.

**Container DNS needs nothing here.** Apple's `container` runtime registers a
macOS split-DNS domain of its own:

```bash
sudo container system dns create mydomain
container system dns list
```

That writes `/etc/resolver/mydomain`, which mDNSResponder consults _before_ the
configured nameserver — so those names resolve on the host regardless of which
resolver the system points at.

### After a reboot or a crash, nothing brings the containers back

Three separate things are broken once the machine comes up again, and only the
last one had an owner before:

1. **The runtime does not return.** `container system start` writes its
   LaunchAgent to `~/Library/Application Support/com.apple.container/apiserver/`
   and bootstraps it from there — outside `~/Library/LaunchAgents`, the only
   place launchd loads from by itself. After a reboot the job is simply not
   registered and every `container` command ends in
   `XPC connection error: Connection invalid`. The plist it writes also pins the
   versioned Cellar path (`/opt/homebrew/Cellar/container/<version>/libexec/…`),
   so a `brew upgrade container` breaks the registered job as well.
2. **Nothing starts the containers.** apple/container has no restart policy —
   there is no `--restart` flag. Every container stays `stopped`.
3. **The addresses are new.** See above: DHCP in start order, so
   `/etc/adguardhome/zones/kiac.txt` names yesterday's addresses.

`container_autostart` — a LaunchAgent, `RunAtLoad` plus a 300s safety net —
does all three. It calls `container system start` unconditionally, which also
rewrites the pinned path and so heals point 1 on every login. It reads
`~/.zsh/rcs/proxy` first, because the API server inherits the environment of
whoever started it and would otherwise run with no proxy at all, or with a
stale one.

Then it starts every stopped container **except cluster nodes**, and refreshes
the zone only when an address actually changed.

**Cluster nodes are never started with `container start`.** That boots the VM
and produces a cluster that _looks_ healthy and is not: the node address moved,
`~/.kube/config` points nowhere, the kubeadm certificates need healing and
Cilium needs a Helm upgrade with a fresh `k8sServiceHost`. A cluster is
therefore either resumed through LocalKubernetes' `playbooks/resume.yml`, which
does all of that in order, or left alone.

Autostart is off by default and opted into per cluster, in LocalKubernetes'
`inventory/host_vars/<cluster>.yml`:

```yaml
cluster_autostart: true # resumed on the first boot after a crash/reboot
cluster_autostart: false # never resumed — same as leaving the key out
```

**Currently every cluster has it off**, `main` included: it is three node VMs
and 12 GB, and it is only needed while actually being worked on. Bringing it up
by hand is one command (below), which is cheaper than 12 GB resident at every
boot.

The key lives beside the cluster's own definition rather than in a list here,
so there is nothing to keep in sync, and a new cluster is never resumed by
surprise. It replaces an earlier rule that derived autostart from
`cluster_role: main` — a proxy for the wrong question, since whether a cluster
is _meant_ to run continuously says nothing about whether its memory is worth
spending while nobody asked for it.

Two limits on a cluster that _is_ opted in, because a resume is expensive and
unattended:

- **Only on the first run after a boot**, never on the 300s tick. The tick is
  there to catch a stopped container, not to fight a human who just stopped a
  cluster by hand.
- **Only if the cluster was still running when the script last looked.** A
  deliberate stop is recorded within one tick and then respected; a crash is
  not, because the crash left the state saying "running". The one case this
  gets wrong is stopping a cluster and powering off inside the same tick — it
  comes back once.

A failed resume raises a macOS notification, not just a log line: a half-resumed
cluster is otherwise noticed hours later as something unreachable.

Start a cluster by hand — the normal case now — with:

```bash
cd ~/Workspace/Schretzi/LocalKubernetes
ansible-playbook playbooks/resume.yml --limit main
```

Stopping one again frees the memory. `kiac` has no `stop cluster` verb — only
`kiac stop node <node>`, a chaos-testing tool that refuses to stop a cluster's
only node. LocalKubernetes wraps the real thing:

```bash
ansible-playbook playbooks/stop.yml --limit main
```

That stops every node VM of one cluster — exactly the state a reboot leaves
behind, and the state `resume.yml` is built to heal, so the cluster keeps its
data. Do not use `container system stop`: it halts every VM system-wide,
across every cluster and the service containers too.

It keeps no list of containers, nodes or clusters — all three would drift.
Nodes come from `kiac get clusters -o json` at run time (plus the `kiac-` name
prefix, since kiac reports `[]` for a node whose name it cannot parse);
everything else is "whatever the runtime reports, minus the nodes, minus
`buildkit`" (which `container build` starts on demand and which costs 2 GB
sitting idle).

State lives in `~/.local/state/container-autostart/addresses.json`: the address
fingerprint, the per-cluster running flags, and the boot ID that distinguishes
a boot run from a tick.

Logs are `~/Library/Logs/container-autostart.log`, and empty output means it
found nothing to do.

### DNSSEC/DoH/DoT — not solved right now

Needs to be investigated in detail

### Tailscale

Tailscale is installed by the `homebrew` role — `tailscale-app` in
`60_security.brew`. It is a pkg cask, so it is exactly the case
`Scripts/verify-casks.sh` exists to catch: cancel its installer prompt and the
receipt is written anyway. Signing in stays manual, once per machine.

**It needs no rule here, even with the system pointed at `127.0.0.3`.**
Tailscale registers a split-DNS resolver for the tailnet domain, and
mDNSResponder consults that _before_ the configured nameserver — the same
mechanism as `/etc/resolver`:

```bash
scutil --dns | grep -A3 ts.net
#   domain   : tail….ts.net
#   nameserver[0] : 100.100.100.100     <- Tailscale's fixed MagicDNS resolver

dscacheutil -q host -a name <host>.<tailnet>.ts.net
```

The catch: that split lives in mDNSResponder, not in AdGuard Home. Anything
talking to a resolver directly — `dig`, `host`, the kiac VMs — never sees it. So
test MagicDNS with `dscacheutil` or `ping`, not with `dig @127.0.0.3`, which
correctly returns nothing. If a tailnet name really has to come out of the local
resolver, add `[/ts.net/]100.100.100.100` as a per-domain upstream from the
private overlay rather than a rule.

### Pointing the system at it

AdGuard Home only listens on its own addresses, so nothing reaches it until a
network service's DNS server is set to `127.0.0.3`. **macswitcher does that on
every context switch**: it runs `networksetup -setdnsservers` against every
active service, using `dns.local_resolver` from
`~/.config/macswitcher/config.yaml` unless the context overrides it with its own
`dns.resolvers`. One switch therefore repoints the machine and rewrites the
default upstreams together, which is the point — the resolver and its upstreams
always match the network you are on.

```bash
macswitcher switch home-alone
macswitcher status
networksetup -getdnsservers Wi-Fi     # 127.0.0.3
```

**Ansible never sets this**, on purpose: it is the one step that breaks all name
resolution when the resolver is not healthy, and the daemon has to be verified
running first. Without macswitcher, or to back out, do it by hand — System
Settings → Network → Details → DNS, or:

```bash
networksetup -setdnsservers Wi-Fi 127.0.0.3   # point at AdGuard Home
networksetup -setdnsservers Wi-Fi empty       # back to whatever DHCP hands out
```

Logs: `/Library/Logs/adguardhome.log` (written by AdGuard Home itself, which
