# Kitty — terminal emulator

**Config:** [`../kitty/kitty.conf`](../kitty/kitty.conf) (`kitty_mod` = **cmd+option**, set at line 320)
Related: [`../kitty/pass_keys.py`](../kitty/pass_keys.py) (custom kitten), [`../kitty/quick-access-terminal-*.conf`](../kitty/quick-access-terminal-center.conf), session files under [`../kitty/sessions/`](../kitty/sessions).

## Defaults

Source: [kitty docs — Mappable actions](https://sw.kovidgoyal.net/kitty/actions/) and
[Making your keyboard dance](https://sw.kovidgoyal.net/kitty/mapping/). Not
exhaustive — see those pages for the complete list.

**Important:** kitty's default shortcuts are defined *using* the `kitty_mod`
variable, and this repo sets `kitty_mod cmd+option` (the stock default is
`ctrl+shift`). That single line silently changes every default shortcut
below from `ctrl+shift+X` to `cmd+option+X` — nothing in `kitty.conf` needs
to redefine them individually for that shift to take effect. `kitty.conf`
does **not** set `clear_all_shortcuts`, so all of these remain live
underneath the custom bindings.

### Fixed macOS shortcuts (not affected by `kitty_mod`)

| Key | Action |
|---|---|
| `cmd+c` | Copy selection to clipboard (or pass `ctrl+c` through if there's no selection) |
| `cmd+k` | Clear screen up to the cursor/prompt |
| `cmd+ctrl+l` | Clear screen |
| `option+cmd+k` | Clear scrollback |
| `cmd+l` | Clear last command + its output (needs shell integration) |
| `ctrl+shift+delete` | Reset the terminal |
| `cmd+h` | Hide kitty |
| `option+cmd+h` | Hide other apps |
| `cmd+m` | Minimize the OS window |
| `cmd+q` | Quit kitty |
| `` cmd+` `` | Cycle through kitty OS windows |
| `` cmd+shift+` `` | Cycle through kitty OS windows, backwards |
| `shift+cmd+w` | Close the OS window |
| `option+cmd+s` | Toggle secure keyboard entry |
| `shift+cmd+/` | Open kitty's website |
| `cmd+,` | Edit `kitty.conf` |

### `kitty_mod`-based shortcuts (= **cmd+option** here)

| Key (as `cmd+option+…`) | Action | Status in this repo |
|---|---|---|
| `+enter` | New window | Still active; the custom `cmd+enter` below is an *additional* key for the same action |
| `+n` | New OS window | Unmodified default |
| `+w` | Close window | Same combo as the custom `kitty_mod+w` entry below — this is just that default, restated |
| `+t` | New tab | Still active; the custom bare `cmd+t` below is an *additional* key for a different action (`new_tab_with_cwd`) |
| `+]` / `+[` | Next / previous window | Still active; the custom `ctrl+shift+alt+super+h/l` below is an *additional* pair of keys for the same thing |
| `+1` … `+0` | Focus window 1–10 | Unmodified default |
| `+l` | Next layout | Unmodified default |
| `+r` | Start resizing window (interactive) | Unmodified default — distinct from the custom fixed-amount resize keys below |
| `+c` | Copy to clipboard | Unmodified default (separate from the fixed `cmd+c` above) |
| `+v` | Paste from clipboard | Unmodified default |
| `+s` | Paste from selection | Unmodified default |
| `+o` | Pass selection to program | Unmodified default |
| `+e` | Open URL (click via hints) | Unmodified default |
| `+/` | Search scrollback | Unmodified default |
| `+g` | Show last shell command's output | Unmodified default |
| `+h` | Show scrollback (pager) | Still active; the custom `kitty_mod+z` below is an *additional* key for the same action |
| `+a>l` / `+a>m` / `+a>1` / `+a>d` | Decrease / increase / max / reset background opacity | **Overridden.** This repo reuses the `+a` prefix for the quick-access-terminal submenu below — `+a>d` in particular now launches a terminal instead of resetting opacity |
| `+b` / `+f` | Move window backward / forward | Unmodified default |
| `` +` `` | Move window to top | Unmodified default |
| `+f7` | Visually select & focus a window | Unmodified default |
| `+f8` | Visually swap window with another | Unmodified default — distinct from the custom `ctrl+cmd+h` swap-with-window binding |
| `+t` (tab), `+alt+t` | Set tab title | Unmodified default |
| `+f10` / `+f11` | Toggle maximized / fullscreen | Unmodified default |
| `+minus` / `+equal` / `+backspace` | Decrease / increase / reset font size | Unmodified default |
| `+q` (tab) | Close tab | Unmodified default |
| `+,` / `+.` | Move tab backward / forward | Unmodified default |
| `+x` | Scroll to previous shell prompt | Unmodified default |
| `+f2` | Edit config file | Unmodified default (mac shortcut for this is the fixed `cmd+,` above) |
| `+f5` | Reload `kitty.conf` | Still active; this repo's custom `ctrl+cmd+,` is the same action, restated explicitly |
| `+f6` | Show effective/debug configuration | Unmodified default |
| `+f3` | Command palette | Unmodified default |
| `+escape` | Open the kitty shell | Unmodified default |

## Custom bindings

### Layout / windows

| Key | Action |
|---|---|
| `ctrl+cmd+option+u` | Layout: tall |
| `ctrl+cmd+option+i` | Layout: fat |
| `ctrl+cmd+option+o` | Layout: stack |
| `cmd+z` | Toggle stack layout |
| `cmd+enter` | New window (split) |
| `ctrl+shift+alt+super+k` / `+j` | Next / previous tab |
| `ctrl+shift+alt+super+h` / `+l` | Previous / next window |
| `ctrl+cmd+h` | Swap with window |
| `ctrl+cmd+option+h` / `+l` | Resize window narrower / wider |
| `ctrl+cmd+option+k` / `+j` | Resize window taller / shorter |
| `kitty_mod+w` (cmd+option+w) | Close window |
| `ctrl+cmd+,` | Reload config file |

### `ctrl+h` / `ctrl+j` / `ctrl+k` / `ctrl+l` — smart nvim-aware pane navigation

```
map ctrl+j kitten pass_keys.py bottom ctrl+j "nvim"
map ctrl+k kitten pass_keys.py top    ctrl+k "nvim"
map ctrl+h kitten pass_keys.py left   ctrl+h "nvim"
map ctrl+l kitten pass_keys.py right  ctrl+l "nvim"
```
Labeled in the config itself as *"Config from neovim plugin knubie/vim-kitty-navigator"*. This is **not** a plain window-nav shortcut — `pass_keys.py` checks whether the focused kitty window's foreground process matches the regex `n?vim`:
- **If nvim is running:** the raw `ctrl+h/j/k/l` keystroke is forwarded into nvim's stdin instead of moving kitty windows.
- **If nvim is not running:** kitty moves focus to the neighboring window itself.

This is designed to hand off to **[`../neobean/lua/plugins/vim-kitty-navigator.lua`](../neobean/lua/plugins/vim-kitty-navigator.lua)**, which catches `<C-h/j/k/l>` *inside* nvim (modes n/v/i) and calls `:KittyNavigateLeft/Down/Up/Right` — which in turn asks kitty to move focus when there's no more vim split in that direction. See [keybindings.md](keybindings.md) "The kitty ↔ neobean handoff" for why this is the exact behavior you noticed ("stops working once neobean is active").

### Scrollback / sessions

| Key | Action |
|---|---|
| `kitty_mod+z` | Show scrollback |
| `kitty_mod+i` | Open scrollback in a fresh neobean instance (sets `SIMPLER_SCROLLBACK=deeznuts`, `NVIM_APPNAME=neobean`) — see below |
| `ctrl+shift+s` | Save current state as a session file |
| `cmd+s`→`d` | Go to (or launch) the **setup** dedicated instance |
| `cmd+s`→`o` | Go to (or launch) the **obsidian** dedicated instance |
| `cmd+s`→`r` | Go to (or launch) the **work-network** dedicated instance (work overlay) |
| `cmd+s`→`m` | Go to (or launch) the **mail** dedicated instance (neomutt) |
| `cmd+s`→`-` | Go to alternate/previous session (native kitty `goto_session -1`, only meaningful within `home`'s own tabs) |
| `cmd+s`→`s` | Interactive session picker ([`kitty-list-sessions.sh`](../kitty/scripts/kitty-list-sessions.sh)) — currently broken, the script was deleted from this repo |
| `cmd+s`→`z` | Zoxide-based session picker ([`kitty-zoxide-session.sh`](../kitty/scripts/kitty-zoxide-session.sh)) — currently broken, the script was deleted from this repo |
| `cmd+t` | New tab with current working directory |

**Dedicated instances** — `setup`, `obsidian`, `mail`, `daily-note` (and `work-network` from the work overlay) are genuinely separate OS-level kitty processes, not tabs muxed into one window. This replaced plain `goto_session` (which only ever affects the currently-focused window's tabs) after it caused exactly the bug it looks like: pressing a "go to X" shortcut while a different window had focus just changed *that* window's tabs instead of jumping to X. All of them are launched/focused via [`kitty-focus-or-launch.sh`](../kitty/scripts/kitty-focus-or-launch.sh) `<session-file>`: it `pgrep`s for a process already running that exact `kitty --session <file>` command line, and if found, focuses it through *that instance's own* remote-control socket (`/tmp/kitty-<pid>` — every kitty process gets one, `listen_on` is global in kitty.conf); if not found, it does `open -a kitty -n --args --session <file>` (`-n`/`--new` forces a genuinely new instance — plain `open -a kitty --args ...` does *not* forward new `--args` to kitty's already-running singleton, it just refocuses whatever was already showing, which was the original bug). `open` is used deliberately over invoking the kitty binary directly — it detaches the new process cleanly regardless of the caller's own session, which matters since this also gets called from kanata's root LaunchDaemon.

**Cmd-Tab names & icons** — each dedicated instance runs from its own small app bundle in `~/Applications/Kitty Sessions/`, so macOS's app switcher shows `Setup` / `Obsidian` / `Neomutt` / `Daily Note` (plus any overlay session) with a distinct coloured, lettered icon instead of five identical `kitty` entries. This is needed because Cmd-Tab switches *applications* and takes its name from the bundle's `CFBundleName` — there's no per-process override, and every instance executing `/Applications/kitty.app` means they all read "kitty" (`lsappinfo list` shows them as identical entries). Window titles were always correct; they just never reached Cmd-Tab (they do show in Mission Control, Cmd-` cycling, and the Dock's window list).

The bundles are generated by [`kitty/scripts/make-session-apps.sh`](../kitty/scripts/make-session-apps.sh) from the table in [`kitty/session-apps.conf`](../kitty/session-apps.conf) (session glob → app name → icon letter → icon colour), with icons rendered by [`kitty/scripts/make-session-icon.js`](../kitty/scripts/make-session-icon.js) through JXA's Objective-C bridge — AppKit is always present, unlike ImageMagick/librsvg/PIL. They're generated artifacts, not tracked in git; ~700 KB each, ~4 MB total. The structure copies kitty's own `kitty.app/Contents/kitty-quick-access.app`: own `Info.plist`, everything heavy symlinked back to the real install. `home` deliberately has no wrapper — it's the Dock icon / `startup_session` instance and should stay "kitty".

Overlay sessions declare their wrapper in `~/.config/kitty/session-apps.d/*.conf` (same format, read before the base table), mirroring the `globinclude local.d/*.conf` that `kitty.conf` itself uses — that's how the work overlay contributes `work-network` → `Work Network`. An overlay-only session must *not* be listed in the base `session-apps.conf`, or a machine without that overlay builds a wrapper for a session it doesn't have. Note that the glob matches the name the session is *linked* as under `~/.config/kitty/sessions`, which need not be the filename the overlay uses in its own repo.

Two things worth knowing: the bundle's main executable must be a real **copy** of kitty's launcher (symlinking it fails to launch with `error -54`), so **re-run `make-session-apps.sh` after `brew upgrade kitty`**; and the wrappers strip `CFBundleDocumentTypes`/`CFBundleURLTypes`/`NSServices`/`CFBundleIconName` from kitty's plist, otherwise they'd each claim `.sh`/folders/`file:`/`git:` in every "Open With" menu and the asset-catalog icon would silently override the generated one. `kitty-focus-or-launch.sh` picks the wrapper up automatically and falls back to plain `kitty.app` for any session without one.

`daily-note` additionally goes through [`open-daily-note.sh`](../kitty/scripts/open-daily-note.sh), which creates today's note (from `Templates/daily.md`) if missing, generates a *per-day* session file at `~/.cache/kitty-sessions/daily-note-YYYY-MM-DD.kitty-session` (not tracked in git), and hands that to `kitty-focus-or-launch.sh`. The per-day filename is what makes "always today's note" work: a window left open from a previous day has a different filename, so it's never mistaken for today's — it's simply left alone in the background, and a fresh dedicated instance opens for today.

`ctrl+b` is used as a **tmux-style prefix** — the config comment literally says *"This is similar to tmux prefix + key"* — even though tmux itself isn't used; kitty sessions replace tmux here (see the "Kitty Sessions section (To replace tmux)" comment block).

| Key | Action |
|---|---|
| `ctrl+b`→`i` | Launch/open daily note (same `open-daily-note.sh` as `^` + d in kanata — see [kanata.md](kanata.md)) |
| `ctrl+b`→`n` | Browse & select from known projects (session picker) |

**`home`** ([`../kitty/sessions/home.kitty-session`](../kitty/sessions/home.kitty-session)) is the main/default session — plain shell at `~`, tab layout `tall`. It's kitty's `startup_session`, i.e. what a cold-launched kitty opens into; it isn't one of the dedicated instances above and has no dedicated hotkey of its own.

### Quick-access floating terminal (`kitty_mod+a` → letter)

`kitty_mod` = cmd+option, so these are cmd+option+a, then a second key. As
noted in Defaults above, this **overrides** the default `kitty_mod+a>{l,m,1,d}`
background-opacity submap — most noticeably `+a>d`, which in stock kitty
resets opacity but here launches the default quick-access terminal instead.

| Key | Action |
|---|---|
| `…+a`→`d` | Default quick-access terminal |
| `…+a`→`t` | System-task floating terminal (center config) |
| `…+a`→`q` | Bookmarks floating terminal — triggers a script literally named for **skhd** (`557-skhdQatBookmarks.sh`), even though no skhd config exists in this repo (see [keybindings.md](keybindings.md) "Duplicates & conflicts") |
| `…+a`→`c` | Colorscheme selector |
| `…+a`→`n` | Daily-note floating terminal |
| `…+a`→`s` | "skitty" notes terminal (opens neobean on a specific file) |
