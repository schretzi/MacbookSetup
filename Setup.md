
# Schretzi Macbook Setup

Everything needed to take a Mac out of the box and end up with my working
environment.

> Employer-specific steps are not in this repository. They live in a private
> **work overlay** together with the DNS zones, work mail account and
> shell helpers; see [Overlays](#identity-and-the-overlay-repositories).

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

### DisplayLink (docks)

Docks that drive external displays over USB need Synaptics' driver. There is no
cask, so it is a manual download:
<https://www.synaptics.com/products/displaylink-graphics/downloads/macos>

DisplayLink Manager needs **Screen Recording** permission — it captures the
desktop to push it over USB — granted in System Settings → Privacy & Security.
Without it the external screens stay black.

### Karabiner DriverKit VirtualHIDDevice

kanata, installed by Ansible later, drives the keyboard through this virtual HID
driver. It needs **package version 6.2.0**; the driver bundled with full
Karabiner-Elements is newer and breaks kanata.

Download the `.pkg` from
<https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice>, install it,
then activate the driver and approve the extension in **System Settings →
Privacy & Security**:

```bash
/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager activate
```

Two version numbers are in play and they never match: the pqrs _package_ is
6.2.0 (readable from the Manager app's `Info.plist`), while the extension it
registers reports **1.8.0** — which is the only one `systemextensionsctl` ever
shows:

```bash
systemextensionsctl list | grep Karabiner
# ...VirtualHIDDevice (1.8.0/1.8.0) ... [activated enabled]
```

The `kanata` role checks both and stops if the extension is not active.

## How this repo works

**The real file always lives here.** Nothing is copy-pasted into `~` and then
forgotten. Two mechanisms keep it that way:

| Mechanism   | Used for                                                                    | Why                                                                                                                                             |
| ----------- | --------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- |
| **Symlink** | `~/.config/*`, `~/.zshrc`, `~/.gitconfig`, `~/.ssh/config`, unbound configs | Editing the live file edits the repo file. Nothing to sync.                                                                                     |
| **Copy**    | LaunchAgents, LaunchDaemons, `/etc/newsyslog.d`, `/usr/local/bin`           | launchd and root-owned locations refuse to follow links into a user checkout. The repo copy is still the truth — re-run the play after editing. |

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
locations: `sudoers`, `unbound`, `java`, `kanata`,
`firefox_enterprise_roots`. There is a way to authenticate once up front
instead — see [sudo](#sudo) below — but it is switched off until Touch ID for
sudo works.

| Role / tag      | Switch                 | What it does                                                      |
| --------------- | ---------------------- | ----------------------------------------------------------------- |
| `base_dirs`     | `enable_base_dirs`     | `~/bin`, `~/tmp`, `~/Workspace`                                   |
| `homebrew`      | `enable_homebrew`      | `brew bundle` per Brewfile, each file individually toggleable     |
| `dotfiles`      | `enable_dotfiles`      | symlinks `~/.config/*` and the home dotfiles into `Dotfiles/`     |
| `git`           | `enable_git`           | links the shared git ignore file, checks the signing key          |
| `ssh`           | `enable_ssh`           | links `~/.ssh/config`, fixes permissions                          |
| `gitlab`        | `enable_gitlab`        | renders instance list for `gl`, checks tokens are in the keychain |
| `kubeconfig`    | `enable_kubeconfig`    | creates `~/.kube/configs` for `kubeconfig-add`/`kubeconfig-merge` |
| `sudoers`       | `enable_sudoers`       | Touch ID for sudo, the shared credential cache, NOPASSWD rules    |
| `java`          | `enable_java`          | links the Homebrew JDKs into `/Library/Java/JavaVirtualMachines`  |
| `kanata`        | `enable_kanata`        | builds kanata with `cmd`, installs both daemons + log rotation    |
| `windowmanager` | `enable_windowmanager` | yabai + skhd LaunchAgents                                         |
| `mail`          | `enable_mail`          | maildir, notmuch index, offlineimap/omt agents, mail dotfiles     |
| `unbound`       | `enable_unbound`       | loopback aliases, `_unbound` account, configs, resolver daemon    |
| `macswitcher`   | `enable_macswitcher`   | seeds `~/.config/macswitcher` and the shell proxy variables       |
| `gcloud`        | `enable_gcloud`        | gcloud components                                                 |
| `ai`            | `enable_ai`            | links `schretzi-skills` into every assistant, assistant configs   |
| `work`          | `enable_work`          | employer profile, supplied by the work overlay                    |

Two helper roles are never run directly: `link` (backup-then-symlink) and
`launchd` (copy or render plist + `bootout`/`bootstrap`).

### Identity and the overlay repositories

This repository is the **public base**: all machinery, no identity. Nothing in
it names a person, an address or an employer. Two private repositories layer on
top:

| Repo     | Setting             | Holds                                                          |
| -------- | ------------------- | -------------------------------------------------------------- |
| this one | —                   | roles, Brewfiles, scripts, plists, shared dotfiles             |
| private  | `private_repo_root` | `identity.yml`, personal git/ssh/mail config, gitlab.com instance |
| work     | `work_repo_root`    | employer mail account, intranet DNS, work aliases and sessions, work gitlab instances |

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

`~/bin` (personal binaries), `~/tmp` (Scratch, And the unbound control socket),
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
  `Dotfiles/macswitcher/proxy.zsh` (`"off"` until `macswitcher proxy set`
  flips it), so an accidentally-left-on proxy is never invisible.
- **`kubernetes`** — the active context from `~/.kube/config` (built by the
  `kubeconfig` role — see Kubernetes below), enabled since it's off by
  default in Starship.

```
MacbookSetup on  main [!] on ☁️  user@corp.example
proxy: off on ⛵ APL-GCP-2-Staging
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
its *own* files fine but macOS's TCC silently denies reads of the
iCloud-backed Obsidian vault - the daily note still gets created with the
right filename, just without its template content (the fallback in
`open-daily-note.sh` swallows the failure instead of erroring). Grant Full
Disk Access to `kanata`, then `kanata_restart` (see `~/.zsh/aliases/general`)
to pick it up.

Ansible then does the rest: it verifies the driver is active and the right
version, builds kanata **from source with the `cmd` feature** (`cargo install
kanata --features cmd` — the Homebrew build lacks it, so it cannot start or
switch applications), installs `com.kanata.daemon` and the Karabiner daemon,
and installs the newsyslog rule that rotates `/tmp/kanata.*.log`.

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
  - name: com                       # short name used with `gl`
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
makes the *non-interactive* call (`LACopyResultOfPolicyEvaluation`), gets
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
for *other* authorizations works — a System Settings padlock offers it, and
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
  the cache does *not* push the deadline back. So the window has to cover the
  whole stretch from `sudo -v` to the last root task — and site.yml reaches
  its first root task (the `sudoers` role itself) only after `homebrew`, so on
  a cold machine the credential can be gone before Ansible ever needs it.
- The cost is real: for those 20 minutes any process running as this user can
  sudo without authenticating, not just the terminal that did. `sudo -k` drops
  it immediately, everywhere.

That cost buys one Touch ID instead of a typed password. With Touch ID not
authenticating, it would buy one *typed password* instead of one typed
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
two LaunchAgents: `org.schretzi.omt-daemon` (keeps tokens fresh) and
`org.schretzi.offlineimap-sync` (syncs every 5 minutes, logging to
`~/Library/Logs/offlineimap-sync.log`). Both are skipped if
`/opt/homebrew/bin/omt` is missing, so the agents do not sit in a failure loop.

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

## DNS — local unbound resolver

I need different DNS routing depending on where I am: home network, local kubernetes
clusters, VMs, VPN. A local unbound instance resolves all of them at once
instead of rewriting resolver settings per network.

The role runs the full chain:

1. **Loopback aliases.** mDNSResponder owned `127.0.0.1:53` before, so unbound
   listens on `127.0.0.2`, would not be needed anymore, but still stays for
   historical reasons. `Scripts/MacOS/localhost_alias.sh` is copied to
   `/usr/local/bin/localhost_alias` and run at boot by `org.localhost.alias`.
   This adds additional IPs on loopback which I used for different clusters
   earlier with k3d, with apple containers not necessary anymore, but cheap and I
   keep it for maybe future use.
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

| Profile           | From            | Default               | Notes                                                                                      |
| ----------------- | --------------- | --------------------- | ------------------------------------------------------------------------------------------ |
| `forwarders.conf` | base            | on                    | upstream resolvers — runtime-managed at `/opt/homebrew/etc/unbound/conf.d/forwarders.conf` |
| `kiac.conf`       | base            | on                    | local kubernetes hosts on the vmnet (`192.168.64.0/24`)                                    |
| `schretzi.conf`   | private overlay | on                    | home LAN and private domains                                                               |
| intranet zones    | work overlay    | follows `enable_work` | employer forward zones                                                                     |

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

To restart the daemon without a sudo password, the sudoers role installs this
restricted rule (see `roles/sudoers/defaults/main.yml` for every rule and how
to add more, or to switch passwordless sudo off entirely):

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

That writes `/etc/resolver/mydomain`, which mDNSResponder consults _before_ the
configured nameserver — so those names resolve on the host regardless of
whether the system points at unbound.

**kiac clusters resolve through the host.** kiac is a Go tool of its own
(`~/Workspace/Schretzi/kiac`); nothing about it is installed from this
repository. Its node VMs sit on the same `vmnet` network and take their
nameserver from the vmnet gateway `192.168.64.1` — the Mac's own mDNSResponder
— so their lookups follow whatever the active network service points at. With
the system pointed at `127.0.0.2`, `kiac.conf` answers `*.kiac` for the VMs as
well as for the host. It maps the fixed vmnet addresses: host-side containers
(gitea, registry, the pull-through mirrors) at `192.168.64.10-15`, and each
cluster's Gateway LoadBalancer at `.20` (main) and `.30` (test1).

Two consequences follow from going through mDNSResponder:

- A `/etc/resolver` split — the container runtime's, Tailscale's — is host-side
  only. Anything the VMs must resolve needs a real zone here.
- A VPN client that seizes port 53 stops mDNSResponder answering on the gateway
  and every lookup from the VMs is refused. `kiac create cluster --dns 1.1.1.1`
  writes the VM's `resolv.conf` directly and bypasses the gateway, but only at
  creation time.

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
  - { file: lab.conf, enabled: true, root: "{{ private_repo_root }}" }
```

Then `ansible-playbook site.yml --tags unbound --ask-become-pass`, or just
symlink it into `conf.d/` and reload — the Homebrew prefix is user-writable, so
that needs no sudo either.

Zone-type cheat sheet: **`transparent`** answers what you list and forwards the
rest, **`redirect`** answers _every_ name under the zone with the listed data,
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

**Do not use `unbound-control start`.** It exists, but it launches a _new_
daemon as whoever runs it — and an unprivileged process cannot bind
`127.0.0.2:53`, so it fails with:

```
error: can't bind socket: Permission denied for 127.0.0.2 port 53
fatal error: could not open ports
```

The daemon is owned by launchd, which starts it as root and lets it drop
privileges to `_unbound` _after_ binding. Start, stop and restart it there:

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
  `docker.arpa` does not exist. That entry has since been removed entirely, but
  is a good example for such use-cases.

Zones answered by `local-zone`/`local-data` (`kiac.`, the private overlay's
LAN zone) need nothing — local data is returned without validation. It is only
_forwarding_ that has to be exempted. The work overlay marks all of its
forwarded zones insecure for consistency, so adding one there does not silently
require hunting down a matching entry.

### Tailscale

Tailscale is installed by the `homebrew` role — `tailscale-app` in
`60_security.brew`. It is a pkg cask, so it is exactly the case
`Scripts/verify-casks.sh` exists to catch: cancel its installer prompt and the
receipt is written anyway. Signing in stays manual, once per machine.

**It needs no unbound profile, even with the system pointed at `127.0.0.2`.**
Tailscale registers a split-DNS resolver for the tailnet domain, and
mDNSResponder consults that _before_ the configured nameserver — the same
mechanism as `/etc/resolver`:

```bash
scutil --dns | grep -A3 ts.net
#   domain   : tail….ts.net
#   nameserver[0] : 100.100.100.100     <- Tailscale's fixed MagicDNS resolver

dscacheutil -q host -a name <host>.<tailnet>.ts.net
```

The catch: that split lives in mDNSResponder, not in unbound. Anything that
talks to a resolver directly — `dig`, `host`, the kiac VMs — never sees it. So
test MagicDNS with `dscacheutil` or `ping`, not with `dig @127.0.0.2`, which
correctly returns nothing. If a tailnet name really has to come out of unbound,
forward the zone from the private overlay rather than adding local data:

```
forward-zone:
  name: "ts.net"
  forward-addr: 100.100.100.100
```

### Pointing the system at it

unbound only listens on `127.0.0.2`, so nothing reaches it until a network
service's DNS server is set to that address. **macswitcher does that on every
context switch**: it runs `networksetup -setdnsservers` against every active
service, using `dns.local_resolver` from `~/.config/macswitcher/config.yaml`
(`127.0.0.2` here) unless the context overrides it with its own
`dns.resolvers`. One switch therefore repoints the machine and rewrites
`conf.d/forwarders.conf` together, which is the point — the resolver and its
upstreams always match the network you are on.

```bash
macswitcher switch home
macswitcher status
networksetup -getdnsservers Wi-Fi     # 127.0.0.2
```

**Ansible never sets this**, on purpose: it is the one step that breaks all
name resolution when the resolver is not healthy, and unbound has to be
verified running first. Without macswitcher, or to back out, do it by hand —
System Settings → Network → Details → DNS, or:

```bash
networksetup -setdnsservers Wi-Fi 127.0.0.2   # point at unbound
networksetup -setdnsservers Wi-Fi empty       # back to whatever DHCP hands out
```

Logs: `/tmp/unbound.err.log`, `/tmp/unbound.out.log`.

_Role: `unbound`_ — needs sudo

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

  Not yet wired into the `unbound`/`gcloud` roles - a manual, one-time edit
  until the tunnel wrapper script lands.
- **Tunnel connects but the SSH session immediately drops/reconnects** — this
  is almost always a stale or untrusted host key/cert for `localhost:<port>`
  in `~/.ssh/known_hosts`, not a problem with the tunnel itself. Connect
  directly against the forwarded port to see and accept the real prompt:

  ```bash
  ssh -p <port from the tunnel> <gcp-username>@localhost
  # e.g. ssh -p 12022 ext_user_corp@localhost
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

Locally-generated root CAs — e.g. from a LocalKubernetes-style cluster's
`roles/host_ca` — are trusted system-wide with:

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
  root.** Writing into another app's `.app` bundle needs the *calling
  process* — the terminal you run `ansible-playbook` from (Terminal, iTerm,
  Kitty, ...) — to be granted access under **System Settings → Privacy &
  Security → App Management**, in addition to `sudo`/`--ask-become-pass`. A
  failure here shows up as `Operation not permitted [Errno 1]` even though
  the become password was accepted. Enable the toggle for that terminal app
  (add it with **+** if missing), restart it, and re-run the tag.

_Role: `firefox_enterprise_roots`_ — `enable_firefox_enterprise_roots`

---

## macswitcher configuration

_Role: `macswitcher`_ — `enable_macswitcher`

**Nothing under `~/.config/macswitcher` is a symlink, by design.** macswitcher
rewrites `config.yaml`, the context files and `state.json` in place on every
switch. Linking any of them back into a repository means the runtime writes its
live values into the source tree — the same trap `dotfiles_real_dirs` documents
and the same one the unbound role avoids for `forwarders.conf`. So the role
_seeds_ each file once (`copy` with `force: false`) and never touches it again.

Where each file comes from:

| File                                         | Source                                        | Notes                                       |
| -------------------------------------------- | --------------------------------------------- | ------------------------------------------- |
| `config.yaml`                                | this repo, `Dotfiles/macswitcher/config.yaml` | generic, no addresses                       |
| `contexts/home.yaml`, `contexts/remote.yaml` | private overlay                               | via `macswitcher_contexts_overlay`          |
| `contexts/work.yaml`                         | work overlay                                  | same, follows `enable_work`                 |
| `state.json`                                 | macswitcher itself                            | never versioned                             |
| `~/.zsh/rcs/proxy`                           | this repo, `Dotfiles/macswitcher/proxy.zsh`   | neutral defaults, then owned by the runtime |

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
- [DisplayLink macOS driver (Synaptics)](https://www.synaptics.com/products/displaylink-graphics/downloads/macos)
