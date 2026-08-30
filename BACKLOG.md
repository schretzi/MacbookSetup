
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

- [x] **AdGuard Home replaces unbound.** Done. unbound is gone from the
      repository and from the machine; AdGuard Home installs, configures and
      verifies itself from the `adguardhome` role, the zones are native rule
      lists owned by whoever owns the names (private overlay, work overlay,
      LocalKubernetes for `.kiac`), and macswitcher writes the upstreams. The
      whole picture is `Setup.md` -> DNS; the trial document it replaced is
      gone with it.

      Still open, and deliberately not decided while the base setup was being
      finished — to understand properly first, then decide:
      - **DNSSEC is no longer validated locally.** AdGuard Home sets the DO/AD
        bits towards the upstream and reports whatever comes back, so the
        machine trusts Quad9's validation rather than doing its own. What does
        that actually give up, and against what — the ad/tracker/malware
        filtering?
      - **DNS over TLS / DNS over HTTPS.** AdGuard Home can speak both
        upstream. How they relate to DNSSEC (transport privacy vs. answer
        authenticity — they solve different problems and do not replace each
        other), what it costs, and what it means for the upstreams macswitcher
        rewrites per network context.
      - **A Homebrew tap formula + a GitHub workflow tracking upstream
        releases**, so the version stops being pinned by hand. The role
        verifies the release against a checksum before unpacking it, but
        bumping it is still editing two lines in
        `roles/adguardhome/defaults/main.yml`.
      - **The `zonesync` account does not exist on this machine.** The zone
        refresh therefore never takes the API path (no restart, cache kept) and
        always falls back to rewriting the filter cache and restarting. Create
        it in the web UI with the password the role put in the System keychain
        under `adguardhome api`.
      - **Adding a zone to a running machine needs a manual step**, because
        `AdGuardHome.yaml`'s `filters:` block names each list with a fixed id
        and belongs to the runtime after the first seed.

      Two costs of the switch, both now handled, both worth remembering:
      - `bind_hosts: 0.0.0.0` does not serve the vmnet. AdGuard Home answers
        TCP but silently drops UDP replies to non-loopback IPv4-mapped clients,
        so every container and kiac node VM lost DNS. unbound did this with one
        `interface: 0.0.0.0` line; AdGuard Home needs a script, a LaunchDaemon
        and two sudo rules to follow `192.168.64.1` as the vmnet comes and
        goes.
      - Writing a zone file changes nothing on its own — AdGuard Home serves
        its own cached copy. Everything that changes a zone has to end in
        `adguardhome_zones_refresh`.
- [x] **unbound removed from this machine.** Done: the LaunchDaemon plist, the
      Homebrew formula, `/opt/homebrew/etc/unbound`, the installed translator,
      the `unbound-restart` sudoers file and the `_unbound` account are all
      gone. Verified afterwards rather than assumed.

      One thing it surfaced, still open: the sudoers role only removes rule
      files while `sudoers_passwordless_enabled` is false, so a rule dropped
      from `sudoers_rules` stays on disk unmanaged. It was harmless here - a
      NOPASSWD grant for a launchctl label that no longer exists - but the gap
      applies to any rule removed in future.
- [x] **Untangle com.schretzi.localhost-alias from the unbound role.** Done:
      its own role `localhost_alias`, behind `enable_localhost_alias`, running
      before every resolver role. The addresses outlive whichever resolver
      uses them, which is exactly why tying them to unbound broke when unbound
      was switched off.
- [x] **`ansible-lint site.yml` is clean.** Done: 29 findings down to zero,
      profile `production`, 49 files. Task-name casing and Jinja placement,
      role prefixes on variables (`service_cli_*` -> `launchd_service_cli_*`,
      `kka_*` -> `kerberoskeepalive_*`, pf_vmnet_proxy's vmnet vars), and one
      `no-handler` suppressed with its reason inline - the newsyslog parse
      check must fail at the point of the change, and the role is included
      once per conf file, so a handler would verify whichever ran last.
- [ ] **Root CA key is plaintext at rest.** Came with the root when it moved
      from LocalKubernetes' `roles/host_ca` into `local_ca` (it was always
      `--no-password --insecure`). `PLAN.md` §6 over there wants it
      age/sops-encrypted, and the requirement moved with the key — now with
      more weight, since privoxy's inspection CA hangs off the same root and
      can mint a certificate for any site. privoxy's own key must stay
      readable unattended, so the encryption can only cover the root: issue
      intermediates from a decrypted-on-demand root, and keep the plaintext
      copy out of the fixed location.

