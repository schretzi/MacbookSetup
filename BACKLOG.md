
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

      Still open before this can be called finished — in this order, because
      each step keeps DNS answering while the next is prepared:

      1. **`work.txt` — work overlay.** Same move as `schretzi.txt` already
         did: write `Dotfiles/adguardhome/zones.d/work.txt` in the work
         overlay by hand (start from the current generated file, the rule set
         must come out identical), swap `unbound_profiles_overlay` for
         `adguardhome_zones_overlay` in its `overlay.yml`, then
         `rm /opt/homebrew/etc/unbound/conf.d/corp.conf`. The role refuses to
         manage a zone whose unbound source still exists, and says so with the
         exact `rm`.
         Also move its per-domain forwarders (`[/corp.example/]10.0.0.106`
         and friends) into `adguardhome_upstreams_overlay`, or they vanish
         from `upstreams.conf` the first time it is re-seeded.
      2. **`kiac.txt` — LocalKubernetes.** `roles/host_dns` there renders
         unbound config into `conf.d/kiac.conf`. It has to render AdGuard Home
         rules into `/etc/adguardhome/zones/kiac.txt` instead and then call
         `sudo -n /usr/local/bin/adguardhome_zones_refresh`. Until that lands,
         `kiac.conf` must stay in `conf.d` and keep being translated — this is
         the one zone that cannot simply be hand-written, because the vmnet
         hands out new addresses on every reboot.
      3. **macswitcher.** Drop `Unbound.ForwardersFile` and the writer behind
         it (`internal/app/config.go`, `internal/app/network.go`). It already
         writes `upstreams.conf` natively and preserves the `[/domain/]addr`
         lines, so this is a removal, not a rewrite.
      4. **Retire unbound.** Only once 1–3 are done and nothing reads
         `conf.d` any more: the `unbound` role, `Dotfiles/unbound/`,
         `net.unbound.plist`, the formula in `00_base.brew`, the
         `unbound-restart` sudoers rule, `enable_unbound`,
         `unbound_to_adguard.py`, `adguardhome-compare.sh`,
         `adguardhome-cutover.sh`, `adguardhome-test-install.sh`, and
         `adguardhome_legacy_confd` plus the migration guard in the
         `adguardhome` role. On the machine: `launchctl bootout`,
         `brew uninstall unbound`, remove the `_unbound` account and
         `/opt/homebrew/etc/unbound`. Then rewrite `Setup.md` → DNS, which
         still describes unbound as the resolver, and dissolve
         `docs/adguardhome-test.md` into it — the trial is over.
      - a Homebrew tap formula + a GitHub workflow tracking upstream
        releases, so the version stops being pinned by hand. The `adguardhome`
        role installs the release itself now (verified against a checksum
        before it is unpacked), but bumping it is still editing two lines in
        `roles/adguardhome/defaults/main.yml`.

      Two smaller things noticed on the way:
      - **The `zonesync` account does not exist on this machine.** The zone
        refresh therefore never takes the API path (`POST
        /control/filtering/refresh`, no restart, cache kept) and always falls
        back to rewriting the filter cache and restarting. Create the account
        in the web UI with the password the role put in the System keychain
        under `adguardhome api`.
      - **Adding a zone to a running machine needs a manual step.** AdGuard
        Home loads a rule list because `AdGuardHome.yaml`'s `filters:` block
        names it with a fixed id, and that file belongs to the runtime after
        the first seed. Either add the entry in the web UI, or delete the
        config and let the role re-seed.

      **Open, deliberately not decided while the base setup is being
      finished — to understand properly first, then decide:**
      - **DNSSEC is no longer validated locally.** AdGuard Home only relays
        the upstream's AD flag, so the machine now trusts Quad9's validation
        rather than doing its own. What does that actually give up, and
        against what — the ad/tracker/malware filtering?
      - **DNS over TLS / DNS over HTTPS.** AdGuard Home can speak both
        upstream. How they relate to DNSSEC (transport privacy vs. answer
        authenticity — they solve different problems and do not replace each
        other), what it costs, and what it means for the upstreams
        macswitcher rewrites per network context.

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
- [x] **Untangle com.schretzi.localhost-alias from the unbound role.** Done:
      its own role `localhost_alias`, behind `enable_localhost_alias`, running
      before every resolver role. The addresses outlive whichever resolver
      uses them, which is exactly why tying them to unbound broke when unbound
      was switched off.
- [ ] **`ansible-lint site.yml` is not clean.** `Ansible/README.md` says it
      must stay clean; it currently reports 24 findings, all in the launchd
      conventions work committed in fd44d94 and none of them behavioural:
      7× `name[casing]` in `pf_vmnet_nat`, 12× `var-naming[no-role-prefix]`
      across `kerberoskeepalive`, `launchd/require_service_cli`, `macswitcher`,
      `mail` and `tunneling`, 3× `name[template]`, 1× `no-handler` in
      `newsyslog`, 1× `yaml[line-length]` in `work`. Mechanical to fix, but it
      touches five roles, so it wants its own commit rather than riding along
      with something else.
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

