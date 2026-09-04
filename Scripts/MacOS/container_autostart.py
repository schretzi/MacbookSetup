#!/usr/bin/env python3
"""Bring the container runtime and its service containers back after a boot.

Deployed to /usr/local/bin/container_autostart by the Ansible role
"container_autostart" and run by
~/Library/LaunchAgents/com.schretzi.container-autostart.plist - at login, and
then every few minutes as a safety net. Safe to re-run at any time: it starts
only what is stopped and touches DNS only when an address actually changed.

Three separate things are broken after a reboot or a crash, and only the last
one was automated before this script existed:

1. The runtime itself is gone. `container system start` writes its LaunchAgent
   to ~/Library/Application Support/com.apple.container/apiserver/apiserver.plist
   and bootstraps it from there - outside ~/Library/LaunchAgents, which is the
   only place launchd loads from on its own. So the API server does not come
   back at login and every `container` command fails with
   "XPC connection error: Connection invalid".

   Re-running `container system start` also rewrites that plist, which quietly
   fixes a second problem: its ProgramArguments carry the versioned Homebrew
   Cellar path (.../Cellar/container/<version>/libexec/container-apiserver), so
   a `brew upgrade container` leaves the registered job pointing at a path that
   no longer exists.

2. Nothing starts the containers. apple/container has no restart policy - there
   is no `--restart always` - so every container stays `stopped` until someone
   says otherwise.

3. Their addresses are new. The vmnet hands out 192.168.64.x by DHCP in start
   order, so every container's IP moves, and /etc/adguardhome/zones/kiac.txt
   still names yesterday's. `com.schretzi.adguardhome-bind` already re-binds
   AdGuard Home to the vmnet gateway on its own 60s timer; it does not know
   anything about which name maps to which container.

Cluster node VMs are deliberately NOT started here. `container start
kiac-main-control-plane` boots the VM and produces a cluster that looks up and
is not: the node's address changed, so ~/.kube/config points at nothing, the
kubeadm certs need healing and Cilium needs a helm upgrade with a fresh
k8sServiceHost. That is what LocalKubernetes' playbooks/resume.yml is for, and
it ends by refreshing DNS itself. Starting them here would produce a broken
cluster that no longer announces itself as broken.

Exit status is the interface:

    0   nothing to do, or everything done
    1   the runtime could not be started (nothing else was attempted)
"""

import fcntl
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HOME = Path.home()

# launchd gives a job PATH=/usr/bin:/bin:/usr/sbin:/sbin, so every Homebrew
# binary has to be found rather than assumed.
SEARCH_PATH = ["/opt/homebrew/bin", "/usr/local/bin", str(HOME / "bin"), "/usr/bin", "/bin"]

# apple/container's own builder VM. It is started on demand by `container
# build` and costs 2 GB of memory while idle, so it is not part of a login.
SKIP = {"buildkit"}

STATE_FILE = HOME / ".local/state/container-autostart/addresses.json"
LOCK_FILE = HOME / ".local/state/container-autostart/lock"

# Long enough for a container to be handed a DHCP address, short enough that a
# login is not visibly delayed by it. A container that takes longer is simply
# picked up by the next scheduled run.
ADDRESS_SETTLE_TIMEOUT = 30
ADDRESS_SETTLE_INTERVAL = 2


def log(message):
    print(f"{time.strftime('%Y-%m-%dT%H:%M:%S')}  {message}", flush=True)


def which(name):
    for directory in SEARCH_PATH:
        candidate = Path(directory) / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def run(args, timeout=120, **kwargs):
    """Run a command, capturing output, never raising.

    Always bounded. Every tool here can hang: a `container` call whose XPC
    peer died blocks forever, and that is precisely the state this script
    exists to recover from. An unbounded child would be worse than useless -
    launchd does not start a second instance while the first is alive, so one
    hung run silently retires the 300s safety net, and the hung process keeps
    the lock so manual runs bail out too.

    A timeout is reported the same way a non-zero exit is, so callers need no
    extra branch: returncode 124, matching timeout(1).
    """
    try:
        return subprocess.run(
            args, capture_output=True, text=True, check=False, timeout=timeout, **kwargs
        )
    except subprocess.TimeoutExpired as exc:
        return subprocess.CompletedProcess(
            args, 124, exc.stdout or "", f"timed out after {timeout}s"
        )


def proxy_environment():
    """The proxy variables macswitcher maintains, as a dict.

    `container system start` bakes the environment it was run in into the
    API server's plist, and the API server is what pulls images. Started from
    a login shell it inherits the proxy; started from launchd it inherits
    nothing, and image pulls then bypass the local proxy and fail on any
    network that requires it. Reading macswitcher's own rc file keeps the two
    in step without duplicating the values - it is rewritten on every context
    switch, so this always picks up the current network's settings.
    """
    rc = HOME / ".zsh/rcs/proxy"
    env = {}
    try:
        text = rc.read_text()
    except OSError:
        return env
    for line in text.splitlines():
        match = re.match(r'^\s*export\s+([A-Za-z_][A-Za-z0-9_]*)="(.*)"\s*$', line)
        if match:
            env[match.group(1)] = match.group(2)
    return env


