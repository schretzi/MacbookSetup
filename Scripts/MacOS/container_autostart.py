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

Cluster node VMs are never started with `container start`. That boots the VM
and produces a cluster that looks up and is not: the node's address changed, so
~/.kube/config points at nothing, the kubeadm certs need healing and Cilium
needs a helm upgrade with a fresh k8sServiceHost. LocalKubernetes'
playbooks/resume.yml does all of that in order (and ends by refreshing DNS and
unsealing OpenBao), so a cluster is either resumed through that playbook or
left alone.

Which clusters get resumed is not a list kept here. LocalKubernetes already
draws the distinction, in inventory/host_vars/<cluster>.yml:

    cluster_role: main    -> "meant to run continuously (hosts OpenBao +
                             ArgoCD)"
    cluster_role: test    -> "disposable test clusters, stopped/resumed on
                             demand"

(README, "Design"). So `cluster_role: main` is read at run time and only those
clusters are resumed - a new test cluster is correctly ignored the day it is
created, without anything here being edited.

Two further limits on that, because a resume is expensive (main is 3 node VMs,
12 GB of memory, and a playbook that takes minutes) and unattended:

- Only on the first run after a boot, never on the periodic tick. The tick
  exists to catch a stopped container, not to fight a human who just ran
  `kiac stop cluster`.
- Only if the cluster was still running when this script last looked. A
  deliberate `kiac stop cluster main` is recorded within one tick and then
  respected forever; a crash is not, because the crash left the state saying
  "running". The one case that gets this wrong is stopping a cluster and
  powering the machine off inside the same tick - it comes back once.

A failed resume raises a notification rather than only a log line: a
half-resumed cluster is otherwise noticed hours later, as something unreachable.

Exit status is the interface:

    0   nothing to do, or everything done
    1   the runtime could not be started, or the container list was unreadable
        (nothing else was attempted)
