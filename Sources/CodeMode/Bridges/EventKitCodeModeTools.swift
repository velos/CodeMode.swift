import Foundation
#if canImport(EventKit)
import EventKit
#endif

// MARK: - Constrained argument values
//
// These enums are the single source of truth for their arguments: the catalog
// advertises `codeModeAllowedValues`, tool decode and the bridges parse through
// `codeModeValue(matching:)`, so advertised and accepted spellings cannot drift.

enum CalendarEventSpan: String, CodeModeStringEnum {
    case thisEvent
    case futureEvents

    static let codeModeAliases: [String: Self] = [
        "this_event": .thisEvent,
        "this": .thisEvent,
        "future_events": .futureEvents,
        "future": .futureEvents,
    ]

    #if canImport(EventKit)
    var ekSpan: EKSpan {
        switch self {
        case .thisEvent:
            return .thisEvent
        case .futureEvents:
            return .futureEvents
        }
    }
    #endif
}

enum CalendarPickerSelectionStyle: String, CodeModeStringEnum {
    case single
    case multiple
}

enum CalendarPickerDisplayStyle: String, CodeModeStringEnum {
    case writable
    case all
}

// MARK: - Calendar tools

@BuiltInCodeMode(.calendarRead, path: "apple.calendar.listEvents")
struct CalendarListEventsTool: BuiltInCodeModeTool {
    static let codeModeSummary = "List events in a date range from EventKit."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]

    struct Arguments: Sendable {
        @ToolParam("Range start; uses now when omitted.")
        var start: Date?
        @ToolParam("Range end; uses start + 14 days when omitted.")
        var end: Date?
        @ToolParam("Max number of items.")
        var limit: Int = 50
        @ToolParam("EventKit calendarIdentifier to restrict results.")
        var calendarIdentifier: String?
        @ToolParam("EventKit calendarIdentifier strings to restrict results.")
        var calendarIdentifiers: [String]?
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> [CalendarEvent] {
        #if canImport(EventKit)
        let store = EKEventStore()
        let start = arguments.start ?? Date()
        let end = arguments.end
            ?? Calendar.current.date(byAdding: .day, value: 14, to: start)
            ?? start
        let limit = arguments.limit
        let calendars = try EventKitBridge.resolveCalendars(
            identifier: arguments.calendarIdentifier,
            identifiers: arguments.calendarIdentifiers,
            in: store,
            entityType: .event,
            capability: "calendar.read"
        )

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        let events = store.events(matching: predicate).prefix(max(1, limit)).map { event in
            CalendarEvent(event)
        }

        return events
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.calendarWrite, path: "apple.calendar.createEvent")
struct CalendarCreateEventTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Create a calendar event."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]

    struct Arguments: Sendable {
        @ToolParam("Event title.")
        var title: String
        @ToolParam("Event start.")
        var start: Date
        @ToolParam("Event end.")
        var end: Date
        @ToolParam("Notes/body text.")
        var notes: String?
        @ToolParam("Event location.")
        var location: String?
        @ToolParam("Absolute URL attached to the event.")
        var url: String?
        @ToolParam("Whether the event is all-day.")
        var isAllDay: Bool?
        @ToolParam("Destination EventKit calendarIdentifier.")
        var calendarIdentifier: String?
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> CalendarEvent {
        #if canImport(EventKit)
        guard arguments.title.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.write title cannot be empty")
        }

        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = arguments.title
        event.startDate = arguments.start
        event.endDate = arguments.end
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
            event.calendar = try EventKitBridge.calendar(
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
            return CalendarEvent(event)
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
        #else
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.calendarWrite, path: "apple.calendar.updateEvent")
struct CalendarUpdateEventTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Patch an existing event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.updateEvent({ identifier: 'EVENT_ID', notes: null })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]

    struct Arguments: Sendable {
        @ToolParam("EventKit eventIdentifier to update.")
        var identifier: String
        @ToolParam("Event title.")
        var title: String?
        @ToolParam("Event start.")
        var start: Date?
        @ToolParam("Event end.")
        var end: Date?
        @ToolParam("Notes/body text.")
        var notes: Patch<String>
        @ToolParam("Event location.")
        var location: Patch<String>
        @ToolParam("Absolute URL attached to the event.")
        var url: Patch<String>
        @ToolParam("Whether the event is all-day.")
        var isAllDay: Patch<Bool>
        @ToolParam("Destination EventKit calendarIdentifier.")
        var calendarIdentifier: String?
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> CalendarEvent {
        #if canImport(EventKit)
        let identifier = arguments.identifier
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("calendar.write update requires identifier")
        }

        guard Self.hasChanges(arguments) else {
            throw BridgeError.invalidArguments("calendar.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let event = store.event(withIdentifier: identifier) else {
            throw BridgeError.invalidArguments("calendar.write could not find event identifier \(identifier)")
        }

        try arguments.apply(to: event, in: store)

        do {
            try store.save(event, span: .thisEvent)
            return CalendarEvent(event)
        } catch {
            throw BridgeError.nativeFailure("calendar.write failed: \(error.localizedDescription)")
        }
        #else
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

extension CalendarUpdateEventTool.Arguments {
    #if canImport(EventKit)
    func apply(to event: EKEvent, in store: EKEventStore) throws {
        if let title {
            guard !title.isEmpty else { throw BridgeError.invalidArguments("calendar.write title cannot be empty") }
            event.title = title
        }
        if let start { event.startDate = start }
        if let end { event.endDate = end }
        notes.apply { event.notes = $0 }
        location.apply { event.location = $0 }
        try url.apply { text in
            let text = text ?? ""
            let parsedURL = text.isEmpty ? nil : URL(string: text)
            guard text.isEmpty || parsedURL != nil else {
                throw BridgeError.invalidArguments("calendar.write url must be valid when provided")
            }
            event.url = parsedURL
        }
        isAllDay.apply { event.isAllDay = $0 ?? false }
        if let calendarIdentifier {
            event.calendar = try EventKitBridge.calendar(calendarIdentifier, in: store, entityType: .event, capability: "calendar.write")
        }
    }
    #endif
}

@BuiltInCodeMode(.calendarDelete, path: "apple.calendar.deleteEvent")
struct CalendarDeleteEventTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Delete an existing EventKit event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule", "delete"]
    static let codeModeExample = "await apple.calendar.deleteEvent({ identifier: 'EVENT_ID', span: 'thisEvent' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]

    struct Arguments: Sendable {
        @ToolParam("EventKit eventIdentifier from apple.calendar.listEvents.")
        var identifier: String
        @ToolParam("Scope for recurring events.")
        var span: CalendarEventSpan = .thisEvent
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> EventKitDeletion {
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
            return EventKitDeletion(identifier: identifier, deleted: true)
        } catch {
            throw BridgeError.nativeFailure("calendar.delete failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.calendarUIPickCalendar, path: "apple.calendar.pickCalendar")
struct CalendarPickCalendarTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Present EventKit calendar chooser UI and return the user-selected writable calendars."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.pickCalendar({ selectionStyle: 'single' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeResultSummary = "Array of selected calendars with identifier/title/type/allowsContentModifications."

    struct Arguments: Sendable {
        @ToolParam("Calendar selection style; uses single when omitted.")
        var selectionStyle: CalendarPickerSelectionStyle?
        @ToolParam("Calendars to display; uses writable when omitted.")
        var displayStyle: CalendarPickerDisplayStyle?
        @ToolParam("Timeout in milliseconds for waiting on user selection.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.pickCalendar(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.calendarUIPresentEvent, path: "apple.calendar.presentEvent")
struct CalendarPresentEventTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Present system UI for an existing calendar event identifier."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "details"]
    static let codeModeExample = "await apple.calendar.presentEvent({ identifier: 'EVENT_ID', allowsEditing: false })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeResultSummary = "Object with action dismissed."

    struct Arguments: Sendable {
        @ToolParam("EventKit eventIdentifier from apple.calendar.listEvents.")
        var identifier: String
        @ToolParam("Whether the user can edit from the detail UI; uses false when omitted.")
        var allowsEditing: Bool?
        @ToolParam("Whether the UI may show calendar day previews; uses true when omitted.")
        var allowsCalendarPreview: Bool?
        @ToolParam("Timeout in milliseconds for waiting on dismissal.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentCalendarEvent(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.calendarUIPresentNewEvent, path: "apple.calendar.presentNewEvent")
struct CalendarPresentNewEventTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Present system UI to let the user create or edit a new calendar event draft."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.presentNewEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeResultSummary = "Object with action plus identifier/title when the user saves."

    struct Arguments: Sendable {
        @ToolParam("Event title shown in the editor.")
        var title: String?
        @ToolParam("ISO 8601 start timestamp.")
        var start: String?
        @ToolParam("ISO 8601 end timestamp.")
        var end: String?
        @ToolParam("Event notes/body text.")
        var notes: String?
        @ToolParam("Location string.")
        var location: String?
        @ToolParam("Timeout in milliseconds for waiting on user save/cancel.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentNewCalendarEvent(arguments: arguments.raw, context: context)
    }
}

// MARK: - Reminder tools

@BuiltInCodeMode(.remindersRead, path: "apple.reminders.listReminders")
struct RemindersListTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Read incomplete reminders from EventKit."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.listReminders({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]

    struct Arguments: Sendable {
        @ToolParam("Due-date lower bound.")
        var start: Date?
        @ToolParam("Due-date upper bound.")
        var end: Date?
        @ToolParam("Whether completed reminders are included.")
        var includeCompleted: Bool = false
        @ToolParam("EventKit reminder calendarIdentifier to restrict results.")
        var calendarIdentifier: String?
        @ToolParam("EventKit reminder calendarIdentifier strings to restrict results.")
        var calendarIdentifiers: [String]?
        @ToolParam("Max number of reminder items.")
        var limit: Int = 50
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> [Reminder] {
        #if canImport(EventKit)
        let store = EKEventStore()
        let includeCompleted = arguments.includeCompleted
        let start = arguments.start
        let end = arguments.end
        let limit = max(1, arguments.limit)
        let calendars = try EventKitBridge.resolveCalendars(
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
            timeout: EventKitBridge.reminderFetchTimeoutSeconds,
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
                complete(filtered.map { Reminder($0) })
            }
        }

        return result
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.remindersWrite, path: "apple.reminders.createReminder")
struct RemindersCreateTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Create a reminder."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]

    struct Arguments: Sendable {
        @ToolParam("Reminder title.")
        var title: String
        @ToolParam("Reminder due date.")
        var dueDate: Date?
        @ToolParam("Reminder notes.")
        var notes: String?
        @ToolParam("Completion state.")
        var isCompleted: Bool?
        @ToolParam("EventKit reminder priority integer.")
        var priority: Int?
        @ToolParam("Destination EventKit reminders calendarIdentifier.")
        var calendarIdentifier: String?
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> Reminder {
        #if canImport(EventKit)
        guard arguments.title.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write title cannot be empty")
        }

        let store = EKEventStore()
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = try EventKitBridge.reminderCalendar(identifier: arguments.calendarIdentifier, in: store)
        reminder.title = arguments.title
        reminder.notes = arguments.notes
        reminder.priority = arguments.priority ?? 0
        if let isCompleted = arguments.isCompleted {
            EventKitBridge.applyCompletion(.set(isCompleted), to: reminder)
        }

        if let dueDate = arguments.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: dueDate)
        }

        do {
            try store.save(reminder, commit: true)
            return Reminder(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
        #else
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.remindersWrite, path: "apple.reminders.updateReminder")
struct RemindersUpdateTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Patch an existing reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.updateReminder({ identifier: 'REMINDER_ID', dueDate: null })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]

    struct Arguments: Sendable {
        @ToolParam("EventKit calendarItemIdentifier to update.")
        var identifier: String
        @ToolParam("Reminder title.")
        var title: String?
        @ToolParam("Reminder due date.")
        var dueDate: Patch<Date>
        @ToolParam("Reminder notes.")
        var notes: Patch<String>
        @ToolParam("Completion state.")
        var isCompleted: Patch<Bool>
        @ToolParam("EventKit reminder priority integer.")
        var priority: Patch<Int>
        @ToolParam("Destination EventKit reminders calendarIdentifier.")
        var calendarIdentifier: Patch<String>
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> Reminder {
        #if canImport(EventKit)
        let identifier = arguments.identifier
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write update requires identifier")
        }

        guard Self.hasChanges(arguments) else {
            throw BridgeError.invalidArguments("reminders.write update requires at least one patch field")
        }

        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.invalidArguments("reminders.write could not find reminder identifier \(identifier)")
        }

        try arguments.apply(to: reminder, in: store)

        do {
            try store.save(reminder, commit: true)
            return Reminder(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
        #else
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

extension RemindersUpdateTool.Arguments {
    #if canImport(EventKit)
    func apply(to reminder: EKReminder, in store: EKEventStore) throws {
        if let title {
            guard !title.isEmpty else { throw BridgeError.invalidArguments("reminders.write title cannot be empty") }
            reminder.title = title
        }
        dueDate.apply { reminder.dueDateComponents = $0.map { Calendar.current.dateComponents(in: .current, from: $0) } }
        notes.apply { reminder.notes = $0 }
        EventKitBridge.applyCompletion(isCompleted, to: reminder)
        priority.apply { reminder.priority = $0 ?? 0 }
        try calendarIdentifier.apply { reminder.calendar = try EventKitBridge.reminderCalendar(identifier: $0, in: store) }
    }
    #endif
}

@BuiltInCodeMode(.remindersWrite, path: "apple.reminders.completeReminder")
struct RemindersCompleteTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Set an existing reminder's completion state."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.completeReminder({ identifier: 'REMINDER_ID' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]

    struct Arguments: Sendable {
        @ToolParam("EventKit calendarItemIdentifier to complete.")
        var identifier: String
        @ToolParam("Completion state.")
        var isCompleted: Bool = true
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> Reminder {
        #if canImport(EventKit)
        let identifier = arguments.identifier
        guard identifier.isEmpty == false else {
            throw BridgeError.invalidArguments("reminders.write complete requires identifier")
        }
        let store = EKEventStore()
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
            throw BridgeError.invalidArguments("reminders.write could not find reminder identifier \(identifier)")
        }
        EventKitBridge.applyCompletion(.set(arguments.isCompleted), to: reminder)
        do {
            try store.save(reminder, commit: true)
            return Reminder(reminder)
        } catch {
            throw BridgeError.nativeFailure("reminders.write failed: \(error.localizedDescription)")
        }
        #else
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}

@BuiltInCodeMode(.remindersDelete, path: "apple.reminders.deleteReminder")
struct RemindersDeleteTool: BuiltInCodeModeTool {
    static let codeModeSummary = "Delete an existing EventKit reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task", "delete"]
    static let codeModeExample = "await apple.reminders.deleteReminder({ identifier: 'REMINDER_ID' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]

    struct Arguments: Sendable {
        @ToolParam("EventKit calendarItemIdentifier from apple.reminders.listReminders.")
        var identifier: String
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> EventKitDeletion {
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
            return EventKitDeletion(identifier: identifier, deleted: true)
        } catch {
            throw BridgeError.nativeFailure("reminders.delete failed: \(error.localizedDescription)")
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("EventKit")
        #endif
    }
}
