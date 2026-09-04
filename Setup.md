
# Schretzi Macbook Setup

Everything needed to take a Mac out of the box and end up with my working
environment.

> Employer-specific steps are not in this repository. They live in a private
> **work overlay** together with the DNS zones, work mail account and
> shell helpers; see [Overlays](#identity-and-the-overlay-repositories).

> **Sharing the networking tools with someone else?**
> [docs/networking-tools.md](docs/networking-tools.md) covers installing and
> using macswitcher, kerberoskeepalive and omt **without** this repository —
> no Ansible, no clone, no overlays. It is the page to send to a colleague.
> The rest of this file assumes you are rebuilding _my_ machine.

## Software outside Automation

Three things cannot come from `brew bundle` and Ansible: one has to filter the
network before anything else is installed, one needs a driver the vendor ships
no cask for, and one is a system extension that must be approved by hand.
Install them first, in this order.

### Little Snitch

The outbound firewall goes on before anything else starts talking to the
internet — which is also why it is deliberately **not** in a Brewfile: by the
time the `homebrew` role runs, it should already be filtering.

```bash
brew install --cask little-snitch
```

It installs a network system extension; approve it in **System Settings →
Privacy & Security** and reboot when asked:

```bash
systemextensionsctl list | grep littlesnitch   # [activated enabled]
```

There is no ruleset to import yet, so the first hours on an empty rule list are
brutal — every process asks, and you approve blindly. Start in **Silent Mode —
Allow Connections** instead: Little Snitch records the rules without prompting.
A day or two later, review what accumulated, keep the obvious ones (Apple,
Microsoft, Google), and drop the rest. Then switch back to **Alert Mode** so new
connections ask again.

### DisplayLink (docks)

Docks that drive external displays over USB need Synaptics' driver, and there is
no cask for it — download DisplayLink Manager by hand:
<https://www.synaptics.com/products/displaylink-graphics/downloads/macos>

It then needs **Screen & System Audio Recording** permission (the pane older
notes still call _Screen Recording_), granted in **System Settings → Privacy &
Security** — it captures the desktop to push those pixels over USB. Without it
the external screens stay black.

### Karabiner DriverKit VirtualHIDDevice

kanata, installed by Ansible later, drives the keyboard through this virtual HID
driver. Take **package version 6.2.0** specifically — the newer driver bundled
with full Karabiner-Elements breaks kanata.

Download that release's `.pkg` from
<https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases> and
install it. Installing only places the Manager app; the driver stays dormant
until you activate it, which is what triggers the approval prompt in **System
Settings → Privacy & Security**:

```bash
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

Expect two version numbers that never match. The pqrs _package_ is 6.2.0, which
only the Manager app's `Info.plist` reports; the _extension_ it registers calls
itself 1.8.0, and that is the only number `systemextensionsctl` will ever show:

```bash
plutil -p /Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/Info.plist | grep ShortVersion
# "CFBundleShortVersionString" => "6.2.0"

systemextensionsctl list | grep Karabiner
# ...VirtualHIDDevice (1.8.0/1.8.0) ... [activated enabled]
```

The `kanata` role checks both and stops if the extension is not active.

## How this repo works

**The real file always lives here.** Nothing is copy-pasted into `~` and then
forgotten. Two mechanisms keep it that way:

| Mechanism   | Used for                                                          | Why                                                                                                                                             |
| ----------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Symlink** | `~/.config/*`, `~/.zshrc`, `~/.gitconfig`, `~/.ssh/config`        | Editing the live file edits the repo file. Nothing to sync.                                                                                     |
| **Copy**    | LaunchAgents, LaunchDaemons, `/etc/newsyslog.d`, `/usr/local/bin` | launchd and root-owned locations refuse to follow links into a user checkout. The repo copy is still the truth — re-run the play after editing. |

If a config is not in this repo, it is not managed, and rebuilding the machine
will lose it.

```
Ansible/     the automation (see below)
Brewfiles/   package lists, numbered by topic
Dotfiles/    every config file, symlinked into place
Scripts/     shell scripts (referenced by absolute path, or copied to /usr/local/bin)
plists/      LaunchAgents + LaunchDaemons, copied into place
etc/         files that belong under /etc (newsyslog rotation configs)
docs/        standalone guides that do not assume this repo — shareable
Addons/      dictionaries, markdownlint config
```

Two documents sit beside this one:

- [CONVENTIONS.md](CONVENTIONS.md) — the rules every background job follows
  (labels, log paths, rotation, CLI surface), and why.
- [docs/networking-tools.md](docs/networking-tools.md) — a self-contained
  install/use guide for the three networking CLIs, written for someone who
  does not have this repository.

## Ansible

Everything that can be automated is a role under `Ansible/`. **Every topic can
be switched off individually** in `Ansible/group_vars/all.yml`.

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Ansible

ansible-playbook site.yml --ask-become-pass          # everything enabled in all.yml
ansible-playbook site.yml --check                    # dry run, changes nothing
ansible-playbook site.yml --tags dotfiles            # one topic
ansible-playbook site.yml --skip-tags mail,adguardhome   # everything except these
ansible-playbook site.yml --tags mail -e enable_mail=true   # force a disabled topic
```

`--ask-become-pass` is only needed for the roles that touch root-owned
locations: `sudoers`, `localhost_alias`, `adguardhome`, `java`, `kanata`,
`firefox_enterprise_roots`. There is a way to authenticate once up front
instead — see [sudo](#sudo) below — but it is switched off until Touch ID for
sudo works.

| Role / tag        | Switch                   | What it does                                                      |
| ----------------- | ------------------------ | ----------------------------------------------------------------- |
| `base_dirs`       | `enable_base_dirs`       | `~/bin`, `~/tmp`, `~/Workspace`                                   |
| `homebrew`        | `enable_homebrew`        | `brew bundle` per Brewfile, each file individually toggleable     |
| `dotfiles`        | `enable_dotfiles`        | symlinks `~/.config/*` and the home dotfiles into `Dotfiles/`     |
| `git`             | `enable_git`             | links the shared git ignore file, checks the signing key          |
| `ssh`             | `enable_ssh`             | links `~/.ssh/config`, fixes permissions                          |
| `gitlab`          | `enable_gitlab`          | renders instance list for `gl`, checks tokens are in the keychain |
| `kubeconfig`      | `enable_kubeconfig`      | creates `~/.kube/configs` for `kubeconfig-add`/`kubeconfig-merge` |
| `sudoers`         | `enable_sudoers`         | Touch ID for sudo, the shared credential cache, NOPASSWD rules    |
| `java`            | `enable_java`            | links the Homebrew JDKs into `/Library/Java/JavaVirtualMachines`  |
| `kanata`          | `enable_kanata`          | builds kanata with `cmd`, installs both daemons + log rotation    |
| `windowmanager`   | `enable_windowmanager`   | yabai + skhd LaunchAgents                                         |
| `mail`            | `enable_mail`            | maildir, notmuch index, offlineimap/omt agents, mail dotfiles     |
| `localhost_alias` | `enable_localhost_alias` | the extra 127.0.0.x addresses on lo0                              |
| `adguardhome`     | `enable_adguardhome`     | the resolver: pinned release, seeded config, zones, daemons       |
| `macswitcher`     | `enable_macswitcher`     | seeds `~/.config/macswitcher` and the shell proxy variables       |
| `gcloud`          | `enable_gcloud`          | gcloud components                                                 |
| `ai`              | `enable_ai`              | links `schretzi-skills` into every assistant, assistant configs   |
| `work`            | `enable_work`            | employer profile, supplied by the work overlay                    |

Two helper roles are never run directly: `link` (backup-then-symlink) and
`launchd` (copy or render plist + `bootout`/`bootstrap`).

### Identity and the overlay repositories

This repository is the **public base**: all machinery, no identity. Nothing in
it names a person, an address or an employer. Two private repositories layer on
top:

| Repo     | Setting             | Holds                                                                                 |
| -------- | ------------------- | ------------------------------------------------------------------------------------- |
| this one | —                   | roles, Brewfiles, scripts, plists, shared dotfiles                                    |
| private  | `private_repo_root` | `identity.yml`, personal git/ssh/mail config, gitlab.com instance                     |
| work     | `work_repo_root`    | employer mail account, intranet DNS, work aliases and sessions, work gitlab instances |

Both paths may be empty. **A machine with neither cloned still converges** — it
simply has nothing personal configured, and the mail role reports that it found
no accounts rather than failing.

An overlay mirrors this repo's layout and contributes through an `overlay.yml`
at its root — extra dotfile links, Brewfiles, AdGuard Home zones, mail
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

Run the setup wizard: Wifi, local user, iCloud accounts, Touch ID.

## 2. Homebrew

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

This also pulls in the Xcode Command Line Tools — which is where `git` comes
from — and takes awhile. Then put it on the PATH:

```bash
(echo; echo 'eval "$(/opt/homebrew/bin/brew shellenv)"') >> ~/.zprofile
eval "$(/opt/homebrew/bin/brew shellenv)"
```

> Once `Dotfiles/zsh/.zshrc` is linked it puts `/opt/homebrew/bin` on the PATH
> itself, so `~/.zprofile` only matters for the bootstrap window.

## 3. SSH key

The configuration files in this repo are private, so cloning needs to SSH first. **Each
device and each usage gets its own key, with its own passphrase:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_thishost_github -C "thishost github"
ssh-add --apple-use-keychain ~/.ssh/id_thishost_github
```

Add the public key to GitHub **twice** — once as an authentication key, once as
a _signing_ key — otherwise signed commits show as unverified.

The passphrase prompt is interactive by design, which is why the `ssh` role
only reports missing keys instead of creating them.

## 4. Clone the repo

```bash
mkdir -p ~/Workspace/Schretzi
git clone git@github.com:schretzi/MacbookSetup.git ~/Workspace/Schretzi/MacbookSetup
```

Clone also the Overlay if you want it in one step

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

`~/bin` (personal binaries), `~/tmp` (scratch),
`~/Workspace` (all checkouts). Already on the PATH via `.zshrc`.

_Role: `base_dirs`_

## Homebrew packages

All installs are declarative, split by topic. `Ansible/roles/homebrew/defaults/main.yml`
decides which files are installed — `12_microsoft`, `51_mqtt` and `70_studio`
are off by default.

The Brewfiles pull from third-party taps (koekeishiya, FelixKratz, hashicorp,
saiyam1814, goreleaser, samuong, go-swagger, schretzi). Those execute arbitrary code at
install time — review them before the first run, or drop the entries you do not
want. A tap you have not accepted makes `brew bundle` exit non-zero; the role
keeps going and prints a summary at the end rather than aborting the setup.

### Verifying casks are really installed

`brew bundle` answers _"does Homebrew have a receipt"_, which is not the same
question as _"is the software installed"_. Two ways they diverge:

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

_Role: `homebrew`_

## Dotfiles

Symlinks every live config location back into `Dotfiles/`. The map is in
`Ansible/roles/dotfiles/defaults/main.yml`; add an entry there and it is picked
up on the next run.

Mail configs are a separate list and only linked when `enable_mail` is true.

Neovim is launched as `NVIM_APPNAME=neobean nvim` (see `.zsh/aliases/general`),
so the real config directory is `~/.config/neobean` — there is no `~/.config/nvim`.

_Role: `dotfiles`_

## Shell

`~/.zshrc` and `~/.zsh/` (aliases, completions, functions, rcs) are symlinked.

_Role: `dotfiles`_

## Starship prompt

`~/.config/starship.toml` is symlinked from `Dotfiles/starship/starship.toml`.
It keeps every one of Starship's built-in default modules and styling
(`directory`, `git_branch`, `git_status`, `gcloud`, `character`, ...) via the
`$all` placeholder in `format`, and adds two things Starship doesn't show by
default, on their own second line:

- **`env_var.PROXY_STATE`** — mirrors `PROXY_STATE` from
  `Dotfiles/macswitcher/proxy.zsh`, so an accidentally-left-on proxy is never
  invisible. Three values: `off`, `on`, and `filtered` when privoxy is in the
  path for the active context (see "Filtering proxy"). It describes routing
  as of the last context switch, not liveness — `macswitcher status` probes
  the port for that.
- **`kubernetes`** — the active context from `~/.kube/config` (built by the
  `kubeconfig` role — see Kubernetes below), enabled since it's off by
  default in Starship.

```
MacbookSetup on  main [!] on ☁️
proxy: filtered on ⛵ APL-GCP-2-Staging
❯
```

Only referenced modules move; everything else keeps its default position,
order and color. `$all`/`${env_var.PROXY_STATE}` and friends are Starship's
own [config schema](https://starship.rs/config/) — see there for module docs.

_Role: `dotfiles`_

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

The yabai scripting addition is deliberately _not_ installed — it requires
disabling SIP.

_Role: `windowmanager`_

## Kanata (keyboard remapping)

two requirements:

1. **karabiner drinver** installed already in the manual section
2. **Input Monitoring** for kanata in System Settings.

A third permission is needed for one specific feature: kanata's `cmd` action
(e.g. `^`+d opening today's daily note) runs as **root** via the
`com.kanata.daemon` LaunchDaemon. Without **Full Disk Access** for
`~/.cargo/bin/kanata` in System Settings → Privacy & Security, root can read
its _own_ files fine but macOS's TCC silently denies reads of the
iCloud-backed Obsidian vault - the daily note still gets created with the
right filename, just without its template content (the fallback in
`open-daily-note.sh` swallows the failure instead of erroring). Grant Full
Disk Access to `kanata`, then `kanata_restart` (see `~/.zsh/aliases/general`)
to pick it up.

Ansible then does the rest: it verifies the driver is active and the right
version, builds kanata **from source with the `cmd` feature** (`cargo install
kanata --features cmd` — the Homebrew build lacks it, so it cannot start or
switch applications), installs `com.kanata.daemon` and the Karabiner daemon,
and installs the newsyslog rule that rotates `/Library/Logs/kanata.*.log`.

**Automatic recovery after Bluetooth reconnect**: kanata's macOS backend grabs
every keyboard device once at startup and never rescans - a Bluetooth keyboard
that was absent when `com.kanata.daemon` last started (e.g. worked a day
without it, on-site) stays invisible to kanata even after it reconnects, until
the daemon restarts. `sleepwatcher` (Brewfiles/00_base.brew) plus the
`com.schretzi.kanata-wake` LaunchDaemon (`kanata` Ansible role) now does that
restart automatically on every system wake -
`Scripts/MacOS/kanata_wake_refresh.sh` is sleepwatcher's `-w` callback, waits a
few seconds for Bluetooth to actually reconnect, then runs the same
`launchctl kickstart -k system/com.kanata.daemon` as the manual `kanata_restart`
alias (`~/.zsh/aliases/general`). Runs as root, same as `com.kanata.daemon`, so
no sudo/interactive session is needed. `kanata_restart` still exists for the
immediate case (right after unplugging a cable, or if the wake-triggered
restart lost the race with Bluetooth reconnecting).

CLI to inspect kanata's state directly:
- `kanata --list` - keyboards macOS currently exposes for grabbing (works
  independent of whether the daemon is running).
- `sudo launchctl print system/com.kanata.daemon` - whether the daemon is
  loaded/running and its last exit status.
- `tail -f /Library/Logs/kanata.log` - live log, including
  `virtual_hid_keyboard_ready` and layer-change lines. The former prints about
  once a second and is >99% of the volume; see `etc/newsyslog.d/kanata.conf`
  for why `--quiet` is not the answer.
- `macswitcher observe` lists kanata alongside the other daemons, shows the
  grabbed devices as its status, tails both logs, and can start/stop/restart
  it without a password prompt (the `kanata-service` sudoers rule).

The keymap itself is `Dotfiles/kanata/kanata.kbd`, symlinked to
`~/.config/kanata/`. Keybindings are documented in
[Dotfiles/Keybindings/keybindings.md](Dotfiles/Keybindings/keybindings.md).

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

_Role: `kanata`_

## Git

`~/.gitconfig` and `~/.config/git/` live in `Dotfiles/git/` and are symlinked.
`git config --global` still works — git resolves the symlink before writing, so
edits land in the repo file.

Commit and tag signing use the SSH key, not GPG:

- `gpg.format = ssh`
- `user.signingkey = ~/.ssh/id_thishost.pub`
- `commit.gpgsign = true`
- `gpg.ssh.allowedSignersFile = ~/.ssh/allowed_signers` — needed for
  `git log --show-signature` to verify rather than just display

An `includeIf` on the work checkout directory (`work_workspace_dir`, set by the
work overlay) switches to the work identity for anything cloned there.

The role warns if the signing key is missing — with `commit.gpgsign` on, every
commit would otherwise fail at the worst moment.

_Role: `git`_

## SSH

Private keys are never generated or stored here. The role manages
`~/.ssh/config` (symlinked from `Dotfiles/ssh/config`), enforces `0700` on
`~/.ssh`, and reports which keys are not yet loaded in the agent.

This repo's `Dotfiles/ssh/config` is the **public base only** — generic client
behavior, no key names, no internal/work hostnames:

```
Include ~/.ssh/config.d/*.conf

Host *
    UseKeychain yes
    AddKeysToAgent yes
    ServerAliveInterval 240
    ServerAliveCountMax 3
    SetEnv TERM=xterm-256color
```

`Host *` sets `UseKeychain yes` and `AddKeysToAgent yes`, so a passphrase is
entered once and then comes from the login keychain; it deliberately carries
no `IdentityFile` — SSH always additionally offers whatever keys are already
loaded in the agent, `IdentityFile` here would only matter for a non-default-
named key that also isn't in the agent yet, and per-host blocks below already
name the right key explicitly where needed. `SetEnv TERM=xterm-256color`
overrides kitty's own `TERM=xterm-kitty` for the remote session, since most
remote hosts don't have kitty's terminfo installed; the remote `sshd` must
have `AcceptEnv TERM` (or accept it another way) for this to take effect —
without that, the client sends it but the server silently drops it.

Actual per-host blocks — personal hosts (including `github.com`) and work
hosts alike, each with its own key name — live in the private and work
overlays as `Dotfiles/ssh/config.d/{private,work}.conf`, linked via
`dotfiles_links_overlay` to `~/.ssh/config.d/{private,work}.conf` and pulled
in by the `Include` above. `Include` runs before `Host *` so a specific
block's own settings win over the generic fallback; nothing overlay-specific
ever needs to touch this repo. A machine with neither overlay cloned still
gets a working, if hostname-empty, `~/.ssh/config`.

Public keys trusted for verifying signed commits (`allowed_signers`) follow
the same overlay pattern via `dotfiles_links_overlay` — see the private
overlay's `overlay.yml`.

The role deliberately does **not** run `ssh-add` for you: for a key whose
passphrase is not in the keychain yet, `ssh-add` prompts on the terminal and
would hang the playbook. Run it once by hand:

```bash
ssh-add --apple-use-keychain ~/.ssh/<key>
```

_Role: `ssh`_

## GitLab

Three GitLab instances, none of them named in this repo: gitlab.com (personal),
a private-hosted instance and a SaaS instance, both work's. The role itself
carries no hostnames — it only renders `~/.config/gitlab/instances.yaml` from
`gitlab_instances` and checks that a token is in the keychain for each one.
The private overlay contributes the gitlab.com entry, the work overlay the
other two, each through `gitlab_instances` in its `overlay.yml`:

```yaml
gitlab_instances:
  - name: com # short name used with `gl`
    hostname: gitlab.com
    keychain_service: "glab gitlab.com"
  # api_host: only needed when the API endpoint differs from hostname
```

Store the matching personal access token (`api` scope) once per instance:

```bash
security add-generic-password -s "glab gitlab.com" -a "$USER" -w
```

`glab` itself is repetitive across three hosts — every command otherwise needs
its own `--hostname`. The `gl` shell function (`Dotfiles/zsh/.zsh/functions/
gitlab`) switches the active host for the current shell instead:

```bash
gl -l          # list configured instances
gl com         # glab now targets gitlab.com in this shell
gl             # show which instance is active
```

It reads the token from the keychain at switch time and exports
`GITLAB_HOST`/`GITLAB_API_HOST`/`GITLAB_TOKEN`; nothing is written to disk.

_Role: `gitlab`_

## Kubernetes

Dozens of clusters means dozens of kubeconfigs, and one growing
`~/.kube/config` with every cluster's certs and keys embedded inline becomes
unreadable and hard to audit. Instead, each cluster gets its own directory
under `~/.kube/configs/` holding its extracted `ca.crt`/`client.crt`/
`client.key` and a `config` that references them by full path; `~/.kube/config`
itself is a generated merge of just those `config` files, so it stays small
and secret-free.

The role only creates `~/.kube/configs` (mode `0700`, since it ends up full of
private keys) - it never touches what goes inside it. That is `kubeconfig-add`
and `kubeconfig-merge`'s job (`Dotfiles/zsh/.zsh/functions/kubeconfig`):

```bash
mkdir -p ~/.kube/configs/<name>
mv ~/Downloads/kubeconfig.yaml ~/.kube/configs/<name>/   # the cluster's original download

kubeconfig-add <name>                        # extract ca/cert/key, write config
kubeconfig-add <name> --server host:port     # ... overriding the address (SSH tunnel etc.)
kubeconfig-merge                             # (re)build ~/.kube/config from every configs/*/config
```

`<name>` becomes the cluster, context and user name, so pick something short
and unique - `kubectx`/`kubens` then work as usual against the merged
`~/.kube/config`. The CA cert is always pulled out into its own file when
present; the client certificate/key are too, if the cluster uses cert-based
auth. Clusters using a token, an `exec` plugin or `auth-provider` (OIDC etc.)
have nothing else to extract, so that part of the user entry is copied
through unchanged - still smaller than before since the CA is out of the way.
The original download can sit next to other files (notes, a README) in the
same directory; only the file that actually parses as a kubeconfig is picked
up automatically, and `--source` breaks the tie if more than one does. A
previous `~/.kube/config` is backed up (`config.bak-<timestamp>`) before each
merge, and the active context is preserved across re-merges when it still
exists.

### Switching clusters per shell

`kubectx`/`kubens` switch `current-context` in the merged `~/.kube/config`,
which is shared by every shell - fine day-to-day, but awkward when different
terminals need different clusters at the same time. `kubeconfig-use` instead
points `KUBECONFIG` at one cluster's own `~/.kube/configs/<name>/config` for
the current shell only; nothing is written to disk and other shells are
unaffected.

```bash
kubeconfig-use            # interactive picker: fzf if installed, else a
                           # numbered `select` menu - both just scroll, no
                           # typing required; <TAB> also completes names
kubeconfig-use <name>      # switch straight to <name>
kubeconfig-use -           # unset KUBECONFIG, back to the merged config
```

`kubects` is an alias for `kubeconfig-use` (`kubects <name>`, `kubects -`, ...),
named after `kubectx`/`kubens` for muscle memory.

_Role: `kubeconfig`_

GKE clusters are the exception: they have no cert to extract, and `kubectl`
authenticates live through `gke-gcloud-auth-plugin`, which needs Application
Default Credentials rather than a kubeconfig entry - see Google Cloud ->
"Application Default Credentials" below.

## sudo

Three separate things, all owned by one role so that everything this machine
lets happen as root is auditable in one directory.

### Touch ID

`/etc/pam.d/sudo` opens with `auth include sudo_local`, and on a stock system
that include simply does not exist — Apple ships `sudo_local.template` next to
it as the invitation. The role writes the real file:

```
auth       sufficient     pam_tid.so
```

That is the whole feature. `sufficient` means a fingerprint ends
authentication; every other outcome — no sensor, lid closed, three bad reads,
a caller that cannot prompt — falls through to `pam_opendirectory`, i.e. the
password prompt that was there before. The file cannot lock sudo out, and
being `sudo_local` rather than `sudo` it survives system updates.

**Status on this machine (2026-08-29): it does not actually authenticate.**
The configuration above is correct and is reached — the unified log shows sudo
creating an `LAContext`, requesting `DeviceOwnerAuthenticationWithBiometrics`,
with `BiometryType=1` and `MechanismTouchId` present. But `pam_tid` only ever
makes the _non-interactive_ call (`LACopyResultOfPolicyEvaluation`), gets
`-1004 "User interaction is required"`, and returns **24**
(`PAM_NO_MODULE_DATA`) — a value openpam itself logs as an unexpected return
for `pam_sm_authenticate()`. It never presents a biometric prompt. What
appears instead is authd's `SecurityAgent` panel for
`authenticate-session-owner`, a password field that no fingerprint can answer.

Ruled out by measurement, so nobody repeats it: the terminal (Terminal.app
behaves identically to kitty), tmux/`pam_reattach`, MDM (the machine is not
enrolled), clamshell, remote sessions, enrollment (`bioutil -r` reports
effective), file modes, PAM ordering, a missing module, and a replaced sudo
(`/usr/bin/sudo` sits on the sealed system volume with SIP enabled). Touch ID
for _other_ authorizations works — a System Settings padlock offers it, and
notably does so without ever spawning `SecurityAgent`.

**So the file is not installed** (`sudoers_touchid_enabled: false`). It cannot
lock sudo out — that part holds — but "harmless" was wrong, and measurably so:
Ansible drops sudo's `-n` flag as soon as a become password is supplied, so
under `--ask-become-pass` every `become: true` task runs the full interactive
PAM stack. `pam_tid` engages, fails as described, and authd puts a password
panel on screen — one per root task, dozens in a full `site.yml` run, each
answering nothing because Ansible feeds the real password on stdin anyway.
With `-n` (no become password) `pam_tid` never engages, which is why this
stayed invisible until the first `--ask-become-pass` run.

Everything below still applies and the switch is one line, so this comes back
the day the OS side authenticates.

_Only when it does not work:_ inside tmux or screen the PAM session is
detached from the GUI login session, so `pam_tid` has nowhere to draw its
dialog and Touch ID silently does nothing. `brew install pam-reattach` and
`sudoers_touchid_pam_reattach: true` fixes that. Off by default — kitty is the
only terminal here. It also does not work over SSH, and never will.

### One credential cache, not one per terminal — built, verified, switched off

**This is the piece that would replace `--ask-become-pass`, and it is off
(`sudoers_shared_timestamp: false`) until Touch ID works.** It is documented
here in full because it was built and measured, not guessed at, and turning it
on is a one-line change the day the Touch ID side authenticates.

The obstacle it removes: sudo caches an authentication **per tty** by default,
and Ansible escalates from child processes that have no tty at all. Under that
default, a `sudo -v` typed in a shell does nothing for Ansible, and every
`become: true` task authenticates on its own.

`/etc/sudoers.d/00-timestamp` switches that to one cache per user:

```sudoers
Defaults timestamp_type=global
Defaults timestamp_timeout=20
```

which makes this work:

```bash
sudo -v && ansible-playbook site.yml
```

Verified on this machine: with the rule installed, a credential created in a
terminal was usable from a tty-less process. Ansible's own `sudo` calls carry
`-n` and never prompt — they only ever consume the cache, they cannot fill it,
which is why the priming `sudo -v` is not optional. Without a valid credential
the become tasks fail with `sudo: a password is required` rather than hanging.

Two things measured while getting there, both worth keeping:

- The 20 minutes run from the **authentication**, and a `sudo` that consumes
  the cache does _not_ push the deadline back. So the window has to cover the
  whole stretch from `sudo -v` to the last root task — and site.yml reaches
  its first root task (the `sudoers` role itself) only after `homebrew`, so on
  a cold machine the credential can be gone before Ansible ever needs it.
- The cost is real: for those 20 minutes any process running as this user can
  sudo without authenticating, not just the terminal that did. `sudo -k` drops
  it immediately, everywhere.

That cost buys one Touch ID instead of a typed password. With Touch ID not
authenticating, it would buy one _typed password_ instead of one typed
password — nothing. Hence off.

### Passwordless rules

Individual commands that need no password at all — the ones shell aliases and
runtime tools shell out to — are declared in `roles/sudoers/defaults/main.yml`
as `sudoers_rules`, one file per entry under `/etc/sudoers.d/`, each carrying
the comment that says why it exists. Absolute paths only, no wildcards.
`sudoers_passwordless_enabled: false` removes all of them again.

_Role: `sudoers`_ — needs sudo

## Java

Homebrew installs the JDK under its own prefix, where `/usr/libexec/java_home`
and anything using it (maven, IDEs) cannot find it. The role symlinks every
installed `openjdk*` into `/Library/Java/JavaVirtualMachines/` and then prints
what macOS detects.

_Role: `java`_ — needs sudo

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
two LaunchAgents: `com.schretzi.omt` (keeps tokens fresh) and
`com.schretzi.offlineimap-sync` (syncs every 5 minutes). Both log to
`~/Library/Logs/<name>.log`, rotated by newsyslog. Both are skipped if
`/opt/homebrew/bin/omt` is missing, so the agents do not sit in a failure loop.

`com.schretzi.omt` has no plist in this repo: `omt service install` renders and
loads it from omt's own `internal/service`, the same way macswitcher and
kerberoskeepalive do. See [CONVENTIONS.md](CONVENTIONS.md).

### One account list, five rendered configs

msmtp, notmuch, offlineimap, omt and muttrc each enumerate **every account in a
single line of a single file**. There is no include mechanism in any of them,
which is exactly why they are _rendered_ from one list rather than symlinked —
it is the only way the work account can come from one repository while the
personal accounts come from another.

The list lives in `Ansible/local/identity.yml`:

```yaml
mail_accounts:
  - id: gmail-personal
    sync_order: 10
    address: …
    login: … # differs from address for Workspace aliases
    provider: google # google | o365 | o365-consumers
    backend: Gmail # offlineimap repository type
    mutt_key: "2" # neomutt switch digit - pinned so it never reshuffles
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

Set `enable_mail: false` to skip the whole stack, including the mail dotfiles.

_Role: `mail`_

## DNS — AdGuard Home

I need different DNS routing depending on where I am: home network, local
kubernetes clusters, VMs, VPN. A local resolver answers all of them at once
instead of rewriting resolver settings per network. unbound did that job for
years; AdGuard Home replaced it because it does the same and adds the half
unbound never had — ad, tracker and malware filtering, a query log, per-client
stats.

The role runs the full chain:

1. **Loopback aliases** — _its own role, `localhost_alias`._ mDNSResponder owns
   `127.0.0.1:53`, so the resolver binds another loopback alias: `127.0.0.3`,
   for both DNS and the web UI. `Scripts/MacOS/localhost_alias.sh` is copied to
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

| file           | from                        | holds                                           |
| -------------- | --------------------------- | ----------------------------------------------- |
| `kiac.txt`     | LocalKubernetes, at runtime | cluster and container addresses on the vmnet    |
| `schretzi.txt` | private overlay             | home LAN and private domains                    |
| `work.txt`     | work overlay                | the one intranet name that needs a fixed answer |

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

### DNSSEC — not validated here any more

Be clear about what `enable_dnssec: true` does: AdGuard Home sets the DO/AD bits
towards the upstream and reports whatever AD flag comes back. It does **not**
validate locally the way unbound did with its own trust anchor.

```bash
dig +dnssec @127.0.0.3 cloudflare.com A | grep 'flags:'
#  ... flags: qr rd ra ad;   <- "ad" is Quad9's verdict now, not ours
```

Quad9 validates, so a bogus domain still fails — but the validation happens
there rather than here. That is a real regression against the previous setup and
is deliberately **still an open question**, together with DNS over TLS/HTTPS:
they solve different problems (transport privacy versus answer authenticity) and
neither replaces the other. See `BACKLOG.md`.

One thing the switch removed for free: the `domain-insecure` exemptions. unbound
validated, so every zone forwarded to an internal resolver had to be marked
insecure — `.internal`/`.intranet`/`.local` are not real TLDs, so the signed root
proves they do not exist while the internal resolver answers anyway. With no
local validation there is nothing to exempt, and the work overlay's thirteen
duplicate entries went with it.

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
keeps its own rotation because it holds the fd open) and
`/Library/Logs/adguardhome.err.log` (launchd, rotated by newsyslog). The
documented exception in [CONVENTIONS.md](CONVENTIONS.md).

