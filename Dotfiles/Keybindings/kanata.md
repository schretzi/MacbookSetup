# Kanata — system-wide key remapping

**Config:** [`../kanata/kanata.kbd`](../kanata/kanata.kbd)
Runs as a LaunchDaemon ([`../kanata/com.kanata.daemon.plist`](../kanata/com.kanata.daemon.plist)) and intercepts keys system-wide, before any app (including kitty) sees them. German QWERTZ layout; key names below are kanata's physical-position names, not printed characters.

**Status/troubleshooting:** `kanata --list` shows the keyboards macOS currently exposes for grabbing; `sudo launchctl print system/com.kanata.daemon` shows whether the daemon is loaded; `tail -f /Library/Logs/kanata.log` is the live log. kanata never rescans devices after startup, so a keyboard that reconnects later (Bluetooth after wake, cable ↔ Bluetooth switches) needs the daemon restarted to be grabbed — `com.schretzi.kanata-wake` (a `sleepwatcher`-backed LaunchDaemon) does this automatically on every system wake; `kanata_restart` (`~/.zsh/aliases/general`) does it on demand. See Setup.md → "Kanata" for details.

## Defaults

Kanata has no keybindings of its own to fall back on. Once it loads, it
intercepts the **entire** keyboard: any key listed in `defsrc` is fully
remapped by this config (there is no factory/stock behavior underneath it to
revert to), and any key *not* listed in `defsrc` passes straight through as
its raw literal. The **F-row table** below looks like a "default" but isn't
one — it's this config *restoring* macOS's own stock media-key behavior,
which would otherwise silently break the moment kanata claimed the keyboard.

## Custom bindings

| Key (physical) | Tap | Hold |
|---|---|---|
| `;` (prints `ö`) | ö | `\` (backslash, sent as literal unicode) |
| `'` (prints `ä`) | ä | `\|` (pipe) |
| `[` (prints `ü`) | ü | `~` (tilde) |
| Caps Lock | *nothing* | **Hyper**: holds Ctrl+Shift+Alt+Cmd together |

**"apps" layer** — active only while **`^`** (kanata name `nubs` — this key reports as `KEY_102ND`, the ISO "extra" key, *not* `KEY_GRAVE`/`grv` despite sitting where a US grave/backtick key would be; confirmed via `kanata --debug`, don't assume `grv` for this key on other keyboards without checking) is held. This is the dedicated app-switching layer; Hyper (Caps Lock) is intentionally kept for non-switching actions instead (see [skhd](skhd.md)). `^` replaced an earlier fn-based trigger because fn sits far from the home row on a full-size external keyboard, and an even earlier "a"-based trigger because "a" is typed constantly and the tap/hold ambiguity made typing feel laggy. Unlike fn, `^` is a genuine tap-hold key (`caret_apps` alias, using `tap-hold-press`): tapping it still composes accents as normal (e.g. `^` then `a` → `â`), holding it activates the apps layer. `tap-hold-press` resolves to "hold" the instant another key (e.g. `k`) is pressed while `^` is still down, regardless of timing, so there's no perceptible delay on the shortcuts below; only a lone tap of `^` waits out the tap-timeout before typing the character.

| Key | Action |
|---|---|
| `^` + y *(physical "Z", German swap of Y/Z)* | Launch/switch to **Zen** |
| `^` + k | Launch/switch to **kitty** |
| `^` + b | Launch/switch to **Bitwarden** |
| `^` + c | Launch/switch to **Claude** |
| `^` + t | Launch/switch to **Microsoft Teams** |
| `^` + s | Go to (or launch) the **setup** dedicated kitty instance ([`../kitty/sessions/setup.kitty-session`](../kitty/sessions/setup.kitty-session)): cwd `~/Workspace/Schretzi/MacbookSetup`, opens neobean |
| `^` + d | Go to (or launch) the **daily-note** dedicated kitty instance: today's Obsidian daily note in neobean, creating it from the daily template if it doesn't exist yet ([`../kitty/scripts/open-daily-note.sh`](../kitty/scripts/open-daily-note.sh)) |
| `^` + o | Go to (or launch) the **obsidian** dedicated kitty instance ([`../kitty/sessions/obsidian.kitty-session`](../kitty/sessions/obsidian.kitty-session)): cwd `~/Brain`, opens neobean |
| `^` + r | Go to (or launch) the **work-network** dedicated kitty instance: three shells (VPN / Proxy / Tunneling). Session file and binding come from the work overlay; without it this key does nothing. |
| `^` + m | Go to (or launch) the **mail** dedicated kitty instance ([`../kitty/sessions/mail.kitty-session`](../kitty/sessions/mail.kitty-session)): runs neomutt; quitting neomutt closes the whole instance |
| `^` + F1 … `^` + F12 | Literal **F1–F12**, shift passed through — so `^` + Shift + F5 is a genuine Shift+F5, which the Shift-only route below cannot produce (see the F-row table) |

Notes baked into the config itself: `^` + s / `^` + d call [`kitty-focus-or-launch.sh`](../kitty/scripts/kitty-focus-or-launch.sh) / [`open-daily-note.sh`](../kitty/scripts/open-daily-note.sh) — see [kitty.md](kitty.md) "Dedicated instances" for how those work and why plain `open -a kitty --args --session <file>` doesn't. fn is no longer listed in `defsrc` at all, so it's passed straight through unmodified — it may or may not regain its native macOS behavior (emoji picker/dictation/etc.), not verified. Hyper (Caps Lock hold) is consumed by skhd — see [skhd.md](skhd.md).

**F-row** — F1-F12 are listed explicitly in `defsrc` and mapped to their stock macOS media-key actions, restoring the behavior that kanata otherwise breaks (it takes over the whole keyboard, so any key not listed in `defsrc` passes through as a raw literal — this is what silently broke brightness/mute once kanata started managing this keyboard).

There are three ways to reach the row:

| Press | Result |
|---|---|
| bare F-key | The media action in the table below |
| **Shift + F-key** | The literal **F1–F12** |
| `^` + F-key | The literal **F1–F12** (apps layer) |

Shift is only the access modifier here, not part of the output: the `fk1`–`fk12` aliases are `fork`s that wrap the function key in `unshift`, releasing `lsft`/`rsft` for that press alone. So an app receives a clean `F5`, not `Shift+F5` — and `Ctrl+Shift+F5` arrives as `Ctrl+F5`, since `unshift` touches nothing but shift. The consequence is that a genuinely *shifted* function key is unreachable this way; use `^` + Shift + F-key for that, which passes the row through untouched.

`fork` tests kanata's own active key outputs rather than the raw hardware, so a shift that is merely passed through still counts — but only because `process-unmapped-keys yes` is set. That setting is load-bearing for this, not a convenience; the kanata config reference calls out the dependency explicitly for modifiers used this way.

Media actions on a bare press:

| Key | Action |
|---|---|
| F1 / F2 | Brightness down / up |
| F3 | Mission Control |
| F4 | Spotlight search |
| F5 | Dictation |
| F6 | Do Not Disturb |
| F7 / F8 / F9 | Previous track / play-pause / next track |
| F10 | Mute |
| F11 / F12 | Volume down / up |