def ensure_runtime(container):
    if run([container, "system", "status"]).returncode == 0:
        return True

    log("container runtime is not running, starting it")
    env = dict(os.environ)
    env.update(proxy_environment())
    # --disable-kernel-install: the prompt it would otherwise raise has no one
    # to answer it here, and the kernel is installed already on a machine that
    # has been running containers.
    result = run(
        [container, "system", "start", "--disable-kernel-install", "--timeout", "60"],
        env=env,
    )
    if result.returncode != 0:
        log(f"failed to start the runtime: {result.stderr.strip()}")
        return False
    log("runtime started")
    return True


def cluster_node_names(kiac):
    """Container names that belong to a kiac cluster, from kiac itself.

    Asked at run time rather than kept as a list here: clusters are created and
    destroyed without this script hearing about it, and a stale list would
    either start a node VM behind resume.yml's back or skip a service container
    that happens to be named like one.
    """
    if kiac:
        result = run([kiac, "get", "clusters", "-o", "json"])
        if result.returncode == 0:
            try:
                clusters = json.loads(result.stdout)
            except json.JSONDecodeError:
                clusters = None
            if clusters is not None:
                return {
                    node["name"]
                    for cluster in clusters
                    for node in cluster.get("nodes", [])
                }
    # kiac gone or unreadable. Its containers are all named kiac-<cluster>-<role>,
    # so fall back to that rather than risk starting a node VM directly.
    log("could not ask kiac for its clusters; excluding kiac-* by name instead")
    return None


def list_containers(container):
    """Every container the runtime knows about, or None if it could not say.

    None and [] must stay distinct. An empty list is a legitimate answer that
    means "nothing to start, nothing to publish"; a failed query looks
    identical but every conclusion drawn from it is wrong - it would report no
    running clusters (so suppress the Gateway wait), differ from the stored
    fingerprint (so re-render the zone), and then record the empty map as
    successfully applied.
    """
    result = run([container, "list", "--all", "--format", "json"])
    if result.returncode != 0:
        log(f"could not list containers: {result.stderr.strip()}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        log("could not parse the container list")
        return None


def is_cluster_node(name, cluster_nodes):
    """Both rules, always, rather than one as a fallback for the other.

    kiac derives its cluster list from the container name alone and silently
    drops any kiac-* container whose suffix it cannot parse as -control-plane
    or -worker-N. Such a node reduces `kiac get clusters` to [], which is a
    successful answer - so a prefix rule that only runs when kiac is *missing*
    never sees it, and the node VM gets started.

    The two rules are meant to describe the same set, so applying both costs
    nothing. The asymmetry of being wrong decides it: over-excluding skips a
    service container that happens to be named kiac-*, under-excluding boots a
    cluster that no longer reports itself as broken.
    """
    if name.startswith("kiac-"):
        return True
    return cluster_nodes is not None and name in cluster_nodes


def addresses(containers, cluster_nodes):
    """name -> IPv4 address, for the running service containers.

    This is what the AdGuard Home zone is rendered from, so it is also exactly
    the thing worth comparing between runs.
    """
    found = {}
    for entry in containers:
        name = entry.get("configuration", {}).get("id")
        status = entry.get("status", {})
        if not name or status.get("state") != "running":
            continue
        if is_cluster_node(name, cluster_nodes) or name in SKIP:
            continue
        for network in status.get("networks") or []:
            address = network.get("ipv4Address")
            if address:
                found[name] = address.split("/")[0]
                break
    return found


def start_stopped(container, containers, cluster_nodes):
    started = []
    for entry in containers:
        name = entry.get("configuration", {}).get("id")
        if not name or entry.get("status", {}).get("state") == "running":
            continue
        if name in SKIP or is_cluster_node(name, cluster_nodes):
            continue
        result = run([container, "start", name])
        if result.returncode == 0:
            started.append(name)
        else:
            log(f"could not start {name}: {result.stderr.strip()}")
    return started


def refresh_adguard_bind():
    """Re-bind AdGuard Home to the vmnet gateway now rather than within 60s.

    192.168.64.1 exists only while at least one container runs, and AdGuard
    Home refuses to start on an address it cannot bind, so the bind list has to
    follow the interface. com.schretzi.adguardhome-bind polls for this every
    60 seconds; calling it directly means the containers we just started have a
    resolver immediately instead of up to a minute later. The sudoers rule for
    it already exists for exactly this reason.
    """
    script = "/usr/local/bin/adguardhome_bind_refresh"
    if not Path(script).exists():
        return
    result = run(["/usr/bin/sudo", "-n", script])
    if result.returncode != 0:
        log(f"adguardhome_bind_refresh failed: {result.stderr.strip()}")


def playbook_running():
    """True while a LocalKubernetes playbook is in flight.

    create/resume/destroy start and stop containers and re-render the same zone
    file this script would. Two writers produce a zone that matches neither, so
    stand down: every one of those playbooks ends with its own DNS refresh, and
    the next scheduled run will see the result.
    """
    result = run(["/usr/bin/pgrep", "-f", "ansible-playbook.*playbooks/"])
    return result.returncode == 0


def clusters_running(containers, cluster_nodes):
    for entry in containers:
        name = entry.get("configuration", {}).get("id")
        if not name or entry.get("status", {}).get("state") != "running":
            continue
        if is_cluster_node(name, cluster_nodes):
            return True
    return False


def update_dns(any_cluster_running):
    """Re-render the AdGuard Home zone through LocalKubernetes' own playbook.

    Not reimplemented here: the zone carries cluster Gateway addresses and
    per-app names as well as these containers, and roles/host_dns is where that
    template lives.
    """
    wrapper = which("kiac-dns-update")
    if not wrapper:
        log("kiac-dns-update not installed; skipping the DNS refresh")
        return False

    args = [wrapper]
    if not any_cluster_running:
        # dns-update.yml asks each cluster for its Gateway address and retries
        # for 150s before giving up. With every cluster stopped that is a
        # guaranteed five-minute wait for an answer we already know, so say so.
        #
        # As JSON, not `-e key=false`: that form passes the string "false",
        # and the role's `when: host_dns_wait_for_gateway | default(false)`
        # then fails outright, because Ansible refuses a conditional whose
        # result came from a non-boolean.
        args += ["-e", json.dumps({"host_dns_wait_for_gateway": False})]

    # Far more than the 120s default: this is a whole ansible-playbook run, and
    # with clusters up it legitimately spends 150s per cluster waiting for
    # Gateway addresses. Still bounded, because an ansible run that wedges
    # would otherwise hold the lock and retire the safety net.
    result = run(args, timeout=900)
    if result.returncode != 0:
        log(f"kiac-dns-update failed:\n{result.stdout.strip()}\n{result.stderr.strip()}")
        return False
    log("DNS zone refreshed")
    return True


def read_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def write_state(current):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(current, indent=2, sort_keys=True))


