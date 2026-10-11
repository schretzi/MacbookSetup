---
created: 2026-09-06
type: unsorted
---

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

### Little Snitch — see [docs/investigations/little-snitch.md](docs/investigations/little-snitch.md)

> [!IMPORTANT]
> Hostbased Firewalls are a great tool to improve security, but skip this if you don't have or plan to have a license for it.

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

### DisplayLink (docks) — see [docs/investigations/displaylink.md](docs/investigations/displaylink.md)

Docks that drive external displays over USB need Synaptics' driver, and there is
no cask for it — download DisplayLink Manager by hand:
<https://www.synaptics.com/products/displaylink-graphics/downloads/macos>

It then needs **Screen & System Audio Recording** permission (the pane older
notes still call _Screen Recording_), granted in **System Settings → Privacy &
Security** — it captures the desktop to push those pixels over USB. Without it
the external screens stay black.

### Karabiner DriverKit VirtualHIDDevice — see [docs/investigations/karabiner-driverkit.md](docs/investigations/karabiner-driverkit.md)

### MacFUSE

- [ ] Add macfuse und rclone instructions

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

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_thishost_gitlab -C "thishost gitlab"
ssh-add --apple-use-keychain ~/.ssh/id_thishost_gitlab
```

Add the public key to Gitlab **twice** — once as an authentication key, once as
a _signing_ key — otherwise signed commits show as unverified.

The passphrase prompt is interactive by design, which is why the `ssh` role
only reports missing keys instead of creating them.

## 4. Clone the repo

```bash
mkdir -p ~/Workspace/Schretzi
git clone git@github.com:schretzi/MacbookSetup.git ~/Workspace/Schretzi/MacbookSetup
```

Clone also the Overlays if you want it in one step

## 5. Minimum tooling for Ansible

`35_python.brew` installs Ansible itself, `31_rust.brew` is needed to build
kanata:

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Brewfiles
brew bundle install --file=35_python.brew
brew bundle install --file=31_rust.brew
```

From here on, run the playbook.

## 6. Travel machine — the Intel MacBook Air

The company M5 may not travel abroad, so the old MacBook Air (MacBookAir7,2,
stuck on macOS 12) carries the personal part of the setup: shell, kitty,
neobean, Zen and the mail stack. `Ansible/profiles/travel.yml` selects exactly
that; everything work, Apple Silicon only or root-level is switched off there.

The constraint behind every choice in that profile: **macOS 12 on Intel is a
Homebrew Tier 3 configuration with no bottles.** Every formula that is not
already installed is built from source, and anything Rust- or Python-based
drags a whole toolchain in with it. Hence:

- `Brewfiles/90_travel.brew` is the Air's only Brewfile, and lists only what is
  already installed or cheap to build. Its header names what is missing and
  what replaces it.
- neovim comes from the official release tarball (`neovim_release` role,
  `~/.local/bin/nvim`), not from Homebrew. Remove an old Homebrew neovim
  (`brew uninstall neovim`) so it does not sit next to it on PATH.
- Ansible and uv come from uv's standalone installer, not from Homebrew:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh     # -> ~/.local/bin/uv
~/.local/bin/uv tool install ansible-core           # -> ~/.local/bin/ansible-playbook
```

Budget time for the second line: `cryptography` has no wheel for macOS 12 on
Intel either, so uv fetches a Rust toolchain and compiles it - about 45
minutes on the Air.

Then, with the private overlay cloned next to the repo as usual:

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Ansible
export ANSIBLE_BECOME_ASK_PASS=false
ansible-playbook site.yml -e @profiles/travel.yml --check
ansible-playbook site.yml -e @profiles/travel.yml
```

No become password is needed - no role in the profile escalates - but
`ansible.cfg` sets `become_ask_pass = True` for the full machine, hence the
environment override. Still
manual on the Air, as on any new machine: the SSH key (step 3), the OAuth
client credentials in the keychain (`Scripts/omt-oauth-keychain.sh store`),
and the first `omt` authorisation per account.

The notes vault cannot come over the M5's WebDAV mount: on the road the Air
is often offline. The `notes_sync` role keeps a real local copy in
`~/Notes/Brain` instead, synced with Nextcloud by `Scripts/notes-sync.sh`
(rclone bisync) every ten minutes from a LaunchAgent, and links it as
`~/Brain/Private` - where the M5 links its mount. It needs a Nextcloud
app password in the login keychain under the name in
`notes_sync_keychain_name`; the role does the first `--resync` itself.

