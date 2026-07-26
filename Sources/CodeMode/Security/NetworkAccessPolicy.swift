import Foundation

/// Controls which destinations `network.fetch` may reach and how much response
/// data it may buffer.
///
/// The default (`.standard`) blocks loopback, private-range, link-local, and
/// other non-public destinations so agent-authored JavaScript cannot reach
/// `127.0.0.1`, cloud metadata endpoints such as `169.254.169.254`, or hosts on
/// the local network, and caps buffered response bodies at 10 MB.
///
/// Host matching is by URL host only; DNS resolution is not performed, so a
/// public hostname that resolves to a private address is not detected. Hosts
/// that need stricter guarantees should set `allowedHosts`.
public struct NetworkAccessPolicy: Sendable, Equatable {
    /// When non-nil, only these hosts are reachable. Entries match the host
    /// exactly or as a parent domain (`"example.com"` also matches
    /// `"api.example.com"`). Entries bypass the private-network check, so a
    /// host app can deliberately allowlist `"localhost"`.
    public var allowedHosts: [String]?

    /// Hosts that are always refused, matched like `allowedHosts` entries and
    /// checked before it.
    public var blockedHosts: [String]

    /// Refuses loopback, RFC 1918, link-local (including cloud metadata),
    /// CGNAT, unique-local and IPv4-mapped IPv6 literals, `localhost`, and
    /// `.local`/`.localhost`/`.internal` names.
    public var blocksPrivateNetworks: Bool

    /// Maximum response body size in bytes that fetch will buffer. Responses
    /// that exceed this are cancelled mid-transfer.
    public var maxResponseBytes: Int

    /// Whether script-supplied credential headers reach the wire.
    ///
    /// `Cookie`, `Authorization`, and the `Proxy-*` pair are how a request
    /// carries authority. Script-authored code should not be minting them
    /// against arbitrary origins, so they are refused by default. Hosts whose
    /// scripts legitimately call an authenticated API — a bearer token the
    /// script fetched from the keychain, say — set this to true.
    public var allowsCredentialHeaders: Bool

    /// Request headers refused when `allowsCredentialHeaders` is false.
    /// Matched case-insensitively; `proxy-` is matched as a prefix.
    static let credentialHeaderNames: Set<String> = [
        "cookie",
        "cookie2",
        "authorization",
    ]

    public init(
        allowedHosts: [String]? = nil,
        blockedHosts: [String] = [],
        blocksPrivateNetworks: Bool = true,
        maxResponseBytes: Int = 10_485_760,
        allowsCredentialHeaders: Bool = false
    ) {
        self.allowedHosts = allowedHosts
        self.blockedHosts = blockedHosts
        self.blocksPrivateNetworks = blocksPrivateNetworks
        self.maxResponseBytes = maxResponseBytes
        self.allowsCredentialHeaders = allowsCredentialHeaders
    }

    /// Secure default: private networks blocked, 10 MB response cap, no
    /// script-supplied credential headers.
    public static let standard = NetworkAccessPolicy()

    /// No destination restrictions, no response size cap, and script-supplied
    /// credential headers permitted. Matches the pre-policy behavior of
    /// `network.fetch`; opt in deliberately.
    public static let permissive = NetworkAccessPolicy(
        blocksPrivateNetworks: false,
        maxResponseBytes: .max,
        allowsCredentialHeaders: true
    )

    /// Returns a reason the header is refused, or nil when it may be sent.
    func headerViolationReason(for name: String) -> String? {
        guard allowsCredentialHeaders == false else {
            return nil
        }

        let normalized = name.lowercased()
        guard Self.credentialHeaderNames.contains(normalized) || normalized.hasPrefix("proxy-") else {
            return nil
        }

        return "the \"\(name)\" request header carries authority and is refused by the host app's network access policy"
    }

