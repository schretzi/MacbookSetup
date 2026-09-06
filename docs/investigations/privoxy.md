## Filtering proxy — privoxy

_Role: `privoxy`_
_Ansible Tag: enable_privoxy_

URL filtering for the networks where nobody else does it. On a corporate
network the company proxy already filters; at home, alpaca went straight out.
This closes that gap without changing which contexts use which path:

```
browser / CLI  ->  alpaca 127.0.0.1:3128  ->  privoxy 127.0.0.1:8118  ->  internet
                                    (proxy_mode: direct only)

browser / CLI  ->  alpaca 127.0.0.1:3128  ->  corporate proxy
                                    (proxy_mode: forward — privoxy not in the path)
```

### How alpaca is made to forward

alpaca has no "always use this upstream" flag — `-C <pac>` is its only way to
choose one. macswitcher therefore owns this: a `filter_proxy` block in
`config.yaml` generates the PAC and starts alpaca with it, for any context
whose `proxy_mode` is `direct`.

```yaml
filter_proxy:
  enabled: true
  host: 127.0.0.1
  port: 8118
  fail_open: true
  direct: [.kiac, .ts.net]
```

The generated file lands in `~/.local/state/macswitcher/filter.pac` — state,
rewritten on every switch, safe to delete. It is generated rather than
hand-written because its local-network exceptions have to agree with
`local_proxy.no_proxy`, and two hand-maintained copies of that list drift
apart. `macswitcher status` gained a `filter_proxy:` line, `observe` a
`privoxy` row, and `config validate` warns when the block is enabled but
nothing answers on the port.

**The trailing `DIRECT` is a deliberate fail-open.** privoxy down means
unfiltered browsing, not a dead network. That would be silent on its own, so
`macswitcher status` probes the port and says
`NOT LISTENING - traffic is going out unfiltered (fail_open)` when it is. Everything local — plain hostnames,
`.kiac`, `.local`, `.ts.net`, RFC1918 and CGNAT literals — returns `DIRECT`
before that line is reached, and no branch calls `dnsResolve()`, so evaluating
the PAC never costs a lookup.

### It has to be the tap build

`brew install privoxy` from homebrew-core is **not** enough. That formula
configures without `--with-openssl`, so `FEATURE_HTTPS_INSPECTION` is compiled
out (`otool -L` shows no TLS library at all) and privoxy answers every `ca-*`
directive with

```
Error: Ignoring unrecognized directive 'ca-directory ...'
```

and then runs happily, filtering nothing but plain HTTP. A proxy that silently
does not inspect looks exactly like one that does, so the role asserts on the
linked libraries rather than warning. `schretzi/tap/privoxy` is core's formula
plus `openssl@3`, `--with-openssl` and `--enable-extended-statistics`.

### HTTPS inspection, and what it costs

Without inspection privoxy sees only `CONNECT host:443` — host-level blocking,
which AdGuard Home already does at the DNS layer. Inspection is what makes URL
_paths_ filterable on HTTPS, and it works by privoxy terminating TLS with a
certificate it mints from a local CA.
