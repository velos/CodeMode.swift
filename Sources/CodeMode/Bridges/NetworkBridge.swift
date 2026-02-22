import Foundation

public final class NetworkBridge: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let urlString = arguments.string("url"), let url = URL(string: urlString) else {
            throw BridgeError.invalidArguments("network.fetch requires valid 'url'")
        }

        let options = arguments.object("options") ?? [:]
        var request = URLRequest(url: url)
        request.httpMethod = options.string("method")?.uppercased() ?? "GET"
        request.timeoutInterval = 30

        if let headers = options.object("headers") {
            for (key, value) in headers {
                if let string = value.stringValue {
                    request.setValue(string, forHTTPHeaderField: key)
                }
            }
        }

        if let body = options.string("body") {
            request.httpBody = Data(body.utf8)
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

        guard semaphore.wait(timeout: .now() + 30) == .success else {
            throw BridgeError.timeout(milliseconds: 30_000)
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

            let bodyText = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let headers = httpResponse.allHeaderFields.reduce(into: [String: JSONValue]()) { partial, pair in
                partial[String(describing: pair.key)] = .string(String(describing: pair.value))
            }

            context.log(.info, message: "fetch \(request.httpMethod ?? "GET") \(urlString) -> \(httpResponse.statusCode)")

            return .object([
                "ok": .bool((200...299).contains(httpResponse.statusCode)),
                "status": .number(Double(httpResponse.statusCode)),
                "statusText": .string(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)),
                "headers": .object(headers),
                "bodyText": .string(bodyText),
            ])
        }
    }
}
