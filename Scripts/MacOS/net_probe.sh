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

# srv_targets prints the target names of an SRV answer, one per line.
#
# A `+short` SRV answer is "<priority> <weight> <port> <target>."; anything
# else on stdout is dig complaining, which it does while still exiting 0.
# Matching the shape keeps ";; connection timed out" from being mistaken for a
# KDC named "out;". $2 is an optional "@server" argument.
srv_targets() {
	# shellcheck disable=SC2086 # $2 is an optional @server, deliberately split
	dig +short +time="$DNS_TIMEOUT" +tries=1 ${2:-} "$1" SRV 2>/dev/null |
		awk '$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/ && NF == 4 {
			sub(/\.$/, "", $4); print $4
		}'
}

# probe_realm discovers a Kerberos realm's KDCs over DNS and tests each one.
#
# Discovery is reported on its own because kinit's "tried 0 KDCs" means it
# never got that far, and no amount of KDC-side debugging helps in that case.
#
# When the usual lookup finds nothing, the realm's own SOA nameserver is asked
# directly. That distinguishes the two reasons for an empty answer, which need
# opposite fixes: a local resolver that does not carry the records (fix the
# resolver) versus a zone that genuinely does not publish them (configure the
# KDCs statically, since discovery is never going to work).
probe_realm() {
	_realm=$1
	_lc=$(echo "$_realm" | tr '[:upper:]' '[:lower:]')
	echo "realm     $_realm"

	# _tcp is what kinit prefers; _udp is checked too so that a realm
	# publishing only the UDP records is not reported as publishing none.
	_kdcs=""
	for _proto in _tcp _udp; do
		_srv="_kerberos.$_proto.$_realm"
		_found=$(srv_targets "$_srv")
		if [ -n "$_found" ]; then
			echo "  SRV       $_srv -> $(echo "$_found" | tr '\n' ' ')"
			_kdcs=$(printf '%s\n%s' "$_kdcs" "$_found")
		else
			echo "  SRV       $_srv -> nothing"
		fi
	done
	_kdcs=$(echo "$_kdcs" | grep -v '^$' | sort -u)

	if [ -z "$_kdcs" ]; then
		probe_realm_no_records "$_realm" "$_lc"
		return 1
	fi

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

# probe_realm_no_records works out why discovery came back empty, by asking the
# zone's own nameserver what the local resolver could not answer.
probe_realm_no_records() {
	_realm=$1
	_lc=$2
	echo
	echo "No KDC records came back. This is what kinit reports as \"tried 0"
	echo "KDCs\": it found none to contact, so nothing was ever unreachable."
	echo

	_soa=$(dig +short +time="$DNS_TIMEOUT" +tries=1 "$_lc" SOA 2>/dev/null |
		awk 'NF >= 7 {sub(/\.$/, "", $1); print $1; exit}')
	if [ -z "$_soa" ]; then
		echo "The realm's domain ($_lc) does not resolve at all, so the records"
		echo "could not have been found. Fix name resolution for that domain"
		echo "first - on a VPN, that usually means the resolver holding it is"
		echo "not reachable through the tunnel yet."
		return
	fi
	echo "zone      $_lc is served by $_soa"

	_soa_ip=$(resolve "$_soa" | head -1)
	if [ -z "$_soa_ip" ]; then
		echo "          (which does not itself resolve; cannot ask it directly)"
		return
	fi
	echo "asking    $_soa_ip directly, bypassing the local resolver"

	_direct=""
	for _proto in _tcp _udp; do
		_found=$(srv_targets "_kerberos.$_proto.$_realm" "@$_soa_ip")
		[ -n "$_found" ] && _direct=$(printf '%s\n%s' "$_direct" "$_found")
	done
	_direct=$(echo "$_direct" | grep -v '^$' | sort -u)

	echo
	if [ -n "$_direct" ]; then
		echo "  -> the zone DOES publish KDCs: $(echo "$_direct" | tr '\n' ' ')"
		echo "     The local resolver is what is losing them. Check that the"
		echo "     per-domain upstream for this zone points at a server that"
		echo "     is reachable and authoritative."
	else
		echo "  -> the zone publishes no _kerberos SRV records at all, so DNS"
		echo "     discovery is never going to find a KDC here. Name the KDCs"
		echo "     statically instead, in a krb5.conf:"
		echo
		echo "       [realms]"
		echo "         $_realm = {"
		echo "           kdc = <domain-controller>"
		echo "         }"
		echo
		echo "     Domain controllers usually answer _ldap._tcp; try:"
		echo "       dig +short @$_soa_ip _ldap._tcp.$_lc SRV"
	fi
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
