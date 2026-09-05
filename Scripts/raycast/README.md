# Raycast script commands

Raycast **Script Commands**, not a Raycast *extension*. The distinction matters
and is easy to get wrong: an extension is an npm package with a `package.json`
`commands` array, written in TypeScript against `@raycast/api` and built with
the `ray` CLI. There is no YAML manifest format - anything shaped like
`apiVersion: / kind: Extension` is not a thing Raycast reads.

Script Commands are plain scripts with a `@raycast.*` metadata header. No
build, no `node_modules`, no `ray` CLI, and they version here as readable
source rather than as compiled bundles in Raycast's store directory
(`~/.config/raycast`, which is symlinked into this repo and is Raycast's own
state - do not hand-author anything in there).

## Setup

Raycast -> Settings -> Extensions -> Script Commands -> **Add Script
Directory**, and point it at this folder:

    ~/Workspace/Schretzi/MacbookSetup/Scripts/raycast

No symlink is needed; Raycast reads the directory wherever it lives.

## What is here, and what deliberately is not

    Focus Window    jump to a window by app name or title, across all spaces
    List Windows    every window yabai knows about, grouped by space
    Kitty Session   focus a dedicated kitty session, launching it if needed

That is the whole list on purpose. `Dotfiles/skhd/skhdrc` already binds 27
yabai actions - focus next/prev, toggle float, toggle split and so on - and a
keystroke beats a launcher round-trip for every one of them. The thing a
keybinding genuinely cannot do is search: picking one window out of ten spaces
by typing part of its name. That is what these add.

`Focus Window` ranks app-name matches above title matches, so typing `kit`
lands on kitty rather than on a browser tab that mentions it.

## Kitty Session, and why the app bundles are not enough

Raycast's own app search finds `~/Applications/Kitty Sessions/*.app` and will
happily launch one - but that gives you a plain home shell, not the session.
Those bundles exist to give Cmd-Tab a distinct name and icon per instance
(see `Dotfiles/kitty/session-apps.conf`); their executable is an unmodified
copy of kitty's launcher, so running one with no arguments makes kitty fall
back to `startup_session` from `kitty.conf`. Everything that makes a session a
session - `--session <file>`, `-o close_on_child_death=yes`,
`-o macos_quit_when_last_window_closed=yes`, the already-running check - lives
in `Dotfiles/kitty/scripts/kitty-focus-or-launch.sh`, which is what kanata's
"^" + s/d/o/m shortcuts call.

`Kitty Session` is the launcher-side entry point into that same script, so a
session opened from Raycast behaves identically to one opened from the
keyboard. It takes a session name (`obsidian`, `mail`, `setup`, `daily-note`,
plus whatever the overlay adds), matched exact -> prefix -> substring, so `obs`
is enough; with no argument it lists what is available. `daily-note` is not a
file in `sessions/` - it is dispatched to `open-daily-note.sh`, which
regenerates today's session under `~/.cache/kitty-sessions` first, which is
what keeps "always today's note" honest.

The session list is read from `~/.config/kitty/sessions` at run time, so
overlay sessions from `MacbookSetup-Work` need no change here.