_Role: `adguardhome`_ — needs sudo

## AI tooling — one set of skills, every assistant

Skills are `SKILL.md` directories on disk.

Each assistant looks in a different place:

| Tool        | Personal skills                                         |
| ----------- | ------------------------------------------------------- |
| Claude      | `~/.claude/skills/`                                     |
| Copilot CLI | `~/.copilot/skills/` or `~/.agents/skills/`             |
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

Conversation content and caches: `~/.claude/projects/`,
`history.jsonl` (every prompt typed), `backups/`, `file-history/`, `sessions/`,
`paste-cache/`, `shell-snapshots/`, `plugins/cache|data|marketplaces/`,
`~/.gemini/google_accounts.json`, `~/.copilot/logs/`, and every `auth.db*`.

## Google Cloud

The SDK comes from `41_clouds.brew`. The role installs the components
(`alpha`, `beta`, `gke-gcloud-auth-plugin`), skipping ones already present.

`gcloud init` needs a browser and stays manual:

```bash
gcloud init
```

_Role: `gcloud`_

### Application Default Credentials (ADC)

`gcloud init`/`gcloud auth login` only authenticate the `gcloud` CLI itself.
Everything else that talks to Google on your behalf — `kubectl` against a GKE
cluster, `gcloud compute start-iap-tunnel`, Terraform's `google` provider, any
Google client library — looks for a separate credential file instead:
**Application Default Credentials**. The `gcloud` role checks for it and
prints a reminder if it's missing, but enabling it is an interactive, manual
step:

