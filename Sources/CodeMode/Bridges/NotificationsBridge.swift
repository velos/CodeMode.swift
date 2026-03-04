import Foundation

#if canImport(UserNotifications)
import UserNotifications
#endif

public final class NotificationsBridge: @unchecked Sendable {
    public init() {}

    public func requestPermission(context: BridgeInvocationContext) throws -> JSONValue {
        let requested = context.permissionBroker.request(for: .notifications)
        context.recordPermission(.notifications, status: requested)
        return .object([
            "status": .string(requested.rawValue),
            "granted": .bool(requested == .granted),
        ])
    }

    public func schedule(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard let title = arguments.string("title"), title.isEmpty == false else {
            throw BridgeError.invalidArguments("notifications.schedule requires title")
        }

        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.notifications)
        }

        #if canImport(UserNotifications)
        let identifier = arguments.string("identifier") ?? "codemode.\(UUID().uuidString)"
        let subtitle = arguments.string("subtitle") ?? ""
        let body = arguments.string("body") ?? ""
        let repeats = arguments.bool("repeats") ?? false

        let content = UNMutableNotificationContent()
        content.title = title
        content.subtitle = subtitle
        content.body = body
        content.sound = .default

        let trigger: UNNotificationTrigger
        if let fireDateText = arguments.string("fireDate"), let fireDate = isoDate(fireDateText) {
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: fireDate
            )
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        } else {
            let seconds = arguments.double("secondsFromNow") ?? 5
            let timeInterval = max(1, seconds)
            if repeats, timeInterval < 60 {
                throw BridgeError.invalidArguments("notifications.schedule requires secondsFromNow >= 60 when repeats=true")
            }
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: timeInterval, repeats: repeats)
        }

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        let semaphore = DispatchSemaphore(value: 0)
        let addError = LockedBox<Error?>(nil)
        UNUserNotificationCenter.current().add(request) { error in
            addError.set(error)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw BridgeError.timeout(milliseconds: 10_000)
        }

        if let addError = addError.get() {
            throw BridgeError.nativeFailure("notifications.schedule failed: \(addError.localizedDescription)")
        }

        return .object([
            "identifier": .string(identifier),
            "scheduled": .bool(true),
            "repeats": .bool(repeats),
        ])
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("UserNotifications")
        #endif
    }

    public func readPending(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.notifications)
        }

        #if canImport(UserNotifications)
        let limit = max(1, arguments.int("limit") ?? 50)
        let semaphore = DispatchSemaphore(value: 0)
        let payload = LockedBox<[JSONValue]>([])

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let entries: [JSONValue] = requests.prefix(limit).map { request in
                JSONValue.object([
                    "identifier": .string(request.identifier),
                    "title": .string(request.content.title),
                    "subtitle": .string(request.content.subtitle),
                    "body": .string(request.content.body),
                    "triggerType": .string(Self.triggerType(request.trigger)),
                    "repeats": .bool(Self.triggerRepeats(request.trigger)),
                ])
            }
            payload.set(entries)
            semaphore.signal()
        }

        if semaphore.wait(timeout: .now() + 10) == .timedOut {
            throw BridgeError.timeout(milliseconds: 10_000)
        }

        return .array(payload.get())
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("UserNotifications")
        #endif
    }

    public func deletePending(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.notifications)
        }

        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        var removedCount = 0

        if let identifier = arguments.string("identifier"), identifier.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            removedCount = 1
        } else if let identifiers = arguments.array("identifiers")?.compactMap(\.stringValue), identifiers.isEmpty == false {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            removedCount = identifiers.count
        } else {
            center.removeAllPendingNotificationRequests()
            removedCount = -1
        }

        return .object([
            "deleted": .bool(true),
            "count": .number(Double(removedCount)),
        ])
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("UserNotifications")
        #endif
    }

    private func resolvePermission(context: BridgeInvocationContext) -> PermissionStatus {
        let status = context.permissionBroker.status(for: .notifications)
        context.recordPermission(.notifications, status: status)
        if status == .notDetermined {
            let requested = context.permissionBroker.request(for: .notifications)
            context.recordPermission(.notifications, status: requested)
            return requested
        }

        return status
    }

    private func isoDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    #if canImport(UserNotifications)
    private static func triggerType(_ trigger: UNNotificationTrigger?) -> String {
        switch trigger {
        case is UNCalendarNotificationTrigger:
            return "calendar"
        case is UNTimeIntervalNotificationTrigger:
            return "timeInterval"
        case nil:
            return "none"
        default:
            return "other"
        }
    }

    private static func triggerRepeats(_ trigger: UNNotificationTrigger?) -> Bool {
        switch trigger {
        case let value as UNCalendarNotificationTrigger:
            return value.repeats
        case let value as UNTimeIntervalNotificationTrigger:
            return value.repeats
        default:
            return false
        }
    }
    #endif
}
