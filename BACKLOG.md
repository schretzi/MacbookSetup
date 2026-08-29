
# Backlog

Open topics collected from past working sessions and `Setup.md`. Check items
off (or remove them) as they get resolved; keep new open threads added here
instead of scattering them across chat history.

## My Notes

- refactor tunneling
- make docs-check reports "docs out of date" locally right now. That's it working — it diffs against git HEAD, and the regenerated docs are uncommitted. Docs are current and idempotent (verified by regenerating twice).
- Add littlesnitch and tailscale to observe
-

## Open decisions

- [ ] `kubeconfig-add` / `kubeconfig-merge`: keep as zsh functions
      (`Dotfiles/zsh/.zsh/functions/kubeconfig`) or convert to standalone
      scripts symlinked into `~/bin`? Asked, never decided.
- [ ] Confirm the `com` (gitlab.com) and `apl` (work) GitLab tokens are
      actually stored in the macOS keychain
      (`security add-generic-password -s "glab <host>" -a "$USER" -w`) —
      `gl com` / `gl apl` fail until that's done.

## In progress / follow-ups

- [ ] **AdGuard Home as unbound's replacement** — cutover done, unbound is
      booted out and `launchctl disable`d, `enable_unbound: false`. See
      `docs/adguardhome-test.md`. Zones/upstreams are still generated from
      unbound's `conf.d`, which stays the single source of truth.

      Still open before this can be called finished:
      - Homebrew tap formula + a GitHub workflow tracking upstream releases;
        the install is still `Scripts/MacOS/adguardhome-test-install.sh` with
        a pinned version and hardcoded checksums. The `adguardhome` role
        covers only the runtime glue.
      - retire the unbound role (see the localhost-alias item below).

      Open question that decides whether to keep it at all: **DNSSEC is no
      longer validated locally** (AdGuard Home only relays the upstream's AD
      flag). Is trusting Quad9's validation acceptable in exchange for the
      ad/tracker/malware filtering?

      Two costs of the switch that only surfaced once the machine ran on it,
      both now fixed, both worth weighing in that decision:
      - `bind_hosts: 0.0.0.0` does not serve the vmnet. AdGuard Home answers
        TCP but silently drops UDP replies to non-loopback IPv4-mapped
        clients, so every container and kiac node VM lost DNS. unbound did
        this with one `interface: 0.0.0.0` line; AdGuard Home needs a script,
        a LaunchDaemon and two sudo rules to follow `192.168.64.1` as the
        vmnet comes and goes.
      - the web UI on `127.0.0.3:3053` blocked gitea from publishing
        `0.0.0.0:3000`. Moved to `3053`.
- [ ] **Untangle com.schretzi.localhost-alias from the unbound role.** With
      `enable_unbound: false` the loopback aliases 127.0.0.2-.12 are no longer
      managed by Ansible — but AdGuard Home's web UI (`127.0.0.3:3053`) and its
      resolver address still depend on them. The daemon stays loaded and keeps
      working; it simply stops being reinstalled on a fresh machine. Give it
      its own role (or fold it into an adguardhome role) before the unbound
      role is deleted.
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
- [x] SSH config is one big file mixing private and work — split it.
      (`Include ~/.ssh/config.d/*.conf` in the public repo, per-host blocks
      moved to `Dotfiles/ssh/config.d/{private,work}.conf` in the overlays.)
- [ ] look into checkmate.nvim (see above — partially researched already).
- [ ] macswitcher: list context
- [ ] macswitcher: autocompletion on context

## Recently resolved (for reference)

- gcloud ADC + IAP tunneling docs, `gitlab` role + `gl` switcher, `kubeconfig`
  role + `kubeconfig-add`/`-merge`, `kubeconfig-use`/`kubects` shell-scoped
  context switching, kanata restart alias + passwordless sudoers rule,
  `kiac.conf` seed-once behavior, kitty layout cycling + tab window-count
  indicator, mini.files → neo-tree explorer swap, Tab/Shift-Tab buffer
  cycling, Starship second prompt line (proxy state + kubernetes context).