def main():
    # Once, for every subprocess below rather than for the ones that obviously
    # need it: launchd gives a job PATH=/usr/bin:/bin:/usr/sbin:/sbin, and these
    # tools shell out to each other. `kiac get clusters` runs `container` and
    # fails with "executable file not found in $PATH" without this - and it
    # fails in a way that reads like kiac being broken rather than unreachable.
    os.environ["PATH"] = os.pathsep.join(
        SEARCH_PATH + [p for p in os.environ.get("PATH", "").split(os.pathsep) if p]
    )

    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    lock = open(LOCK_FILE, "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        # A previous run is still going. Its scheduled successor is five
        # minutes away; overlapping them would race on both the container list
        # and the zone file. Say so - silence here and a hung predecessor look
        # identical in the log, and the second one needs noticing.
        log("another run still holds the lock; standing down")
        return 0

    container = which("container")
    if not container:
        log("the container CLI is not installed; nothing to do")
        return 0

    if playbook_running():
        log("a LocalKubernetes playbook is running; standing down")
        return 0

    if not ensure_runtime(container):
        return 1

    cluster_nodes = cluster_node_names(which("kiac"))
    containers = list_containers(container)
    if containers is None:
        return 1

    started = start_stopped(container, containers, cluster_nodes)
    if started:
        log(f"started: {', '.join(sorted(started))}")
        refresh_adguard_bind()

        # An address only exists once the guest has been given one, which is
        # not the moment `container start` returns.
        deadline = time.monotonic() + ADDRESS_SETTLE_TIMEOUT
        while time.monotonic() < deadline:
            settling = list_containers(container)
            if settling is None:
                break
            containers = settling
            current = addresses(containers, cluster_nodes)
            if all(name in current for name in started):
                break
            time.sleep(ADDRESS_SETTLE_INTERVAL)

    containers = list_containers(container)
    if containers is None:
        return 1
    current = addresses(containers, cluster_nodes)

    if current == read_state():
        return 0

    # Again, not only at the top. Starting the containers above is serial and
    # the settle poll adds up to ADDRESS_SETTLE_TIMEOUT on top, so a minute or
    # more has passed since the first check - ample time for a resume.yml to
    # have started and reached its own closing DNS refresh. This is the point
    # the guard actually protects, and pgrep is cheap.
    if playbook_running():
        log("a LocalKubernetes playbook started meanwhile; leaving DNS to it")
        return 0

    log(f"addresses changed: {json.dumps(current, sort_keys=True)}")
    if update_dns(clusters_running(containers, cluster_nodes)):
        # Only on success: a failed refresh must not be remembered as applied,
        # or the zone stays stale until the next address change.
        write_state(current)

    stopped_nodes = [
        entry["configuration"]["id"]
        for entry in containers
        if entry.get("status", {}).get("state") != "running"
        and is_cluster_node(entry.get("configuration", {}).get("id", ""), cluster_nodes)
    ]
    if stopped_nodes:
        log(
            f"{len(stopped_nodes)} cluster node(s) are stopped and were left alone; "
            "recover a cluster with `ansible-playbook playbooks/resume.yml --limit <name>`"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
