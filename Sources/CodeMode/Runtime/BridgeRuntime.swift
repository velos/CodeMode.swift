import Foundation
import JavaScriptCore

final class BridgeRuntime: @unchecked Sendable {
    private struct JavaScriptExceptionSnapshot: Sendable {
        var name: String?
        var message: String
        var line: Int?
        var column: Int?
    }

    private struct RejectionPayload: Sendable {
        var code: String?
        var message: String
        var capability: CapabilityID?
        var functionName: String?
    }

    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let config: CodeModeConfiguration

    init(registry: CapabilityRegistry, catalog: BridgeCatalog, config: CodeModeConfiguration) {
        self.registry = registry
        self.catalog = catalog
        self.config = config
    }

    func search(_ request: JavaScriptAPISearchRequest) throws -> JavaScriptAPISearchResponse {
        var diagnostics: [ToolDiagnostic] = []
        let limit = min(max(request.limit, 1), 20)

        if request.limit != limit {
            diagnostics.append(
                ToolDiagnostic(
                    severity: .warning,
                    code: "SEARCH_LIMIT_CLAMPED",
                    message: "search.limit was clamped to \(limit)",
                    category: "validation"
                )
            )
        }

        if let capability = request.capability {
            let matches = catalog.reference(for: capability).map { [$0] } ?? []
            return JavaScriptAPISearchResponse(matches: matches, diagnostics: diagnostics)
        }

        let query = request.query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard query.isEmpty == false else {
            throw CodeModeToolError(
                code: "INVALID_REQUEST",
                message: "searchJavaScriptAPI requires a non-empty query or an explicit capability"
            )
        }

        let matches = catalog.search(query: query, limit: limit, tags: request.tags)
        return JavaScriptAPISearchResponse(matches: matches, diagnostics: diagnostics)
    }

    func makeExecutionCall(_ request: JavaScriptExecutionRequest) -> JavaScriptExecutionCall {
        let cancellationController = ExecutionCancellationController()
        let continuationBox = LockedBox<AsyncStream<JavaScriptExecutionEvent>.Continuation?>(nil)
        let events = AsyncStream<JavaScriptExecutionEvent> { continuation in
            continuationBox.set(continuation)
        }
        let transcript = ExecutionTranscript { event in
            continuationBox.get()?.yield(event)
        }

        let resultTask = Task<JavaScriptExecutionResult, Error> {
            do {
                let result = try self.execute(
                    request,
                    transcript: transcript,
                    cancellationController: cancellationController
                )
                continuationBox.get()?.yield(.finished)
                continuationBox.get()?.finish()
                return result
            } catch let error as CodeModeToolError {
                continuationBox.get()?.yield(self.event(for: error))
                continuationBox.get()?.finish()
                throw error
            } catch is CancellationError {
                let result = transcript.snapshot()
                let toolError = CodeModeToolError(
                    code: "CANCELLED",
                    message: "Execution cancelled",
                    diagnostics: result.diagnostics,
                    logs: result.logs,
                    permissionEvents: result.permissionEvents
                )
                continuationBox.get()?.yield(.toolError(toolError))
                continuationBox.get()?.finish()
                throw toolError
            } catch {
                let result = transcript.snapshot()
                let toolError = CodeModeToolError(
                    code: "INTERNAL_FAILURE",
                    message: error.localizedDescription,
                    diagnostics: result.diagnostics,
                    logs: result.logs,
                    permissionEvents: result.permissionEvents
                )
                continuationBox.get()?.yield(.toolError(toolError))
                continuationBox.get()?.finish()
                throw toolError
            }
        }

        return JavaScriptExecutionCall(
            events: events,
            resultTask: resultTask,
            cancelImpl: {
                cancellationController.cancel()
            }
        )
    }

    private func execute(
        _ request: JavaScriptExecutionRequest,
        transcript: ExecutionTranscript,
        cancellationController: ExecutionCancellationController
    ) throws -> JavaScriptExecutionResult {
        let invocationContext = BridgeInvocationContext(
            executionContext: request.context,
            allowedCapabilities: Set(request.allowedCapabilities),
            pathPolicy: config.pathPolicy,
            artifactStore: config.artifactStore,
            permissionBroker: config.permissionBroker,
            auditLogger: config.auditLogger,
            transcript: transcript,
            cancellationController: cancellationController
        )

        let context = JSContext()
        guard let context else {
            throw CodeModeToolError(code: "INTERNAL_FAILURE", message: "Unable to initialize JavaScriptCore context")
        }

        let lastException = LockedBox<JavaScriptExceptionSnapshot?>(nil)
        context.exceptionHandler = { _, exception in
            lastException.set(Self.snapshot(from: exception))
        }

        try installBaseRuntime(into: context, invocationContext: invocationContext, lastException: lastException)
        let output = try runUserScript(
            request.code,
            timeoutMs: request.timeoutMs,
            context: context,
            invocationContext: invocationContext,
            cancellationController: cancellationController,
            lastException: lastException
        )

        let result = transcript.snapshot(output: output)
        return JavaScriptExecutionResult(
            output: output,
            logs: result.logs,
            diagnostics: result.diagnostics,
            permissionEvents: result.permissionEvents
        )
    }

