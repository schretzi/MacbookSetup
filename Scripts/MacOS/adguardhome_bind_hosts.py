#!/usr/bin/env python3
"""Set dns.bind_hosts in AdGuard Home's config, using only the standard library.

    adguardhome_bind_hosts.py <config> <backup> <addr> [<addr> ...]

Exit status is the interface:

    0   the list already matched, nothing was written
    10  the list was changed (the old and new values are printed)
    1   the file does not have the shape this can safely edit

Why not PyYAML: this is called by /usr/local/bin/adguardhome_bind_refresh, which
runs as root from a LaunchDaemon at boot and from Ansible's become environment.
PyYAML on this machine lives in ~/Library/Python/*/site-packages - user site
packages, invisible to root - so the first version of this died with
ModuleNotFoundError once it left an interactive shell. A daemon that has to
work at boot cannot depend on a module that exists for one login account.

Why not sed: `bind_hosts` has to be the one under the top-level `dns:` mapping,
and the surrounding file is rewritten by AdGuard Home itself whenever anything
changes in the web UI - so its formatting is not ours to predict and every byte
we do not mean to touch has to be copied through verbatim. This locates the
block structurally and replaces exactly one key's list.

Both block and flow style are read, because both occur in practice here:
AdGuard Home's Go marshaller indents sequence items under the key, PyYAML (what
the earlier cutover script used) puts them at the key's own indentation, and a
hand-edit may leave `bind_hosts: []`. Output is always block style.
"""

from __future__ import annotations

import os
import re
import shutil
import sys
import tempfile

UNCHANGED, CHANGED = 0, 10


def find_dns_block(lines: list[str]) -> tuple[int, int]:
    """Return the half-open line range of the top-level `dns:` mapping."""
    start = next(
        (i for i, line in enumerate(lines) if re.match(r"^dns:\s*(#.*)?$", line)), None
    )
    if start is None:
        raise SystemExit("adguardhome_bind_hosts: no top-level 'dns:' block")

    # The block ends at the next line that starts in column 0. Blank lines and
    # comment lines inside it are indented or empty, so they do not end it.
    for i in range(start + 1, len(lines)):
        if lines[i].strip() and not lines[i][:1].isspace():
            return start, i
    return start, len(lines)


def read_bind_hosts(lines: list[str], start: int, end: int) -> tuple[int, int, str, list[str]]:
    """Locate dns.bind_hosts and read its current value.

    Returns (first line, last line, the key's indentation, the addresses).
    """
    found = None
    for i in range(start + 1, end):
        m = re.match(r"^(\s+)bind_hosts:\s*(.*?)\s*$", lines[i])
        if m:
            found = (i, m.group(1), m.group(2))
            break
    if found is None:
        raise SystemExit("adguardhome_bind_hosts: no dns.bind_hosts key")

    idx, indent, inline = found

    if inline and inline != "[]":
        addrs = [
            item.strip().strip("'\"")
            for item in inline.strip("[]").split(",")
            if item.strip()
        ]
        return idx, idx, indent, addrs

    if inline == "[]":
        return idx, idx, indent, []

    addrs, last = [], idx
    for j in range(idx + 1, end):
        m = re.match(r"^(\s*)-\s*(\S+)\s*$", lines[j])
        # A list item of *this* key is indented at least as far as the key
        # itself; anything shallower belongs to the enclosing mapping.
        if not m or len(m.group(1)) < len(indent):
            break
        addrs.append(m.group(2).strip("'\""))
        last = j
    return idx, last, indent, addrs


def write_atomically(path: str, text: str) -> None:
    """Replace path's contents without ever leaving a half-written config.

    AdGuard Home may be reading this file at any moment, and a truncated config
    is a machine with no resolver.
    """
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".")
    try:
        with os.fdopen(fd, "w") as fh:
            fh.write(text)
        shutil.copystat(path, tmp)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main(argv: list[str]) -> int:
    if len(argv) < 4:
        raise SystemExit(__doc__)

    path, backup, desired = argv[1], argv[2], argv[3:]

    with open(path) as fh:
        lines = fh.read().split("\n")

    start, end = find_dns_block(lines)
    first, last, indent, current = read_bind_hosts(lines, start, end)

    if current == desired:
        return UNCHANGED

    block = ["%sbind_hosts:" % indent] + ["%s  - %s" % (indent, a) for a in desired]

    # The backup is taken before the write, so the caller can restore a
    # byte-exact copy instead of trying to edit its way back out of a mess.
    shutil.copy2(path, backup)
    write_atomically(path, "\n".join(lines[:first] + block + lines[last + 1 :]))

    print(
        "bind_hosts: %s -> %s"
        % (" ".join(current) or "(none)", " ".join(desired))
    )
    return CHANGED


if __name__ == "__main__":
    sys.exit(main(sys.argv))
