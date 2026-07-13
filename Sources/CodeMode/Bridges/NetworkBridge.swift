import Foundation

public final class NetworkBridge: @unchecked Sendable {
    private static let defaultTimeoutMs = 30_000

    private let session: URLSession
    private let policy: NetworkAccessPolicy

    public init(session: URLSession = .shared, policy: NetworkAccessPolicy = .standard) {
        self.session = session
        self.policy = policy
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

        if let reason = policy.violationReason(for: url) {
            context.auditLogger.log(AuditEvent(
                capability: CapabilityID.networkFetch.rawValue,
                message: "denied \(urlString): \(reason)"
            ))
            throw BridgeError.networkPolicyViolation(reason)
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

        let handler = FetchTaskHandler(policy: policy)
        let task = session.dataTask(with: request)
        task.delegate = handler
        task.resume()

        guard handler.semaphore.wait(timeout: .now() + TimeInterval(timeoutMs) / 1_000) == .success else {
            task.cancel()
            throw BridgeError.timeout(milliseconds: timeoutMs)
        }

        let outcome = handler.outcome()

        if let reason = outcome.violationReason {
            context.auditLogger.log(AuditEvent(
                capability: CapabilityID.networkFetch.rawValue,
                message: "denied \(urlString): \(reason)"
            ))
            throw BridgeError.networkPolicyViolation(reason)
        }

        if let error = outcome.error {
            throw BridgeError.nativeFailure("network.fetch failed: \(error.localizedDescription)")
        }

        guard let httpResponse = outcome.response else {
            throw BridgeError.nativeFailure("network.fetch received non-HTTP response")
        }

        let responseData = outcome.data
        let headers = httpResponse.allHeaderFields.reduce(into: [String: JSONValue]()) { partial, pair in
            partial[String(describing: pair.key)] = .string(String(describing: pair.value))
        }

        let summary = "fetch \(request.httpMethod ?? "GET") \(urlString) -> \(httpResponse.statusCode)"
        context.log(.info, message: summary)
        context.auditLogger.log(AuditEvent(
            capability: CapabilityID.networkFetch.rawValue,
            message: summary
        ))

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

/// Per-task delegate that enforces the network access policy while the
/// transfer is in flight: redirect targets are re-validated before they are
/// followed, and the response body is cancelled as soon as it exceeds the
/// policy's size cap instead of being buffered whole.
private final class FetchTaskHandler: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    struct Outcome {
        var response: HTTPURLResponse?
        var data: Data
        var error: Error?
        var violationReason: String?
    }

    let semaphore = DispatchSemaphore(value: 0)

    private let policy: NetworkAccessPolicy
    private let lock = NSLock()
    private var response: HTTPURLResponse?
    private var data = Data()
    private var completionError: Error?
    private var violationReason: String?

    init(policy: NetworkAccessPolicy) {
        self.policy = policy
    }

    func outcome() -> Outcome {
        lock.lock()
        defer { lock.unlock() }
        return Outcome(
            response: response,
            data: data,
            error: completionError,
            violationReason: violationReason
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let url = request.url, let reason = policy.violationReason(for: url) {
            setViolation("redirect to \(url.absoluteString) refused: \(reason)")
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if response.expectedContentLength > 0, response.expectedContentLength > Int64(policy.maxResponseBytes) {
            setViolation("response of \(response.expectedContentLength) bytes exceeds the \(policy.maxResponseBytes)-byte network access policy limit")
            completionHandler(.cancel)
            return
        }

        lock.lock()
        self.response = response as? HTTPURLResponse
        // Content-Length is known and within the cap here: reserve once instead
        // of growing the buffer through repeated reallocations as chunks arrive.
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive chunk: Data) {
        lock.lock()
        data.append(chunk)
        let overLimit = data.count > policy.maxResponseBytes
        lock.unlock()

        if overLimit {
            setViolation("response exceeded the \(policy.maxResponseBytes)-byte network access policy limit")
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        if completionError == nil {
            completionError = error
        }
        lock.unlock()
        semaphore.signal()
    }

    private func setViolation(_ reason: String) {
        lock.lock()
        if violationReason == nil {
            violationReason = reason
        }
        lock.unlock()
    }
}
