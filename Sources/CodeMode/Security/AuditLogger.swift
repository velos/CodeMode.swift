import Foundation

public struct AuditEvent: Sendable, Codable, Equatable {
    public var capability: String
    public var message: String
    public var timestamp: Date

    public init(capability: String, message: String, timestamp: Date = Date()) {
        self.capability = capability
        self.message = message
        self.timestamp = timestamp
    }
}

public protocol AuditLogger: Sendable {
    func log(_ event: AuditEvent)
    func drain() -> [AuditEvent]
}

public final class SyncAuditLogger: AuditLogger, @unchecked Sendable {
    private let lock = NSLock()
    private var events: [AuditEvent] = []

    public init() {}

    public func log(_ event: AuditEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    public func drain() -> [AuditEvent] {
        lock.lock()
        defer { lock.unlock() }
        let current = events
        events.removeAll(keepingCapacity: true)
        return current
    }
}
