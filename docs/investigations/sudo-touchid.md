# Sudo: Touch ID and Credential Caching

Three separate things, all owned by one role so that everything this machine
lets happen as root is auditable in one directory.

## Touch ID

/etc/pam.d/sudo opens with `auth include sudo_local`, and on a stock system
that include simply does not exist — Apple ships `sudo_local.template` next to
it as the invitation. The role writes the real file:

```
auth       sufficient     pam_tid.so
```

That is the whole feature. `sufficient` means a fingerprint ends
authentication; every other outcome — no sensor, lid closed, three bad reads,
a caller that cannot prompt — falls through to `pam_opendirectory`, i.e. the
password prompt that was there before. The file cannot lock sudo out, and
being `sudo_local` rather than `sudo` it survives system updates.

**Status on this machine (2026-08-29): it does not actually authenticate.**
The configuration above is correct and is reached — the unified log shows sudo
creating an `LAContext`, requesting `DeviceOwnerAuthenticationWithBiometrics`,
with `BiometryType=1` and `MechanismTouchId` present. But `pam_tid` only ever
makes the _non-interactive_ call (`LACopyResultOfPolicyEvaluation`), gets
`-1004 "User interaction is required"`, and returns **24**
(`PAM_NO_MODULE_DATA`) — a value openpam itself logs as an unexpected return
for `pam_sm_authenticate()`. It never presents a biometric prompt. What
appears instead is authd's `SecurityAgent` panel for
`authenticate-session-owner`, a password field that no fingerprint can answer.

Ruled out by measurement, so nobody repeats it: the terminal (Terminal.app
behaves identically to kitty), tmux/`pam_reattach`, MDM (the machine is not
enrolled), clamshell, remote sessions, enrollment (`bioutil -r` reports
effective), file modes, PAM ordering, a missing module, and a replaced sudo
(`/usr/bin/sudo` sits on the sealed system volume with SIP enabled). Touch ID
for _other_ authorizations works — a fingerprint on a padlock offers it, and
notably does not so without ever spawning `SecurityAgent`.

**So the file is not installed** (`sudoers_touchid_enabled: false`). It cannot
lock sudo out — that part holds — but "harmless" was wrong, and measurably so:
Ansible drops sudo's `-n` flag as soon as a become password is supplied, so
every `become: true` task authenticates on its own. With `-n` (no become password)
`pam_tid` never engages, which is why this stayed invisible until the first
`--ask-become-pass` run.

Everything below still applies and the switch is one line, so this comes back
the day the OS side authenticates.

## One credential cache, not one per terminal — built, verified, switched off

**This is the piece that would replace `--ask-become-pass`, and it is off
(`sudoers_shared_timestamp: false`) until Touch ID works.** It is documented
here in full because it was built and measured, not guessed at, and turning it
on is a one-line change the day the Touch ID side authenticates.

The obstacle it removes: sudo caches an authentication **per tty** by default,
and Ansible escalates from child processes that have no tty at all. Under that
default, a `sudo -v` typed in a shell does nothing for Ansible, and every
`become: true` task authenticates on its own.

/etc/sudoers.d/00-timestamp switches that to one cache per user:

```sudoers
Defaults timestamp_type=global
Defaults timestamp_timeout=20
```

which makes this work:

```bash
sudo -v && ansible-playbook site.yml
```

Verified on this machine: with the rule installed, a credential created in a
terminal was usable from a tty-less process. Ansible's own `sudo` calls carry
`-n` and never prompt — they only ever consume the cache, they cannot fill it,
which is why the priming `sudo -v` is not optional. Without a valid credential
the become tasks fail with `sudo: a password is required` rather than hanging.

Two things measured while getting there, both worth keeping:

- The 20 minutes run from the **authentication**, and a `sudo` that consumes
  the cache does _not_ push the deadline back. So the window has to cover the
  whole stretch from `sudo -v` to the last root task — and site.yml reaches
  its first root task (the `sudoers` role itself) only after `homebrew`, so on
  a cold machine the credential can be gone before Ansible ever needs it.
- The cost is real: for those 20 minutes any process running as this user can
  sudo without authenticating, not just the terminal that did. `sudo -k` drops
  it immediately, everywhere.

That cost buys one Touch ID instead of a typed password. With Touch ID not
authenticating, it would buy one _typed password_ instead of one typed
password — nothing. Hence off.
