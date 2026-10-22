import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// Shared EventKit lookup, patching, and serialization helpers.
enum EventKitBridge {
    static let reminderFetchTimeoutSeconds: TimeInterval = 15

    #if canImport(EventKit)
    static func applyCompletion(_ patch: Patch<Bool>, to reminder: EKReminder) {
        patch.apply { isCompleted in
            reminder.isCompleted = isCompleted ?? false
            reminder.completionDate = reminder.isCompleted ? (reminder.completionDate ?? Date()) : nil
        }
    }

    static func resolveCalendars(
        identifier: String?,
        identifiers: [String]?,
        in store: EKEventStore,
        entityType: EKEntityType,
        capability: String
    ) throws -> [EKCalendar]? {
        let identifiers = (identifier.map { [$0] } ?? []) + (identifiers ?? [])

        guard identifiers.isEmpty == false else {
            return nil
        }

        let calendars = store.calendars(for: entityType)
        let uniqueIdentifiers = Set(identifiers)
        let matches = calendars.filter { uniqueIdentifiers.contains($0.calendarIdentifier) }
        let matchedIdentifiers = Set(matches.map(\.calendarIdentifier))
        let missing = uniqueIdentifiers.subtracting(matchedIdentifiers)
        if missing.isEmpty == false {
            throw BridgeError.invalidArguments("\(capability) could not find calendarIdentifier \(missing.sorted().joined(separator: ", "))")
        }
        return matches
    }

    static func calendar(
        _ identifier: String,
        in store: EKEventStore,
        entityType: EKEntityType,
        capability: String
    ) throws -> EKCalendar {
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("\(capability) calendarIdentifier cannot be empty")
        }
        guard let calendar = store.calendars(for: entityType).first(where: { $0.calendarIdentifier == identifier }) else {
            throw BridgeError.invalidArguments("\(capability) could not find calendarIdentifier \(identifier)")
        }
        return calendar
    }

    static func reminderCalendar(identifier: String?, in store: EKEventStore) throws -> EKCalendar {
        if let calendarIdentifier = identifier {
            return try calendar(
                calendarIdentifier,
                in: store,
                entityType: .reminder,
                capability: "reminders.write"
            )
        }
        guard let calendar = store.defaultCalendarForNewReminders() else {
            throw BridgeError.nativeFailure("reminders.write could not resolve a default reminders calendar")
        }
        return calendar
    }

    static func eventJSON(_ event: EKEvent) -> JSONValue {
        .object([
            "identifier": .string(event.eventIdentifier ?? ""),
            "title": .string(event.title ?? ""),
            "startDate": .string(event.startDate.ISO8601Format()),
            "endDate": .string(event.endDate.ISO8601Format()),
            "notes": .string(event.notes ?? ""),
            // `EKEvent.calendar` is `EKCalendar!` and is nil for an orphaned
            // event — every neighboring field here is nil-coalesced, and this one
            // crashed the execution thread.
            "calendarIdentifier": .string(event.calendar?.calendarIdentifier ?? ""),
            "calendarTitle": .string(event.calendar?.title ?? ""),
            "location": .string(event.location ?? ""),
            "url": .string(event.url?.absoluteString ?? ""),
            "isAllDay": .bool(event.isAllDay),
        ])
    }

    static func reminderJSON(_ reminder: EKReminder) -> JSONValue {
        var object: [String: JSONValue] = [
            "identifier": .string(reminder.calendarItemIdentifier),
            // `EKReminder.title` is `String!`.
            "title": .string(reminder.title ?? ""),
            "isCompleted": .bool(reminder.isCompleted),
            "dueDate": .string(reminder.dueDateComponents?.date?.ISO8601Format() ?? ""),
            "completionDate": .string(reminder.completionDate?.ISO8601Format() ?? ""),
            "notes": .string(reminder.notes ?? ""),
            "priority": .number(Double(reminder.priority)),
        ]
        if let calendar = reminder.calendar {
            object["calendarIdentifier"] = .string(calendar.calendarIdentifier)
            object["calendarTitle"] = .string(calendar.title)
        } else {
            object["calendarIdentifier"] = .string("")
            object["calendarTitle"] = .string("")
        }
        return .object(object)
    }
    #endif
}
