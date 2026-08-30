# Ansible

Automation for the Mac setup. Full documentation is in [../Setup.md](../Setup.md);
this file is the quick reference.

```bash
cd ~/Workspace/Schretzi/MacbookSetup/Ansible

ansible-playbook site.yml --ask-become-pass          # everything enabled in group_vars/all.yml
ansible-playbook site.yml --check                    # dry run
ansible-playbook site.yml --tags dotfiles            # one topic
ansible-playbook site.yml --skip-tags mail,adguardhome   # all but these
ansible-playbook site.yml --tags mail -e enable_mail=true   # force a disabled topic

ansible-lint site.yml                                # must stay clean
```

Only `sudoers`, `localhost_alias`, `adguardhome`, `java`, `kanata` and
`firefox_enterprise_roots` need
`--ask-become-pass`.

## Layout

```
group_vars/all.yml    the enable_* switches - the switchboard
site.yml              role order and tags
roles/link/           helper: back up whatever is there, then symlink into the repo
roles/launchd/        helper: copy a plist, bootout + bootstrap it
roles/<topic>/        one role per topic, each behind its own enable_ flag
```

Per-role knobs live in `roles/<role>/defaults/main.yml`:

| File | Controls |
| --- | --- |
| `roles/homebrew/defaults/main.yml` | which Brewfiles are installed |
| `roles/dotfiles/defaults/main.yml` | the symlink map |
| `roles/adguardhome/defaults/main.yml` | the pinned release, the zones, the per-domain upstreams |
| `roles/localhost_alias/defaults/main.yml` | which 127.0.0.x aliases exist on lo0, and which of them the play refuses to run without |
| `roles/sudoers/defaults/main.yml` | every passwordless (NOPASSWD) sudo rule, Touch ID for sudo, the shared credential cache |
| `roles/kanata/defaults/main.yml` | kanata version, driver version, rebuild |
| `roles/gcloud/defaults/main.yml` | gcloud components |
| `roles/macswitcher/defaults/main.yml` | where the seeded config and contexts come from |
| `roles/firefox_enterprise_roots/defaults/main.yml` | which Firefox-based browser bundles are checked, and the policies.json content |

## Overlays — the three-repo split

This repository is the **publishable base**: all machinery, no identity. Two
optional private repositories layer on top of it.

| Repo | `group_vars/all.yml` | Holds |
| --- | --- | --- |
| this one | — | roles, Brewfiles, scripts, plists, shared dotfiles |
| private | `private_repo_root` | `identity.yml`, personal mail/git/ssh config |
| work | `work_repo_root` | employer mail account, intranet DNS, work aliases and sessions |

Point them at a checkout, or leave them empty for none. A machine with neither cloned still converges —
it just has nothing personal configured. `work_repo_root` additionally requires
`enable_work: true`.

An overlay mirrors this repo's layout (`Dotfiles/`, `Brewfiles/`, …) and may
provide two files at its root:

- **`identity.yml`** — personal identity; the private overlay's copy wins over
  `Ansible/local/identity.yml`
- **`overlay.yml`** — what it contributes to the base:

```yaml
dotfiles_links_overlay:
  - { src: Dotfiles/zsh/.zsh/aliases/work, dest: .zsh/aliases/work, root: "{{ work_repo_root }}" }
adguardhome_zones_overlay:
  - { file: intranet.txt, enabled: true, root: "{{ work_repo_root }}" }
homebrew_brewfiles_overlay:
  - { file: 90_work.brew, enabled: true, root: "{{ work_repo_root }}" }
mail_work_accounts:
  - { id: work, address: ..., sync_order: 30, work: true, ... }
```

The `root:` key is what makes this work: the `link` role resolves each source
against `item.root | default(repo_root)`, so the base never needs to know what
an overlay contains.

### Identity lives in exactly one place

Every name, address and mail account lives in a single `identity.yml`, supplied
by the **private overlay**. This repository ships only
`Ansible/local/identity.example.yml`; a local copy at
`Ansible/local/identity.yml` also works and is gitignored. With none of them
present the playbook still converges — the mail role reports that no accounts
are configured and skips itself.

`mail_accounts` there drives **five** rendered configs: msmtp, notmuch,
offlineimap, omt and muttrc. Those five each enumerate every account in a
single line of a single file, which is precisely why they are templated rather
than symlinked — there is no other way to have the work account come from one
repository and the personal accounts from another. Adding an account is a
change to that one list.

`sync_order` gives a stable ordering no matter which repository an account
arrives from; `mutt_key` pins the neomutt switch digit so the split cannot
silently reshuffle muscle memory.

OAuth **application** credentials are not in any file: the role reads
`mail_oauth_clients` from the macOS keychain
(`Scripts/omt-oauth-keychain.sh`). They are Thunderbird's published credentials
rather than personal secrets, but a literal `client_secret:` makes a repository
unpushable — GitHub's push protection rejects the pattern outright, private repo
or not. `roles/mail/defaults/main.yml` carries endpoints only. The role asserts
a `client_id` exists for every provider in use and names the missing ones,
rather than letting it surface later as an opaque auth failure mid-sync.

### Verifying the mail stack

The five configs are generated, so the question after any change is whether the
tools still resolve what they did before:

```bash
Scripts/verify-mail-config.sh baseline   # capture current state
# ...make changes, re-run the play...
Scripts/verify-mail-config.sh check      # compare
```

It compares *parsed* state (INI sections, YAML, `msmtp -P`, `notmuch config
get`, `neomutt -Q`) rather than bytes, then exercises the live OAuth path with
`omt token`. Everything is regenerated on every run — comparing against a stale
artifact once produced a false "identical" here, and a config that parses can
still be unusable.

## Conventions

- **Repo is the truth.** Roles symlink live paths into the repo; where launchd
  or root refuses a symlink, they copy from the repo instead.
- **Nothing is destroyed.** A real file or directory sitting where a symlink
  belongs is moved to `<path>.bak-<timestamp>`.
- **Idempotent.** A second run reports zero changes. If it does not, that is a
  bug.
- **Read-only probes carry `check_mode: false`** so `--check` reports reality
  instead of skipping the fact-gathering it depends on.
- **Facts use the `ansible_facts.*` namespace**, not the deprecated top-level
  `ansible_*` variables.

## Adding a topic

1. `roles/<name>/tasks/main.yml` (+ `defaults/main.yml` for its knobs)
2. `enable_<name>: true` in `group_vars/all.yml`, with a comment
3. an entry in `site.yml` with `when: enable_<name> | bool` and a tag
4. a section in `../Setup.md` — what is automated *and* what stays manual
5. `ansible-lint site.yml`, then `--check`, then two real runs to prove
   idempotency
