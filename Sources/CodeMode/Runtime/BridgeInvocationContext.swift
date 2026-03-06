import Foundation

public final class BridgeInvocationContext: @unchecked Sendable {
    public let executionContext: ExecutionContext
    public let allowedCapabilities: Set<CapabilityID>
    public let pathPolicy: any PathPolicy
    public let artifactStore: any ArtifactStore
    public let permissionBroker: any PermissionBroker
    public let auditLogger: any AuditLogger

    private let lock = NSLock()
    private var validatedPermissions: Set<PermissionKind> = []
    private let transcript: ExecutionTranscript
    private let cancellationController: ExecutionCancellationController

    init(
        executionContext: ExecutionContext,
        allowedCapabilities: Set<CapabilityID>,
        pathPolicy: any PathPolicy,
        artifactStore: any ArtifactStore,
        permissionBroker: any PermissionBroker,
        auditLogger: any AuditLogger,
        transcript: ExecutionTranscript,
        cancellationController: ExecutionCancellationController
    ) {
        self.executionContext = executionContext
        self.allowedCapabilities = allowedCapabilities
        self.pathPolicy = pathPolicy
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
        self.transcript = transcript
        self.cancellationController = cancellationController
    }

    public func log(_ level: ExecutionLog.Level, message: String) {
        let entry = ExecutionLog(level: level, message: message)
        transcript.record(log: entry)
    }

    public func recordPermission(_ permission: PermissionKind, status: PermissionStatus) {
        let event = PermissionEvent(permission: permission, status: status)
        transcript.record(permissionEvent: event)
    }

    public func allLogs() -> [ExecutionLog] {
        transcript.snapshot().logs
    }

    public func allPermissionEvents() -> [PermissionEvent] {
        transcript.snapshot().permissionEvents
    }

    func allDiagnostics() -> [ToolDiagnostic] {
        transcript.snapshot().diagnostics
    }

    func markPermissionValidated(_ permission: PermissionKind) {
        lock.lock()
        validatedPermissions.insert(permission)
        lock.unlock()
    }

    func isPermissionValidated(_ permission: PermissionKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return validatedPermissions.contains(permission)
    }

    func resolvedPermission(for permission: PermissionKind) -> PermissionStatus {
        if isPermissionValidated(permission) {
            return .granted
        }

        let status = permissionBroker.status(for: permission)
        recordPermission(permission, status: status)

        let resolved: PermissionStatus
        if status == .notDetermined {
            let requested = permissionBroker.request(for: permission)
            recordPermission(permission, status: requested)
            resolved = requested
        } else {
            resolved = status
        }

        if resolved == .granted {
            markPermissionValidated(permission)
        }

        return resolved
    }

    func recordDiagnostic(_ diagnostic: ToolDiagnostic) {
        transcript.record(diagnostic: diagnostic)
    }

    func checkCancellation() throws {
        if cancellationController.isCancelled || Task.isCancelled {
            throw BridgeError.cancelled
        }
    }
}
