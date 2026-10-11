#!/usr/bin/env python3
"""Interactively pick which MacbookSetup topics a teammate wants enabled.

Walks the same enable_* switches as Ansible/group_vars/all.yml, in the order
site.yml actually applies them (so a topic is only ever asked about after the
topics it depends on), and writes the answers to a small vars file that layers
on top of all.yml without touching it - a teammate does not need every
feature you personally use.

Usage:
    Scripts/select-features.py
    Scripts/select-features.py --output Ansible/local/features.yml

Then run Ansible with the generated file layered on top of the defaults:
    cd Ansible
    ansible-playbook site.yml -e @local/features.yml --ask-become-pass
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
ALL_YML = REPO_ROOT / "Ansible" / "group_vars" / "all.yml"
DEFAULT_OUTPUT = REPO_ROOT / "Ansible" / "local" / "features.yml"

# Order mirrors the `roles:` list in Ansible/site.yml, which already respects
# every dependency below (e.g. local_ca before trusted_cas before
# firefox_enterprise_roots before privoxy before macswitcher).
ROLE_ORDER = [
    "base_dirs",
    "homebrew",
    "dotfiles",
    "git",
    "ssh",
    "gitlab",
    "kubeconfig",
    "sudoers",
    "java",
    "kanata",
    "windowmanager",
    "mail",
    "localhost_alias",
    "unbound",
    "pf_vmnet_nat",
    "pf_vmnet_proxy",
    "local_ca",
    "trusted_cas",
    "firefox_enterprise_roots",
    "privoxy",
    "macswitcher",
    "kerberoskeepalive",
    "gcloud",
    "tunneling",
    "ai",
    "work",
]

# One-line reminder of what each topic does, taken from the comments above
# each enable_* switch in group_vars/all.yml.
DESCRIPTIONS = {
    "base_dirs": "~/bin, ~/tmp, ~/Workspace ...",
    "homebrew": "brew bundle for the selected Brewfiles",
    "dotfiles": "Symlink ~/.config/* and home dotfiles back into Dotfiles/",
    "git": "~/.gitconfig, ~/.config/git/* + signing setup",
    "ssh": "~/.ssh/config, ~/.ssh/allowed_signers, directory permissions",
    "gitlab": "Renders ~/.config/gitlab/instances.yaml for the `gl` shell function",
    "kubeconfig": "~/.kube/configs for kubeconfig-add/kubeconfig-merge",
    "sudoers": "Touch ID for sudo, shared credential cache, passwordless (NOPASSWD) rules",
    "java": "Link the Homebrew JDK into /Library/Java/JavaVirtualMachines (needs sudo)",
    "kanata": "kanata build with `cmd` feature, LaunchDaemon, log rotation (needs sudo)",
    "windowmanager": "yabai + skhd LaunchAgents",
    "mail": "offlineimap/notmuch/neomutt/msmtp/omt config + sync LaunchAgents",
    "localhost_alias": "Extra 127.0.0.x addresses on lo0 (needs sudo)",
    "unbound": "unbound local DNS resolver (needs sudo)",
    "pf_vmnet_nat": "pf NAT for the kiac vmnet subnet (needs sudo)",
    "pf_vmnet_proxy": "pf redirect exposing the Alpaca proxy to the kiac vmnet (needs sudo)",
    "local_ca": "This machine's own local CA + issued intermediates (needs sudo once)",
    "trusted_cas": "Trust employer/other CA certs contributed by an overlay (needs sudo once)",
    "firefox_enterprise_roots": "Trust System-keychain CAs in Firefox-based browsers (needs sudo)",
    "privoxy": "Filtering HTTP proxy + PAC file",
    "macswitcher": "Network context switcher (proxy/DNS) + shell integration",
    "kerberoskeepalive": "Kerberos ticket keepalive LaunchAgent",
    "gcloud": "gcloud CLI components",
    "tunneling": "tunneling LaunchAgent (SSH/GCP tunnels)",
    "ai": "Shared AI skills (Claude/Copilot) + assistant configs",
    "work": "Employer-specific configuration from the work overlay (gates work mail account)",
}

# Hard, functional dependencies - taken from the "after X, which Y needs/uses"
# notes in site.yml. If a prerequisite ends up disabled, its dependents are
# switched off automatically rather than asked about.
DEPENDENCIES = {
    "unbound": ["localhost_alias", "sudoers"],
    "pf_vmnet_nat": ["sudoers"],
    "pf_vmnet_proxy": ["sudoers", "pf_vmnet_nat"],
    "privoxy": ["local_ca"],
    "macswitcher": ["privoxy"],
    "firefox_enterprise_roots": ["homebrew"],
}


def load_current_defaults(path: Path) -> dict[str, bool]:
    """Read the current enable_* values out of group_vars/all.yml."""
    defaults: dict[str, bool] = {}
    if not path.is_file():
        return defaults
    pattern = re.compile(r"^enable_(\w+):\s*(true|false)\s*$")
    for line in path.read_text().splitlines():
        match = pattern.match(line.strip())
        if match:
            defaults[match.group(1)] = match.group(2) == "true"
    return defaults


def ask_yes_no(prompt: str, default: bool) -> bool:
    suffix = "[Y/n]" if default else "[y/N]"
    while True:
        reply = input(f"{prompt} {suffix} ").strip().lower()
        if reply == "":
            return default
        if reply in ("y", "yes"):
            return True
        if reply in ("n", "no"):
            return False
        print("Please answer y or n.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"where to write the selection (default: {DEFAULT_OUTPUT})",
    )
    args = parser.parse_args()

    if not sys.stdin.isatty():
        print("This script needs a terminal to ask questions interactively.", file=sys.stderr)
        return 1

    defaults = load_current_defaults(ALL_YML)
    answers: dict[str, bool] = {}
    forced: dict[str, list[str]] = {}

    print("MacbookSetup - feature selection")
    print("Answer y/n for each topic; press Enter to accept the default shown.")
    print("Topics that need something you just disabled are switched off automatically.\n")

    for role in ROLE_ORDER:
        deps = DEPENDENCIES.get(role, [])
        unmet = [dep for dep in deps if not answers.get(dep, True)]
        if unmet:
            answers[role] = False
            forced[role] = unmet
            print(f"- {role}: disabled automatically (requires {', '.join(unmet)})")
            continue

        current_default = defaults.get(role, True)
        description = DESCRIPTIONS.get(role, "")
        label = f"Enable {role}? ({description})" if description else f"Enable {role}?"
        answers[role] = ask_yes_no(label, current_default)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "---",
        "# Generated by Scripts/select-features.py - a per-teammate feature selection",
        "# that layers on top of group_vars/all.yml without editing it.",
        "#",
        "# Apply with:",
        "#   cd Ansible",
        "#   ansible-playbook site.yml -e @local/features.yml --ask-become-pass",
        "",
    ]
    for role in ROLE_ORDER:
        comment = ""
        if role in forced:
            comment = f"  # auto-disabled: requires {', '.join(forced[role])}"
        lines.append(f"enable_{role}: {'true' if answers[role] else 'false'}{comment}")

    args.output.write_text("\n".join(lines) + "\n")

    try:
        shown_path = args.output.relative_to(REPO_ROOT)
    except ValueError:
        shown_path = args.output
    print(f"\nWrote {shown_path}")
    print("Enabled:  " + ", ".join(r for r in ROLE_ORDER if answers[r]) or "(none)")
    print("Disabled: " + ", ".join(r for r in ROLE_ORDER if not answers[r]) or "(none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
