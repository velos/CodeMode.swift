import Foundation

public final class BridgeInvocationContext: @unchecked Sendable {
    public let executionContext: ExecutionContext
    /// Built-in capabilities this execution may reach: the model's declaration
    /// intersected with the host's `CapabilityGrant`.
    public let allowedCapabilities: Set<CapabilityID>
    /// Custom provider keys this execution may reach. Deliberately disjoint from
    /// `allowedCapabilities` — a built-in capability is never granted by a key, or
    /// `allowedCapabilityKeys` would be a way around a host that vets only the
    /// strictly-typed `allowedCapabilities`.
    public let allowedCapabilityKeys: Set<CodeModeCapabilityKey>
    /// Identifiers the request asked for and the host's grant withheld. Used to
    /// tell the model a denial is not repairable by widening `allowedCapabilities`.
    public let hostWithheldCapabilityIdentifiers: Set<String>
    public let pathPolicy: any PathPolicy
    public let artifactStore: any ArtifactStore
    public let permissionBroker: any PermissionBroker
    public let auditLogger: any AuditLogger
    public let systemUIPresenter: any SystemUIPresenter

    private let lock = NSLock()
    private var validatedPermissions: Set<PermissionKind> = []
    private let transcript: ExecutionTranscript
    private let cancellationController: ExecutionCancellationController

    init(
        executionContext: ExecutionContext,
        allowedCapabilities: Set<CapabilityID>,
        allowedCapabilityKeys: Set<CodeModeCapabilityKey> = [],
        hostWithheldCapabilityIdentifiers: Set<String> = [],
        pathPolicy: any PathPolicy,
        artifactStore: any ArtifactStore,
        permissionBroker: any PermissionBroker,
        auditLogger: any AuditLogger,
        systemUIPresenter: any SystemUIPresenter = UnavailableSystemUIPresenter(),
        transcript: ExecutionTranscript,
        cancellationController: ExecutionCancellationController
    ) {
        self.executionContext = executionContext
        self.allowedCapabilities = allowedCapabilities
        self.allowedCapabilityKeys = allowedCapabilityKeys
        self.hostWithheldCapabilityIdentifiers = hostWithheldCapabilityIdentifiers
        self.pathPolicy = pathPolicy
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
        self.systemUIPresenter = systemUIPresenter
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

    /// True when the request declared this identifier but the host's
    /// `CapabilityGrant` withheld it — a denial the model cannot repair.
    func isWithheldByHost(_ identifier: String) -> Bool {
        hostWithheldCapabilityIdentifiers.contains(identifier)
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
