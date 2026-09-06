# Little Snitch

The outbound firewall goes on before anything else starts talking to the
internet — which is also why it is deliberately **not** in a Brewfile: by the
time the `homebrew` role runs, it should already be filtering.

```bash
brew install --cask little-snitch
```

It installs a network system extension; approve it in **System Settings →
Privacy & Security** and reboot when asked:

```bash
systemextensionsctl list | grep littlesnitch   # [activated enabled]
```

There is no ruleset to import yet, so the first hours on an empty rule list are
brutal — every process asks, and you approve blindly. Start in **Silent Mode —
Allow Connections** instead: Little Snitch records the rules without prompting.
A day or two later, review what accumulated, keep the obvious ones (Apple,
Microsoft, Google), and drop the rest. Then switch back to **Alert Mode** so new
connections ask again.
