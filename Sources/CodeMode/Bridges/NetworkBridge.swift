import Foundation

public final class NetworkBridge: @unchecked Sendable {
    private static let defaultTimeoutMs = 30_000

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let urlString = arguments.string("url"),
              let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw BridgeError.invalidArguments("network.fetch requires an absolute HTTP(S) 'url'")
        }

        let options = arguments.object("options") ?? [:]
        let timeoutMs = options.int("timeoutMs") ?? Self.defaultTimeoutMs
        guard timeoutMs > 0 else {
            throw BridgeError.invalidArguments("network.fetch options.timeoutMs must be greater than 0")
        }

        let responseEncoding = options.string("responseEncoding")?.lowercased() ?? "text"
        guard ["text", "base64"].contains(responseEncoding) else {
            throw BridgeError.invalidArguments("network.fetch options.responseEncoding must be text or base64")
        }

        var request = URLRequest(url: url)
        request.httpMethod = options.string("method")?.uppercased() ?? "GET"
        request.timeoutInterval = TimeInterval(timeoutMs) / 1_000

        if let headers = options.object("headers") {
            for (key, value) in headers {
                if let string = value.stringValue {
                    request.setValue(string, forHTTPHeaderField: key)
                }
            }
        }

        let body = options.string("body")
        let bodyBase64 = options.string("bodyBase64")
        if body != nil, bodyBase64 != nil {
            throw BridgeError.invalidArguments("network.fetch options.body and options.bodyBase64 are mutually exclusive")
        }

        if let body {
            request.httpBody = Data(body.utf8)
        } else if let bodyBase64 {
            guard let data = Data(base64Encoded: bodyBase64) else {
                throw BridgeError.invalidArguments("network.fetch options.bodyBase64 must be valid base64")
            }
            request.httpBody = data
        }

        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronizedBox<Result<(Data?, URLResponse?), Error>?>(nil)

        let task = session.dataTask(with: request) { data, urlResponse, error in
            if let error {
                resultBox.set(.failure(error))
            } else {
                resultBox.set(.success((data, urlResponse)))
            }
            semaphore.signal()
        }
        task.resume()

        guard semaphore.wait(timeout: .now() + TimeInterval(timeoutMs) / 1_000) == .success else {
            task.cancel()
            throw BridgeError.timeout(milliseconds: timeoutMs)
        }

        guard let result = resultBox.get() else {
            throw BridgeError.nativeFailure("network.fetch finished without result")
        }

        switch result {
        case let .failure(error):
            throw BridgeError.nativeFailure("network.fetch failed: \(error.localizedDescription)")
        case let .success((responseData, response)):
            guard let httpResponse = response as? HTTPURLResponse else {
                throw BridgeError.nativeFailure("network.fetch received non-HTTP response")
            }

            let responseData = responseData ?? Data()
            let headers = httpResponse.allHeaderFields.reduce(into: [String: JSONValue]()) { partial, pair in
                partial[String(describing: pair.key)] = .string(String(describing: pair.value))
            }

            context.log(.info, message: "fetch \(request.httpMethod ?? "GET") \(urlString) -> \(httpResponse.statusCode)")

            var object: [String: JSONValue] = [
                "ok": .bool((200...299).contains(httpResponse.statusCode)),
                "status": .number(Double(httpResponse.statusCode)),
                "statusText": .string(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)),
                "headers": .object(headers),
            ]
            if responseEncoding == "base64" {
                object["bodyBase64"] = .string(responseData.base64EncodedString())
                object["bodyText"] = .string("")
            } else {
                object["bodyText"] = .string(String(data: responseData, encoding: .utf8) ?? "")
            }

            return .object(object)
        }
    }
}
