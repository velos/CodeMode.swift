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
        let calendars = try resolveCalendars(
            from: arguments,
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

    public func writeEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let operation = try eventOperation(arguments)
        let permission: PermissionKind = operation == .update ? .calendar : .calendarWriteOnly
        let status = resolvePermission(permission, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(permission)
        }

        #if canImport(EventKit)
        switch operation {
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

    public func deleteEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.calendar, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.calendar)
        }

        #if canImport(EventKit)
        guard let identifier = arguments.string("identifier"), identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.delete requires identifier")
        }
        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw BridgeError.invalidArguments("calendar.delete could not find event identifier \(identifier)")
        }
        let span = try eventSpan(arguments.string("span"))

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

    public func readReminders(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.reminders, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.reminders)
        }

        #if canImport(EventKit)
        let store = EKEventStore()
        let semaphore = DispatchSemaphore(value: 0)
        var result: [JSONValue] = []
        let includeCompleted = arguments.bool("includeCompleted") ?? false
        let start = isoDate(arguments.string("start"))
        let end = isoDate(arguments.string("end"))
        let limit = max(1, arguments.int("limit") ?? 50)
        let calendars = try resolveCalendars(
            from: arguments,
            in: store,
            entityType: .reminder,
            capability: "reminders.read"
        )

        let predicate = includeCompleted
            ? store.predicateForReminders(in: calendars)
            : store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: calendars)
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
            result = filtered.map { Self.reminderJSON($0) }
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
        switch try reminderOperation(arguments) {
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

    public func deleteReminder(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let status = resolvePermission(.reminders, context: context)
        guard status == .granted else {
            throw BridgeError.permissionDenied(.reminders)
        }

        #if canImport(EventKit)
        guard let identifier = arguments.string("identifier"), identifier.isEmpty == false else {
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

    private func resolvePermission(_ permission: PermissionKind, context: BridgeInvocationContext) -> PermissionStatus {
        context.resolvedPermission(for: permission)
    }

    private func isoDate(_ text: String?) -> Date? {
        guard let text, text.isEmpty == false else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func eventOperation(_ arguments: [String: JSONValue]) throws -> CalendarWriteOperation {
        if let text = arguments.string("operation") {
            guard let operation = CalendarWriteOperation.codeModeValue(matching: text) else {
                throw BridgeError.invalidArguments("calendar.write operation must be one of \(CalendarWriteOperation.codeModeAllowedValues.joined(separator: ", "))")
            }
            return operation
        }
        return arguments.string("identifier") == nil ? .create : .update
    }

    private func reminderOperation(_ arguments: [String: JSONValue]) throws -> ReminderWriteOperation {
        if let text = arguments.string("operation") {
            guard let operation = ReminderWriteOperation.codeModeValue(matching: text) else {
                throw BridgeError.invalidArguments("reminders.write operation must be one of \(ReminderWriteOperation.codeModeAllowedValues.joined(separator: ", "))")
            }
            return operation
        }
        return arguments.string("identifier") == nil ? .create : .update
    }

    #if canImport(EventKit)
    private func createEvent(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let title = arguments.string("title"), title.isEmpty == false,
              let startText = arguments.string("start"),
              let endText = arguments.string("end"),
              let start = isoDate(startText),
              let end = isoDate(endText)
        else {
            throw BridgeError.invalidArguments("calendar.write create requires title/start/end ISO8601")
        }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.notes = arguments.string("notes")
        event.location = arguments.string("location")
        event.isAllDay = arguments.bool("isAllDay") ?? false
        if let urlText = arguments.string("url"), urlText.isEmpty == false {
            guard let url = URL(string: urlText) else {
                throw BridgeError.invalidArguments("calendar.write url must be valid when provided")
            }
            event.url = url
        }
        if let calendarIdentifier = arguments.string("calendarIdentifier") {
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

    private func updateEvent(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let identifier = arguments.string("identifier"), identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.write update requires identifier")
        }

        let patchFields = ["title", "start", "end", "notes", "location", "url", "isAllDay", "calendarIdentifier"]
        guard patchFields.contains(where: { arguments.keys.contains($0) }) else {
            throw BridgeError.invalidArguments("calendar.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw BridgeError.invalidArguments("calendar.write could not find event identifier \(identifier)")
        }

        if arguments.keys.contains("title") {
            guard let title = arguments.string("title"), title.isEmpty == false else {
                throw BridgeError.invalidArguments("calendar.write title cannot be empty")
            }
            event.title = title
        }
        if arguments.keys.contains("start") {
            guard let start = isoDate(arguments.string("start")) else {
                throw BridgeError.invalidArguments("calendar.write start must be ISO8601 when provided")
            }
            event.startDate = start
        }
        if arguments.keys.contains("end") {
            guard let end = isoDate(arguments.string("end")) else {
                throw BridgeError.invalidArguments("calendar.write end must be ISO8601 when provided")
            }
            event.endDate = end
        }
        if arguments.keys.contains("notes") {
            event.notes = arguments.string("notes")
        }
        if arguments.keys.contains("location") {
            event.location = arguments.string("location")
        }
        if arguments.keys.contains("url") {
            let urlText = arguments.string("url") ?? ""
            event.url = urlText.isEmpty ? nil : URL(string: urlText)
            if urlText.isEmpty == false, event.url == nil {
                throw BridgeError.invalidArguments("calendar.write url must be valid when provided")
            }
        }
        if arguments.keys.contains("isAllDay") {
            event.isAllDay = arguments.bool("isAllDay") ?? false
        }
        if let calendarIdentifier = arguments.string("calendarIdentifier") {
            event.calendar = try calendar(
                calendarIdentifier,
                in: store,
                entityType: .event,
                capability: "calendar.write"
            )
        }

        do {
            try store.save(event, span: .thisEvent)
            return Self.eventJSON(event)
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
    }

    private func createReminder(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let title = arguments.string("title"), title.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write create requires title")
        }

        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = try reminderCalendar(from: arguments, in: store)
        reminder.title = title
        reminder.notes = arguments.string("notes")
        reminder.priority = arguments.int("priority") ?? 0

        if let dueDateText = arguments.string("dueDate"), dueDateText.isEmpty == false {
            guard let dueDate = isoDate(dueDateText) else {
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

    private func updateReminder(arguments: [String: JSONValue]) throws -> JSONValue {
        guard let identifier = arguments.string("identifier"), identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write update requires identifier")
        }

        let patchFields = ["title", "dueDate", "notes", "isCompleted", "priority", "calendarIdentifier"]
        guard patchFields.contains(where: { arguments.keys.contains($0) }) else {
            throw BridgeError.invalidArguments("reminders.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.invalidArguments("reminders.write could not find reminder identifier \(identifier)")
        }

        if arguments.keys.contains("title") {
            guard let title = arguments.string("title"), title.isEmpty == false else {
                throw BridgeError.invalidArguments("reminders.write title cannot be empty")
            }
            reminder.title = title
        }
        if arguments.keys.contains("dueDate") {
            if let dueDateText = arguments.string("dueDate"), dueDateText.isEmpty == false {
                guard let dueDate = isoDate(dueDateText) else {
                    throw BridgeError.invalidArguments("reminders.write dueDate must be ISO8601 when provided")
                }
                reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueDate)
            } else {
                reminder.dueDateComponents = nil
            }
        }
        if arguments.keys.contains("notes") {
            reminder.notes = arguments.string("notes")
        }
        if arguments.keys.contains("isCompleted") {
            let isCompleted = arguments.bool("isCompleted") ?? false
            reminder.isCompleted = isCompleted
            reminder.completionDate = isCompleted ? (reminder.completionDate ?? Date()) : nil
        }
        if let priority = arguments.int("priority") {
            reminder.priority = priority
        }
        if arguments.keys.contains("calendarIdentifier") {
            reminder.calendar = try reminderCalendar(from: arguments, in: store)
        }

        do {
            try store.save(reminder, commit: true)
            return Self.reminderJSON(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
    }

    private func resolveCalendars(
        from arguments: [String: JSONValue],
        in store: EKEventStore,
        entityType: EKEntityType,
        capability: String
    ) throws -> [EKCalendar]? {
        var identifiers: [String] = []
        if let identifier = arguments.string("calendarIdentifier") {
            identifiers.append(identifier)
        }
        if let values = arguments.array("calendarIdentifiers") {
            for value in values {
                guard let identifier = value.stringValue else {
                    throw BridgeError.invalidArguments("\(capability) calendarIdentifiers must contain strings")
                }
                identifiers.append(identifier)
            }
        }

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

    private func reminderCalendar(from arguments: [String: JSONValue], in store: EKEventStore) throws -> EKCalendar {
        if let calendarIdentifier = arguments.string("calendarIdentifier") {
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

    private func eventSpan(_ text: String?) throws -> EKSpan {
        guard let text, text.isEmpty == false else {
            return .thisEvent
        }
        guard let span = CalendarEventSpan.codeModeValue(matching: text) else {
            throw BridgeError.invalidArguments("calendar.delete span must be one of \(CalendarEventSpan.codeModeAllowedValues.joined(separator: ", "))")
        }
        return span.ekSpan
    }

    private static func eventJSON(_ event: EKEvent) -> JSONValue {
        .object([
            "identifier": .string(event.eventIdentifier ?? ""),
            "title": .string(event.title ?? ""),
            "startDate": .string(event.startDate.ISO8601Format()),
            "endDate": .string(event.endDate.ISO8601Format()),
            "notes": .string(event.notes ?? ""),
            "calendarIdentifier": .string(event.calendar.calendarIdentifier),
            "calendarTitle": .string(event.calendar.title),
            "location": .string(event.location ?? ""),
            "url": .string(event.url?.absoluteString ?? ""),
            "isAllDay": .bool(event.isAllDay),
        ])
    }

    private static func reminderJSON(_ reminder: EKReminder) -> JSONValue {
        var object: [String: JSONValue] = [
            "identifier": .string(reminder.calendarItemIdentifier),
            "title": .string(reminder.title),
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
