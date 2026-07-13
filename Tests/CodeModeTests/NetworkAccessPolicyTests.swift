import Foundation
import Testing
@testable import CodeMode

private func violation(_ policy: NetworkAccessPolicy, _ urlString: String) -> String? {
    guard let url = URL(string: urlString) else {
        Issue.record("Invalid test URL: \(urlString)")
        return nil
    }
    return policy.violationReason(for: url)
}

@Test func standardPolicyBlocksLoopbackAndPrivateIPv4() {
    let policy = NetworkAccessPolicy.standard

    #expect(violation(policy, "http://127.0.0.1/") != nil)
    #expect(violation(policy, "http://10.0.0.5/") != nil)
    #expect(violation(policy, "http://172.16.9.1/") != nil)
    #expect(violation(policy, "http://172.31.255.1/") != nil)
    #expect(violation(policy, "http://192.168.1.1/") != nil)
    #expect(violation(policy, "http://169.254.169.254/latest/meta-data/") != nil)
    #expect(violation(policy, "http://100.64.0.1/") != nil)
    #expect(violation(policy, "http://0.0.0.0/") != nil)
}

@Test func standardPolicyBlocksEncodedIPv4Literals() {
    let policy = NetworkAccessPolicy.standard

    // Alternate numeric spellings of 127.0.0.1 and 169.254.169.254.
    #expect(violation(policy, "http://2130706433/") != nil)
    #expect(violation(policy, "http://0x7f000001/") != nil)
    #expect(violation(policy, "http://127.1/") != nil)
    #expect(violation(policy, "http://0251.0376.0251.0376/") != nil)
}

@Test func standardPolicyBlocksLocalHostnames() {
    let policy = NetworkAccessPolicy.standard

    #expect(violation(policy, "http://localhost:8080/") != nil)
    #expect(violation(policy, "http://dev.localhost/") != nil)
    #expect(violation(policy, "http://printer.local/") != nil)
    #expect(violation(policy, "http://metadata.google.internal/computeMetadata/v1/") != nil)
}

@Test func standardPolicyBlocksFullyQualifiedTrailingDotHosts() {
    let policy = NetworkAccessPolicy.standard

    // A trailing root dot resolves to the same host and must not bypass the block.
    #expect(violation(policy, "http://localhost./") != nil)
    #expect(violation(policy, "http://metadata.google.internal./") != nil)
    #expect(violation(policy, "http://printer.local./") != nil)
}

@Test func allowlistMatchesTrailingDotHosts() {
    let policy = NetworkAccessPolicy(allowedHosts: ["example.com"])

    #expect(violation(policy, "https://example.com./") == nil)
    #expect(violation(policy, "https://api.example.com./") == nil)
}

@Test func standardPolicyBlocksIPv4EmbeddedIPv6Forms() {
    let policy = NetworkAccessPolicy.standard

    #expect(violation(policy, "http://[::7f00:1]/") != nil)      // IPv4-compatible ::127.0.0.1
    #expect(violation(policy, "http://[64:ff9b::7f00:1]/") != nil) // NAT64 127.0.0.1
    #expect(violation(policy, "http://[64:ff9b::a00:1]/") != nil)  // NAT64 10.0.0.1
}

@Test func standardPolicyBlocksPrivateIPv6() {
    let policy = NetworkAccessPolicy.standard

    #expect(violation(policy, "http://[::1]/") != nil)
    #expect(violation(policy, "http://[fe80::1]/") != nil)
    #expect(violation(policy, "http://[fd12:3456:789a::1]/") != nil)
    #expect(violation(policy, "http://[::ffff:127.0.0.1]/") != nil)
    #expect(violation(policy, "http://[::ffff:10.0.0.1]/") != nil)
}

@Test func standardPolicyAllowsPublicDestinations() {
    let policy = NetworkAccessPolicy.standard

    #expect(violation(policy, "https://example.com/path") == nil)
    #expect(violation(policy, "https://api.github.com/repos") == nil)
    #expect(violation(policy, "http://93.184.216.34/") == nil)
    #expect(violation(policy, "https://[2606:2800:220:1:248:1893:25c8:1946]/") == nil)
}

@Test func permissivePolicyAllowsPrivateDestinations() {
    let policy = NetworkAccessPolicy.permissive

    #expect(violation(policy, "http://127.0.0.1:3000/") == nil)
    #expect(violation(policy, "http://localhost/") == nil)
    #expect(violation(policy, "http://169.254.169.254/") == nil)
}

