import Foundation
import Testing
@testable import CodeMode

struct TestSandbox {
    let root: URL
    let tmp: URL
    let caches: URL
    let documents: URL
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

func makeHost(permissionBroker: any PermissionBroker = NoopPermissionBroker()) throws -> (CodeModeBridgeHost, TestSandbox) {
    let sandbox = try makeTestSandbox()

    let pathPolicy = DefaultPathPolicy(
        config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
    )

    let runtime = BridgeRuntimeConfig(
        pathPolicy: pathPolicy,
        artifactStore: InMemoryArtifactStore(),
        permissionBroker: permissionBroker,
        auditLogger: SyncAuditLogger()
    )

    let host = CodeModeBridgeHost(config: .init(runtimeConfig: runtime))
    return (host, sandbox)
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
        auditLogger: SyncAuditLogger()
    )

    return (context, sandbox)
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
func requireJSONObject(from response: ExecuteResponse) throws -> [String: Any] {
    guard let resultJSON = response.resultJSON else {
        throw BridgeError.nativeFailure("Missing result JSON")
    }

    guard let data = resultJSON.data(using: .utf8) else {
        throw BridgeError.nativeFailure("Unable to decode result JSON")
    }

    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BridgeError.nativeFailure("Result JSON is not an object")
    }

    return object
}

func requireBridgeErrorCode(_ error: Error) -> String {
    if let bridgeError = error as? BridgeError {
        return bridgeError.diagnosticCode
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
