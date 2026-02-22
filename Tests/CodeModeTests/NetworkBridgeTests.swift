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

@Test func networkFetchRejectsInvalidURL() throws {
    let bridge = NetworkBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.fetch(arguments: ["url": .string("://")], context: context)
        Issue.record("Expected invalid URL to throw")
    } catch {
        let code = requireBridgeErrorCode(error)
        #expect(code == "INVALID_ARGUMENTS" || code == "NATIVE_FAILURE")
    }
}

@Test func executeUsesNetworkBridgeViaFetch() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await fetch('://');
            return { ok: true };
            """,
            allowedCapabilities: [.networkFetch]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "INVALID_ARGUMENTS" || $0.code == "NATIVE_FAILURE" }))
}
