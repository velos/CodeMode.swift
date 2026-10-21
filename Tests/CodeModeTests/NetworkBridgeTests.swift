import Foundation
import Testing
@testable import CodeMode

private final class StubHTTPURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let requestBody: String = {
            if let data = request.httpBody {
                return String(data: data, encoding: .utf8) ?? ""
            }

            guard let stream = request.httpBodyStream else {
                return ""
            }

            stream.open()
            defer { stream.close() }

            var data = Data()
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 {
                    break
                }
                data.append(buffer, count: read)
            }
            return String(data: data, encoding: .utf8) ?? ""
        }()

        let payload: [String: Any] = [
            "url": request.url?.absoluteString ?? "",
            "method": request.httpMethod ?? "GET",
            "body": requestBody,
            "timeoutMs": Int((request.timeoutInterval * 1_000).rounded()),
            "xUnit": request.value(forHTTPHeaderField: "X-Unit") ?? "",
        ]

        let bodyData = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://unit.test")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bodyData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test func networkFetchReturnsStubbedResponse() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTPURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(session: session)
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    let result = try bridge.fetch(arguments: [
        "url": .string("https://unit.test/endpoint"),
        "options": .object([
            "method": .string("POST"),
            "body": .string("payload"),
        ]),
    ], context: context)

    let object = try requireObject(result)
    #expect(object.bool("ok") == true)
    #expect(object.int("status") == 200)

    let bodyText = object.string("bodyText") ?? ""
    let bodyData = Data(bodyText.utf8)
    let decoded = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any]
    #expect(decoded?["method"] as? String == "POST")
    #expect(decoded?["body"] as? String == "payload")
}

@Test func networkFetchSupportsBase64BodyHeadersAndTimeout() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTPURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(session: session)
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    let result = try bridge.fetch(arguments: [
        "url": .string("https://unit.test/endpoint"),
        "options": .object([
            "method": .string("PUT"),
            "headers": .object(["X-Unit": .string("yes")]),
            "bodyBase64": .string(Data("payload".utf8).base64EncodedString()),
            "timeoutMs": .number(1_234),
        ]),
    ], context: context)

    let object = try requireObject(result)
    let bodyText = object.string("bodyText") ?? ""
    let decoded = try JSONSerialization.jsonObject(with: Data(bodyText.utf8)) as? [String: Any]
    #expect(decoded?["method"] as? String == "PUT")
    #expect(decoded?["body"] as? String == "payload")
    #expect(decoded?["timeoutMs"] as? Int == 1_234)
    #expect(decoded?["xUnit"] as? String == "yes")
}

@Test func networkFetchCanReturnBase64Response() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTPURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(session: session)
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    let result = try bridge.fetch(arguments: [
        "url": .string("https://unit.test/endpoint"),
        "options": .object([
            "responseEncoding": .string("base64"),
        ]),
    ], context: context)

    let object = try requireObject(result)
    let encoded = try #require(object.string("bodyBase64"))
    let data = try #require(Data(base64Encoded: encoded))
    let decoded = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    #expect(decoded?["method"] as? String == "GET")
    #expect(object.string("bodyText") == "")
}

@Test func networkFetchRejectsInvalidURL() throws {
    let bridge = NetworkBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.fetch(arguments: ["url": .string("://")], context: context)
        Issue.record("Expected invalid URL to throw")
    } catch {
        let code = requireBridgeErrorCode(error)
        #expect(code == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.fetch(arguments: ["url": .string("file:///tmp/a.txt")], context: context)
        Issue.record("Expected non-HTTP URL to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func networkFetchRejectsConflictingRequestBodies() throws {
    let bridge = NetworkBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.fetch(arguments: [
            "url": .string("https://unit.test/endpoint"),
            "options": .object([
                "body": .string("payload"),
                "bodyBase64": .string(Data("payload".utf8).base64EncodedString()),
            ]),
        ], context: context)
        Issue.record("Expected body/bodyBase64 conflict to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func executeUsesNetworkBridgeViaFetch() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await fetch('://');
            return { ok: true };
            """,
            allowedCapabilities: [.networkFetch]
        )
    )

    #expect(observed.error?.code == "INVALID_ARGUMENTS")
}

@Test func executeURLPolyfillStringifiesURLObjects() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const url = new URL("https://example.com/path?q=1");
            return { stringValue: String(url), methodValue: url.toString() };
            """,
            allowedCapabilities: []
        )
    )

    let result = try #require(observed.result?.output?.objectValue)
    #expect(result.string("stringValue") == "https://example.com/path?q=1")
    #expect(result.string("methodValue") == "https://example.com/path?q=1")
}

// MARK: - Ambient authority

@Test func networkBridgeDefaultSessionCarriesNoAmbientCredentials() {
    // The shipping default used to be `URLSession.shared`, which reads
    // HTTPCookieStorage.shared and URLCredentialStorage.shared — so a script got
    // authenticated session-riding against every origin the app is logged in to,
    // and a Set-Cookie in a script-fetched response poisoned the app's jar.
    let configuration = NetworkBridge.isolatedSession.configuration
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCredentialStorage == nil)
    #expect(configuration.urlCache == nil)
    #expect(configuration.httpShouldSetCookies == false)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(NetworkBridge.isolatedSession !== URLSession.shared)
}

@Test func networkFetchRefusesCredentialHeadersByDefault() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTPURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(session: session)
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    for header in ["Cookie", "cookie", "Authorization", "Proxy-Authorization", "proxy-authenticate"] {
        do {
            _ = try bridge.fetch(arguments: [
                "url": .string("https://unit.test/endpoint"),
                "options": .object(["headers": .object([header: .string("secret")])]),
            ], context: context)
            Issue.record("Expected \(header) to be refused")
        } catch {
            #expect(requireBridgeErrorCode(error) == "NETWORK_POLICY_VIOLATION")
        }
    }

    // Ordinary headers are unaffected.
    let ok = try bridge.fetch(arguments: [
        "url": .string("https://unit.test/endpoint"),
        "options": .object(["headers": .object(["X-Unit": .string("plain")])]),
    ], context: context)
    #expect(try requireObject(ok).bool("ok") == true)
}

@Test func networkFetchAllowsCredentialHeadersWhenHostOptsIn() throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubHTTPURLProtocol.self]
    let session = URLSession(configuration: configuration)

    let bridge = NetworkBridge(
        session: session,
        policy: NetworkAccessPolicy(allowsCredentialHeaders: true)
    )
    let (context, sandbox) = try makeInvocationContext()
    defer {
        cleanup(sandbox)
        session.invalidateAndCancel()
    }

    let result = try bridge.fetch(arguments: [
        "url": .string("https://unit.test/endpoint"),
        "options": .object(["headers": .object(["Authorization": .string("Bearer t")])]),
    ], context: context)
    #expect(try requireObject(result).bool("ok") == true)
    #expect(NetworkAccessPolicy.permissive.allowsCredentialHeaders)
}
