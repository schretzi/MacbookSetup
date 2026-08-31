# Proxy configuration values.
#
# Seeded into ~/.zsh/rcs/proxy by the macswitcher role, as a REAL file rather
# than a symlink: macswitcher rewrites this file in place on every context
# switch, and a symlink here would write those runtime values straight back
# into this repository. Ansible copies it once and never overwrites it after,
# so the live file belongs to macswitcher from then on.
#
# These are the neutral defaults for a machine that has not switched context
# yet. `macswitcher proxy set` / `unset` replace the whole file.
# PROXY_STATE is three-valued: off | on | filtered. "filtered" means the
# local proxy is active AND a filtering proxy (privoxy) is in the path for
# the current context - "on" alone cannot tell those apart, and on this
# machine the difference is the point.
#
# It describes routing at the moment the context was applied, not liveness:
# a filter that dies afterwards still reads "filtered" here.
# `macswitcher status` probes the port and answers that question instead.
export PROXY_STATE="off"

# host:port of the filtering proxy while it is in the path, empty otherwise.
export PROXY_FILTER=""
export PROXY_HOST="127.0.0.1"
export PROXY_PORT="3128"
export PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
export PROXY_NO_PROXY="localhost,127.0.0.1,::1"
