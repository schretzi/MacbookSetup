# Backlog

Open topics collected from past working sessions and `Setup.md`. Check items
off (or remove them) as they get resolved; keep new open threads added here
instead of scattering them across chat history.

## Open decisions

- [ ] `kubeconfig-add` / `kubeconfig-merge`: keep as zsh functions
      (`Dotfiles/zsh/.zsh/functions/kubeconfig`) or convert to standalone
      scripts symlinked into `~/bin`? Asked, never decided.
- [ ] Confirm the `com` (gitlab.com) and `apl` (work) GitLab tokens are
      actually stored in the macOS keychain
      (`security add-generic-password -s "glab <host>" -a "$USER" -w`) —
      `gl com` / `gl apl` fail until that's done.

## In progress / follow-ups

- [ ] **gcloud IAP tunneling wrapper script** — currently only documented
      manually in `Setup.md` (SSH key prereq via `gcloud compute ssh`,
      `/etc/hosts` `kubernetes` alias, stale-host-key workaround). Script
      itself not written yet.
- [ ] **glab repo clone -g --include-subgroups** returns `exit status 128`
      for some (not all) repos in a group — cause not yet investigated.
- [ ] **checkmate.nvim** (bngarren/checkmate.nvim) identified as the closest
      Obsidian-Tasks-plugin equivalent for neovim + Obsidian vaults (custom
      todo states, `@started`/`@done` metadata) — researched, not installed
      or configured yet.

## Ideas (mirrors `Setup.md` → "Improvment Ideas")

- [ ] When a kitty session stops, focus goes to Finder — want the last
      active session to regain focus instead.
- [ ] Tunneling script modernization (see gcloud IAP item above).
- [ ] Move Work configs into an overlay and find/create a repo to push it to.
- [ ] Regular vulnerability checks + a way to track overall project status.
- [ ] SSH config is one big file mixing private and work — split it.
- [ ] look into checkmate.nvim (see above — partially researched already).

## Recently resolved (for reference)

- gcloud ADC + IAP tunneling docs, `gitlab` role + `gl` switcher, `kubeconfig`
  role + `kubeconfig-add`/`-merge`, `kubeconfig-use`/`kubects` shell-scoped
  context switching, kanata restart alias + passwordless sudoers rule,
  `kiac.conf` seed-once behavior, kitty layout cycling + tab window-count
  indicator, mini.files → neo-tree explorer swap, Tab/Shift-Tab buffer
  cycling, Starship second prompt line (proxy state + kubernetes context).