Paths that used to say `/opt/homebrew` work on both machines now:
`homebrew_prefix` follows the architecture, plists that name a Homebrew
binary are `.j2` templates, and everything that starts neovim goes through
`Dotfiles/neobean/bin/neobean`, which knows where each machine keeps `nvim`.

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
ansible-playbook site.yml --skip-tags mail,unbound   # everything except these
ansible-playbook site.yml --tags mail -e enable_mail=true   # force a disabled topic
```

`--ask-become-pass` is only needed for the roles that touch root-owned
locations: `sudoers`, `localhost_alias`, `unbound`, `java`, `kanata`,
`firefox_enterprise_roots`. There is a way to authenticate once up front
instead — see [sudo](#sudo) below — but it is switched off until Touch ID for
sudo works.

| Role / tag            | Switch                       | What it does                                                                 |
| --------------------- | ---------------------------- | ---------------------------------------------------------------------------- |
| `base_dirs`           | `enable_base_dirs`           | `~/bin`, `~/tmp`, `~/Workspace`                                              |
| `homebrew`            | `enable_homebrew`            | `brew bundle` per Brewfile, each file individually toggleable                |
| `dotfiles`            | `enable_dotfiles`            | symlinks `~/.config/*` and the home dotfiles into `Dotfiles/`                |
| `git`                 | `enable_git`                 | links the shared git ignore file, checks the signing key                     |
| `ssh`                 | `enable_ssh`                 | links `~/.ssh/config`, fixes permissions                                     |
| `gitlab`              | `enable_gitlab`              | renders instance list for `gl`, checks tokens are in the keychain            |
| `kubeconfig`          | `enable_kubeconfig`          | creates `~/.kube/configs` for `kubeconfig-add`/`kubeconfig-merge`            |
| `sudoers`             | `enable_sudoers`             | Touch ID for sudo, the shared credential cache, NOPASSWD rules               |
| `java`                | `enable_java`                | links the Homebrew JDKs into `/Library/Java/JavaVirtualMachines`             |
| `kanata`              | `enable_kanata`              | builds kanata with `cmd`, installs both daemons + log rotation               |
| `windowmanager`       | `enable_windowmanager`       | yabai + skhd LaunchAgents                                                    |
| `statusbar`           | `enable_statusbar`           | sketchybar LaunchAgent: desktop strip + gtt running-timer widget             |
| `mail`                | `enable_mail`                | maildir, notmuch index, offlineimap/omt agents, mail dotfiles                |
| `localhost_alias`     | `enable_localhost_alias`     | the extra 127.0.0.x addresses on lo0                                         |
| `unbound`             | `enable_unbound`             | the resolver: brew service, unbound.conf, zones, overlays                    |
| `macswitcher`         | `enable_macswitcher`         | seeds `~/.config/macswitcher` and the shell proxy variables                  |
| `container_autostart` | `enable_container_autostart` | restarts the container runtime, service containers and `main`, refreshes DNS |
| `gcloud`              | `enable_gcloud`              | gcloud components                                                            |
| `ai`                  | `enable_ai`                  | links `schretzi-skills` into every assistant, assistant configs              |
| `work`                | `enable_work`                | employer profile, supplied by the work overlay                               |

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
at its root — extra dotfile links, Brewfiles, unbound zones, mail
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

---

# What Ansible does, topic by topic

## User directories

`~/bin` (personal binaries), `~/tmp` (scratch),
`~/Workspace` (all checkouts). Already on the PATH via `.zshrc`.

_Role: `base_dirs`_
_Ansible Tag: enable_base_dirs_

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
_Ansible Tag: enable_homebrew_

## Dotfiles

Symlinks every live config location back into `Dotfiles/`. The map is in
`Ansible/roles/dotfiles/defaults/main.yml`; add an entry there and it is picked
up on the next run.

Mail configs are a separate list and only linked when `enable_mail` is true.

Neovim is launched as `NVIM_APPNAME=neobean nvim` (see `.zsh/aliases/general`),
so the real config directory is `~/.config/neobean` — there is no `~/.config/nvim`.

_Role: `dotfiles`_
_Ansible Tag: enable_dotfiles_

## Shell

`~/.zshrc` and `~/.zsh/` (aliases, completions, functions, rcs) are symlinked.

_Role: `dotfiles`_
_Ansible Tag: enable_dotfiles_

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
_Ansible Tag: enable_dotfiles_

## Terminal environment

- **kitty** — terminal emulator; sessions and scripts under `Dotfiles/kitty/`
- **yabai** — tiling window manager
- **skhd** — hotkeys for yabai
- **sketchybar** — status bar: desktops + gtt running timer, see below
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
_Ansible Tag: enable_windowmanager_

### sketchybar

`Dotfiles/sketchybar/` — pure bash + `jq`, no Lua/SbarLua. Left to right:

- **desktops** — `space.desk1`..`space.desk10`, statically grouped into the
  three physical displays yabairc documents (MacBook screen, Left, Right
  external), with a monitor-glyph divider between each group. The focused
  space gets a highlighted background; every space's label shows one icon per
  app open on it (via the vendored `helpers/icon_map.sh` and
  `font-sketchybar-app-font`, see below), so both "which space is active" and
  "what's open where" are visible at a glance without opening Mission Control.
  `plugins/spaces.sh` rebuilds all ten from two `yabai -m query` calls at once,
  triggered by the `yabai -m signal` block added to `Dotfiles/yabai/yabairc`
  (window/space/display changes all fire the same custom
  `space_windows_change` event) — it does not use sketchybar's built-in
  `--add space`, because that binds to yabai's space *index*, which Mission
  Control silently renumbers across displays; the desk<N> *label* is what
  stays stable.
- **front_app** — frontmost app name.
- **gtt** — the [gtt](https://github.com/schretzi/gtt) running time entry:
  client · project/task · elapsed, polled every 5s (`plugins/gtt.sh`). Name
  lookups (client/project/task IDs → names) are cached in
  `~/.local/state/sketchybar-gtt/` and only refetched when the running
  entry's IDs change, so steady-state polling is a single `gtt current --json`
  call. Click opens `gtt tui` in a new kitty window. Shows "no timer" when
  nothing is running.
- **clock**.

Started from `homebrew.mxcl.sketchybar.plist` — the same LaunchAgent label and
plist the `sketchybar` Homebrew formula itself ships (`brew info sketchybar`'s
caveats), unmodified: `homebrew.mxcl.*` is one of the CONVENTIONS.md
exceptions, same as yabai/skhd next to it.

**Multi-display / native menu bar:** the bar runs `topmost=on` so it draws
above macOS's own menu bar instead of being overlapped by it on external
(non-notch) displays — without this, an external display's own native menu
bar renders at the same position and both become unreadable, while the
MacBook's notched display happens to look fine either way. This does hide the
real Apple/File/Edit menu visually (it's still there, just covered). Press
`hyper - b` (skhdrc) to toggle sketchybar's visibility and reveal the native
menu bar on demand instead of relying on macOS's "automatically hide menu
bar" hover gesture, which doesn't trigger reliably through a topmost bar.
`yabairc`'s `external_bar all:32:0` reserves matching space so windows aren't
drawn under the bar on any display.

_Role: `statusbar`_
_Ansible Tag: enable_statusbar_

## Kanata (keyboard remapping) — see [docs/investigations/kanata.md](docs/investigations/kanata.md)

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
_Ansible Tag: enable_git_

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
_Ansible Tag: enable_ssh_

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
_Ansible Tag: enable_gitlab_

## Kubernetes — see [docs/investigations/kubernetes.md](docs/investigations/kubernetes.md)

## sudo

Three separate things, all owned by one role so that everything this machine
lets happen as root is auditable in one directory.

- **Touch ID & Credential Caching**: Technical deep-dives on current status and caveats. [See investigation](docs/investigations/sudo-touchid.md).
- **Passwordless rules**: Individual commands that need no password at all — the ones shell aliases and
  runtime tools shell out to — are declared in `roles/sudoers/defaults/main.yml` as `sudoers_rules`, one
  file per entry under `/etc/sudoers.d/`, each carrying the comment that says why it exists. Absolute
  paths only, no wildcards. `sudoers_passwordless_enabled: false` removes all of them again.

_Role: `sudoers`_ — needs sudo
_Ansible Tag: enable_sudoers_

## Java

Homebrew installs the JDK under its own prefix, where `/usr/libexec/java_home`
and anything using it (maven, IDEs) cannot find it. The role symlinks every
installed `openjdk*` into `/Library/Java/JavaVirtualMachines/` and then prints
what macOS detects.

_Role: `java`_ — needs sudo
_Ansible Tag: enable_java_

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

### Bulk triage macros — one file per overlay

Two neomutt macros sweep the mailboxes: **F9** bulk-deletes work noise, **F10**
files personal receipts into `=Belege` and deletes the rest. Both name
individual senders, so neither can live in this public repository. Each comes
from the overlay that owns those senders:

| File                           | Overlay | Key |
| ------------------------------ | ------- | --- |
| `bulk-handling-work.muttrc`    | work    | F9  |
| `bulk-handling-private.muttrc` | private | F10 |

`neo.muttrc` sources each through a guarded `source` that echoes `/dev/null`
when the file is absent, so a machine with only one overlay binds only that
key and one with neither binds nothing — without an error either way.

Two traps are worth recording, because both fail silently:

- **The names must differ per overlay.** Both overlays link into the same
  `~/.config/mutt`, so one shared filename would let whichever ran last win and
  quietly replace the other's macro.
- **The link must be declared by the overlay, not by `mail_mutt_static_files`.**
  That list is linked from `repo_root`, always this repository. A macro listed
  there resolves to a base path that never holds it, and the `[ -r $f ]` guard
  turns the resulting dangling symlink into a no-op — the macros just never
  load, with nothing reported. That is exactly how F9/F10 sat broken.

Under kanata the F-row is media keys on a bare press, so these are reached with
**Shift+F9 / Shift+F10** or `^`+F9 / `^`+F10 — see
[`Dotfiles/Keybindings/kanata.md`](Dotfiles/Keybindings/kanata.md).

Set `enable_mail: false` to skip the whole stack, including the mail dotfiles.

_Role: `mail`_
_Ansible Tag: enable_mail_

## DNS — unbound — see [docs/investigations/unbound-dns.md](docs/investigations/unbound-dns.md)

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

### Local models — ollama, goose and opencode

> [!WARNING]
> this is work in progress, still testing different tools and models. Probably next steps are vLLM for hosting models and llm.nvim

LM Studio and ollama do **not** share models, and the reason is format, not
configuration. Everything LM Studio downloaded here is MLX — Apple-silicon
`.safetensors` quantised with MLX's own affine scheme. ollama runs llama.cpp
and reads GGUF. It cannot load MLX in any form, and its `FROM <safetensors>`
path only takes _unquantised_ fp16/bf16 weights, so a 4-bit MLX directory is
rejected there too. Converting locally is not worth it either: de-quantising
4-bit back to fp16 and re-quantising to GGUF loses more than downloading a
GGUF built from the original weights.

So `Scripts/ollama-import-model.sh` imports a GGUF straight from LM Studio's
directory, and for an MLX model it finds the matching GGUF build of the _same_
release and pulls that instead:

```bash
Scripts/ollama-import-model.sh --list          # format of every LM Studio model
Scripts/ollama-import-model.sh --pull --name devstral:32k Devstral-Small-2
```

The two model sets are independent copies. LM Studio does **not** need to be
running for any of this — nothing in this path talks to port 1234.

#### The tag carries the context, because not every client can set it

A `PARAMETER num_ctx` in the ollama model is only a _default_, and whether a
client can override it depends on which endpoint it speaks to:

| client   | endpoint                | can send num_ctx?           | context declared in          |
| -------- | ----------------------- | --------------------------- | ---------------------------- |
| goose    | ollama native           | yes, as `GOOSE_INPUT_LIMIT` | `Dotfiles/goose/config.yaml` |
| opencode | OpenAI-compatible `/v1` | no such field               | `limit.context`              |

That asymmetry is why the tags are named for their window — `devstral:32k`,
`:64k`, `:128k`. For opencode the tag _is_ the setting; for goose it is the
default that the client then has to agree with.

Both failure modes are silent. A client that declares more than the model was
built with does not get an error: llama.cpp truncates the over-long prompt, so
context is quietly dropped instead. Measured on a fresh goose session before
this was set: goose reported `13k/128k` while ollama had the model loaded at
32768, because `GOOSE_CONTEXT_LIMIT` defaults to 128000 for a model it does
not recognise.

#### Context size and what it costs

The KV cache is 81920 elements per token (40 layers x 8 KV heads x 128 dim,
K and V). The LaunchAgent's `OLLAMA_KV_CACHE_TYPE=q8_0` and
`OLLAMA_FLASH_ATTENTION=1` nearly halve it against f16:

| ctx  | KV cache (q8_0) | resident with 24B Q4_K_M              |
| ---- | --------------- | ------------------------------------- |
| 32k  | 2.85 GB         | ~18.7 GB                              |
| 64k  | 5.70 GB         | ~21.5 GB                              |
| 128k | 11.4 GB         | ~27.2 GB                              |
| 256k | 22.8 GB         | ~38.6 GB — over the default GPU limit |

`iogpu.wired_limit_mb` is 0, which on 48 GB means roughly 36 GB available to
Metal, so 128k is the practical ceiling. llama.cpp allocates the whole KV
cache **at load time**, so a 128k tag holds 27 GB resident for the entire
`OLLAMA_KEEP_ALIVE` window even for a two-line prompt — which is the cost the
RunAtLoad=false plist exists to avoid. Hence 32k as the default, with larger
tags created for when a job actually needs them. Extra tags are free on disk:
ollama shares the weights blob and only the Modelfile differs.

```bash
ollama_service start                    # the agent never starts itself
goose session                           # ~/.config/goose/config.yaml picks the model
```

To use a bigger window, point the client at `devstral:64k` or `devstral:128k`
and move its declared context to match in the same commit — the two numbers
are a pair, and splitting them is the silent failure above.

#### goose

`Dotfiles/goose/config.yaml`. goose has a first-class ollama provider, so
there is no compatibility shim, no API key, and nothing for it in
`~/.zsh/rcs/ca` — a model call never leaves the loopback.

Three settings are not defaults and each is deliberate:

- `GOOSE_CONTEXT_LIMIT` — goose's own budgeting number, i.e. when it compacts.
- `GOOSE_INPUT_LIMIT` — mapped onto ollama's `num_ctx` on the wire.
- `GOOSE_MODE: smart_approve` — goose defaults to `auto`, which executes tool
  calls without asking. That is a reasonable default for a frontier model and a
  poor one for a 24B with shell access: `goose doctor` on this very setup
  produced a confidently invented `go install github.com/AAIF/goose@latest`.
  `smart_approve` lets read-only calls through and asks before anything with
  consequences.

`goose configure` rewrites the config in place and follows the symlink, so an
interactive reconfigure edits the repo copy rather than detaching it.

#### opencode against the same model

`Dotfiles/opencode/opencode.json` points opencode at the same ollama tag. It
is JSONC — the config schema sets `allowComments`, so the file is commented
like everything else here.

The transport is the thing that matters here. opencode drives
ollama through `@ai-sdk/openai-compatible` against `/v1`, the OpenAI-shaped
endpoint, which **has no `num_ctx` field**. So opencode cannot set the context
window at all — it inherits whatever the Modelfile baked in. opencode's own
docs say as much sideways ("if tool calls aren't working, try increasing
num_ctx in Ollama"), and it is the reason the tags are named for their
context: with opencode the tag _is_ the setting.

`limit.context` in the config therefore has to match the tag, since opencode
uses that number to decide when to compact a session rather than discovering
it from the server. `small_model` is pinned to the same model so session
titles do not quietly reach for a cloud provider.

Tool calling is hungry — the system prompt and tool definitions are resident
in every request — so 32k is tight for an agentic loop. `devstral:64k` is the
first thing to try if tool calls start failing.

##### It needs a CA bundle to install its provider package

opencode fetches `@ai-sdk/openai-compatible` from npm on first use, and its
runtime carries its own trust store — the case "Anything with its own trust
store" warns about under HTTPS inspection below. Unfixed it fails with
`UNABLE_TO_VERIFY_LEAF_SIGNATURE`. The bundle the privoxy role already
assembles is the answer, since it carries both the local root and the
inspection intermediate:

```bash
export NODE_EXTRA_CA_CERTS=~/.local/state/privoxy/trusted-cas.pem
```

## Google Cloud

The SDK comes from `41_clouds.brew`. The role installs the components
(`alpha`, `beta`, `gke-gcloud-auth-plugin`), skipping ones already present.

`gcloud init` needs a browser and stays manual:

```bash
gcloud init
```

_Role: `gcloud`_
_Ansible Tag: enable_gcloud_

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

  Not yet wired into the `unbound`/`gcloud` roles - a manual, one-time edit
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

- `Dotfiles/github-copilot/auth.db` — holds a live OAuth token, gitignored
  and not versioned.

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

_Role: `firefox_enterprise_roots`_
_Ansible Tag: enable_firefox_enterprise_roots_

---

## macswitcher configuration

_Role: `macswitcher`_
_Ansible Tag: enable_macswitcher_

**`config.yaml` and `state.json` are never symlinks, by design.** macswitcher
rewrites both in place on every switch, so linking them back into a repository
means the runtime writes its live values into the source tree — the same trap
`dotfiles_real_dirs` documents and the same one the unbound role avoids for
`forwarders.conf`. The role _seeds_ them once (`copy` with `force: false`) and
never touches them again.

**Context files are the exception: they are linked, not seeded.** Switching
does not rewrite them — `saveConfig` is reached only from `config init` — so a
link is safe, and it is what keeps their values in git. Seeding them cost more
than it protected: `force: false` cannot tell "never installed" from
"deliberately deleted", so the superseded `home` context reappeared on every
run, and seeded copies drifted from their repository originals unnoticed.

Where each file comes from:

| File                                                                                                       | Source                                        | Notes                                       |
| ---------------------------------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------------- |
| `config.yaml`                                                                                              | this repo, `Dotfiles/macswitcher/config.yaml` | generic, no addresses                       |
| `contexts/example.yaml.template`                                                                           | this repo, `Dotfiles/macswitcher/contexts/`   | the only seeded context file                |
| `contexts/home-alone.yaml`, `contexts/remote.yaml`, `contexts/no-filter.yaml`, `contexts/full-direct.yaml` | private overlay                               | linked via `dotfiles_links_overlay`         |
| `contexts/office.yaml`, `contexts/home-vpn.yaml`, `contexts/vpn-debug.yaml`, `contexts/remote-vpn.yaml`    | work overlay                                  | same, follows `enable_work`                 |
| `state.json`                                                                                               | macswitcher itself                            | never versioned                             |
| `~/.zsh/rcs/proxy`                                                                                         | this repo, `Dotfiles/macswitcher/proxy.zsh`   | neutral defaults, then owned by the runtime |

`Dotfiles/macswitcher/proxy.zsh` deliberately does **not** live in
`Dotfiles/zsh/.zsh/rcs/`. That directory is a dotfiles merge dir: every file in
it is force-symlinked into `$HOME`, and there is no per-file exclusion, so
macswitcher would write its runtime proxy values straight back into this repo.

The one context file this repo seeds is `contexts/example.yaml.template` — a
blank context with every key documented, to copy from. Its extension is
`.yaml.template` rather than `.yaml` on purpose: macswitcher loads _every_
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

_Role: `local_ca`_
_Ansible Tag: enable_local_ca_

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

The role can issue **server certificates** for local services reached over
HTTPS. They are issued with `step --bundle`, so the `.crt` is leaf +
intermediate: an ordinary TLS server sends that whole chain and the client
verifies against the root it already trusts.

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

```sh
ls -la ~/.local/share/localca                       # 0700, keys 0600
security verify-cert -c ~/.local/share/localca/root_ca.crt
security find-certificate -c "Privoxy HTTPS Inspection CA" /Library/Keychains/System.keychain
```

Note that `verify-cert` on an _intermediate_ proves nothing about the
keychain: it chains the file it is handed up to the trusted root and reports
success either way. Use `find-certificate` for intermediates.

## Filtering proxy — privoxy — see [docs/investigations/privoxy.md](docs/investigations/privoxy.md)

## Reference

- [Mutt / notmuch / offlineimap introduction](https://bascht.com/blog/2014/05/28/einstieg-in-mutt-notmuch-offlineimap/)
- [Mutt password management](https://wiki.archlinux.org/title/Mutt#Passwords_management)
- [offlineimap config examples](https://www.offlineimap.org/doc/conf_examples.html)
- [YubiKey guide](https://github.com/drduh/YubiKey-Guide)
- [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice)
- [DisplayLink macOS driver (Synaptics)](https://www.synaptics.com/products/displaylink-graphics/downloads/macos)
