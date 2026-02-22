import Foundation

public final class BridgeInvocationContext: @unchecked Sendable {
    public let executionContext: ExecutionContext
    public let allowedCapabilities: Set<CapabilityID>
    public let pathPolicy: any PathPolicy
    public let artifactStore: any ArtifactStore
    public let permissionBroker: any PermissionBroker
    public let auditLogger: any AuditLogger

    private let lock = NSLock()
    private var logs: [ExecutionLog] = []
    private var permissionEvents: [PermissionEvent] = []

    public init(
        executionContext: ExecutionContext,
        allowedCapabilities: Set<CapabilityID>,
        pathPolicy: any PathPolicy,
        artifactStore: any ArtifactStore,
        permissionBroker: any PermissionBroker,
        auditLogger: any AuditLogger
    ) {
        self.executionContext = executionContext
        self.allowedCapabilities = allowedCapabilities
        self.pathPolicy = pathPolicy
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
    }

    public func log(_ level: ExecutionLog.Level, message: String) {
        let entry = ExecutionLog(level: level, message: message)
        lock.lock()
        logs.append(entry)
        lock.unlock()
    }

    public func recordPermission(_ permission: PermissionKind, status: PermissionStatus) {
        let event = PermissionEvent(permission: permission, status: status)
        lock.lock()
        permissionEvents.append(event)
        lock.unlock()
    }

    public func allLogs() -> [ExecutionLog] {
        lock.lock()
        defer { lock.unlock() }
        return logs
    }

    public func allPermissionEvents() -> [PermissionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return permissionEvents
    }
}
