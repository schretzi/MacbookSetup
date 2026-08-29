
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

- [ ] **Touch ID for sudo does not authenticate — blocked on the OS side.**
      The `/etc/pam.d/sudo_local` the sudoers role writes is correct (see
      `sudoers_touchid_enabled`), and the full diagnosis is in `Setup.md` →
      "sudo": `pam_tid` is reached, requests
      `DeviceOwnerAuthenticationWithBiometrics`, but only ever makes the
      non-interactive `LACopyResultOfPolicyEvaluation` call, gets
      `-1004 "User interaction is required"` and returns `24`
      (`PAM_NO_MODULE_DATA`); authd's `SecurityAgent` password panel appears
      instead, which no fingerprint can answer. Ruled out by measurement:
      terminal (Terminal.app behaves like kitty), tmux/`pam_reattach`, MDM
      (not enrolled), clamshell, remote sessions, enrollment, file modes, PAM
      ordering, missing module, replaced sudo. Touch ID for *other*
      authorizations works.

      Not yet tried: external Touch ID keyboard disconnected (the log reports
      two accessories), and a reboot (`BKDevice::extendedBioLockoutState`
      returned an odd value at 5 days uptime).

      The PAM file is therefore **not installed** — it is not free: Ansible
      drops sudo's `-n` as soon as a become password is supplied, so under
      `--ask-become-pass` every root task runs the interactive PAM stack and
      authd throws a password panel per task.

      **When it does authenticate, this is the rest of the work:**
      0. `sudoers_touchid_enabled: true` in `group_vars/all.yml`.
      1. `sudoers_shared_timestamp: true` in `group_vars/all.yml` — installs
         `/etc/sudoers.d/00-timestamp` (`timestamp_type=global`), already
         built and verified to make one `sudo -v` cover a whole play.
      2. `become_ask_pass = False` in `Ansible/ansible.cfg`.
      3. Swap the documented invocation to `sudo -v && ansible-playbook
         site.yml` in `Setup.md`, `Ansible/README.md`,
         `group_vars/all.yml`, `site.yml`'s assert message, `CONVENTIONS.md`
         and `Scripts/MacOS/migrate-launchd-conventions.sh`.
      4. Decide `sudoers_timestamp_timeout`: the window runs from the
         authentication and is *not* extended by use, and site.yml reaches
         its first root task only after `homebrew` — 20 minutes may not cover
         a cold run.
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
