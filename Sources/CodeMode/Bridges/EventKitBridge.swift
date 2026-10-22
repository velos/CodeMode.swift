import Foundation

#if canImport(EventKit)
import EventKit
#endif

public final class EventKitBridge: @unchecked Sendable {
    static let reminderFetchTimeoutSeconds: TimeInterval = 15

    public init() {}

    func readEvents(arguments: CalendarListEventsTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        let store = EKEventStore()
        let start = arguments.start ?? Date()
        let end = arguments.end
            ?? Calendar.current.date(byAdding: .day, value: 14, to: start)
            ?? start
        let limit = arguments.limit
        let calendars = try resolveCalendars(
            identifier: arguments.calendarIdentifier,
            identifiers: arguments.calendarIdentifiers,
            in: store,
            entityType: .event,
            capability: "calendar.read"
        )

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate).prefix(max(1, limit)).map { event in
            Self.eventJSON(event)
        }

        return .array(Array(events))
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    func writeEvent(arguments: CalendarWriteEventTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        switch arguments.resolvedOperation {
        case .create:
            return try createEvent(arguments: arguments)
        case .update:
            return try updateEvent(arguments: arguments)
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    func deleteEvent(arguments: CalendarDeleteEventTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        let identifier = arguments.identifier
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.delete requires identifier")
        }
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw BridgeError.invalidArguments("calendar.delete could not find event identifier \(identifier)")
        }
        let span = arguments.span.ekSpan

        do {
            try store.remove(event, span: span)
            return .object([
                "identifier": .string(identifier),
                "deleted": .bool(true),
            ])
        } catch {
            throw BridgeError.nativeFailure("calendar.delete failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    func readReminders(arguments: RemindersListTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        let store = EKEventStore()
        let includeCompleted = arguments.includeCompleted
        let start = arguments.start
        let end = arguments.end
        let limit = max(1, arguments.limit)
        let calendars = try resolveCalendars(
            identifier: arguments.calendarIdentifier,
            identifiers: arguments.calendarIdentifiers,
            in: store,
            entityType: .reminder,
            capability: "reminders.read"
        )

        let predicate = includeCompleted
            ? store.predicateForReminders(in: calendars)
            : store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: calendars)
        // Previously a `var` written from EventKit's completion queue, read after
        // a semaphore wait whose timeout result was discarded — a data race with
        // the late callback, and an empty array on timeout that the script could
        // not tell apart from "no reminders".
        let result = try CompletionWait.value(
            timeout: Self.reminderFetchTimeoutSeconds,
            operationName: "reminders.read"
        ) { complete in
            store.fetchReminders(matching: predicate) { reminders in
                let filtered = (reminders ?? [])
                    .filter { reminder in
                        guard includeCompleted else { return true }
                        guard let dueDate = reminder.dueDateComponents?.date else {
                            return start == nil && end == nil
                        }
                        if let start, dueDate < start { return false }
                        if let end, dueDate > end { return false }
                        return true
                    }
                    .prefix(limit)
                complete(filtered.map { Self.reminderJSON($0) })
            }
        }

        return .array(result)
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    func writeReminder(arguments: RemindersWriteTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        switch arguments.resolvedOperation {
        case .create:
            return try createReminder(arguments: arguments)
        case .update, .complete:
            return try updateReminder(arguments: arguments)
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    func deleteReminder(arguments: RemindersDeleteTool.Arguments) throws -> JSONValue {
        #if canImport(EventKit)
        let identifier = arguments.identifier
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.delete requires identifier")
        }
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.invalidArguments("reminders.delete could not find reminder identifier \(identifier)")
        }

        do {
            try store.remove(reminder, commit: true)
            return .object([
                "identifier": .string(identifier),
                "deleted": .bool(true),
            ])
        } catch {
            throw BridgeError.nativeFailure("reminders.delete failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }

    #if canImport(EventKit)
    private func createEvent(arguments: CalendarWriteEventTool.Arguments) throws -> JSONValue {
        guard let title = arguments.title, title.isEmpty == false,
              let startText = arguments.start,
              let endText = arguments.end,
              let start = CodeModeDate.parse(startText),
              let end = CodeModeDate.parse(endText)
        else {
            throw BridgeError.invalidArguments("calendar.write create requires title/start/end ISO8601")
        }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = arguments.notes
        event.location = arguments.location
        event.isAllDay = arguments.isAllDay ?? false
        if let urlText = arguments.url, urlText.isEmpty == false {
            guard let url = URL(string: urlText) else {
                throw BridgeError.invalidArguments("calendar.write url must be valid when provided")
            }
            event.url = url
        }
        if let calendarIdentifier = arguments.calendarIdentifier {
            event.calendar = try calendar(
                calendarIdentifier,
                in: store,
                entityType: .event,
                capability: "calendar.write"
            )
        } else {
            event.calendar = store.defaultCalendarForNewEvents
        }

        do {
            try store.save(event, span: .thisEvent)
            return Self.eventJSON(event)
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
    }

    private func updateEvent(arguments: CalendarWriteEventTool.Arguments) throws -> JSONValue {
        guard let identifier = arguments.identifier, identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.write update requires identifier")
        }

        let patchFields = ["title", "start", "end", "notes", "location", "url", "isAllDay", "calendarIdentifier"]
        guard patchFields.contains(where: { arguments.providedArguments.contains($0) }) else {
            throw BridgeError.invalidArguments("calendar.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw BridgeError.invalidArguments("calendar.write could not find event identifier \(identifier)")
        }

        try applyEventPatch(arguments: arguments, to: event, in: store)

        do {
            try store.save(event, span: .thisEvent)
            return Self.eventJSON(event)
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
    }

    private func createReminder(arguments: RemindersWriteTool.Arguments) throws -> JSONValue {
        guard let title = arguments.title, title.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write create requires title")
        }

        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = try reminderCalendar(identifier: arguments.calendarIdentifier, in: store)
        reminder.title = title
        reminder.notes = arguments.notes
        reminder.priority = arguments.priority ?? 0

        if let dueDateText = arguments.dueDate, dueDateText.isEmpty == false {
            guard let dueDate = CodeModeDate.parse(dueDateText) else {
                throw BridgeError.invalidArguments("reminders.write dueDate must be ISO8601 when provided")
            }
            reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueDate)
        }

        do {
            try store.save(reminder, commit: true)
            return Self.reminderJSON(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
    }

    private func updateReminder(arguments: RemindersWriteTool.Arguments) throws -> JSONValue {
        guard let identifier = arguments.identifier, identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write update requires identifier")
        }

        let patchFields = ["title", "dueDate", "notes", "isCompleted", "priority", "calendarIdentifier"]
        guard patchFields.contains(where: { arguments.providedArguments.contains($0) }) else {
            throw BridgeError.invalidArguments("reminders.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.invalidArguments("reminders.write could not find reminder identifier \(identifier)")
        }

        try applyReminderPatch(arguments: arguments, to: reminder, in: store)

        do {
            try store.save(reminder, commit: true)
            return Self.reminderJSON(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
    }

    /// Applies decoded patch values independently of item lookup and persistence.
    func applyEventPatch(arguments: CalendarWriteEventTool.Arguments, to event: EKEvent, in store: EKEventStore) throws {
        if arguments.providedArguments.contains("title") {
            guard let title = arguments.title, title.isEmpty == false else {
                throw BridgeError.invalidArguments("calendar.write title cannot be empty")
            }
            event.title = title
        }
        if arguments.providedArguments.contains("start") {
            guard let start = CodeModeDate.parse(arguments.start) else {
                throw BridgeError.invalidArguments("calendar.write start must be ISO8601 when provided")
            }
            event.startDate = start
        }
        if arguments.providedArguments.contains("end") {
            guard let end = CodeModeDate.parse(arguments.end) else {
                throw BridgeError.invalidArguments("calendar.write end must be ISO8601 when provided")
            }
            event.endDate = end
        }
        if arguments.providedArguments.contains("notes") {
            event.notes = arguments.notes
        }
        if arguments.providedArguments.contains("location") {
            event.location = arguments.location
        }
        if arguments.providedArguments.contains("url") {
            let urlText = arguments.url ?? ""
            event.url = urlText.isEmpty ? nil : URL(string: urlText)
            if urlText.isEmpty == false, event.url == nil {
                throw BridgeError.invalidArguments("calendar.write url must be valid when provided")
            }
        }
        if arguments.providedArguments.contains("isAllDay") {
            event.isAllDay = arguments.isAllDay ?? false
        }
        if let calendarIdentifier = arguments.calendarIdentifier {
            event.calendar = try calendar(
                calendarIdentifier,
                in: store,
                entityType: .event,
                capability: "calendar.write"
            )
        }
    }

    /// Applies decoded patch values independently of item lookup and persistence.
    func applyReminderPatch(arguments: RemindersWriteTool.Arguments, to reminder: EKReminder, in store: EKEventStore) throws {
        if arguments.providedArguments.contains("title") {
            guard let title = arguments.title, title.isEmpty == false else {
                throw BridgeError.invalidArguments("reminders.write title cannot be empty")
            }
            reminder.title = title
        }
        if arguments.providedArguments.contains("dueDate") {
            if let dueDateText = arguments.dueDate, dueDateText.isEmpty == false {
                guard let dueDate = CodeModeDate.parse(dueDateText) else {
                    throw BridgeError.invalidArguments("reminders.write dueDate must be ISO8601 when provided")
                }
                reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueDate)
            } else {
                reminder.dueDateComponents = nil
            }
        }
        if arguments.providedArguments.contains("notes") {
            reminder.notes = arguments.notes
        }
        if arguments.providedArguments.contains("isCompleted") {
            let isCompleted = arguments.isCompleted ?? false
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? (reminder.completionDate ?? Date()) : nil
        }
        if let priority = arguments.priority {
            reminder.priority = priority
        }
        if arguments.providedArguments.contains("calendarIdentifier") {
            reminder.calendar = try reminderCalendar(identifier: arguments.calendarIdentifier, in: store)
        }
    }

    private func resolveCalendars(
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

    private func calendar(
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

    private func reminderCalendar(identifier: String?, in store: EKEventStore) throws -> EKCalendar {
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

    /// Test seam: these serializers are the only EventKit logic reachable
    /// without a live, permission-granted store, and they are where the
    /// implicitly-unwrapped `calendar`/`title` crashes lived.
    static func eventJSONForTesting(_ event: EKEvent) -> JSONValue {
        eventJSON(event)
    }

    static func reminderJSONForTesting(_ reminder: EKReminder) -> JSONValue {
        reminderJSON(reminder)
    }

    private static func eventJSON(_ event: EKEvent) -> JSONValue {
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

    private static func reminderJSON(_ reminder: EKReminder) -> JSONValue {
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