"""

import fcntl
import json
import os
import re
import signal
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

# Where LocalKubernetes lives. Read from the kiac-dns-update wrapper, which is
# Ansible-managed and already carries the answer, so the path is not stated
# twice; the constant is only the fallback for a machine without the wrapper.
DNS_WRAPPER_REPO_RE = re.compile(r'^REPO_ROOT="([^"]+)"', re.MULTILINE)
LOCALKUBERNETES = HOME / "Workspace/Schretzi/LocalKubernetes"

# A resume boots node VMs, heals kubeadm state, runs a Cilium helm upgrade,
# re-renders DNS and unseals OpenBao with retries. Minutes, legitimately.
RESUME_TIMEOUT = 1800

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

    Always bounded, and bounded for real. Every tool here can hang: a
    `container` call whose XPC peer died blocks forever, and that is precisely
    the state this script exists to recover from. An unbounded child would be
    worse than useless - launchd does not start a second instance while the
    first is alive, so one hung run silently retires the 300s safety net, and
    the hung process keeps the lock so manual runs bail out too.

    Not subprocess.run(timeout=...): on a timeout that kills only the direct
    child and then waits, with no timeout of its own, for the stdout pipe to
    close - which needs every process holding it to exit. ansible-playbook
    forks workers that inherit it, so killing the parent is not enough and the
    "bounded" call blocks anyway. Running the child in its own session lets the
    whole group be signalled instead.

    A timeout is reported the way a non-zero exit is, so callers need no extra
    branch: returncode 124, matching timeout(1).
    """
    try:
        proc = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
            **kwargs,
        )
    except OSError as exc:
        return subprocess.CompletedProcess(args, 127, "", str(exc))

    try:
        stdout, stderr = proc.communicate(timeout=timeout)
        return subprocess.CompletedProcess(args, proc.returncode, stdout, stderr)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except OSError:
            proc.kill()
        try:
            stdout, stderr = proc.communicate(timeout=10)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                proc.kill()
            stdout, stderr = "", ""
        return subprocess.CompletedProcess(
            args, 124, stdout or "", f"timed out after {timeout}s\n{stderr or ''}"
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


def boot_time():
    """The current boot's identity, so a boot run can be told from a tick.

    kern.boottime is stable for the life of a boot and changes across one, which
    is exactly the question - unlike an uptime threshold, which guesses.
    """
    result = run(["/usr/sbin/sysctl", "-n", "kern.boottime"])
    if result.returncode != 0:
        return None
    match = re.search(r"sec\s*=\s*(\d+)", result.stdout)
    return match.group(1) if match else None


def notify(message):
    """A notification, because a log line nobody reads is not a report.

    Best effort: this is a user-session agent so osascript is available, but a
    failure to notify must never fail the run.
    """
    log(message)
    osascript = which("osascript")
    if not osascript:
        return
    script = (
        'display notification {} with title "Container autostart"'.format(
            json.dumps(message)
        )
    )
    run([osascript, "-e", script], timeout=15)


def localkubernetes_root():
    wrapper = which("kiac-dns-update")
    if wrapper:
        try:
            match = DNS_WRAPPER_REPO_RE.search(Path(wrapper).read_text())
        except OSError:
            match = None
        if match:
            return Path(match.group(1))
    return LOCALKUBERNETES


def continuous_clusters(root):
    """Clusters whose host_vars say `cluster_role: main`.

    Read at run time rather than configured here: LocalKubernetes already
    distinguishes the cluster that is meant to run continuously from the
    disposable test ones, and a second copy of that decision would drift the
    first time a cluster is added.

    Parsed with a regex rather than a YAML library on purpose - this runs as a
    root-owned script, and PyYAML is installed in the user's site-packages
    where root cannot see it. The files are Ansible-authored `key: value`.
    """
    found = set()
    host_vars = root / "inventory/host_vars"
    try:
        candidates = sorted(host_vars.glob("*.yml"))
    except OSError:
        return found
    for path in candidates:
        try:
            text = path.read_text()
        except OSError:
            continue
        match = re.search(r"^cluster_role:\s*(\S+)", text, re.MULTILINE)
        if match and match.group(1) == "main":
            found.add(path.stem)
    return found


def cluster_states(containers, cluster_nodes):
    """cluster name -> True if any of its node VMs is running.

    Derived from the node containers rather than asked of kiac, so it stays
    right when kiac cannot answer.
    """
    states = {}
    for entry in containers:
        name = entry.get("configuration", {}).get("id", "")
        if not is_cluster_node(name, cluster_nodes):
            continue
        cluster = re.sub(r"^kiac-", "", name)
        cluster = re.sub(r"-(control-plane|worker-\d+)$", "", cluster)
        running = entry.get("status", {}).get("state") == "running"
        states[cluster] = states.get(cluster, False) or running
    return states


def resume_cluster(root, name):
    """Hand the cluster to the playbook that knows how to heal it."""
    playbook = which("ansible-playbook")
    if not playbook:
        notify(f"ansible-playbook not found; cannot resume cluster {name}")
        return False

    log("resuming cluster {} (this takes minutes)".format(name))
    result = run(
        [playbook, "playbooks/resume.yml", "--limit", name],
        cwd=str(root),
        timeout=RESUME_TIMEOUT,
    )
    if result.returncode != 0:
        notify(
            "resume of cluster {} failed - it may be half up. "
            "Check ~/Library/Logs/container-autostart.log".format(name)
        )
        log(f"{result.stdout.strip()}\n{result.stderr.strip()}")
        return False
    log(f"cluster {name} resumed")
    return True


def read_state():
    """The previous run's view of the world.

    Shape:
        {"addresses": {name: ipv4}, "clusters": {name: bool}, "boot": "<sec>"}

    The first version of this file was a bare {name: ipv4} map. Migrate it
    rather than discard it, so the upgrade does not force one pointless DNS
    re-render, and so a cluster is not resumed on the strength of a missing key.
    """
    try:
        state = json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {"addresses": {}, "clusters": {}, "boot": None}
    if "addresses" not in state:
        return {"addresses": state, "clusters": {}, "boot": None}
    state.setdefault("addresses", {})
    state.setdefault("clusters", {})
    state.setdefault("boot", None)
    return state


def write_state(state):
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, indent=2, sort_keys=True))


