#!/bin/sh
# Answer one question: can this machine actually talk to that server?
#
# Written for the case where something reports a host as unreachable and the
# error says nothing about which half failed - the name not resolving, or the
# port not answering. Those are different faults with different fixes, and
# guessing between them wastes the most time when a VPN is involved, because a
# tunnel that is up still leaves both halves able to fail independently:
# resolvers that live inside the tunnel, routes that only cover some subnets.
#
#   net_probe.sh <host> <port> [port...]      one host, one or more ports
#   net_probe.sh --realm <KERBEROS-REALM>     discover a realm's KDCs, test all
#
# Examples:
#   net_probe.sh www-proxy.corp.example 8080
#   net_probe.sh --realm CORP.EXAMPLE.COM
#
# The realm mode exists because "kinit: unable to reach any KDC in realm X,
# tried 0 KDCs" is not a reachability failure at all - "tried 0" means kinit
# never found a KDC to try. With no /etc/krb5.conf there is nothing configured
# statically, so it discovers them over DNS, and a failed SRV lookup produces
# the same message as a genuinely dead KDC would. This separates the two.

set -u

DNS_TIMEOUT=3
TCP_TIMEOUT=5

usage() {
	sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
	exit 2
}

# resolve prints the addresses for a name, or nothing if it does not resolve.
# dig is asked directly rather than going through dscacheutil so that a failure
# here is a DNS failure and not macOS's cache having an opinion.
#
# dig reports "no servers could be reached" on stdout and still exits 0, so the
# output is filtered to the shape being asked for rather than trusted - taking
# it at face value turns an unreachable resolver into a bogus answer.
resolve() {
	dig +short +time="$DNS_TIMEOUT" +tries=1 "$1" A 2>/dev/null |
		grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$'
}

# probe_port reports whether host:port completes a TCP handshake.
probe_port() {
	_host=$1
	_port=$2
	if nc -z -G "$TCP_TIMEOUT" -w "$TCP_TIMEOUT" "$_host" "$_port" 2>/dev/null; then
		printf '  port %-6s OPEN\n' "$_port"
		return 0
	fi
	printf '  port %-6s no answer\n' "$_port"
	return 1
}

# probe_host resolves a name and then tests each port against it, reporting the
# two failures separately - an unresolvable name is never a port problem.
probe_host() {
	_host=$1
	shift
	printf '%s\n' "$_host"

	_addrs=$(resolve "$_host")
	if [ -z "$_addrs" ]; then
		echo "  DNS       does not resolve"
		echo "  -> the name is the problem, not the server. On a VPN, check that"
		echo "     the resolver for this domain is reachable through the tunnel."
		return 1
	fi
	echo "  DNS       $(echo "$_addrs" | tr '\n' ' ')"

	_rc=1
	for _port in "$@"; do
		if probe_port "$_host" "$_port"; then
			_rc=0
		fi
	done
	if [ "$_rc" != 0 ]; then
		echo "  -> the name resolves but nothing answers. Check routes and"
		echo "     firewall rather than DNS."
	fi
	return "$_rc"
}

# probe_realm discovers a Kerberos realm's KDCs over DNS and tests each one.
# Discovery is reported on its own because kinit's "tried 0 KDCs" means it
# never got this far, and no amount of KDC-side debugging helps in that case.
probe_realm() {
	_realm=$1
	_srv="_kerberos._tcp.$_realm"
	echo "realm     $_realm"
	echo "discovery $_srv"

	# A `+short` SRV answer is "<priority> <weight> <port> <target>."; anything
	# else on stdout is dig complaining, which it does while still exiting 0.
	# Matching the shape keeps ";; connection timed out" from being mistaken
	# for a KDC named "out;".
	_kdcs=$(dig +short +time="$DNS_TIMEOUT" +tries=1 "$_srv" SRV 2>/dev/null |
		awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && NF == 4 {
			sub(/\.$/, "", $4); print $4
		}')
	if [ -z "$_kdcs" ]; then
		echo "  SRV       no records"
		echo
		echo "This is what kinit reports as \"tried 0 KDCs\": it found no KDC to"
		echo "contact, so nothing was ever unreachable. Either the realm's domain"
		echo "is being resolved by a server that does not hold these records, or"
		echo "the resolver for it is not reachable right now."
		echo
		echo "Check which resolver answers for the realm's domain:"
		echo "  dig +short $(echo "$_realm" | tr '[:upper:]' '[:lower:]') SOA"
		return 1
	fi

	echo "  SRV       $(echo "$_kdcs" | tr '\n' ' ')"
	echo
	_rc=1
	for _kdc in $_kdcs; do
		if probe_host "$_kdc" 88; then
			_rc=0
		fi
	done
	if [ "$_rc" != 0 ]; then
		echo
		echo "KDCs were discovered but none answered on 88; this is a routing or"
		echo "firewall question, not a DNS one."
	fi
	return "$_rc"
}

[ "$#" -ge 1 ] || usage

case $1 in
--realm)
	[ "$#" -eq 2 ] || usage
	probe_realm "$2"
	;;
-h | --help)
	usage
	;;
*)
	[ "$#" -ge 2 ] || usage
	probe_host "$@"
	;;
esac