    private func installBaseRuntime(
        into context: JSContext,
        invocationContext: BridgeInvocationContext,
        lastException: LockedBox<JavaScriptExceptionSnapshot?>
    ) throws {
        let invokeBlock: @convention(block) (String, String) -> String = { capability, payload in
            do {
                try invocationContext.checkCancellation()
                let data = Data(payload.utf8)
                let decoded = try JSONDecoder.codeModeBridge.decode(JSONValue.self, from: data)
                guard let parsed = decoded.objectValue else {
                    throw BridgeError.invalidRequest("Bridge payload must be a JSON object")
                }

                let result = try self.registry.invoke(capability, arguments: parsed, context: invocationContext)
                try invocationContext.checkCancellation()
                invocationContext.log(.debug, message: "Capability executed: \(capability)")
                invocationContext.auditLogger.log(AuditEvent(capability: capability, message: "success"))

                let envelope = JSONValue.object([
                    "ok": .bool(true),
                    "value": result,
                ])
                let encoded = try JSONEncoder.codeModeBridge.encode(envelope)
                return String(data: encoded, encoding: .utf8) ?? "{\"ok\":false,\"error\":{\"code\":\"INTERNAL_FAILURE\",\"message\":\"Encoding failed\"}}"
            } catch {
                let bridgeError = (error as? BridgeError) ?? BridgeError.nativeFailure(error.localizedDescription)
                let capabilityID = CapabilityID(rawValue: capability)
                let errorPayload = self.bridgeFailurePayload(
                    for: bridgeError,
                    capability: capabilityID
                )
                invocationContext.log(.error, message: "Capability failed \(capability): \(errorPayload.message)")
                invocationContext.auditLogger.log(AuditEvent(capability: capability, message: "failed: \(errorPayload.message)"))

                let envelope = JSONValue.object([
                    "ok": .bool(false),
                    "error": .object([
                        "code": .string(errorPayload.code),
                        "message": .string(errorPayload.message),
                        "capability": capabilityID.map { .string($0.rawValue) } ?? .null,
                    ]),
                ])
                let encoded = try? JSONEncoder.codeModeBridge.encode(envelope)
                return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false,\"error\":{\"code\":\"INTERNAL_FAILURE\",\"message\":\"Unknown bridge error\"}}"
            }
        }
        context.setObject(invokeBlock, forKeyedSubscript: "__bridgeInvokeSync" as NSString)

        let consoleLogBlock: @convention(block) (String) -> Void = { message in
            invocationContext.log(.info, message: message)
        }
        context.setObject(consoleLogBlock, forKeyedSubscript: "__nativeConsoleLog" as NSString)

        if context.evaluateScript(RuntimeJavaScript.bootstrap) == nil {
            let message = lastException.get()?.message ?? "Failed to install base runtime"
            throw CodeModeToolError(
                code: "INTERNAL_FAILURE",
                message: message,
                diagnostics: [
                    ToolDiagnostic(
                        severity: .error,
                        code: "JS_BOOTSTRAP",
                        message: message,
                        category: "internal"
                    )
                ]
            )
        }
    }

    private func runUserScript(
        _ code: String,
        timeoutMs: Int,
        context: JSContext,
        invocationContext: BridgeInvocationContext,
        cancellationController: ExecutionCancellationController,
        lastException: LockedBox<JavaScriptExceptionSnapshot?>
    ) throws -> JSONValue? {
        let script = """
        globalThis.__codemode.state = 'pending';
        globalThis.__codemode.result = undefined;
        globalThis.__codemode.error = null;
        (async function(){
        \(indented(code, prefix: "    "))
        })()
        .then(function(value){
            globalThis.__codemode.state = 'fulfilled';
            globalThis.__codemode.result = value;
        })
        .catch(function(error){
            globalThis.__codemode.state = 'rejected';
            globalThis.__codemode.error = {
                message: String(error),
                code: error && error.code ? String(error.code) : null,
                capability: error && error.capability ? String(error.capability) : null,
                functionName: error && error.functionName ? String(error.functionName) : null
            };
        });
        """

        lastException.set(nil)
        let evaluation = context.evaluateScript(script)
        let snapshot = lastException.get() ?? Self.snapshot(from: context.exception)
        if snapshot != nil || evaluation == nil {
            throw syntaxError(from: snapshot)
        }

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)

