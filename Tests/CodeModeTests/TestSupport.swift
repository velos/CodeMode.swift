import Foundation
import Testing
@testable import CodeMode

struct TestSandbox {
    let root: URL
    let tmp: URL
    let caches: URL
    let documents: URL
}

struct ObservedExecution {
    let events: [JavaScriptExecutionEvent]
    let result: JavaScriptExecutionResult?
    let error: CodeModeToolError?
}

func makeTestSandbox() throws -> TestSandbox {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent("CodeModeTests-\(UUID().uuidString)", isDirectory: true)
    let tmp = root.appendingPathComponent("tmp", isDirectory: true)
    let caches = root.appendingPathComponent("caches", isDirectory: true)
    let documents = root.appendingPathComponent("documents", isDirectory: true)

    try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
    try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)

    return TestSandbox(root: root, tmp: tmp, caches: caches, documents: documents)
}

func cleanup(_ sandbox: TestSandbox) {
    try? FileManager.default.removeItem(at: sandbox.root)
}

func makeTools(permissionBroker: any PermissionBroker = NoopPermissionBroker()) throws -> (CodeModeAgentTools, TestSandbox) {
    let sandbox = try makeTestSandbox()

    let pathPolicy = DefaultPathPolicy(
        config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
    )

    let configuration = CodeModeConfiguration(
        pathPolicy: pathPolicy,
        artifactStore: InMemoryArtifactStore(),
        permissionBroker: permissionBroker,
        auditLogger: SyncAuditLogger()
    )

    let tools = CodeModeAgentTools(config: configuration)
    return (tools, sandbox)
}

func makeInvocationContext(
    permissionBroker: any PermissionBroker = NoopPermissionBroker(),
    allowedCapabilities: Set<CapabilityID> = Set(CapabilityID.allCases)
) throws -> (BridgeInvocationContext, TestSandbox) {
    let sandbox = try makeTestSandbox()
    let pathPolicy = DefaultPathPolicy(
        config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
    )

    let context = BridgeInvocationContext(
        executionContext: .init(userID: "test-user", sessionID: "test-session"),
        allowedCapabilities: allowedCapabilities,
        pathPolicy: pathPolicy,
        artifactStore: InMemoryArtifactStore(),
        permissionBroker: permissionBroker,
        auditLogger: SyncAuditLogger(),
        transcript: ExecutionTranscript(),
        cancellationController: ExecutionCancellationController()
    )

    return (context, sandbox)
}

func observe(_ call: JavaScriptExecutionCall) async -> ObservedExecution {
    let eventTask = Task { () -> [JavaScriptExecutionEvent] in
        var events: [JavaScriptExecutionEvent] = []
        for await event in call.events {
            events.append(event)
        }
        return events
    }

    do {
        let result = try await call.result
        let events = await eventTask.value
        return ObservedExecution(events: events, result: result, error: nil)
    } catch let error as CodeModeToolError {
        let events = await eventTask.value
        return ObservedExecution(events: events, result: nil, error: error)
    } catch {
        let events = await eventTask.value
        return ObservedExecution(
            events: events,
            result: nil,
            error: CodeModeToolError(code: "INTERNAL_FAILURE", message: error.localizedDescription)
        )
    }
}

func execute(_ tools: CodeModeAgentTools, request: JavaScriptExecutionRequest) async throws -> ObservedExecution {
    let call = try await tools.executeJavaScript(request)
    return await observe(call)
}

struct FixedPermissionBroker: PermissionBroker {
    var statuses: [PermissionKind: PermissionStatus]
    var requestStatuses: [PermissionKind: PermissionStatus]

    init(statuses: [PermissionKind: PermissionStatus], requestStatuses: [PermissionKind: PermissionStatus] = [:]) {
        self.statuses = statuses
        self.requestStatuses = requestStatuses
    }

    func status(for permission: PermissionKind) -> PermissionStatus {
        statuses[permission] ?? .unavailable
    }

    func request(for permission: PermissionKind) -> PermissionStatus {
        requestStatuses[permission] ?? statuses[permission] ?? .unavailable
    }
}

@discardableResult
func requireJSONObject(from result: JavaScriptExecutionResult) throws -> [String: Any] {
    guard let output = result.output else {
        throw BridgeError.nativeFailure("Missing result output")
    }

    let data = try JSONEncoder.codeModeBridge.encode(output)
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BridgeError.nativeFailure("Result output is not an object")
    }

    return object
}

func requireBridgeErrorCode(_ error: Error) -> String {
    if let bridgeError = error as? BridgeError {
        return bridgeError.diagnosticCode
    }

    if let toolError = error as? CodeModeToolError {
        return toolError.code
    }

    if let localized = error as? LocalizedError {
        return localized.errorDescription ?? String(describing: error)
    }

    return String(describing: error)
}

func requireObject(_ value: JSONValue) throws -> [String: JSONValue] {
    guard let object = value.objectValue else {
        throw BridgeError.nativeFailure("Expected JSON object")
    }
    return object
}

func requireArray(_ value: JSONValue) throws -> [JSONValue] {
    guard let array = value.arrayValue else {
        throw BridgeError.nativeFailure("Expected JSON array")
    }
    return array
}
