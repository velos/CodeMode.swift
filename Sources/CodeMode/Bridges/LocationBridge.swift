import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

public final class LocationBridge: @unchecked Sendable {
    public init() {}

    public func read(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let mode = arguments.string("mode") ?? "current"

        switch mode {
        case "permissionStatus":
            let status = context.permissionBroker.status(for: .locationWhenInUse)
            context.recordPermission(.locationWhenInUse, status: status)
            return .string(status.rawValue)
        case "current":
            let status = resolvedPermission(for: .locationWhenInUse, context: context)
            guard status == .granted else {
                throw BridgeError.permissionDenied(.locationWhenInUse)
            }

            #if canImport(CoreLocation)
            let manager = CLLocationManager()
            if let current = manager.location {
                return .object([
                    "latitude": .number(current.coordinate.latitude),
                    "longitude": .number(current.coordinate.longitude),
                    "altitude": .number(current.altitude),
                    "horizontalAccuracy": .number(current.horizontalAccuracy),
                    "timestamp": .string(current.timestamp.ISO8601Format()),
                ])
            }
            throw BridgeError.nativeFailure("No location available yet")
            #else
            throw BridgeError.unsupportedPlatform("CoreLocation")
            #endif
        default:
            throw BridgeError.invalidArguments("Unknown location.read mode: \(mode)")
        }
    }

    public func requestPermission(context: BridgeInvocationContext) -> JSONValue {
        let status = context.permissionBroker.request(for: .locationWhenInUse)
        context.recordPermission(.locationWhenInUse, status: status)
        return .string(status.rawValue)
    }

    private func resolvedPermission(for permission: PermissionKind, context: BridgeInvocationContext) -> PermissionStatus {
        let status = context.permissionBroker.status(for: permission)
        context.recordPermission(permission, status: status)
        if status == .notDetermined {
            let requested = context.permissionBroker.request(for: permission)
            context.recordPermission(permission, status: requested)
            return requested
        }
        return status
    }
}
