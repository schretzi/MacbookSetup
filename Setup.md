# Schretzi Macbook Setup

Everything needed to take a Mac out of the box and end up with my working
environment.

> Employer-specific steps are not in this repository. They live in a private
> **work overlay** together with the intranet DNS zones, work mail account and
> shell helpers; see [Overlays](#identity-and-the-overlay-repositories).

## How this repo works

**The real file always lives here.** Nothing is copy-pasted into `~` and then
forgotten. Two mechanisms keep it that way:

| Mechanism | Used for | Why |
| --- | --- | --- |
| **Symlink** | `~/.config/*`, `~/.zshrc`, `~/.gitconfig`, `~/.ssh/config`, unbound configs | Editing the live file edits the repo file. Nothing to sync. |
| **Copy** | LaunchAgents, LaunchDaemons, `/etc/newsyslog.d`, `/usr/local/bin` | launchd and root-owned locations refuse to follow links into a user checkout. The repo copy is still the truth — re-run the play after editing. |

If a config is not in this repo, it is not managed, and rebuilding the machine
will lose it.

```
Ansible/     the automation (see below)
Brewfiles/   package lists, numbered by topic
Dotfiles/    every config file, symlinked into place
Scripts/     shell scripts (referenced by absolute path, or copied to /usr/local/bin)
plists/      LaunchAgents + LaunchDaemons, copied into place
etc/         files that belong under /etc
Addons/      dictionaries, markdownlint config
```

## Ansible

Everything that can be automated is a role under `Ansible/`. **Every topic can
be switched off individually** in `Ansible/group_vars/all.yml`.

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Ansible

ansible-playbook site.yml --ask-become-pass          # everything enabled in all.yml
ansible-playbook site.yml --check                    # dry run, changes nothing
ansible-playbook site.yml --tags dotfiles            # one topic
ansible-playbook site.yml --skip-tags mail,unbound   # everything except these
ansible-playbook site.yml --tags unbound -e enable_unbound=true   # force a disabled topic
```

`--ask-become-pass` is only needed for the roles that touch root-owned
locations: `unbound`, `java`, `kanata`.

| Role / tag | Switch | What it does |
| --- | --- | --- |
| `base_dirs` | `enable_base_dirs` | `~/bin`, `~/tmp`, `~/Workspace` |
| `homebrew` | `enable_homebrew` | `brew bundle` per Brewfile, each file individually toggleable |
| `dotfiles` | `enable_dotfiles` | symlinks `~/.config/*` and the home dotfiles into `Dotfiles/` |
| `git` | `enable_git` | links the shared git ignore file, checks the signing key |
| `ssh` | `enable_ssh` | links `~/.ssh/config`, fixes permissions |
| `java` | `enable_java` | links the Homebrew JDKs into `/Library/Java/JavaVirtualMachines` |
| `kanata` | `enable_kanata` | builds kanata with `cmd`, installs both daemons + log rotation |
| `windowmanager` | `enable_windowmanager` | yabai + skhd LaunchAgents |
| `mail` | `enable_mail` | maildir, notmuch index, offlineimap/omt agents, mail dotfiles |
| `unbound` | `enable_unbound` | loopback aliases, `_unbound` account, configs, resolver daemon |
| `macswitcher` | `enable_macswitcher` | seeds `~/.config/macswitcher` and the shell proxy variables |
| `gcloud` | `enable_gcloud` | gcloud components |
| `work` | `enable_work` | employer profile, supplied by the work overlay |

Two helper roles are never run directly: `link` (backup-then-symlink) and
`launchd` (copy or render plist + `bootout`/`bootstrap`).

### Identity and the overlay repositories

This repository is the **public base**: all machinery, no identity. Nothing in
it names a person, an address or an employer. Two private repositories layer on
top:

| Repo | Setting | Holds |
| --- | --- | --- |
| this one | — | roles, Brewfiles, scripts, plists, shared dotfiles |
| private | `private_repo_root` | `identity.yml`, personal git/ssh/mail config |
| work | `work_repo_root` | employer mail account, intranet DNS, work aliases and sessions |

Both paths may be empty. **A machine with neither cloned still converges** — it
simply has nothing personal configured, and the mail role reports that it found
no accounts rather than failing.

An overlay mirrors this repo's layout and contributes through an `overlay.yml`
at its root — extra dotfile links, Brewfiles, unbound zone profiles, mail
accounts — each entry carrying `root:` so links resolve into that checkout.
Identity comes from the private overlay's `identity.yml`; this repo ships only
`Ansible/local/identity.example.yml`. See
[Ansible/README.md](Ansible/README.md#overlays--the-three-repo-split).

Where the base cannot simply omit something, it leaves an extension point
rather than a hardcoded slot: `kanata.kbd` carries `(include "work.kbd")`
(kanata ignores a missing include), `kitty.conf` a `globinclude local.d/*.conf`,
and `.zshrc` already globs `~/.zsh/{rcs,aliases,functions}/`. Directories that
more than one repo contributes to — `~/.config/{kitty,kanata,git,mutt}` — are
real directories with links from each, not one link to this repo.

The play is idempotent — a second run reports zero changes. Anything real
already sitting where a symlink should go is moved to
`<path>.bak-<timestamp>` rather than deleted.

---

# Bootstrap — the manual part

These come before Ansible exists, so they cannot be automated.

## 1. macOS itself

Run the setup wizard: WLAN, local user, iCloud accounts, Touch ID.

## 2. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This also pulls in the Xcode Command Line Tools — which is where `git` comes
from — and takes a while. Then put it on the PATH:

```bash
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

> Once `Dotfiles/zsh/.zshrc` is linked it puts `/opt/homebrew/bin` on the PATH
> itself, so `~/.zprofile` only matters for the bootstrap window.

## 3. SSH key

The config files in this repo are private, so cloning needs SSH first. **Each
device and each usage gets its own key, with its own passphrase:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_mbm5_github -C "mbm5 github"
ssh-add --apple-use-keychain ~/.ssh/id_mbm5_github
```

Add the public key to GitHub **twice** — once as an authentication key, once as
a *signing* key — otherwise signed commits show as unverified.

The passphrase prompt is interactive by design, which is why the `ssh` role
only reports missing keys instead of creating them.

## 4. Clone the repo

```bash
mkdir -p ~/Workspace/Schretzi
git clone git@github.com:schretzi/MacbookSetup.git ~/Workspace/Schretzi/MacbookSetup
```

## 5. Minimum tooling for Ansible

`35_python.brew` installs Ansible itself, `31_rust.brew` is needed to build
kanata:

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Brewfiles
brew bundle install --file=35_python.brew
brew bundle install --file=31_rust.brew
```

From here on, run the playbook.

---

# What Ansible does, topic by topic

## User directories

`~/bin` (personal binaries), `~/tmp` (scratch, and the unbound control socket),
`~/Workspace` (all checkouts). Already on the PATH via `.zshrc`.

*Role: `base_dirs`*

## Homebrew packages

All installs are declarative, split by topic. `Ansible/roles/homebrew/defaults/main.yml`
decides which files are installed — `12_microsoft`, `51_mqtt` and `70_studio`
are off by default.

The Brewfiles pull from third-party taps (koekeishiya, FelixKratz, hashicorp,
saiyam1814, goreleaser, samuong, go-swagger). Those execute arbitrary code at
install time — review them before the first run, or drop the entries you do not
want. A tap you have not accepted makes `brew bundle` exit non-zero; the role
keeps going and prints a summary at the end rather than aborting the setup.

### Verifying casks are really installed

`brew bundle` answers *"does Homebrew have a receipt"*, which is not the same
question as *"is the software installed"*. Two ways they diverge:

- a **pkg cask** (Tailscale, for example) downloads an installer and runs it
  with sudo. Skip or cancel that prompt and the Caskroom receipt is written
  anyway — `brew bundle` then reports `Using tailscale-app` forever while
  nothing is installed and macOS has no `pkgutil` receipt
- an **app cask** whose `.app` was dragged to the Trash keeps its receipt too

So the role checks artifacts instead: `.app` bundles must exist under
`/Applications`, and pkg casks must have the `pkgutil` receipt they declare.

```bash
Scripts/verify-casks.sh      # non-zero exit when something is missing
```

It runs automatically at the end of the `homebrew` role. Anything it flags will
**not** fix itself on the next run — `brew bundle` still sees a receipt — so
reinstall the named cask:

```bash
brew reinstall --cask tailscale-app     # will prompt for your password
```

> Cask tokens get renamed upstream and the old name keeps resolving, so nothing
> looks wrong. `google-cloud-sdk` became `gcloud-cli` this way; the Brewfile now
> uses the current token.

*Role: `homebrew`*

## Dotfiles

Symlinks every live config location back into `Dotfiles/`. The map is in
`Ansible/roles/dotfiles/defaults/main.yml`; add an entry there and it is picked
up on the next run.

Mail configs are a separate list and only linked when `enable_mail` is true.

Neovim is launched as `NVIM_APPNAME=neobean nvim` (see `.zsh/aliases/general`),
so the real config directory is `~/.config/neobean` — there is no `~/.config/nvim`.

*Role: `dotfiles`*

## Shell

`~/.zshrc` and `~/.zsh/` (aliases, completions, functions, rcs) are symlinked.

**Umlauts:** the old setup added `export LC_CTYPE='UTF-8'`. Not needed any more —
`.zshrc` already sets `LANG=en_US.UTF-8`, which covers it.

*Role: `dotfiles`*

## Terminal environment

- **kitty** — terminal emulator; sessions and scripts under `Dotfiles/kitty/`
- **yabai** — tiling window manager
- **skhd** — hotkeys for yabai
- **raycast** — launcher + clipboard manager
- **fzf**, **zoxide**, **bat**, **eza**, **btop**, **nnn** — shell tools
- **neovim** (neobean config) — editor

yabai and skhd run as LaunchAgents. Two permissions have to be granted by hand
the first time each binary runs, in **System Settings → Privacy & Security**:

- **Accessibility** → yabai
- **Input Monitoring** → skhd

The yabai scripting addition is deliberately *not* installed — it requires
disabling SIP.

> `nnn` comes from Homebrew now. The old note about building it (and sxiv) from
> the GitHub project is obsolete.

*Role: `windowmanager`*

## Kanata (keyboard remapping)

Two manual prerequisites:

1. **Karabiner DriverKit VirtualHIDDevice, exactly version 6.2.0.** The version
   bundled with full Karabiner-Elements is wrong and breaks kanata.
   - Download the `.pkg` from
     <https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice>
   - Install it, then activate:
     ```bash
     /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
     ```
   - Approve the extension in **System Settings → Privacy & Security**
   - Confirm with `systemextensionsctl list` — it must show 6.2.0
2. **Input Monitoring** for kanata in System Settings.

Ansible then does the rest: it verifies the driver is active and the right
version, builds kanata **from source with the `cmd` feature** (`cargo install
kanata --features cmd` — the Homebrew build lacks it, so it cannot start or
switch applications), installs `com.kanata.daemon` and the Karabiner daemon,
and installs the newsyslog rule that rotates `/tmp/kanata.*.log`.

The keymap itself is `Dotfiles/kanata/kanata.kbd`, symlinked to
`~/.config/kanata/`. Keybindings are documented in
[Dotfiles/KEYBINDINGS.md](Dotfiles/KEYBINDINGS.md).

### `cmd` actions and `$HOME`

kanata runs as **root**, and launchd gives a root job no useful `HOME` — so
anything a `cmd` action spawns inherits an unset or `/var/root` home. That is
why the LaunchDaemon plist is a template: it pins

```xml
<key>EnvironmentVariables</key>
<dict><key>HOME</key><string>/Users/&lt;you&gt;</string></dict>
```

With that in place, `kanata.kbd` can say `$HOME` and stay a static, portable,
publishable file:

```lisp
hyper-s (cmd /bin/sh -c "exec $HOME/.config/kitty/scripts/kitty-focus-or-launch.sh …")
```

> The two kitty helper scripts (`kitty-focus-or-launch.sh`, `open-daily-note.sh`)
> keep a hardcoded home on purpose — they run under `set -u`, where an unset
> `$HOME` aborts the script outright and the shortcut silently does nothing.
> The comments in those files explain it; do not "fix" them to `$HOME`.

*Role: `kanata`*

## Git

`~/.gitconfig` and `~/.config/git/` live in `Dotfiles/git/` and are symlinked.
`git config --global` still works — git resolves the symlink before writing, so
edits land in the repo file.

Commit and tag signing use the SSH key, not GPG:

- `gpg.format = ssh`
- `user.signingkey = ~/.ssh/id_mbm5_github.pub`
- `commit.gpgsign = true`
- `gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers` — needed for
  `git log --show-signature` to verify rather than just display

An `includeIf` on the work checkout directory (`work_workspace_dir`, set by the
work overlay) switches to the work identity for anything cloned there.

The role warns if the signing key is missing — with `commit.gpgsign` on, every
commit would otherwise fail at the worst moment.

*Role: `git`*

## SSH

Private keys are never generated or stored here. The role manages
`~/.ssh/config` and `~/.ssh/allowed_signers` (both symlinked from
`Dotfiles/ssh/`), enforces `0700` on `~/.ssh`, and reports which keys are not
yet loaded in the agent.

`Host *` sets `UseKeychain yes` and `AddKeysToAgent yes`, so a passphrase is
entered once and then comes from the login keychain.

It deliberately does **not** run `ssh-add` for you: for a key whose passphrase
is not in the keychain yet, `ssh-add` prompts on the terminal and would hang the
playbook. Run it once by hand:

```bash
ssh-add --apple-use-keychain ~/.ssh/<key>
```

*Role: `ssh`*

## Java

Homebrew installs the JDK under its own prefix, where `/usr/libexec/java_home`
and anything using it (maven, IDEs) cannot find it. The role symlinks every
installed `openjdk*` into `/Library/Java/JavaVirtualMachines/` and then prints
what macOS detects.

*Role: `java`* — needs sudo

## Mail

Reading mail in the shell, four tools plus a token helper:

- **omt** — <https://github.com/schretzi/OauthMailToken>, my OAuth token
  manager. Installed from my own tap as the `schretzi/tap/omt` cask (listed in
  `Brewfiles/00_base.brew`), so it lands at `/opt/homebrew/bin/omt`. Without it,
  offlineimap cannot authenticate.
- **offlineimap** — syncs IMAP into `~/Maildir`
- **notmuch** — indexes the maildir
- **neomutt** — the TUI
- **msmtp** — sending

The role creates `~/Maildir`, initialises the notmuch database, and installs
two LaunchAgents: `org.schretzi.omt-daemon` (keeps tokens fresh) and
`org.schretzi.offlineimap-sync` (syncs every 5 minutes, logging to
`~/Library/Logs/offlineimap-sync.log`). Both are skipped if
`/opt/homebrew/bin/omt` is missing, so the agents do not sit in a failure loop.

### One account list, five rendered configs

msmtp, notmuch, offlineimap, omt and muttrc each enumerate **every account in a
single line of a single file**. There is no include mechanism in any of them,
which is exactly why they are *rendered* from one list rather than symlinked —
it is the only way the work account can come from one repository while the
personal accounts come from another.

The list lives in `Ansible/local/identity.yml`:

```yaml
mail_accounts:
  - id: gmail-personal
    sync_order: 10
    address: …
    login: …          # differs from address for Workspace aliases
    provider: google  # google | o365 | o365-consumers
    backend: Gmail    # offlineimap repository type
    mutt_key: "2"     # neomutt switch digit - pinned so it never reshuffles
    work: false
```

Adding or removing an account is a change **there and nowhere else**. Re-run
`--tags mail` and all five configs follow.

Two ordering keys exist so the eventual repo split cannot silently change
behaviour: `sync_order` fixes offlineimap's sync sequence regardless of which
repository an account came from, and `mutt_key` pins the neomutt switch digit.

OAuth **application** credentials sit in the same file as `mail_oauth_clients`,
keyed by provider — Thunderbird's published credentials, kept out of the rest of
the tree so no `client_secret:` literal ends up in a publishable repo. The role
fails fast, naming any provider missing a `client_id`.

Because those five are generated, they are **not** symlinks — editing
`~/.msmtprc` directly will be overwritten on the next run. Edit the account
list instead. `~/.config/mutt`, `~/.config/offlineimap` and `~/.config/omt` are
therefore real directories containing a mix of symlinks (static files) and
rendered output.

> `muttrc.mailboxes` is regenerated by offlineimap's `mbnames` at every sync.
> While `~/.config/mutt` was a symlink, that generated file was being written
> back into the repository on every run; it is now gitignored and stays out.

After changing anything here, verify the tools still resolve what they did
before — this compares parsed state and then exercises the live OAuth path:

```bash
Scripts/verify-mail-config.sh baseline    # before
Scripts/verify-mail-config.sh check       # after
```

### Retired tooling

`neverest`, `ortie` and `himalaya` were experiments alongside this stack and
have all been removed — configs deleted, `~/.config` links dropped, hand-built
binaries deleted from `~/.local/bin`. None of them was ever in a Brewfile, so a
rebuild does not bring them back.

Their jobs are covered by what remains: `ortie` handed OAuth tokens to
offlineimap, which **omt** does; `neverest` mirrored maildirs, which
**offlineimap** does; `himalaya` was an optional TUI next to **neomutt**. The
recent releases of that family are still in flux and did not work reliably
here, which is why they are gone rather than pinned.

The zsh `m` function (a `himalaya envelopes list` wrapper) went with them.

> **Fixed during the migration:** the config directory and file were named
> `mstmp/.mstmprc`, and `~/.mstmprc` was linked to it — but the binary is
> `msmtp`, which reads `~/.msmtprc`. The config was never being read. Renamed to
> `Dotfiles/msmtp/.msmtprc`; `msmtp -P` now confirms it loads.

Set `enable_mail: false` to skip the whole stack, including the mail dotfiles.

*Role: `mail`*

## DNS — local unbound resolver

I need different DNS routing depending on where I am: home network, k3d
clusters, lima VMs, VPN. A local unbound instance resolves all of them at once
instead of rewriting resolver settings per network.

The role runs the full chain:

1. **Loopback aliases.** mDNSResponder already owns `127.0.0.1:53`, so unbound
   listens on `127.0.0.2`. The k3d and cluster zones resolve to `127.0.0.3` …
   `127.0.0.12` and `127.0.0.100`, and those addresses must exist first.
   `Scripts/MacOS/localhost_alias.sh` is copied to `/usr/local/bin/localhost_alias`
   and run at boot by `org.localhost.alias`.
2. **Service account.** `_unbound`, uid/gid 444 (system range — check
   `/etc/passwd` if 444 is taken), created via `dscl`. Its `RecordName` lists
   both `_unbound` and `unbound` so either name in the config resolves.
3. **Configuration.** `Dotfiles/unbound/` is symlinked into
   `/opt/homebrew/etc/unbound/`. Brew's untouched default is preserved once as
   `unbound.conf.brew-default`.
4. **DNSSEC + control certs.** `unbound-anchor` and `unbound-control-setup`.
5. **Validation, then start.** `unbound-checkconf` must pass before
   `net.unbound` is loaded. Afterwards the role resolves a name through
   `127.0.0.2` and reports the result.

### Zone profiles

`unbound.conf` names no zone file. It includes `conf.d/*.conf`, and
`unbound_profiles` (`Ansible/roles/unbound/defaults/main.yml`) decides which
profiles get symlinked in — plus `unbound_profiles_overlay` from each overlay.
That is what lets a zone set be switched off without editing `unbound.conf`;
naming a disabled file directly would make unbound refuse to start.

| Profile | From | Default | Notes |
| --- | --- | --- | --- |
| `forwarders.conf` | base | on | upstream resolvers — runtime-managed at `/opt/homebrew/etc/unbound/conf.d/forwarders.conf` |
| `kiac.conf` | base | on | local kubernetes hosts on the vmnet (`192.168.64.0/24`) |
| `schretzi.conf` | private overlay | on | home LAN and private domains |
| intranet zones | work overlay | follows `enable_work` | employer forward zones |

The role warns about any `.conf` in `conf.d/` it does not know about — unbound
loads those too — and **deletes links whose target no longer exists**. A profile
file removed from a repo otherwise leaves a dangling include, and unbound
refuses to start on an include it cannot open, which only surfaces at the next
reload or reboot.

### Changing upstream resolvers

Everything unbound cannot answer locally goes to `forwarders.conf`. It is a
separate profile precisely so that adapting to a different network is one file:

```bash
$EDITOR ~/Workspace/Schretzi/MacbookSetup/Dotfiles/unbound/forwarders.conf
unbound-checkconf /opt/homebrew/etc/unbound/unbound.conf
unbound-control reload
```

Default is Quad9 then Google. On an office LAN that resolves internal names,
point the root zone at the LAN gateway instead.

To restart the daemon without a sudo password, the unbound role installs this
restricted sudoers entry:

```sudoers
schretzi ALL=(root) NOPASSWD: /bin/launchctl kickstart -k system/net.unbound
```

The zsh function `unbound_restart` uses that exact command.

`macswitcher` manages the runtime file at
`/opt/homebrew/etc/unbound/conf.d/forwarders.conf`. On a fresh installation
Ansible links that path to the repository default
`Dotfiles/unbound/forwarders.conf`. When macswitcher changes contexts, it
removes only the destination symlink and writes a real file, leaving the
repository source untouched. Later Ansible runs preserve that real file; if
the link is recreated deliberately, the next context switch will replace it
again.

**Container DNS needs nothing here.** Apple's `container` runtime registers a
macOS split-DNS domain of its own:

```bash
sudo container system dns create mydomain
container system dns list
```

That writes `/etc/resolver/mydomain`, which mDNSResponder consults *before* the
configured nameserver — so those names resolve on the host regardless of
whether the system points at unbound. Add a forward-zone here only if the kiac
VMs need to resolve them, since they query unbound directly at the vmnet
gateway and never see the host's `/etc/resolver`.

### Adding private domains

Private names belong in the **private overlay**, not here — that is what keeps
this repository publishable. Add them to
`MacbookSetup-Private/Dotfiles/unbound/schretzi.conf`:

```
server:
  # transparent: names not listed fall through to the forwarders
  local-zone: "home.internal" transparent
  local-data: "nas.home.internal      A 192.168.1.10"
  local-data: "printer.home.internal  A 192.168.1.11"

  # redirect: every name under the zone resolves to one address
  local-zone: "apps.home.internal" redirect
  local-data: "apps.home.internal     A 192.168.1.20"
```

To add a whole new profile file rather than extend the existing one, drop it in
that overlay's `Dotfiles/unbound/` and register it in its `overlay.yml`:

```yaml
unbound_profiles_overlay:
  - { file: schretzi.conf, enabled: true, root: "{{ private_repo_root }}" }
  - { file: lab.conf,      enabled: true, root: "{{ private_repo_root }}" }
```

Then `ansible-playbook site.yml --tags unbound --ask-become-pass`, or just
symlink it into `conf.d/` and reload — the Homebrew prefix is user-writable, so
that needs no sudo either.

Zone-type cheat sheet: **`transparent`** answers what you list and forwards the
rest, **`redirect`** answers *every* name under the zone with the listed data,
**`static`** answers what you list and returns NXDOMAIN for the rest.

### Reloading without sudo

`unbound-control` talks to the daemon over **TCP on `127.0.0.1:8953` with a
client certificate**, not over a unix socket:

```bash
unbound-control reload      # no sudo
unbound-control status
unbound-control lookup nas.home.internal
```

unbound creates its unix socket owned by the account it drops privileges to
(`_unbound`, mode `0660`) and offers no option to change that, so socket-based
control always needs root. Over TCP the client authenticates with
`unbound_control.{key,pem}` instead, and the Ansible role hands the key to your
user (`0600`) while leaving the server key to `_unbound`. Access is still
loopback-only and still certificate-gated.

> `unbound-control` lives in `/opt/homebrew/sbin`, which `.zshrc` now puts on
> the PATH.

**Do not use `unbound-control start`.** It exists, but it launches a *new*
daemon as whoever runs it — and an unprivileged process cannot bind
`127.0.0.2:53`, so it fails with:

```
error: can't bind socket: Permission denied for 127.0.0.2 port 53
fatal error: could not open ports
```

The daemon is owned by launchd, which starts it as root and lets it drop
privileges to `_unbound` *after* binding. Start, stop and restart it there:

```bash
sudo launchctl kickstart -k system/net.unbound   # restart
sudo launchctl print system/net.unbound          # status
```

`unbound-control` is for talking to a daemon that is already running —
`reload`, `status`, `lookup`, `stats`. Note `reload` re-reads the config but
cannot rebind sockets, so a change to `unbound.conf` itself (interfaces, ports,
remote-control) needs the restart above; zone files under `conf.d/` only need a
reload. The Ansible role picks the right one automatically based on what
changed.

### DNSSEC

Validation happens **here**, not at the upstream resolver. `unbound.conf` sets:

```
auto-trust-anchor-file: "/opt/homebrew/etc/unbound/root.key"
val-log-level: 1
```

Without that line the role still fetches `root.key` via `unbound-anchor` and
unbound then ignores it — a state that is easy to miss, because a broken domain
still fails. Quad9 validates too, so `dnssec-failed.org` returns SERVFAIL either
way. The honest test is the **AD flag** on a good domain:

```bash
dig +dnssec @127.0.0.2 cloudflare.com A | grep 'flags:'
#  ... flags: qr rd ra ad;   <- "ad" present means we validated it
```

The role checks exactly this after starting and says so either way.

`root.key` is owned by `_unbound` and mode `0644`: it must stay **writable** by
unbound (RFC 5011 rewrites it in place as the root KSK rolls) and **readable**
by you, or `unbound-checkconf` fails with the unhelpful
`validator: could not apply configuration settings`. The anchor is published
IANA data, not a secret.

#### Split-horizon zones need `domain-insecure`

Any zone forwarded to an internal resolver has to be exempted, or validation
rejects the answer:

```
server:
  domain-insecure: "example.internal"
```

Two cases make this mandatory rather than cosmetic:

- **`.internal`, `.intranet`, `.local`** and similar are not real TLDs, so the
  signed root proves they do not exist while your internal resolver answers
  anyway — the answer is bogus by definition.
- Anything forwarded that sits under a **signed public parent**. The old
  `docker.arpa` entry was the example: `.arpa` is signed, so the root proves
  `docker.arpa` does not exist. That entry has since been removed entirely —
  it pointed at Colima's resolver, and Colima is no longer installed.

Zones answered by `local-zone`/`local-data` (`kiac.`, the private overlay's
LAN zone) need nothing — local data is returned without validation. It is only
*forwarding* that has to be exempted. The work overlay marks all of its
forwarded zones insecure for consistency, so adding one there does not silently
require hunting down a matching entry.

### Tailscale

**You do not need an unbound profile for Tailscale**, and the old
`tailscale.conf` has been deleted — it had an unbalanced quote on line 2 and its
remaining lines were a stray copy of the home zone. Tailscale is not currently
installed on this machine at all.

MagicDNS is handled by Tailscale itself: it registers a split-DNS resolver for
your tailnet domain, so `<host>.<tailnet>.ts.net` resolves without unbound
knowing anything about it.

The one case where it matters: **if you point the whole system at unbound**
(see below), tailnet queries reach unbound instead of Tailscale's resolver and
fail. The fix is a forward, not local data — add to the private overlay:

```
forward-zone:
  name: "ts.net"
  forward-addr: 100.100.100.100      # Tailscale's local MagicDNS resolver
```

`100.100.100.100` is Tailscale's fixed internal resolver address. Confirm with
`scutil --dns | grep -A3 ts.net` once Tailscale is running.

### Pointing the system at it

unbound only listens on `127.0.0.2`. To route the machine through it, set
`127.0.0.2` as the DNS server of the active network service (System Settings →
Network → Details → DNS, or `networksetup -setdnsservers Wi-Fi 127.0.0.2`).
This is left manual on purpose — it is the step that breaks all name
resolution if the resolver is not healthy.

Logs: `/tmp/unbound.err.log`, `/tmp/unbound.out.log`.

*Role: `unbound`* — needs sudo

## AI tooling — one set of skills, every assistant

Skills are `SKILL.md` directories on disk. They are **not** stored in any
tool's state database — Copilot's `auth.db` is purely OAuth tokens (four
tables: `oauth_tokens`, `active_sessions`, `editor_signout`, `metadata`), and
Claude keeps its credentials in the macOS keychain. Being plain files is what
makes a single shared set possible.

Each assistant looks in a different place:

| Tool | Personal skills |
| --- | --- |
| Claude | `~/.claude/skills/` |
| Copilot CLI | `~/.copilot/skills/` or `~/.agents/skills/` |
| per project | `.github/skills/`, `.agents/skills/`, `.claude/skills/` |

The source of truth is a **separate repository**,
`~/Workspace/Schretzi/schretzi-skills`, and the `ai` role links it into all of
them — whole-directory for Copilot and the neutral `~/.agents/skills` path, and
one link per skill for Claude (whose skills directory holds other files too).
Adding a skill is a commit in that repo; nothing here needs re-running for the
directory-linked tools.

```bash
ansible-playbook site.yml --tags ai
copilot skill list          # confirms Copilot sees the same set
```

> `~/.agents/skills` is the tool-neutral path. Anything adopting the
> `AGENTS.md` convention should find skills there without further work.

### Configuration that is versioned

`Dotfiles/claude/settings.json` and `Dotfiles/gemini/settings.json` are
symlinked into place. `ai_optional_links` in the role also names files that do
**not exist yet** — `CLAUDE.md`, `.claude/agents/`, `.claude/commands/`,
`.claude/hooks/`, `.copilot/mcp-config.json`, `.copilot/AGENTS.md`. Each is
linked only if present, so creating one later is picked up on the next run with
no change to the playbook.

Which Claude plugins are enabled is captured declaratively in
`settings.json` (`enabledPlugins`) rather than from
`plugins/installed_plugins.json`, which carries absolute install paths,
timestamps and commit SHAs.

### Deliberately not versioned

Conversation content and caches: `~/.claude/projects/` (22 MB of transcripts),
`history.jsonl` (every prompt typed), `backups/`, `file-history/`, `sessions/`,
`paste-cache/`, `shell-snapshots/`, `plugins/cache|data|marketplaces/`,
`~/.gemini/google_accounts.json`, `~/.copilot/logs/`, and every `auth.db*`.

> `~/.config/github-copilot` used to be symlinked into this repo, which meant
> Copilot wrote a live OAuth token *inside the source tree*. That link is gone
> and the directory is no longer managed — nothing in it is worth versioning.

## Google Cloud

The SDK comes from `41_clouds.brew`. The role installs the components
(`alpha`, `beta`), skipping ones already present.

> `terraform-tools` was in the old list but the Homebrew SDK does not offer it —
> `gcloud components install` exits 0 with "All components are up to date" and
> installs nothing. Dropped; terraform itself comes from `40_kubernetes_ci.brew`.
> The role now checks availability first and reports anything it cannot provide.

`gcloud init` needs a browser and stays manual:

```bash
gcloud init
```

*Role: `gcloud`*

## Yubikey

Not automated — key generation, PIN/PUK setup and touch policies are all
interactive, and getting them wrong can lock a key permanently.

Reference: <https://github.com/drduh/YubiKey-Guide>. It is long, especially when
starting from fresh GPG keys. I still use RSA 4096 for compatibility with other
systems.

Tools come from `60_security.brew`: `ykman`, `yubico-piv-tool`, `yubikey-agent`,
`yubico-authenticator`.

> The guide's commands assume GNU grep. This setup installs it as `ggrep`
> (Homebrew `grep`), so substitute accordingly.

Check the connection:

```bash
export YKSERIAL=$(ykman list --serials)
ykman --device $YKSERIAL info
```

## Software outside Homebrew

Manual downloads, mostly because of vendor installers or App Store gating:

- Dymo Label Printer
- GoodNotes
- HP Smart
- LabCom
- Ivory (Mastodon client)
- `obsidian_calendar.sh`

`oauth2ms` from the old list is superseded by **omt** (see Mail).

## Not managed here

- `Dotfiles/github-copilot/auth.db` — holds a live OAuth token, now gitignored
  and no longer versioned. It was committed previously, so it is still in git
  history; revoke and re-authenticate Copilot when convenient.

---

## macswitcher configuration

*Role: `macswitcher`* — `enable_macswitcher`

**Nothing under `~/.config/macswitcher` is a symlink, by design.** macswitcher
rewrites `config.yaml`, the context files and `state.json` in place on every
switch. Linking any of them back into a repository means the runtime writes its
live values into the source tree — the same trap `dotfiles_real_dirs` documents
and the same one the unbound role avoids for `forwarders.conf`. So the role
*seeds* each file once (`copy` with `force: false`) and never touches it again.

Where each file comes from:

| File | Source | Notes |
| --- | --- | --- |
| `config.yaml` | this repo, `Dotfiles/macswitcher/config.yaml` | generic, no addresses |
| `contexts/home.yaml`, `contexts/remote.yaml` | private overlay | via `macswitcher_contexts_overlay` |
| `contexts/work.yaml` | work overlay | same, follows `enable_work` |
| `state.json` | macswitcher itself | never versioned |
| `~/.zsh/rcs/proxy` | this repo, `Dotfiles/macswitcher/proxy.zsh` | neutral defaults, then owned by the runtime |

`Dotfiles/macswitcher/proxy.zsh` deliberately does **not** live in
`Dotfiles/zsh/.zsh/rcs/`. That directory is a dotfiles merge dir: every file in
it is force-symlinked into `$HOME`, and there is no per-file exclusion, so
macswitcher would write its runtime proxy values straight back into this repo.

When no overlay supplies a context — a fresh machine with neither overlay
cloned — the role falls back to `macswitcher config init`. That command refuses
to run when a `config.yaml` already exists and writes the global config,
`state.json` and the starter contexts together, so the role renders it into a
throwaway directory and copies out only the context templates. The global
config this repo owns is left alone either way.

Each context is a separate `.yaml` file; the global file holds no context
definitions or proxy profiles. Contexts default to `proxy_mode: direct`; an
optional `forwarder_proxy` block enables upstream forwarding.

Environment-specific addresses, names, PAC URLs, Kerberos paths, and proxy
settings belong only in those overlays. Passwords and other secrets are read
from the macOS Keychain and must not be added to any repository.

## Reference

- [Mutt / notmuch / offlineimap introduction](https://bascht.com/blog/2014/05/28/einstieg-in-mutt-notmuch-offlineimap/)
- [Mutt password management](https://wiki.archlinux.org/title/Mutt#Passwords_management)
- [offlineimap config examples](https://www.offlineimap.org/doc/conf_examples.html)
- [unbound on macOS](https://sizeof.cat/post/unbound-on-macos/)
- [YubiKey guide](https://github.com/drduh/YubiKey-Guide)
- [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)

## Open items

- **`~/Workspace/Schretzi/schretzi-skills` has no git remote.** It is the
  source of truth for all 33 shared skills and currently exists only on this
  machine — a disk failure loses them, and a rebuild cannot restore them.
  Push it somewhere before relying on the setup being reproducible.

- `Dotfiles/unbound/tailscale.conf` has a syntax error (unbalanced quote,
  line 2). It is disabled, so it does not break anything — fix it before
  enabling.
- The unbound config does not set `auto-trust-anchor-file`, so the `root.key`
  the role fetches is not actually used for DNSSEC validation yet.
