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
        var capabilityKey: CodeModeCapabilityKey?
        var functionName: String?
        var suggestions: [String]
    }

    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let config: CodeModeConfiguration
    private let unsupportedBuiltInJavaScriptNames: [String]
    private let executionQueue = DispatchQueue(
        label: "CodeMode.BridgeRuntime.execution",
        qos: .userInitiated,
        attributes: .concurrent
    )

    init(
        registry: CapabilityRegistry,
        catalog: BridgeCatalog,
        config: CodeModeConfiguration,
        unsupportedBuiltInJavaScriptNames: [String] = []
    ) {
        self.registry = registry
        self.catalog = catalog
        self.config = config
        self.unsupportedBuiltInJavaScriptNames = unsupportedBuiltInJavaScriptNames
    }

    func search(_ request: JavaScriptAPISearchRequest) throws -> JavaScriptAPISearchResponse {
        let code = request.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.isEmpty == false else {
            throw CodeModeToolError(
                code: "INVALID_REQUEST",
                message: "searchJavaScriptAPI requires a non-empty async function"
            )
        }

        let transcript = ExecutionTranscript()
        let cancellationController = ExecutionCancellationController()
        let invocationContext = BridgeInvocationContext(
            executionContext: .init(),
            allowedCapabilities: [],
            allowedCapabilityKeys: [],
            pathPolicy: config.pathPolicy,
            artifactStore: config.artifactStore,
            permissionBroker: config.permissionBroker,
            auditLogger: config.auditLogger,
            systemUIPresenter: config.systemUIPresenter,
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

        try installSearchRuntime(
            into: context,
            transcript: transcript,
            lastException: lastException
        )

        let output = try runSearchScript(
            code,
            timeoutMs: 2_000,
            context: context,
            invocationContext: invocationContext,
            cancellationController: cancellationController,
            lastException: lastException
        )

        return JavaScriptAPISearchResponse(
            result: output,
            diagnostics: transcript.snapshot().diagnostics
        )
    }

    func searchAsync(_ request: JavaScriptAPISearchRequest) async throws -> JavaScriptAPISearchResponse {
        try await runOnExecutionQueue {
            try self.search(request)
        }
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
                let result = try await self.runOnExecutionQueue {
                    try self.execute(
                        request,
                        transcript: transcript,
                        cancellationController: cancellationController
                    )
                }
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

    private func runOnExecutionQueue<Output: Sendable>(
        _ operation: @escaping @Sendable () throws -> Output
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            executionQueue.async {
                do {
                    continuation.resume(returning: try operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func execute(
        _ request: JavaScriptExecutionRequest,
        transcript: ExecutionTranscript,
        cancellationController: ExecutionCancellationController
    ) throws -> JavaScriptExecutionResult {
        // `allowedCapabilities` / `allowedCapabilityKeys` are model-authored, so they
        // are a declaration of intent, not a boundary. The host's grant is the
        // boundary: the effective set is always requested ∩ granted.
        let grant = config.capabilityGrant.resolve(
            requestedCapabilities: Set(request.allowedCapabilities),
            requestedCapabilityKeys: Set(request.allowedCapabilityKeys)
        )

        let withheld = grant.withheldEverything
        if withheld.isEmpty == false {
            transcript.record(
                diagnostic: ToolDiagnostic(
                    severity: .warning,
                    code: "CAPABILITY_WITHHELD_BY_HOST",
                    message: "The host's capability grant withheld: \(withheld.joined(separator: ", ")). Calls needing these fail with CAPABILITY_DENIED and cannot be repaired from the script.",
                    category: "security",
                    suggestions: [
                        "Do not retry with a wider allowedCapabilities; the host decides this set.",
                        "Complete what you can with the granted capabilities, or report the missing access to the user.",
                    ]
                )
            )
        }

        let invocationContext = BridgeInvocationContext(
            executionContext: request.context,
            allowedCapabilities: grant.capabilities,
            allowedCapabilityKeys: grant.capabilityKeys,
            hostWithheldCapabilityIdentifiers: Set(withheld),
            pathPolicy: config.pathPolicy,
            artifactStore: config.artifactStore,
            permissionBroker: config.permissionBroker,
            auditLogger: config.auditLogger,
            systemUIPresenter: config.systemUIPresenter,
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
                let capabilityKey = CodeModeCapabilityKey(rawValue: capability)
                let errorPayload = self.bridgeFailurePayload(
                    for: bridgeError,
                    capability: capabilityID,
                    capabilityKey: capabilityKey,
                    invocationContext: invocationContext
                )
                invocationContext.log(.error, message: "Capability failed \(capability): \(errorPayload.message)")
                invocationContext.auditLogger.log(AuditEvent(capability: capability, message: "failed: \(errorPayload.message)"))

                let envelope = JSONValue.object([
                    "ok": .bool(false),
                    "error": .object([
                        "code": .string(errorPayload.code),
                        "message": .string(errorPayload.message),
                        "capability": .string(capabilityKey.rawValue),
                        "suggestions": .array(errorPayload.suggestions.map { .string($0) }),
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

        let builtInScript = RuntimeJavaScript.builtInBootstrap(for: registry.allCapabilityRegistrations())
        if builtInScript.isEmpty == false, context.evaluateScript(builtInScript) == nil {
            let message = lastException.get()?.message ?? "Failed to install built-in JavaScript bindings"
            throw CodeModeToolError(
                code: "INTERNAL_FAILURE",
                message: message,
                diagnostics: [
                    ToolDiagnostic(
                        severity: .error,
                        code: "JS_BUILTIN_BOOTSTRAP",
                        message: message,
                        category: "internal"
                    )
                ]
            )
        }

        let pruningScript = RuntimeJavaScript.pruningScript(
            removingJavaScriptNames: unsupportedBuiltInJavaScriptNames
        )

        if pruningScript.isEmpty == false, context.evaluateScript(pruningScript) == nil {
            let message = lastException.get()?.message ?? "Failed to prune unsupported JavaScript bindings"
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

        let providerScript = RuntimeJavaScript.providerBootstrap(for: registry.allCodeModeRegistrations())
        if providerScript.isEmpty == false, context.evaluateScript(providerScript) == nil {
            let message = lastException.get()?.message ?? "Failed to install provider JavaScript bindings"
            throw CodeModeToolError(
                code: "INTERNAL_FAILURE",
                message: message,
                diagnostics: [
                    ToolDiagnostic(
                        severity: .error,
                        code: "JS_PROVIDER_BOOTSTRAP",
                        message: message,
                        category: "internal"
                    )
                ]
            )
        }

        _ = context.evaluateScript(
            """
            delete globalThis.__codemodeInstallBinding;
            delete globalThis.__codemodeInstallBindingIfMissing;
            """
        )
    }

    private func installSearchRuntime(
        into context: JSContext,
        transcript: ExecutionTranscript,
        lastException: LockedBox<JavaScriptExceptionSnapshot?>
    ) throws {
        let searchConsoleBlock: @convention(block) (String, String) -> Void = { level, message in
            let severity: ToolDiagnostic.Severity
            switch level {
            case "error":
                severity = .error
            case "warning":
                severity = .warning
            default:
                severity = .info
            }

            transcript.record(
                diagnostic: ToolDiagnostic(
                    severity: severity,
                    code: "SEARCH_CONSOLE",
                    message: message,
                    category: "search"
                )
            )
        }
        context.setObject(searchConsoleBlock, forKeyedSubscript: "__searchConsole" as NSString)
        context.setObject(catalog.searchCatalogValue().any, forKeyedSubscript: "api" as NSString)

        if context.evaluateScript(RuntimeJavaScript.searchBootstrap) == nil {
            let message = lastException.get()?.message ?? "Failed to install search runtime"
            throw CodeModeToolError(
                code: "INTERNAL_FAILURE",
                message: message,
                diagnostics: [
                    ToolDiagnostic(
                        severity: .error,
                        code: "JS_SEARCH_BOOTSTRAP",
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
        let executionCode = Self.returningBareAwaitCode(from: code) ?? code
        let script = """
        globalThis.__codemode.state = 'pending';
        globalThis.__codemode.result = undefined;
        globalThis.__codemode.error = null;
        (async function(){
        \(indented(executionCode, prefix: "    "))
        })()
        .then(function(value){
            globalThis.__codemode.state = 'fulfilled';
            globalThis.__codemode.result = value;
        })
        .catch(function(error){
            globalThis.__codemode.state = 'rejected';
            globalThis.__codemode.error = {
                message: error && error.code && error.message ? String(error.message) : String(error),
                code: error && error.code ? String(error.code) : null,
                capability: error && error.capability ? String(error.capability) : null,
                functionName: error && error.functionName ? String(error.functionName) : null,
                suggestions: error && Array.isArray(error.suggestions) ? error.suggestions.map(function(value){ return String(value); }) : []
            };
        });
        """

        let watchdog = ExecutionWatchdog(timeoutMs: timeoutMs, cancellationController: cancellationController)
        watchdog.install(on: context)
        defer { watchdog.uninstall(from: context) }

        lastException.set(nil)
        let evaluation = context.evaluateScript(script)

        switch watchdog.termination {
        case .timedOut:
            throw toolError(
                code: "EXECUTION_TIMEOUT",
                message: "Execution timed out after \(timeoutMs)ms",
                transcript: invocationContext
            )
        case .cancelled:
            throw toolError(
                code: "CANCELLED",
                message: "Execution cancelled",
                transcript: invocationContext
            )
        case nil:
            break
        }

        let snapshot = lastException.get() ?? Self.snapshot(from: context.exception)
        if snapshot != nil || evaluation == nil {
            throw syntaxError(from: snapshot, lineOffset: 4)
        }

        let settlement = try waitForSettlement(
            context: context,
            watchdog: watchdog,
            cancellationController: cancellationController,
            invocationContext: invocationContext,
            timeoutCode: "EXECUTION_TIMEOUT",
            timeoutMessage: "Execution timed out after \(timeoutMs)ms",
            cancelMessage: "Execution cancelled"
        )

        // Give result serialization its own bounded budget so a script that
        // settled near the deadline still serializes, while a runaway getter or
        // toJSON is terminated instead of hanging the execution thread.
        watchdog.rearm(timeoutMs: max(timeoutMs, 1_000))

        switch settlement {
        case .fulfilled:
            let output = try decodeOutput(from: context)
            if output == nil {
                invocationContext.recordDiagnostic(Self.noReturnValueDiagnostic(for: code))
            }
            return output
        case .rejected:
            let payload = rejectionPayload(from: context)
            throw classifyRejectedError(payload, invocationContext: invocationContext)
        }
    }

    private enum SettlementState {
        case fulfilled
        case rejected
    }

    /// Polls the wrapped promise's settled state until it resolves, is
    /// cancelled, or the watchdog deadline passes. The settled state is checked
    /// before the deadline on every iteration, so a script that has already
    /// fulfilled — the common case under the synchronous bridge model — returns
    /// its result even if evaluation finished a hair past the deadline, instead
    /// of being discarded with a spurious timeout.
    private func waitForSettlement(
        context: JSContext,
        watchdog: ExecutionWatchdog,
        cancellationController: ExecutionCancellationController,
        invocationContext: BridgeInvocationContext,
        timeoutCode: String,
        timeoutMessage: String,
        cancelMessage: String
    ) throws -> SettlementState {
        while true {
            if cancellationController.isCancelled || Task.isCancelled {
                cancellationController.cancel()
                throw toolError(code: "CANCELLED", message: cancelMessage, transcript: invocationContext)
            }

            let state = context.evaluateScript("globalThis.__codemode.state")?.toString() ?? "unknown"
            switch state {
            case "fulfilled":
                return .fulfilled
            case "rejected":
                return .rejected
            default:
                if let termination = watchdog.termination {
                    switch termination {
                    case .cancelled:
                        throw toolError(code: "CANCELLED", message: cancelMessage, transcript: invocationContext)
                    case .timedOut:
                        throw toolError(code: timeoutCode, message: timeoutMessage, transcript: invocationContext)
                    }
                }
                if Date() >= watchdog.deadline {
                    throw toolError(code: timeoutCode, message: timeoutMessage, transcript: invocationContext)
                }
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    private static func noReturnValueDiagnostic(for code: String) -> ToolDiagnostic {
        let mentionsAsyncIIFE = code.contains("(async") && (code.contains("})()") || code.contains("})();"))
        let message: String
        if mentionsAsyncIIFE {
            message = "Script completed without a top-level return value. The runtime already wraps executeJavaScript code in an async function; do not use an async IIFE as a bare final expression. Use top-level await and a top-level return statement instead."
        } else {
            message = "Script completed without a top-level return value. executeJavaScript only returns values from explicit top-level return statements."
        }

        return ToolDiagnostic(
            severity: .warning,
            code: "NO_RETURN_VALUE",
            message: message,
            category: "execution",
            suggestions: [
                "Return the graded value with a top-level return statement.",
                "Use top-level await directly; avoid wrapping the script in an unreturned async IIFE.",
            ]
        )
    }

    private static func returningBareAwaitCode(from code: String) -> String? {
        var trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix(";") {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard trimmed.hasPrefix("await "),
              !trimmed.dropFirst("await ".count).contains(";") else {
            return nil
        }
        return "return \(trimmed);"
    }

    private func runSearchScript(
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
        Promise.resolve()
        .then(function(){
            const __search = (\(code));
            if (typeof __search !== 'function') {
                const error = new Error('searchJavaScriptAPI code must evaluate to a function');
                error.code = 'INVALID_REQUEST';
                throw error;
            }
            return __search();
        })
        .then(function(value){
            globalThis.__codemode.state = 'fulfilled';
            globalThis.__codemode.result = value;
        })
        .catch(function(error){
            globalThis.__codemode.state = 'rejected';
            globalThis.__codemode.error = {
                message: String(error),
                code: error && error.code ? String(error.code) : null
            };
        });
        """

        let watchdog = ExecutionWatchdog(timeoutMs: timeoutMs, cancellationController: cancellationController)
        watchdog.install(on: context)
        defer { watchdog.uninstall(from: context) }

        lastException.set(nil)
        let evaluation = context.evaluateScript(script)

        switch watchdog.termination {
        case .timedOut:
            throw toolError(
                code: "SEARCH_TIMEOUT",
                message: "Search timed out after \(timeoutMs)ms",
                transcript: invocationContext
            )
        case .cancelled:
            throw toolError(
                code: "CANCELLED",
                message: "Search cancelled",
                transcript: invocationContext
            )
        case nil:
            break
        }

        let snapshot = lastException.get() ?? Self.snapshot(from: context.exception)
        if snapshot != nil || evaluation == nil {
            throw syntaxError(from: snapshot, lineOffset: 5)
        }

        let settlement = try waitForSettlement(
            context: context,
            watchdog: watchdog,
            cancellationController: cancellationController,
            invocationContext: invocationContext,
            timeoutCode: "SEARCH_TIMEOUT",
            timeoutMessage: "Search timed out after \(timeoutMs)ms",
            cancelMessage: "Search cancelled"
        )

        watchdog.rearm(timeoutMs: max(timeoutMs, 1_000))

        switch settlement {
        case .fulfilled:
            return try decodeOutput(
                from: context,
                errorCode: "INVALID_SEARCH_RESULT",
                errorMessagePrefix: "Search result must be JSON-serializable"
            )
        case .rejected:
            let payload = rejectionPayload(from: context)
            throw classifySearchRejectedError(payload, invocationContext: invocationContext)
        }
    }

    private func decodeOutput(
        from context: JSContext,
        errorCode: String = "INVALID_RESULT",
        errorMessagePrefix: String = "Execution result must be JSON-serializable"
    ) throws -> JSONValue? {
        guard let resultValue = context.evaluateScript("globalThis.__codemode.result"), resultValue.isUndefined == false else {
            return nil
        }

        guard let serialization = context.evaluateScript(
            """
            (function(){
                try {
                    return { ok: true, json: JSON.stringify(globalThis.__codemode.result) };
                } catch (error) {
                    return { ok: false, message: String(error) };
                }
            })()
            """
        ) else {
            throw CodeModeToolError(code: errorCode, message: errorMessagePrefix)
        }

        if serialization.forProperty("ok")?.toBool() == false {
            let message = serialization.forProperty("message")?.toString() ?? errorMessagePrefix
            throw CodeModeToolError(code: errorCode, message: "\(errorMessagePrefix): \(message)")
        }

        guard let jsonValue = serialization.forProperty("json"), jsonValue.isUndefined == false, jsonValue.isNull == false,
              let serialized = jsonValue.toString()
        else {
            return nil
        }

        guard let data = serialized.data(using: .utf8) else {
            throw CodeModeToolError(code: errorCode, message: errorMessagePrefix)
        }

        return try JSONDecoder.codeModeBridge.decode(JSONValue.self, from: data)
    }

    private func bridgeFailurePayload(
        for error: BridgeError,
        capability: CapabilityID?,
        capabilityKey: CodeModeCapabilityKey?,
        invocationContext: BridgeInvocationContext? = nil
    ) -> CodeModeToolError {
        let (message, suggestions) = enrichedBridgeFailure(
            for: error,
            capability: capability,
            capabilityKey: capabilityKey,
            invocationContext: invocationContext
        )
        return CodeModeToolError(
            code: error.diagnosticCode,
            message: message,
            capability: capability,
            capabilityKey: capabilityKey,
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
            let suggestions = payload.suggestions.isEmpty
                ? bridgeSuggestions(for: payload.capability, capabilityKey: payload.capabilityKey)
                : payload.suggestions
            return CodeModeToolError(
                code: code,
                message: payload.message,
                functionName: payload.functionName,
                capability: payload.capability,
                capabilityKey: payload.capabilityKey,
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

    private func classifySearchRejectedError(
        _ payload: RejectionPayload,
        invocationContext: BridgeInvocationContext
    ) -> CodeModeToolError {
        let diagnostics = invocationContext.allDiagnostics()

        if payload.code == "INVALID_REQUEST" {
            return CodeModeToolError(
                code: "INVALID_REQUEST",
                message: payload.message,
                diagnostics: diagnostics
            )
        }

        return CodeModeToolError(
            code: "JS_RUNTIME_ERROR",
            message: payload.message,
            diagnostics: diagnostics
        )
    }

    private func syntaxError(from snapshot: JavaScriptExceptionSnapshot?, lineOffset: Int) -> CodeModeToolError {
        let message = snapshot?.message ?? "JavaScript syntax error"
        let adjustedLine = snapshot?.line.map { max(1, $0 - lineOffset) }
        return CodeModeToolError(
            code: "JS_SYNTAX_ERROR",
            message: message,
            line: adjustedLine,
            column: snapshot?.column
        )
    }

    private func rejectionPayload(from context: JSContext) -> RejectionPayload {
        let capabilityString = normalizedOptionalString(
            context.evaluateScript("globalThis.__codemode.error?.capability ?? null")?.toString()
        )
        let capability = capabilityString.flatMap(CapabilityID.init(rawValue:))
        let capabilityKey = capabilityString.map(CodeModeCapabilityKey.init(rawValue:))

        return RejectionPayload(
            code: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.code ?? null")?.toString()
            ),
            message: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.message ?? null")?.toString()
            ) ?? "JavaScript promise rejected",
            capability: capability,
            capabilityKey: capabilityKey,
            functionName: normalizedOptionalString(
                context.evaluateScript("globalThis.__codemode.error?.functionName ?? null")?.toString()
            ),
            suggestions: rejectedSuggestions(from: context)
        )
    }

    private func rejectedSuggestions(from context: JSContext) -> [String] {
        guard let json = context.evaluateScript("JSON.stringify(globalThis.__codemode.error?.suggestions ?? [])")?.toString(),
              let data = json.data(using: .utf8),
              let suggestions = try? JSONDecoder.codeModeBridge.decode([String].self, from: data)
        else {
            return []
        }
        return suggestions
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
        capabilityKey: CodeModeCapabilityKey? = nil,
        suggestions: [String] = []
    ) -> CodeModeToolError {
        CodeModeToolError(
            code: code,
            message: message,
            functionName: functionName,
            capability: capability,
            capabilityKey: capabilityKey,
            suggestions: suggestions,
            diagnostics: transcript.allDiagnostics(),
            logs: transcript.allLogs(),
            permissionEvents: transcript.allPermissionEvents()
        )
    }

    private func bridgeSuggestions(for capability: CapabilityID?) -> [String] {
        bridgeSuggestions(for: capability, capabilityKey: capability?.codeModeKey)
    }

    private func bridgeSuggestions(for capability: CapabilityID?, capabilityKey: CodeModeCapabilityKey?) -> [String] {
        let reference: JavaScriptAPIReference?
        if let capability {
            reference = catalog.reference(for: capability)
        } else if let capabilityKey {
            reference = catalog.reference(for: capabilityKey)
        } else {
            reference = nil
        }
        guard let reference else {
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

    private func enrichedBridgeFailure(
        for error: BridgeError,
        capability: CapabilityID?,
        capabilityKey: CodeModeCapabilityKey?,
        invocationContext: BridgeInvocationContext? = nil
    ) -> (String, [String]) {
        let suggestions: [String]
        switch error {
        case let .capabilityDenied(capability):
            if invocationContext?.isWithheldByHost(capability.rawValue) == true {
                suggestions = hostWithheldSuggestions(for: capability.rawValue)
            } else {
                suggestions = [
                    "Add \"\(capability.rawValue)\" to allowedCapabilities and retry.",
                    "Built-in capabilities are granted only by allowedCapabilities; listing one in allowedCapabilityKeys has no effect.",
                ] + bridgeSuggestions(for: capability, capabilityKey: capability.codeModeKey)
            }
        case let .capabilityKeyDenied(capabilityKey):
            if invocationContext?.isWithheldByHost(capabilityKey.rawValue) == true {
                suggestions = hostWithheldSuggestions(for: capabilityKey.rawValue)
            } else {
                suggestions = [
                    "Add \"\(capabilityKey.rawValue)\" to allowedCapabilityKeys and retry.",
                    "Custom provider capabilities are not enabled by allowedCapabilities.",
                ] + bridgeSuggestions(for: nil, capabilityKey: capabilityKey)
            }
        case let .permissionDenied(permission):
            suggestions = permissionDeniedSuggestions(for: permission)
        case .customPermissionDenied:
            suggestions = [
                "The custom provider denied permission after capability allowlisting succeeded.",
                "This is not repaired by adding more allowedCapabilities; request provider permission or ask the host/user to grant access.",
            ]
        case .uiPresenterUnavailable:
            suggestions = [
                "Configure CodeModeConfiguration.systemUIPresenter before using UI-presenting helpers.",
                "Do not retry this helper until the host provides a SystemUIPresenter.",
            ]
        case .networkPolicyViolation:
            suggestions = [
                "The host app's network access policy refused this destination.",
                "This is not repaired by adding more allowedCapabilities; do not retry the same URL.",
                "Only public HTTP(S) destinations permitted by CodeModeConfiguration.networkAccessPolicy are reachable.",
            ]
        default:
            suggestions = bridgeSuggestions(for: capability, capabilityKey: capabilityKey)
        }

        return (error.localizedDescription, suggestions)
    }

    private func hostWithheldSuggestions(for identifier: String) -> [String] {
        [
            "The host app's capability grant does not include \"\(identifier)\".",
            "This is not repaired by adding it to allowedCapabilities or allowedCapabilityKeys; the host owns this decision.",
            "Continue with the capabilities you do have, or report the missing access to the user.",
        ]
    }

    private func permissionDeniedSuggestions(for permission: PermissionKind) -> [String] {
        var suggestions = [
            "Permission \"\(permission.rawValue)\" was denied after capability allowlisting succeeded.",
            "Do not repair this by adding more allowedCapabilities; the host or OS permission must change.",
        ]

        if let helper = permissionRequestHelper(for: permission) {
            suggestions.append("If appropriate, call \(helper) first with its request capability allowlisted, then retry the original helper.")
        } else {
            suggestions.append("No CodeMode request helper is available for this permission; ask the user or host app to grant access.")
        }

        return suggestions
    }

    private func permissionRequestHelper(for permission: PermissionKind) -> String? {
        switch permission {
        case .locationWhenInUse:
            return "apple.location.requestPermission()"
        case .notifications:
            return "apple.notifications.requestPermission()"
        case .alarmKit:
            return "ios.alarm.requestPermission()"
        case .healthKit:
            return "apple.health.requestPermission({ readTypes: [...], writeTypes: [...] })"
        case .speechRecognition:
            return "apple.speech.requestPermission()"
        case .music:
            return "apple.music.requestPermission()"
        case .contacts, .calendar, .calendarWriteOnly, .reminders, .photoLibrary, .homeKit, .microphone:
            return nil
        }
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
            "UI_PRESENTER_UNAVAILABLE",
            "EXECUTION_TIMEOUT",
            "PATH_POLICY_VIOLATION",
            "NETWORK_POLICY_VIOLATION",
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
        if normalized == "fetch"
            || normalized.hasPrefix("apple.")
            || normalized.hasPrefix("ios.")
            || normalized.hasPrefix("fs.")
            || normalized.hasPrefix("path.")
            || catalog.closestFunctionNames(to: name).isEmpty == false
        {
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
