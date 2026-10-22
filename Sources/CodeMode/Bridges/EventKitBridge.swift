import Foundation
#if canImport(EventKit)
import EventKit
#endif

/// Shared EventKit lookup and patching helpers.
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

    #endif
}

/// EventKit's existing JSON contract: absent strings remain empty strings.
@ToolResult
struct CalendarEvent: Sendable {
    var identifier: String
    var title: String
    @ToolField("ISO 8601 timestamp")
    var startDate: Date
    @ToolField("ISO 8601 timestamp")
    var endDate: Date
    var notes: String
    @ToolField(#"Empty ("") when the event has no calendar"#)
    var calendarIdentifier: String
    @ToolField(#"Empty ("") when the event has no calendar"#)
    var calendarTitle: String
    var location: String
    @ToolField(#"Absolute URL, or "" when none"#)
    var url: String
    var isAllDay: Bool
}

@ToolResult
struct Reminder: Sendable {
    var identifier: String
    var title: String
    var isCompleted: Bool
    // These stay strings because an absent date has historically encoded as "".
    @ToolField(#"ISO 8601 timestamp, or "" when none"#)
    var dueDate: String
    @ToolField(#"ISO 8601 timestamp, or "" when none"#)
    var completionDate: String
    var notes: String
    var priority: Int
    @ToolField(#"Empty ("") when the reminder has no calendar"#)
    var calendarIdentifier: String
    @ToolField(#"Empty ("") when the reminder has no calendar"#)
    var calendarTitle: String
}

@ToolResult
struct EventKitDeletion: Sendable {
    var identifier: String
    var deleted: Bool
}

#if canImport(EventKit)
extension CalendarEvent {
    init(_ event: EKEvent) {
        identifier = event.eventIdentifier ?? ""
        title = event.title ?? ""
        startDate = event.startDate
        endDate = event.endDate
        notes = event.notes ?? ""
        // An orphaned event has no calendar (EKCalendar!).
        calendarIdentifier = event.calendar?.calendarIdentifier ?? ""
        calendarTitle = event.calendar?.title ?? ""
        location = event.location ?? ""
        url = event.url?.absoluteString ?? ""
        isAllDay = event.isAllDay
    }
}

extension Reminder {
    init(_ reminder: EKReminder) {
        identifier = reminder.calendarItemIdentifier
        title = reminder.title ?? ""
        isCompleted = reminder.isCompleted
        dueDate = reminder.dueDateComponents?.date?.ISO8601Format() ?? ""
        completionDate = reminder.completionDate?.ISO8601Format() ?? ""
        notes = reminder.notes ?? ""
        priority = reminder.priority
        calendarIdentifier = reminder.calendar?.calendarIdentifier ?? ""
        calendarTitle = reminder.calendar?.title ?? ""
    }
}
#endif
