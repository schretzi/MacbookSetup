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
_Ansible Tag: enable_kanata_