@Test func allowlistRestrictsToListedHostsAndSubdomains() {
    let policy = NetworkAccessPolicy(allowedHosts: ["example.com"])

    #expect(violation(policy, "https://example.com/") == nil)
    #expect(violation(policy, "https://api.example.com/") == nil)
    #expect(violation(policy, "https://notexample.com/") != nil)
    #expect(violation(policy, "https://example.com.evil.net/") != nil)
    #expect(violation(policy, "https://other.org/") != nil)
}

@Test func allowlistedPrivateHostBypassesPrivateNetworkCheck() {
    let policy = NetworkAccessPolicy(allowedHosts: ["localhost"])

    #expect(violation(policy, "http://localhost:8080/") == nil)
    #expect(violation(policy, "http://127.0.0.1/") != nil)
}

@Test func blocklistTakesPrecedenceOverAllowlist() {
    let policy = NetworkAccessPolicy(
        allowedHosts: ["example.com"],
        blockedHosts: ["blocked.example.com"]
    )

    #expect(violation(policy, "https://example.com/") == nil)
    #expect(violation(policy, "https://blocked.example.com/") != nil)
    #expect(violation(policy, "https://deep.blocked.example.com/") != nil)
}

@Test func networkFetchRefusesBlockedDestinationsBeforeConnecting() throws {
    let bridge = NetworkBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    for urlString in [
        "http://127.0.0.1:8080/admin",
        "http://169.254.169.254/latest/meta-data/",
        "http://localhost/",
        "http://[::1]/",
    ] {
        do {
            _ = try bridge.fetch(arguments: ["url": .string(urlString)], context: context)
            Issue.record("Expected \(urlString) to be refused")
        } catch {
            #expect(requireBridgeErrorCode(error) == "NETWORK_POLICY_VIOLATION")
        }
    }

    let auditEvents = context.auditLogger.drain()
    #expect(auditEvents.contains(where: { $0.message.contains("denied") && $0.message.contains("169.254.169.254") }))
}

@Test func executeFetchToPrivateHostFailsWithPolicyViolation() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await fetch('http://169.254.169.254/latest/meta-data/');",
            allowedCapabilities: [.networkFetch]
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "NETWORK_POLICY_VIOLATION")
    #expect(observed.error?.suggestions.contains(where: { $0.contains("network access policy") }) == true)
}

/// Stateless stub keyed off the request path so tests stay safe under
/// parallel execution: `/large` returns 64 bytes, `/small` returns 8 bytes,
/// `/redirect` issues a 302 to the cloud metadata address.
private final class FixedBodyURLProtocol: URLProtocol {
    static let redirectTarget = URL(string: "http://169.254.169.254/latest/meta-data/")!

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let url = request.url ?? URL(string: "https://unit.test")!

        if url.path == "/redirect" {
            let response = HTTPURLResponse(
                url: url,
                statusCode: 302,
                httpVersion: "HTTP/1.1",
                headerFields: ["Location": Self.redirectTarget.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: Self.redirectTarget), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        let bodySize = url.path == "/large" ? 64 : 8
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0x61, count: bodySize))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func networkFetchEnforcesResponseSizeCap() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixedBodyURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(
        session: session,
        policy: NetworkAccessPolicy(maxResponseBytes: 16)
    )
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    do {
        _ = try bridge.fetch(arguments: ["url": .string("https://unit.test/large")], context: context)
        Issue.record("Expected oversized response to be refused")
    } catch {
        #expect(requireBridgeErrorCode(error) == "NETWORK_POLICY_VIOLATION")
    }
}

@Test func networkFetchAllowsResponsesWithinSizeCap() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixedBodyURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(
        session: session,
        policy: NetworkAccessPolicy(maxResponseBytes: 16)
    )
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    let result = try bridge.fetch(arguments: ["url": .string("https://unit.test/small")], context: context)
    let object = try requireObject(result)
    #expect(object.bool("ok") == true)
    #expect(object.string("bodyText") == "aaaaaaaa")
}

@Test func networkFetchRefusesRedirectToPrivateDestination() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FixedBodyURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(session: session)
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    do {
        _ = try bridge.fetch(arguments: ["url": .string("https://unit.test/redirect")], context: context)
        Issue.record("Expected redirect to private destination to be refused")
    } catch {
        #expect(requireBridgeErrorCode(error) == "NETWORK_POLICY_VIOLATION")
    }
}