    /// Returns a human-readable reason the URL is refused, or nil when allowed.
    func violationReason(for url: URL) -> String? {
        guard let rawHost = url.host, rawHost.isEmpty == false else {
            return "URL has no host"
        }
        let host = Self.normalized(host: rawHost)

        if blockedHosts.contains(where: { Self.host(host, matches: $0) }) {
            return "Host \"\(host)\" is blocked by the network access policy"
        }

        if let allowedHosts {
            guard allowedHosts.contains(where: { Self.host(host, matches: $0) }) else {
                return "Host \"\(host)\" is not in the network access policy allowlist"
            }
            return nil
        }

        if blocksPrivateNetworks, Self.isPrivateOrLocal(host: host) {
            return "Host \"\(host)\" is a loopback, private, or link-local destination blocked by the network access policy"
        }

        return nil
    }

    private static func normalized(host: String) -> String {
        var host = host.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        // A trailing root dot ("localhost.", "example.com.") denotes the same
        // host to DNS; strip it so suffix and literal matching cannot be bypassed.
        while host.hasSuffix(".") {
            host.removeLast()
        }
        return host
    }

    private static func host(_ host: String, matches pattern: String) -> Bool {
        let pattern = normalized(host: pattern)
        return host == pattern || host.hasSuffix(".\(pattern)")
    }

    private static func isPrivateOrLocal(host: String) -> Bool {
        if host == "localhost"
            || host.hasSuffix(".localhost")
            || host.hasSuffix(".local")
            || host.hasSuffix(".internal")
        {
            return true
        }

        // inet_aton accepts every numeric IPv4 form URL loaders resolve as an
        // address (dotted quad, partial quads, decimal, octal, and hex), so
        // encoded literals like "2130706433" cannot slip past the check.
        var ipv4 = in_addr()
        if host.contains(":") == false, inet_aton(host, &ipv4) != 0 {
            return isPrivateOrLocal(ipv4: UInt32(bigEndian: ipv4.s_addr))
        }

        let ipv6Host = host.split(separator: "%").first.map(String.init) ?? host
        var ipv6 = in6_addr()
        if inet_pton(AF_INET6, ipv6Host, &ipv6) == 1 {
            return isPrivateOrLocal(ipv6: ipv6)
        }

        return false
    }

    private static func isPrivateOrLocal(ipv4 address: UInt32) -> Bool {
        let octet1 = UInt8(truncatingIfNeeded: address >> 24)
        let octet2 = UInt8(truncatingIfNeeded: address >> 16)

        switch octet1 {
        case 0, 10, 127, 255:
            return true
        case 100:
            return (64...127).contains(octet2) // CGNAT 100.64.0.0/10
        case 169:
            return octet2 == 254 // link-local + cloud metadata
        case 172:
            return (16...31).contains(octet2)
        case 192:
            return octet2 == 168
        default:
            return false
        }
    }

    private static func isPrivateOrLocal(ipv6 address: in6_addr) -> Bool {
        let bytes = withUnsafeBytes(of: address) { Array($0) }

        func embeddedIPv4() -> UInt32 {
            UInt32(bytes[12]) << 24 | UInt32(bytes[13]) << 16 | UInt32(bytes[14]) << 8 | UInt32(bytes[15])
        }

        if bytes[0..<15].allSatisfy({ $0 == 0 }) {
            return bytes[15] == 0 || bytes[15] == 1 // unspecified or loopback
        }
        if bytes[0] & 0xfe == 0xfc {
            return true // unique local fc00::/7
        }
        if bytes[0] == 0xfe, bytes[1] & 0xc0 == 0x80 {
            return true // link-local fe80::/10
        }
        if bytes[0..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xff, bytes[11] == 0xff {
            return isPrivateOrLocal(ipv4: embeddedIPv4()) // IPv4-mapped ::ffff:a.b.c.d
        }
        if bytes[0..<12].allSatisfy({ $0 == 0 }) {
            return isPrivateOrLocal(ipv4: embeddedIPv4()) // IPv4-compatible ::a.b.c.d (deprecated)
        }
        if bytes[0] == 0x00, bytes[1] == 0x64, bytes[2] == 0xff, bytes[3] == 0x9b,
           bytes[4..<12].allSatisfy({ $0 == 0 }) {
            return isPrivateOrLocal(ipv4: embeddedIPv4()) // NAT64 64:ff9b::/96
        }
        return false
    }
}
