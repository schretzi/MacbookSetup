# skhd — Hyper-key hotkeys

**Config:** [`../skhd/skhdrc`](../skhd/skhdrc)
Runs as a LaunchAgent (`~/Library/LaunchAgents/com.koekeishiya.skhd.plist`, installed via `skhd --start-service`), reading config from `~/.config/skhd/skhdrc` (symlinked to `skhd/skhdrc` in this repo). "hyper" = Ctrl+Shift+Alt+Cmd, held via Caps Lock in kanata (see [kanata.md](kanata.md)). By convention in this repo, **`^` is for app switching** (kanata's apps layer) and **hyper is for actions**, to avoid the two overlapping.

## Defaults

skhd ships with **no** default keybindings of its own — `skhdrc` starts
completely empty and every hotkey below is something this repo defines.
Nothing to fall back on beyond the custom bindings below.

## Custom bindings

| Key | Action |
|---|---|
| hyper + m | Toggle mute/unmute in Microsoft Teams (activates Teams, then sends Cmd+Shift+M) |