        while Date() < deadline {
            if cancellationController.isCancelled || Task.isCancelled {
                cancellationController.cancel()
                throw toolError(
                    code: "CANCELLED",
                    message: "Execution cancelled",
                    transcript: invocationContext
                )
            }

            let state = context.evaluateScript("globalThis.__codemode.state")?.toString() ?? "unknown"
            switch state {
            case "fulfilled":
                return try decodeOutput(from: context)
            case "rejected":
                let payload = rejectionPayload(from: context)
                throw classifyRejectedError(payload, invocationContext: invocationContext)
            default:
                Thread.sleep(forTimeInterval: 0.01)
            }
        }

        throw toolError(
            code: "EXECUTION_TIMEOUT",
            message: "Execution timed out after \(timeoutMs)ms",
            transcript: invocationContext
        )
    }

    private func decodeOutput(from context: JSContext) throws -> JSONValue? {
        guard let resultValue = context.evaluateScript("globalThis.__codemode.result"), resultValue.isUndefined == false else {
            return nil
        }

        guard let serialized = context.evaluateScript("JSON.stringify(globalThis.__codemode.result)")?.toString() else {
            return nil
        }

        guard let data = serialized.data(using: .utf8) else {
            throw CodeModeToolError(code: "INTERNAL_FAILURE", message: "Unable to decode execution output")
        }

        return try JSONDecoder.codeModeBridge.decode(JSONValue.self, from: data)
    }

    private func bridgeFailurePayload(for error: BridgeError, capability: CapabilityID?) -> CodeModeToolError {
        let (message, suggestions) = enrichedBridgeFailure(for: error, capability: capability)
        return CodeModeToolError(
            code: error.diagnosticCode,
            message: message,
            capability: capability,
            suggestions: suggestions
        )
    }

    private func classifyRejectedError(
        _ payload: RejectionPayload,
        invocationContext: BridgeInvocationContext
    ) -> CodeModeToolError {
        let code = payload.code ?? "JS_RUNTIME_ERROR"
        let transcript = invocationContext
        let result = JavaScriptExecutionResult(
            output: nil,
            logs: transcript.allLogs(),
            diagnostics: transcript.allDiagnostics(),
            permissionEvents: transcript.allPermissionEvents()
        )

        if isToolFailureCode(code) {
            let suggestions = bridgeSuggestions(for: payload.capability)
            return CodeModeToolError(
                code: code,
                message: payload.message,
                functionName: payload.functionName,
                capability: payload.capability,
                suggestions: suggestions,
                diagnostics: result.diagnostics,
                logs: result.logs,
                permissionEvents: result.permissionEvents
            )
        }

        let missingFunction = payload.functionName ?? missingJavaScriptFunctionName(from: payload.message)
        let suggestions = missingFunction.map { catalog.closestFunctionNames(to: $0) } ?? []
        if let missingFunction,
           missingFunction.isEmpty == false,
           shouldClassifyAsMissingFunction(missingFunction, suggestions: suggestions)
        {
            return CodeModeToolError(
                code: "JS_API_NOT_FOUND",
                message: payload.message,
                functionName: missingFunction,
                suggestions: suggestions,
                diagnostics: result.diagnostics,
                logs: result.logs,
                permissionEvents: result.permissionEvents
            )
        }

        return CodeModeToolError(
            code: "JS_RUNTIME_ERROR",
            message: payload.message,
            diagnostics: result.diagnostics,
            logs: result.logs,
            permissionEvents: result.permissionEvents
        )
    }

    private func syntaxError(from snapshot: JavaScriptExceptionSnapshot?) -> CodeModeToolError {
        let message = snapshot?.message ?? "JavaScript syntax error"
        let adjustedLine = snapshot?.line.map { max(1, $0 - 4) }
        return CodeModeToolError(
            code: "JS_SYNTAX_ERROR",
            message: message,
            line: adjustedLine,
            column: snapshot?.column
        )
    }

    private func rejectionPayload(from context: JSContext) -> RejectionPayload {
        let capability = normalizedOptionalString(
            context.evaluateScript("globalThis.__codemode.error?.capability ?? null")?.toString()
        ).flatMap(CapabilityID.init(rawValue:))

        return RejectionPayload(
            code: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.code ?? null")?.toString()
            ),
            message: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.message ?? null")?.toString()
            ) ?? "JavaScript promise rejected",
            capability: capability,
            functionName: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.functionName ?? null")?.toString()
            )
        )
    }

    private func event(for error: CodeModeToolError) -> JavaScriptExecutionEvent {
        switch error.code {
        case "JS_SYNTAX_ERROR":
            return .syntaxError(error)
        case "JS_API_NOT_FOUND":
            return .functionNotFound(error)
        case "JS_RUNTIME_ERROR":
            return .thrownError(error)
        default:
            return .toolError(error)
        }
    }

    private func toolError(
        code: String,
        message: String,
        transcript: BridgeInvocationContext,
        functionName: String? = nil,
        capability: CapabilityID? = nil,
        suggestions: [String] = []
    ) -> CodeModeToolError {
        CodeModeToolError(
            code: code,
            message: message,
            functionName: functionName,
            capability: capability,
            suggestions: suggestions,
            diagnostics: transcript.allDiagnostics(),
            logs: transcript.allLogs(),
            permissionEvents: transcript.allPermissionEvents()
        )
    }

    private func bridgeSuggestions(for capability: CapabilityID?) -> [String] {
        guard let capability, let reference = catalog.reference(for: capability) else {
            return []
        }

        var suggestions: [String] = []
        if reference.requiredArguments.isEmpty == false {
            suggestions.append("Required arguments: \(formatArguments(reference.requiredArguments, types: reference.argumentTypes))")
        }
        if reference.optionalArguments.isEmpty == false {
            suggestions.append("Optional arguments: \(formatArguments(reference.optionalArguments, types: reference.argumentTypes))")
        }
        suggestions.append("Example: \(reference.example)")
        return suggestions
    }

    private func enrichedBridgeFailure(for error: BridgeError, capability: CapabilityID?) -> (String, [String]) {
        guard case .invalidArguments = error else {
            return (error.localizedDescription, bridgeSuggestions(for: capability))
        }

        return (error.localizedDescription, bridgeSuggestions(for: capability))
    }

    private func formatArguments(_ names: [String], types: [String: CapabilityArgumentType]) -> String {
        names.map { name in
            guard let type = types[name], type != .any else {
                return name
            }
            return "\(name):\(type.rawValue)"
        }
        .joined(separator: ", ")
    }

    private func isToolFailureCode(_ code: String) -> Bool {
        [
            "INVALID_REQUEST",
            "INVALID_ARGUMENTS",
            "CAPABILITY_DENIED",
            "CAPABILITY_NOT_FOUND",
            "PERMISSION_DENIED",
            "UNSUPPORTED_PLATFORM",
            "EXECUTION_TIMEOUT",
            "PATH_POLICY_VIOLATION",
            "JAVASCRIPT_ERROR",
            "NATIVE_FAILURE",
            "CANCELLED",
        ].contains(code)
    }

    private func missingJavaScriptFunctionName(from message: String) -> String? {
        let patterns = [
            "evaluating '([^']+)'",
            "Can't find variable: ([A-Za-z0-9_$.]+)",
            "'([A-Za-z0-9_$.]+)' is undefined",
            "([A-Za-z0-9_$.]+) is not a function",
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                continue
            }

            let nsRange = NSRange(message.startIndex..<message.endIndex, in: message)
            guard let match = regex.firstMatch(in: message, range: nsRange), match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: message)
            else {
                continue
            }

            let raw = String(message[range])
            let functionName = raw
                .split(separator: "(")
                .first
                .map(String.init)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let functionName, functionName.isEmpty == false {
                return functionName
            }
        }

        return nil
    }

    private func shouldClassifyAsMissingFunction(_ name: String, suggestions: [String]) -> Bool {
        guard suggestions.isEmpty == false else {
            return false
        }

        let normalized = name.lowercased()
        if normalized == "fetch" || normalized.hasPrefix("ios.") || normalized.hasPrefix("fs.") || normalized.hasPrefix("path.") {
            return true
        }

        return false
    }

    private static func snapshot(from exception: JSValue?) -> JavaScriptExceptionSnapshot? {
        guard let exception else {
            return nil
        }

        let name = exception.forProperty("name")?.toString()
        let message = exception.toString() ?? exception.forProperty("message")?.toString() ?? "JavaScript exception"
        let line = numericProperty(in: exception, names: ["line", "lineNumber"])
        let column = numericProperty(in: exception, names: ["column", "columnNumber"])

        return JavaScriptExceptionSnapshot(name: name, message: message, line: line, column: column)
    }

    private static func numericProperty(in exception: JSValue, names: [String]) -> Int? {
        for name in names {
            if let value = exception.forProperty(name)?.toNumber() {
                return value.intValue
            }
        }
        return nil
    }

    private func indented(_ code: String, prefix: String) -> String {
        code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    private func normalizedOptionalString(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" || trimmed == "undefined" {
            return nil
        }
        return trimmed
    }
}
