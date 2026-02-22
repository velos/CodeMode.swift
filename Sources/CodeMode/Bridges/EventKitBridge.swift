import Foundation

#if canImport(EventKit)
import EventKit
#endif

public final class EventKitBridge: @unchecked Sendable {
    public init() {}

    public func readEvents(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.calendar, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.calendar)
        }

        #if canImport(EventKit)
        let store = EKEventStore()
        let start = isoDate(arguments.string("start")) ?? Date()
        let end = isoDate(arguments.string("end")) ?? Calendar.current.date(byAdding: .day, value: 14, to: start) ?? start
        let limit = arguments.int("limit") ?? 50

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).prefix(max(1, limit)).map { event in
            JSONValue.object([
                "identifier": .string(event.eventIdentifier ?? ""),
                "title": .string(event.title ?? ""),
                "startDate": .string(event.startDate.ISO8601Format()),
                "endDate": .string(event.endDate.ISO8601Format()),
                "notes": .string(event.notes ?? ""),
                "calendarTitle": .string(event.calendar.title),
            ])
        }

        return .array(Array(events))
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    public func writeEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.calendarWriteOnly, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.calendarWriteOnly)
        }

        #if canImport(EventKit)
        guard let title = arguments.string("title"), let startText = arguments.string("start"), let endText = arguments.string("end"), let start = isoDate(startText), let end = isoDate(endText) else {
            throw BridgeError.invalidArguments("calendar.write requires title/start/end ISO8601")
        }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = arguments.string("notes")
        event.calendar = store.defaultCalendarForNewEvents

        do {
            try store.save(event, span: .thisEvent)
            return .object([
                "identifier": .string(event.eventIdentifier ?? ""),
                "title": .string(title),
            ])
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    public func readReminders(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.reminders, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.reminders)
        }

        #if canImport(EventKit)
        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)
        var result: [JSONValue] = []

        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        store.fetchReminders(matching: predicate) { reminders in
            result = (reminders ?? []).prefix(max(1, arguments.int("limit") ?? 50)).map { reminder in
                .object([
                    "identifier": .string(reminder.calendarItemIdentifier),
                    "title": .string(reminder.title),
                    "isCompleted": .bool(reminder.isCompleted),
                    "dueDate": .string(reminder.dueDateComponents?.date?.ISO8601Format() ?? ""),
                ])
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 15)
        return .array(result)
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    public func writeReminder(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.reminders, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.reminders)
        }

        #if canImport(EventKit)
        guard let title = arguments.string("title") else {
            throw BridgeError.invalidArguments("reminders.write requires title")
        }

        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = store.defaultCalendarForNewReminders()
        reminder.title = title

        if let dueDateText = arguments.string("dueDate"), let dueDate = isoDate(dueDateText) {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueDate)
        }

        do {
            try store.save(reminder, commit: true)
            return .object([
                "identifier": .string(reminder.calendarItemIdentifier),
                "title": .string(title),
            ])
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    private func resolvePermission(_ permission: PermissionKind, context: BridgeInvocationContext) -> PermissionStatus {
        let status = context.permissionBroker.status(for: permission)
        context.recordPermission(permission, status: status)

        if status == .notDetermined {
            let requested = context.permissionBroker.request(for: permission)
            context.recordPermission(permission, status: requested)
            return requested
        }

        return status
    }

    private func isoDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }
}
