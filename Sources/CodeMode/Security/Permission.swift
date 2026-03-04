import Foundation

public enum PermissionKind: String, Sendable, Codable, CaseIterable {
    case locationWhenInUse = "location.whenInUse"
    case contacts = "contacts"
    case calendar = "calendar"
    case calendarWriteOnly = "calendar.writeOnly"
    case reminders = "reminders"
    case photoLibrary = "photoLibrary"
    case notifications = "notifications"
    case homeKit = "homeKit"
}

public enum PermissionStatus: String, Sendable, Codable, Equatable {
    case granted
    case writeOnly
    case denied
    case restricted
    case notDetermined
    case unavailable
}

public protocol PermissionBroker: Sendable {
    func status(for permission: PermissionKind) -> PermissionStatus
    func request(for permission: PermissionKind) -> PermissionStatus
}

public struct NoopPermissionBroker: PermissionBroker {
    public init() {}

    public func status(for permission: PermissionKind) -> PermissionStatus {
        .unavailable
    }

    public func request(for permission: PermissionKind) -> PermissionStatus {
        .unavailable
    }
}