```bash
gcloud auth application-default login
```

This opens a browser, and on success writes
`~/.config/gcloud/application_default_credentials.json`. Run it once per
machine (and again if the file is deleted or the login is revoked).

What it's needed for here:

- **Kubernetes access** — `kubectl`/`kubectx` against a GKE cluster added via
  `gcloud container clusters get-credentials` authenticate through the
  `gke-gcloud-auth-plugin`, which reads ADC. Without it, `kubectl` commands
  fail with an auth error even though `gcloud` itself is logged in.
- **Tunneling** — `gcloud compute start-iap-tunnel` (Identity-Aware Proxy
  tunnels, used to reach a private cluster's control plane or a VM with no
  public IP) also authenticates through ADC.

Reference: [Google Cloud — Set up Application Default
Credentials](https://cloud.google.com/docs/authentication/provide-credentials-adc).

### Tunneling (IAP)

Not automated yet — no wrapper script exists here for
`gcloud compute start-iap-tunnel`. Until then, do it by hand:

- **SSH key setup** — the tunnel forwards a local port to a target's SSH port,
  but Google still needs an OS Login SSH key for the target project before
  anything can accept a connection on the other end. Running any
  `gcloud compute ssh` once against the target generates a key pair (if
  needed) and pushes the public key via OS Login; do this before relying on a
  tunnel. See [Google Cloud — Manage OS Login
  keys](https://cloud.google.com/compute/docs/oslogin/manage-oslogin-in-a-project).
- **`/etc/hosts` alias** — the tunnel listens on `localhost`, but whatever is
  configured to use it (a kubeconfig server address, TLS SNI, etc.) may expect
  a real-looking hostname such as `kubernetes` rather than `localhost` /
  `127.0.0.1` for things to resolve correctly. Add the alias once, manually
  (root, since `/etc/hosts` is not writable otherwise):

  ```bash
  echo "127.0.0.1 kubernetes" | sudo tee -a /etc/hosts
  ```

  Not yet wired into the `adguardhome`/`gcloud` roles - a manual, one-time edit
  until the tunnel wrapper script lands.

- **Tunnel connects but the SSH session immediately drops/reconnects** — this
  is almost always a stale or untrusted host key/cert for `localhost:<port>`
  in `~/.ssh/known_hosts`, not a problem with the tunnel itself. Connect
  directly against the forwarded port to see and accept the real prompt:

  ```bash
  ssh -p <port from the tunnel> <gcp-username>@localhost
  # e.g. ssh -p 12022 <gcp_ssh_username>@localhost
  ```

  Accept/refresh the host key there, then retry whatever was using the tunnel.

Reference: [Google Cloud — Use IAP for TCP
forwarding](https://cloud.google.com/iap/docs/using-tcp-forwarding).

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

## Not managed here

- `Dotfiles/github-copilot/auth.db` — holds a live OAuth token, now gitignored
  and no longer versioned. It was committed previously, so it is still in git
  history; revoke and re-authenticate Copilot when convenient.

---

## Trusting locally-generated root CAs (Firefox/Zen)

The machine's own root CA is created and trusted by the `local_ca` role (see
"Local CA"). The command it runs, and the one to use for any other
locally-generated root, is:

```bash
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain <path-to-root_ca.crt>
```

Safari and Chrome (WebKit/Chromium) read the System keychain directly, so that
one command is enough for them. Firefox does not: it ships its own NSS cert
store (`cert9.db`, per-profile) and ignores OS trust settings entirely unless
told otherwise — normally that means a separate `certutil -A` import into
every profile, and doing it again after every new profile.

The `firefox_enterprise_roots` role removes that step. It writes
`Contents/Resources/distribution/policies.json` (Mozilla's
`ImportEnterpriseRoots` enterprise policy) into every installed Firefox-based
browser's `.app` bundle — currently Zen, and anything else in
`roles/firefox_enterprise_roots/defaults/main.yml`. With that policy in
place, the browser reads the System keychain's trusted roots on startup: the
`security add-trusted-cert` command above is then all that is needed for
Safari, Chrome **and** Firefox/Zen alike.

Caveats:

- A cask reinstall that replaces the whole `.app` (rather than updating it in
  place) wipes `policies.json` along with it — re-run
  `ansible-playbook site.yml --tags firefox_enterprise_roots --ask-become-pass`
  after that.
- The policy takes effect on the browser's next restart, not immediately.
- **macOS's App Management privacy protection (Ventura+) blocks this even as
  root.** Writing into another app's `.app` bundle needs the _calling
  process_ — the terminal you run `ansible-playbook` from (Terminal, iTerm,
  Kitty, ...) — to be granted access under **System Settings → Privacy &
  Security → App Management**, in addition to `sudo`/`--ask-become-pass`. A
  failure here shows up as `Operation not permitted [Errno 1]` even though
  the become password was accepted. Enable the toggle for that terminal app
  (add it with **+** if missing), restart it, and re-run the tag.

_Role: `firefox_enterprise_roots`_ — `enable_firefox_enterprise_roots`

---

## macswitcher configuration

_Role: `macswitcher`_ — `enable_macswitcher`

**`config.yaml` and `state.json` are never symlinks, by design.** macswitcher
rewrites both in place on every switch, so linking them back into a repository
means the runtime writes its live values into the source tree — the same trap
`dotfiles_real_dirs` documents and the same one the adguardhome role avoids for
`upstreams.conf`. The role _seeds_ them once (`copy` with `force: false`) and
never touches them again.

**Context files are the exception: they are linked, not seeded.** Switching
does not rewrite them — `saveConfig` is reached only from `config init` — so a
link is safe, and it is what keeps their values in git. Seeding them cost more
than it protected: `force: false` cannot tell "never installed" from
"deliberately deleted", so the superseded `home` context reappeared on every
run, and seeded copies drifted from their repository originals unnoticed.

Where each file comes from:

| File                                                                                                                                   | Source                                        | Notes                                       |
| -------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------- |
| `config.yaml`                                                                                                                          | this repo, `Dotfiles/macswitcher/config.yaml` | generic, no addresses                       |
| `contexts/example.yaml.template`                                                                                                       | this repo, `Dotfiles/macswitcher/contexts/`   | the only seeded context file                |
| `contexts/home-alone.yaml`, `contexts/remote.yaml`, `contexts/no-filter.yaml`, `contexts/full-direct.yaml`                             | private overlay                               | linked via `dotfiles_links_overlay`         |
| `contexts/office.yaml`, `contexts/home-vpn.yaml`, `contexts/vpn-debug.yaml`, `contexts/smartgadget.yaml`, `contexts/remote-vpn.yaml`   | work overlay                                  | same, follows `enable_work`                 |
| `state.json`                                                                                                                           | macswitcher itself                            | never versioned                             |
| `~/.zsh/rcs/proxy`                                                                                                                     | this repo, `Dotfiles/macswitcher/proxy.zsh`   | neutral defaults, then owned by the runtime |

`Dotfiles/macswitcher/proxy.zsh` deliberately does **not** live in
`Dotfiles/zsh/.zsh/rcs/`. That directory is a dotfiles merge dir: every file in
it is force-symlinked into `$HOME`, and there is no per-file exclusion, so
macswitcher would write its runtime proxy values straight back into this repo.

The one context file this repo seeds is `contexts/example.yaml.template` — a
blank context with every key documented, to copy from. Its extension is
`.yaml.template` rather than `.yaml` on purpose: macswitcher loads *every*
`.yaml` in that directory as a context, so a half-filled template would become
a real, switchable context that silently does nothing.

A machine with neither overlay cloned therefore has no contexts at all, and
macswitcher says so (`no context files found`). The role warns about it in the
same run rather than leaving it to be discovered later. That is deliberate: the
previous fallback rendered starter contexts through `macswitcher config init`,
which filled `mac_network_location` from the header line of `scselect` and
produced contexts that could not be switched to.

Each context is a separate `.yaml` file; the global file holds no context
definitions or proxy profiles. Contexts default to `proxy_mode: direct`; an
optional `forwarder_proxy` block enables upstream forwarding.

Environment-specific addresses, names, PAC URLs, Kerberos paths, and proxy
settings belong only in those overlays. Passwords and other secrets are read
from the macOS Keychain and must not be added to any repository.

## Local CA

_Role: `local_ca`_ — `enable_local_ca`

One trust anchor for the whole machine, in `~/.local/share/localca`:

```
root CA  (CN "LocalKubernetes Root CA", ECDSA P-256, CA:TRUE pathlen:1, → 2036)
├── host_intermediate       gitea.kiac, registry.kiac      (LocalKubernetes)
├── main_intermediate       cert-manager ClusterIssuer     (LocalKubernetes)
├── test1_intermediate      per-cluster                    (LocalKubernetes)
└── privoxy_intermediate    HTTPS inspection               (here)
```

**Why it moved out of LocalKubernetes.** The root used to be created by that
repo's `roles/host_ca`, in `~/.local/share/localkubernetes/pki`. But a root CA
the System keychain trusts is a property of the machine, not of a cluster —
and privoxy needs to sign from the same anchor on a machine that may never
have cloned LocalKubernetes. So `local_ca` owns the root, its keychain trust
and the intermediates; `roles/host_ca` now asserts the root exists and issues
only what clusters need.

The old directory is migrated on first run — the keys and certificates are
_moved_, not regenerated. Regenerating would mean re-trusting the root and
re-issuing everything under it, including certificates inside running
clusters. For the same reason the CN still says "LocalKubernetes Root CA":
renaming a CA does not rename it, it creates a different one. The name is a
misnomer now; that is cheaper than the churn.

The role also issues **server certificates** for services that run here and
are reached over HTTPS — currently one, for `lsrules`, which hands Little
Snitch its rule groups (it refuses to subscribe over anything but HTTPS, and
those files describe this machine — see "Little Snitch rule groups"). They are issued
with `step --bundle`, so the `.crt` is leaf + intermediate: an ordinary TLS
server sends that whole chain and the client verifies against the root it
already trusts. `curl https://localhost:8443/…` succeeds with no `--cacert`.

That is the contrast worth keeping in mind next to privoxy, which can only
send a leaf and therefore needs its intermediate trusted separately.

Intermediates and server certificates are declared in `group_vars/all.yml`:

```yaml
local_ca_intermediates:
  - name: privoxy
    common_name: Privoxy HTTPS Inspection CA
    trust_as_root: true
```

`trust_as_root` imports it with `security add-trusted-cert -r trustAsRoot`.
Needed only where a consumer sends leaves without their chain — privoxy does
exactly that, see the section below.

**The root key is plaintext on disk** (`--no-password --insecure`, as it
always was). LocalKubernetes' `PLAN.md` §6 wants it age/sops-encrypted at
rest, and that requirement came along with the root. It matters more here than
it did there: this key is now also the anchor for a proxy that can mint a
certificate for any site.

```yaml
local_ca_server_certs:
  - name: lsrules
    common_name: localhost
    issuer: services
    sans: [localhost, 127.0.0.1]
```

```sh
ls -la ~/.local/share/localca                       # 0700, keys 0600
security verify-cert -c ~/.local/share/localca/root_ca.crt
security find-certificate -c "Privoxy HTTPS Inspection CA" /Library/Keychains/System.keychain
```

Note that `verify-cert` on an _intermediate_ proves nothing about the
keychain: it chains the file it is handed up to the trusted root and reports
success either way. Use `find-certificate` for intermediates.

## Little Snitch rule groups — lsrules

_Role: `lsrules`_ — `enable_lsrules`

Little Snitch subscribes to a rule group by URL, keeps it in sync, and refuses
anything but HTTPS. The rule groups live in the `LittleSnitchConfig`
repository and describe what runs on this machine, which is an argument
against publishing them — so `lsrules` serves them from it:

```
LittleSnitchConfig/rules/*.lsrules
   └─ lsrules (com.schretzi.lsrules) on https://localhost:8443/
        └─ Little Snitch subscription
```

The certificate is the `lsrules` server certificate from the `local_ca` role
(see "Local CA"). Because an ordinary TLS server sends leaf **and**
intermediate, the client chains up to the root the System keychain already
trusts — `curl https://localhost:8443/…` verifies with no `--cacert`.

The binary is `brew install schretzi/tap/lsrules`
([LittleSnitchRules](https://github.com/schretzi/LittleSnitchRules)); the role
owns only what brew does not — the LaunchAgent and log rotation — exactly like
`kerberoskeepalive` and `omt`.

**A `brew upgrade` removes the launch agent.** The cask's uninstall preflight
runs `lsrules service uninstall` before replacing the binary, so the job is
gone until `lsrules service install` runs again. The next play run does it;
`macswitcher observe` is where you would notice in the meantime.

### Checks

```sh
lsrules status                # served groups, TLS probe, certificate expiry
lsrules status --json         # the same, as macswitcher's observe reads it
tail -f ~/Library/Logs/lsrules.log
```

A live subscription shows up as a fetch followed by conditional requests:

```
2026-08-31T07:10:35+02:00 127.0.0.1 "GET /proxy-chain.lsrules" 200 1478 342µs
2026-08-31T07:11:02+02:00 127.0.0.1 "HEAD /proxy-chain.lsrules" 304 0 340µs
```

The 304 is the point: a one-time import never asks again, so that line is what
distinguishes a subscription from an import.

**Nothing renews the certificate.** `local_ca` issues it for a year;
`lsrules status` and the `observe` row warn 30 days out, and after that
subscriptions fail rather than degrade.

## Filtering proxy — privoxy

_Role: `privoxy`_ — `enable_privoxy`

URL filtering for the networks where nobody else does it. On a corporate
network the company proxy already filters; at home, alpaca went straight out.
This closes that gap without changing which contexts use which path:

```
browser / CLI  ->  alpaca 127.0.0.1:3128  ->  privoxy 127.0.0.1:8118  ->  internet
                                    (proxy_mode: direct only)

browser / CLI  ->  alpaca 127.0.0.1:3128  ->  corporate proxy
                                    (proxy_mode: forward — privoxy not in the path)
```

### How alpaca is made to forward

alpaca has no "always use this upstream" flag — `-C <pac>` is its only way to
choose one. macswitcher therefore owns this: a `filter_proxy` block in
`config.yaml` generates the PAC and starts alpaca with it, for any context
whose `proxy_mode` is `direct`.

```yaml
filter_proxy:
  enabled: true
  host: 127.0.0.1
  port: 8118
  fail_open: true
  direct: [.kiac, .ts.net]
```

The generated file lands in `~/.local/state/macswitcher/filter.pac` — state,
rewritten on every switch, safe to delete. It is generated rather than
hand-written because its local-network exceptions have to agree with
`local_proxy.no_proxy`, and two hand-maintained copies of that list drift
apart. `macswitcher status` gained a `filter_proxy:` line, `observe` a
`privoxy` row, and `config validate` warns when the block is enabled but
nothing answers on the port.

**The trailing `DIRECT` is a deliberate fail-open.** privoxy down means
unfiltered browsing, not a dead network. That would be silent on its own, so
`macswitcher status` probes the port and says
`NOT LISTENING - traffic is going out unfiltered (fail_open)` when it is. Everything local — plain hostnames,
`.kiac`, `.local`, `.ts.net`, RFC1918 and CGNAT literals — returns `DIRECT`
before that line is reached, and no branch calls `dnsResolve()`, so evaluating
the PAC never costs a lookup.

### It has to be the tap build

`brew install privoxy` from homebrew-core is **not** enough. That formula
configures without `--with-openssl`, so `FEATURE_HTTPS_INSPECTION` is compiled
out (`otool -L` shows no TLS library at all) and privoxy answers every `ca-*`
directive with

```
Error: Ignoring unrecognized directive 'ca-directory ...'
```

and then runs happily, filtering nothing but plain HTTP. A proxy that silently
does not inspect looks exactly like one that does, so the role asserts on the
linked libraries rather than warning. `schretzi/tap/privoxy` is core's formula
plus `openssl@3`, `--with-openssl` and `--enable-extended-statistics`.

### HTTPS inspection, and what it costs

Without inspection privoxy sees only `CONNECT host:443` — host-level blocking,
which AdGuard Home already does at the DNS layer. Inspection is what makes URL
_paths_ filterable on HTTPS, and it works by privoxy terminating TLS with a
certificate it mints from a local CA.

That certificate comes from **this machine's own CA**, not from a private root
of privoxy's own — see "Local CA" below. privoxy gets an intermediate
(`privoxy_intermediate`, CN `Privoxy HTTPS Inspection CA`) and never touches
the root key.

The intermediate has to be trusted in the System keychain in its own right,
which looks redundant next to an already-trusted root and is not. privoxy
sends **only the leaf** — `openssl.c:788` uses `SSL_CTX_use_certificate_file`
and never `add_extra_chain_cert` — so the client never receives the
intermediate and cannot build a chain to the root itself. Measured on this
machine: a leaf signed by the intermediate and presented alone fails with
`CSSMERR_TP_NOT_TRUSTED` until the intermediate is imported. The `local_ca`
role imports it with `-r trustAsRoot`.

Safari, Chrome and macOS `curl` (SecureTransport) follow the System keychain;
Firefox and Zen do too, through the `firefox_enterprise_roots` role.

What breaks, and where the escape hatch is:

- **Certificate-pinned clients** — Apple services, Microsoft 365, Dropbox,
  Signal, Tailscale, banking apps. They compare against a shipped key, not the
  machine's trust store, so inspection fails them. `user.action` carries a
  `{-https-inspection}` list; add to it when something works only with the
  proxy out of the path.
- **Anything with its own trust store** — Java's `cacerts`, some Go and Python
  programs. Trusting the CA in the keychain does not reach them.

privoxy is also the TLS _client_ once inspecting, and it does not read the
keychain: with no `trusted-cas-file` at all,
`SSL_CTX_load_verify_locations(NULL, NULL)` fails and every HTTPS connection
dies (`openssl.c:1036`). The role therefore assembles
`~/.local/state/privoxy/trusted-cas.pem` from Homebrew's `ca-certificates`
plus this machine's keychain roots, so locally-signed hosts keep working
through the proxy.

### Files

| Path                                            | Owner                   | Notes                                                                          |
| ----------------------------------------------- | ----------------------- | ------------------------------------------------------------------------------ |
| `~/.config/privoxy/config`                      | this repo (`config.j2`) | templated with force — privoxy never writes it                                 |
| `~/.config/privoxy/user.action`                 | this repo               | inspection defaults, pinning exceptions, blocks                                |
| `~/.config/privoxy/user.filter`                 | this repo               | empty; `config` references it                                                  |
| `~/.local/share/localca/privoxy_intermediate.*` | `local_ca` role         | `0600`, shared PKI, never in git                                               |
| `~/.local/state/privoxy/certs/`                 | privoxy                 | per-site certs, safe to delete                                                 |
| `~/.local/state/privoxy/trusted-cas.pem`        | the role                | regenerated every run                                                          |
| `~/.local/state/macswitcher/filter.pac`         | macswitcher             | what alpaca is pointed at — `filter_proxy` generates it, this repo owns no PAC |

Opposite of the macswitcher role directly above: nothing here is
runtime-owned, so everything is templated with force.

### Logging deviates, on purpose

There is no `privoxy.err.log`, and `privoxy.log` is launchd's
`StandardErrorPath`. privoxy logs everything to stderr, and its own `logfile`
directive is honoured only when it daemonises (`loadcfg.c:1508`), which it
cannot do under launchd. Rotation therefore restarts it: `newsyslog` renames
the log, signals 15 to the pid from `--pidfile`, and `KeepAlive` brings it
back against the new file within a second.

`debug` is set to blocks (1024), startup (4096) and errors (8192).
Deliberately **not** `debug 1`, which logs the destination of every request
and turns the log into a browsing history on disk.

That rules out the usual way of getting numbers out of privoxy.
`privoxy-log-parser --statistics` (shipped by the formula) reads `LOG_LEVEL_CLF`
lines, so it needs `debug 512` — the same browsing history under another name,
and one that rotation makes _worse_ rather than better: the statistics window is
whatever is still on disk, so useful numbers mean deliberately keeping five
generations of every URL visited.

The tap build therefore passes `--enable-extended-statistics` instead, and the
counters live in memory. They are keyed by the block reason from the action file
(`filters.c:645`) and by filter name (`filters.c:1791`) — never by URL or host —
which answers "which rule is actually firing" without any of it being written
down. The cost is that they reset on every restart, including the one rotation
performs; at block-only logging the 5 MB threshold is rare enough that this
means "since the last reboot".

### Integration state

In macswitcher since 0.3.0: the `filter_proxy` block above, a `filter_proxy:`
line in `status` that probes the port rather than reporting what the config
intends, a `privoxy` row in `observe` directly under alpaca, and
`config validate` warnings when the filter is in the path with nothing
listening — or when a context still names its own PAC through
`alpaca.command`, which is the wiring this replaced.

Still open, outside macswitcher:

- **Little Snitch sees one process, not the app behind it.** Outbound traffic
  now leaves as `privoxy`, so proxied connections can no longer be attributed
  to the app that caused them — one allow rule for privoxy replaces the
  per-app decision for everything that goes through it. privoxy runs under
  launchd and connects as itself, so that is a single rule, not a wave of new
  prompts. `LittleSnitchConfig` carries it as `rules/proxy-chain.lsrules`.
- **`docs/networking-tools.md` does not mention it.** That page is the
  self-contained install guide for the three CLIs; privoxy is a fourth moving
  part in the same chain.

### Checks

```sh
launchctl print gui/$(id -u)/com.schretzi.privoxy | grep state
curl -x 127.0.0.1:8118 -s -o /dev/null -w '%{http_code}\n' http://example.com/
curl -x 127.0.0.1:3128 -sv https://example.com/ 2>&1 | grep -i issuer   # via alpaca
tail -f ~/Library/Logs/privoxy.log                                      # blocks land here
```

The status page at <http://config.privoxy.org/show-status> (through the proxy)
lists the compiled-in features, every action file it loaded, and the three
statistics tables — block rate, count per block reason, count per filter. It is
reachable only _through_ the proxy; `http://127.0.0.1:8118/` answers 400.
`/show-url-info` is the one to use when a `user.action` rule does not do what it
looks like it should: it says which actions apply to a URL and which file set
them.

**Little Snitch has to allow it.** privoxy is a new binary making outbound
connections on behalf of everything else; until it has a rule, requests sit
for 30 s and then fail with `No server or forwarder response received`. The
30 s is not configurable — privoxy's connect timeout is hardcoded
(`jbsockets.c:382`).

## Reference

- [Mutt / notmuch / offlineimap introduction](https://bascht.com/blog/2014/05/28/einstieg-in-mutt-notmuch-offlineimap/)
- [Mutt password management](https://wiki.archlinux.org/title/Mutt#Passwords_management)
- [offlineimap config examples](https://www.offlineimap.org/doc/conf_examples.html)
- [YubiKey guide](https://github.com/drduh/YubiKey-Guide)
- [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
- [DisplayLink macOS driver (Synaptics)](https://www.synaptics.com/products/displaylink-graphics/downloads/macos)

## Improvment Ideas

- □ When session-kitty stopped focus goes to finder, I want the last active session to get the focus
- □ Tunneling script modernization
- □ Work configs into overlay and search for repo to push
- □ Regularly vulnerability check and how to keep track of my project status
- □ ssh config - now everything is one big file combined private and work,
  need to adapt and split
- □ look into checkmate.nvim (https://github.com/bngarren/checkmate.nvim)
