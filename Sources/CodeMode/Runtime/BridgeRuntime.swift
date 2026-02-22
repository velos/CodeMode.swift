import Foundation
import JavaScriptCore

public struct BridgeRuntimeConfig: Sendable {
    public var pathPolicy: any PathPolicy
    public var artifactStore: any ArtifactStore
    public var permissionBroker: any PermissionBroker
    public var auditLogger: any AuditLogger

    public init(
        pathPolicy: any PathPolicy = DefaultPathPolicy(),
        artifactStore: any ArtifactStore = InMemoryArtifactStore(),
        permissionBroker: any PermissionBroker = SystemPermissionBroker(),
        auditLogger: any AuditLogger = SyncAuditLogger()
    ) {
        self.pathPolicy = pathPolicy
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
    }
}

public final class BridgeRuntime: @unchecked Sendable {
    private let registry: CapabilityRegistry
    private let catalog: BridgeCatalog
    private let config: BridgeRuntimeConfig

    public init(registry: CapabilityRegistry, catalog: BridgeCatalog, config: BridgeRuntimeConfig) {
        self.registry = registry
        self.catalog = catalog
        self.config = config
    }

    public func search(_ request: SearchRequest) -> SearchResponse {
        var diagnostics: [ToolDiagnostic] = []
        let limit = max(1, request.limit)

        if request.limit < 1 {
            diagnostics.append(
                ToolDiagnostic(
                    severity: .warning,
                    code: "INVALID_SEARCH_LIMIT",
                    message: "search.limit must be >= 1; defaulting to 1"
                )
            )
        }

        switch request.mode {
        case .discover:
            let query = (request.query ?? request.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return SearchResponse(
                items: catalog.search(query: query, limit: limit, tags: request.tags),
                diagnostics: diagnostics
            )
        case .describe:
            guard let capability = resolveDescribeCapability(from: request, diagnostics: &diagnostics) else {
                return SearchResponse(items: [], diagnostics: diagnostics)
            }

            guard let detail = catalog.detail(for: capability) else {
                diagnostics.append(
                    ToolDiagnostic(
                        severity: .error,
                        code: BridgeError.capabilityNotFound(capability.rawValue).diagnosticCode,
                        message: BridgeError.capabilityNotFound(capability.rawValue).localizedDescription
                    )
                )
                return SearchResponse(items: [], diagnostics: diagnostics)
            }

            let items = catalog.entry(for: capability).map { [$0] } ?? []
            return SearchResponse(items: items, detail: detail, diagnostics: diagnostics)
        }
    }

    public func execute(_ request: ExecuteRequest) -> ExecuteResponse {
        let invocationContext = BridgeInvocationContext(
            executionContext: request.context,
            allowedCapabilities: Set(request.allowedCapabilities),
            pathPolicy: config.pathPolicy,
            artifactStore: config.artifactStore,
            permissionBroker: config.permissionBroker,
            auditLogger: config.auditLogger
        )

        var diagnostics: [ToolDiagnostic] = []
        let context = JSContext()

        guard let context else {
            return ExecuteResponse(
                resultJSON: nil,
                logs: [],
                diagnostics: [ToolDiagnostic(severity: .error, code: "JS_CONTEXT_INIT", message: "Unable to initialize JavaScriptCore context")],
                permissionEvents: []
            )
        }

        context.exceptionHandler = { _, exception in
            diagnostics.append(
                ToolDiagnostic(
                    severity: .error,
                    code: "JS_EXCEPTION",
                    message: exception?.toString() ?? "Unknown JavaScript exception"
                )
            )
        }

        installBaseRuntime(into: context, invocationContext: invocationContext, diagnostics: &diagnostics)

        let timedOut = runUserScript(request.code, timeoutMs: request.timeoutMs, context: context, diagnostics: &diagnostics)
        if timedOut {
            diagnostics.append(ToolDiagnostic(severity: .error, code: BridgeError.timeout(milliseconds: request.timeoutMs).diagnosticCode, message: BridgeError.timeout(milliseconds: request.timeoutMs).localizedDescription))
        }

        let resultJSON = context.evaluateScript("JSON.stringify(globalThis.__codemode.result ?? null)")?.toString()

        return ExecuteResponse(
            resultJSON: resultJSON,
            logs: invocationContext.allLogs(),
            diagnostics: diagnostics,
            permissionEvents: invocationContext.allPermissionEvents()
        )
    }

    private func installBaseRuntime(into context: JSContext, invocationContext: BridgeInvocationContext, diagnostics: inout [ToolDiagnostic]) {
        let invokeBlock: @convention(block) (String, String) -> String = { capability, payload in
            do {
                let data = Data(payload.utf8)
                let parsed = (try JSONDecoder.codeModeBridge.decode(JSONValue.self, from: data)).objectValue ?? [:]
                let result = try self.registry.invoke(capability, arguments: parsed, context: invocationContext)
                invocationContext.log(.debug, message: "Capability executed: \(capability)")
                invocationContext.auditLogger.log(AuditEvent(capability: capability, message: "success"))

                let envelope = JSONValue.object([
                    "ok": .bool(true),
                    "value": result,
                ])
                let encoded = try JSONEncoder.codeModeBridge.encode(envelope)
                return String(data: encoded, encoding: .utf8) ?? "{\"ok\":false,\"error\":{\"code\":\"ENCODE_FAILURE\",\"message\":\"Encoding failed\"}}"
            } catch {
                let bridgeError = (error as? BridgeError) ?? BridgeError.nativeFailure(error.localizedDescription)
                let message = self.enrichedErrorMessage(for: capability, error: bridgeError)
                invocationContext.log(.error, message: "Capability failed \(capability): \(message)")
                invocationContext.auditLogger.log(AuditEvent(capability: capability, message: "failed: \(message)"))

                let envelope = JSONValue.object([
                    "ok": .bool(false),
                    "error": .object([
                        "code": .string(bridgeError.diagnosticCode),
                        "message": .string(message),
                    ]),
                ])
                let encoded = try? JSONEncoder.codeModeBridge.encode(envelope)
                return encoded.flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false,\"error\":{\"code\":\"UNKNOWN\",\"message\":\"Unknown bridge error\"}}"
            }
        }

        context.setObject(invokeBlock, forKeyedSubscript: "__bridgeInvokeSync" as NSString)

        let consoleLogBlock: @convention(block) (String) -> Void = { message in
            invocationContext.log(.info, message: message)
        }
        context.setObject(consoleLogBlock, forKeyedSubscript: "__nativeConsoleLog" as NSString)

        let bootScript = RuntimeJavaScript.bootstrap
        if context.evaluateScript(bootScript) == nil {
            diagnostics.append(ToolDiagnostic(severity: .error, code: "JS_BOOTSTRAP", message: "Failed to install base runtime"))
        }
    }

    private func runUserScript(_ code: String, timeoutMs: Int, context: JSContext, diagnostics: inout [ToolDiagnostic]) -> Bool {
        let script = """
        globalThis.__codemode.state = 'pending';
        globalThis.__codemode.result = null;
        globalThis.__codemode.error = null;
        (async function(){
            \(code)
        })()
        .then(function(value){
            globalThis.__codemode.state = 'fulfilled';
            globalThis.__codemode.result = value;
        })
        .catch(function(error){
            globalThis.__codemode.state = 'rejected';
            globalThis.__codemode.error = { message: String(error), code: error && error.code ? String(error.code) : null };
        });
        """

        _ = context.evaluateScript(script)

        let deadline = Date().addingTimeInterval(Double(timeoutMs) / 1000.0)
        while Date() < deadline {
            let state = context.evaluateScript("globalThis.__codemode.state")?.toString() ?? "unknown"
            if state == "fulfilled" {
                return false
            }
            if state == "rejected" {
                let code = context.evaluateScript("globalThis.__codemode.error?.code ?? 'JS_REJECTED'")?.toString() ?? "JS_REJECTED"
                let message = context.evaluateScript("globalThis.__codemode.error?.message ?? 'JavaScript promise rejected'")?.toString() ?? "JavaScript promise rejected"
                diagnostics.append(ToolDiagnostic(severity: .error, code: code, message: message))
                return false
            }
            Thread.sleep(forTimeInterval: 0.01)
        }

        return true
    }

    private func resolveDescribeCapability(from request: SearchRequest, diagnostics: inout [ToolDiagnostic]) -> CapabilityID? {
        if let capability = request.capability {
            return capability
        }

        let candidate = (request.query ?? request.code ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let capability = CapabilityID(rawValue: candidate) {
            return capability
        }

        diagnostics.append(
            ToolDiagnostic(
                severity: .error,
                code: BridgeError.invalidRequest("search.describe requires 'capability'").diagnosticCode,
                message: "search.describe requires 'capability' (for example: calendar.write)"
            )
        )
        return nil
    }

    private func enrichedErrorMessage(for capability: String, error: BridgeError) -> String {
        guard case .invalidArguments = error else {
            return error.localizedDescription
        }

        guard let capabilityID = CapabilityID(rawValue: capability), let detail = catalog.detail(for: capabilityID) else {
            return error.localizedDescription
        }

        var parts: [String] = []
        if detail.requiredArguments.isEmpty == false {
            parts.append("required: \(formatArguments(detail.requiredArguments, types: detail.argumentTypes))")
        }
        if detail.optionalArguments.isEmpty == false {
            parts.append("optional: \(formatArguments(detail.optionalArguments, types: detail.argumentTypes))")
        }
        parts.append("example: \(detail.example)")

        let hint = parts.joined(separator: "; ")
        return "\(error.localizedDescription). Hint: \(hint)"
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
}
