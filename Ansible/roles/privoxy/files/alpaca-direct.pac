// alpaca's PAC for macswitcher contexts whose proxy_mode is `direct`.
//
// Seeded to ~/.config/macswitcher/privoxy.pac by MacbookSetup's privoxy role;
// the source of truth is Ansible/roles/privoxy/files/alpaca-direct.pac.
//
// alpaca has no "forward everything to X" flag - a PAC file is its only way
// of choosing an upstream (`alpaca -C file://...`), so this is what turns
// "alpaca goes straight out" into "alpaca goes out through privoxy".
//
// The trailing DIRECT is a deliberate fail-open: if privoxy is not listening,
// alpaca falls through to a direct connection and browsing keeps working,
// unfiltered, rather than the machine losing the network.
//
// Nothing reports that today. macswitcher knows nothing about privoxy - not
// `status`, not `observe`, whose daemon list is a fixed struct in
// internal/app/config.go - so a dead filter is silent and browsing simply
// looks normal. alpaca's log ("via DIRECT" where a PROXY was expected) and
// `launchctl print gui/$(id -u)/com.schretzi.privoxy` are the only tells.
//
// Nothing here calls dnsResolve(): every test is a string or arithmetic test
// on the host, so a PAC evaluation never costs a DNS lookup.

function FindProxyForURL(url, host) {
    // Single-label names (kubernetes, kiac, a container name) are local by
    // definition - they only resolve through this machine's own resolver.
    if (isPlainHostName(host)) {
        return "DIRECT";
    }

    // Local zones: .kiac is LocalKubernetes, .local is mDNS/Bonjour,
    // .ts.net is the tailnet's MagicDNS.
    if (shExpMatch(host, "*.local") ||
        shExpMatch(host, "*.kiac") ||
        shExpMatch(host, "*.ts.net") ||
        host === "localhost") {
        return "DIRECT";
    }

    // IPv4 literals are compared numerically - shExpMatch has no ranges, and
    // writing them out as globs is how you accidentally send 100.128.0.0/9
    // (public) direct while trying to match Tailscale's 100.64.0.0/10.
    var v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(host);
    if (v4) {
        var a = parseInt(v4[1], 10), b = parseInt(v4[2], 10);
        if (a === 127) return "DIRECT";                       // loopback
        if (a === 10) return "DIRECT";                        // RFC1918
        if (a === 192 && b === 168) return "DIRECT";           // RFC1918, incl. the kiac vmnet
        if (a === 172 && b >= 16 && b <= 31) return "DIRECT";  // RFC1918
        if (a === 169 && b === 254) return "DIRECT";           // link-local
        if (a === 100 && b >= 64 && b <= 127) return "DIRECT"; // CGNAT: the tailnet
    }

    // IPv6 loopback and unique-local (fd00::/8), which is what Tailscale
    // hands out on this machine.
    if (host === "::1" || shExpMatch(host, "fd*:*")) {
        return "DIRECT";
    }

    return "PROXY 127.0.0.1:8118; DIRECT";
}
