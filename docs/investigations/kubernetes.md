## Kubernetes

Dozens of clusters means dozens of kubeconfigs, and one growing
`~/.kube/config` with every cluster's certs and keys embedded inline becomes
unreadable and hard to audit. Instead, each cluster gets its own directory
under `~/.kube/configs/` holding its extracted `ca.crt`/`client.crt`/
`client.key` and a `config` that references them by full path; `~/.kube/config`
itself is a generated merge of just those `config` files, so it stays small
and secret-free.

The role only creates `~/.kube/configs` (mode `0700`, since it ends up full of
private keys) - it never touches what goes inside it. That is `kubeconfig-add`
and `kubeconfig-merge`'s job (`Dotfiles/zsh/.zsh/functions/kubeconfig`):

```bash
mkdir -p ~/.kube/configs/<name>
mv ~/Downloads/kubeconfig.yaml ~/.kube/configs/<name>/   # the cluster's original download

kubeconfig-add <name>                        # extract ca/cert/key, write config
kubeconfig-add <name> --server host:port     # ... overriding the address (SSH tunnel etc.)
kubeconfig-merge                             # (re)build ~/.kube/config from every configs/*/config
```

`<name>` becomes the cluster, context and user name, so pick something short
and unique - `kubectx`/`kubens` then work as usual against the merged
`~/.kube/config`. The CA cert is always pulled out into its own file when
present; the client certificate/key are too, if the cluster uses cert-based
auth. Clusters using a token, an `exec` plugin or `auth-provider` (OIDC etc.)
have nothing else to extract, so that part of the user entry is copied
through unchanged - still smaller than before since the CA is out of the way.
The original download can sit next to other files (notes, a README) in the
same directory; only the file that actually parses as a kubeconfig is picked
up automatically, and `--source` breaks the tie if more than one does. A
previous `~/.kube/config` is backed up (`config.bak-<timestamp>`) before each
merge, and the active context is preserved across re-merges when it still
exists.

### Switching clusters per shell

`kubectx`/`kubens` switch `current-context` in the merged `~/.kube/config`,
which is shared by every shell - fine day-to-day, but awkward when different
terminals need different clusters at the same time. `kubeconfig-use` instead
points `KUBECONFIG` at one cluster's own `~/.kube/configs/<name>/config` for
the current shell only; nothing is written to disk and other shells are
unaffected.

```bash
kubeconfig-use            # interactive picker: fzf if installed, else a
                           # numbered `select` menu - both just scroll, no
                           # typing required; <TAB> also completes names
kubeconfig-use <name>      # switch straight to <name>
kubeconfig-use -           # unset KUBECONFIG, back to the merged config
```

`kubects` is an alias for `kubeconfig-use` (`kubects <name>`, `kubects -`, ...),
named after `kubectx`/`kubens` for muscle memory.

_Role: `kubeconfig`_
_Ansible Tag: enable_kubeconfig_

GKE clusters are the exception: they have no cert to extract, and `kubectl`
authenticates live through `gke-gcloud-auth-plugin`, which needs Application
Default Credentials rather than a kubeconfig entry - see Google Cloud ->
"Application Default Credentials" below.