- [x] **privoxy: filtering URLs on the way out.** Done and live. The chain is
      alpaca -> privoxy -> internet in `direct` contexts, from
      `schretzi/tap/privoxy` (core's bottle has no HTTPS inspection at all),
      with HTTPS inspection signing from a `local_ca` intermediate. macswitcher
      0.3.0 carries the `filter_proxy` block that generates the PAC, plus the
      `status` line, the `observe` row and the `config validate` warnings; the
      per-context `alpaca.command` overrides and the repo's own PAC are gone
      again.

      What it cost to get right, worth remembering:
      - Little Snitch attributes proxied connections as *"app via privoxy"*,
        so every app asks once more. `LittleSnitchConfig` still has no rule
        group for it.
      - The `{-https-inspection}` list is measurement, not prediction:
        `.microsoft.com` does not match `login.microsoftonline.com`, and
        `teams.cloud.microsoft` rejects the handshake. `.sentinelone.net` is
        excluded on principle - decrypting the endpoint security agent is
        wrong regardless of whether it would work.
      - Still to watch: `~/.local/state/privoxy/certs` is never cleaned up,
        and `oebb`/`smartgadget` exist only live, in no overlay.

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
- [ ] **AI: where assistant settings and environment context belong.**
      `~/.claude/settings.json` is a *symlink* into this repository, so Claude
      Code writes runtime state straight into the source tree - which is the
      one thing the setup avoids everywhere else (AdGuardHome.yaml.seed,
      macswitcher's config.yaml: seeded once, then owned by the runtime).

      It showed up as a generated `autoMode.environment` block, 24 entries
      describing the employer VPN, secret stores, DNS zones and data
      classification - in a repository whose README calls it the publishable
      base, all machinery and no identity. Deleted for now (it was meant for
      one session on one project); a copy of what it looked like is not kept.

      What is already known, so the next round does not re-derive it:
      - Settings are layered and merged, more specific winning:
        `~/.claude/settings.json` (machine), `<repo>/.claude/settings.json`
        (project, versioned and shareable), `<repo>/.claude/settings.local.json`
        (project, machine-only - globally ignored through
        `~/.config/git/ignore`, not through a .gitignore in the repo).
      - There is no include/import *inside* a settings file. The layering is
        the mechanism, so "move it out" means "put it in another layer".
      - Per-project environment blocks are therefore possible in principle,
        which is what "one for the private code repo, another for something
        else" would need.
      - It cannot be made assistant-agnostic. The schema and the path are
        Claude Code's; moving the file to `~/.agents/` would only hide it.
        `~/.agents/skills` works because several tools agreed on that path -
        there is no such convention for settings. Only the *content* could be
        neutral prose that one hands to an assistant deliberately.

      Open, and the thing to settle first: **where does the generator write?**
      The block appeared in the machine-level file. If it always goes there,
      relocating it to a project layer is pointless - it would come back.
      Cheap to test: put a block in the project-local file, remove it from the
      machine-level one, trigger a regeneration, see where it lands.

      **The same question, one layer up: symlinked dotfiles are a write target
      for every installer.** `~/.zshrc` is a symlink into this repository, so
      anything that "adds itself to your shell profile" edits the source tree
      unasked. It has now happened twice in one day - Claude Code's autoMode
      block, and the Antigravity CLI installer appending

      ```sh
      # Added by Antigravity CLI installer
      export PATH="/Users/schretzi/.local/bin:$PATH"
      ```

      which was both redundant (`$HOME/.local/bin` is already in the PATH line
      at the top) and wrong for this repository (a hardcoded `/Users/schretzi`
      in the publishable base, where every other line uses `$HOME`). Removed.

      Unlike the Claude settings, `.zshrc` *should* stay versioned and
      symlinked - so the answer here is different: give installers a target
      that hurts nobody. A `~/.zshrc.local`, sourced at the end of `.zshrc`,
      not in the repository, is the usual shape. Worth deciding together with
      the settings question, because both are "who owns this file, the repo or
      the runtime".

      Then decide between: seeding `~/.claude/settings.json` as a real file
      (copy, `force: false`) so the runtime owns it and only the machinery
      stays versioned; splitting by layer and leaving the symlink; or keeping
      the identity-flavoured parts in the work/private overlay.
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