def resume_clusters(containers, cluster_nodes, state, first_run_this_boot):
    """Resume the continuously-running clusters that a crash took down.

    Returns (resumed_any, failed) - `failed` being the clusters that were
    attempted and did not come up, which the caller must keep marked as
    "was running" so the next boot tries again.
    """
    if not first_run_this_boot:
        return False, set()

    down = {
        name: running
        for name, running in cluster_states(containers, cluster_nodes).items()
        if not running
    }
    if not down:
        return False, set()

    root = localkubernetes_root()
    if not root.is_dir():
        return False, set()

    wanted = continuous_clusters(root)
    resumed = False
    failed = set()
    for name in sorted(down):
        if name not in wanted:
            continue
        if not state["clusters"].get(name, False):
            # It was already down when this script last looked, so it was
            # stopped on purpose rather than lost. Leave it.
            log(f"cluster {name} was stopped before the last shutdown; leaving it")
            continue
        if resume_cluster(root, name):
            resumed = True
        else:
            failed.add(name)
    return resumed, failed


def report_stopped_nodes(containers, cluster_nodes):
    stopped = [
        entry["configuration"]["id"]
        for entry in containers
        if entry.get("status", {}).get("state") != "running"
        and is_cluster_node(entry.get("configuration", {}).get("id", ""), cluster_nodes)
    ]
    if stopped:
        log(
            f"{len(stopped)} cluster node(s) are stopped and were left alone; "
            "recover a cluster with `ansible-playbook playbooks/resume.yml --limit <name>`"
        )


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

    state = read_state()
    boot = boot_time()
    first_run_this_boot = boot is not None and boot != state["boot"]
    if first_run_this_boot:
        # Claim the boot now, before any work, rather than recording it at the
        # end. Every early return below - a playbook already running, an
        # unreadable container list, a runtime that will not start - would
        # otherwise leave the marker unadvanced, so the next 300s tick would
        # still look like the first run after a boot. That is not cosmetic:
        # the resume decision is gated on it, so a cluster the user stopped by
        # hand ten minutes into the session would be read as "lost in the
        # crash" and brought back against their wishes. Losing one resume to a
        # failed boot run is the far cheaper mistake, and it says so in the log.
        state["boot"] = boot
        write_state(state)

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

    resumed, resume_failed = resume_clusters(
        containers, cluster_nodes, state, first_run_this_boot
    )

    containers = list_containers(container)
    if containers is None:
        return 1
    current = addresses(containers, cluster_nodes)
    clusters_now = cluster_states(containers, cluster_nodes)

    # A cluster whose resume failed keeps its old "was running" flag. Recording
    # the state we can see would say "stopped", which on the next boot is
    # indistinguishable from the user having stopped it deliberately - so one
    # transient failure would silently retire the cluster from autostart
    # forever. This matters most for a failure early in resume.yml, before kiac
    # has booted the node VMs, because then the nodes really are still down.
    for name in resume_failed:
        clusters_now[name] = True

    # Recorded on every run, not only the ones that touch DNS: this is the
    # answer to "was it running before the crash", and it has to be current.
    state["clusters"] = clusters_now

    if current == state["addresses"]:
        write_state(state)
        report_stopped_nodes(containers, cluster_nodes)
        return 0

    # Again, not only at the top. Starting the containers above is serial, the
    # settle poll adds up to ADDRESS_SETTLE_TIMEOUT on top, and a resume takes
    # minutes - so a long time has passed since the first check, ample for a
    # resume.yml to have been started by hand and to have reached its own
    # closing DNS refresh. This is the point the guard actually protects.
    if playbook_running():
        log("a LocalKubernetes playbook started meanwhile; leaving DNS to it")
        write_state(state)
        return 0

    if resumed:
        # resume.yml ends with its own host_dns pass, with wait_for_gateway
        # enabled - a strictly better render than the one here, because it also
        # carries the per-app Gateway records. Re-running it would only risk
        # replacing that with a skeleton, so just adopt the result.
        log(f"addresses changed: {json.dumps(current, sort_keys=True)}")
        log("DNS already refreshed by resume.yml")
        write_state(state | {"addresses": current})
        report_stopped_nodes(containers, cluster_nodes)
        return 0

    log(f"addresses changed: {json.dumps(current, sort_keys=True)}")
    if update_dns(clusters_running(containers, cluster_nodes)):
        # Only on success: a failed refresh must not be remembered as applied,
        # or the zone stays stale until the next address change.
        state["addresses"] = current
    write_state(state)

    report_stopped_nodes(containers, cluster_nodes)
    return 0


if __name__ == "__main__":
    sys.exit(main())
