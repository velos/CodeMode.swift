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

enum CalendarWriteOperation: String, CodeModeStringEnum {
    case create
    case update
}

enum ReminderWriteOperation: String, CodeModeStringEnum {
    case create
    case update
    case complete
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
    static let codeModeTitle = "Read calendar events"
    static let codeModeSummary = "List events in a date range from EventKit."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeResultSummary = "Array of events with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."

    struct Arguments: Sendable {
        @ToolParam("ISO8601 timestamp; defaults to now.")
        var start: Date?
        @ToolParam("ISO8601 timestamp; defaults to start + 14 days.")
        var end: Date?
        @ToolParam("Max number of items.")
        var limit: Int = 50
        @ToolParam("Optional EventKit calendarIdentifier to restrict results.")
        var calendarIdentifier: String?
        @ToolParam("Optional array of EventKit calendarIdentifier strings to restrict results.")
        var calendarIdentifiers: [String]?
    }

    let eventKit: EventKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.readEvents(arguments: arguments)
    }
}

@BuiltInCodeMode(.calendarWrite, path: "apple.calendar.createEvent", aliases: ["apple.calendar.updateEvent"])
struct CalendarWriteEventTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Create or update calendar event"
    static let codeModeSummary = "Create a calendar event or patch an existing event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeResultSummary = "Object with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."

    struct Arguments: Sendable {
        @ToolParam("create (default without identifier) or update (default with identifier).")
        var operation: CalendarWriteOperation?
        @ToolParam("EventKit eventIdentifier to update. Updates require full calendar access at runtime.")
        var identifier: String?
        @ToolParam("Event title string.")
        var title: String?
        @ToolParam("ISO8601 start timestamp.")
        var start: String?
        @ToolParam("ISO8601 end timestamp.")
        var end: String?
        @ToolParam("Optional notes/body string.")
        var notes: String?
        @ToolParam("Optional location string.")
        var location: String?
        @ToolParam("Optional absolute URL string attached to the event.")
        var url: String?
        @ToolParam("Whether the event is all-day.")
        var isAllDay: Bool?
        @ToolParam("Optional destination EventKit calendarIdentifier.")
        var calendarIdentifier: String?
        // Presence is separate from value: null clears a patch field, omission
        // leaves it alone. No raw values escape the generated decoder.
        var providedArguments: Set<String>
    }

    let eventKit: EventKitBridge

    func argumentDependentPermissions(for arguments: Arguments) -> [PermissionKind] {
        [arguments.resolvedOperation == .update ? .calendar : .calendarWriteOnly]
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.writeEvent(arguments: arguments)
    }
}

@BuiltInCodeMode(.calendarDelete, path: "apple.calendar.deleteEvent")
struct CalendarDeleteEventTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete calendar event"
    static let codeModeSummary = "Delete an existing EventKit event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule", "delete"]
    static let codeModeExample = "await apple.calendar.deleteEvent({ identifier: 'EVENT_ID', span: 'thisEvent' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeResultSummary = "Object with identifier/deleted."

    struct Arguments: Sendable {
        @ToolParam("EventKit eventIdentifier from apple.calendar.listEvents.")
        var identifier: String
        @ToolParam("thisEvent or futureEvents for recurring events.")
        var span: CalendarEventSpan = .thisEvent
    }

    let eventKit: EventKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.deleteEvent(arguments: arguments)
    }
}

@BuiltInCodeMode(.calendarUIPickCalendar, path: "apple.calendar.pickCalendar")
struct CalendarPickCalendarTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Pick calendar with system UI"
    static let codeModeSummary = "Present EventKit calendar chooser UI and return the user-selected writable calendars."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.pickCalendar({ selectionStyle: 'single' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeResultSummary = "Array of selected calendars with identifier/title/type/allowsContentModifications."

    struct Arguments: Sendable {
        @ToolParam("single (default) or multiple.")
        var selectionStyle: CalendarPickerSelectionStyle?
        @ToolParam("writable (default) or all.")
        var displayStyle: CalendarPickerDisplayStyle?
        @ToolParam("Optional timeout for waiting on user selection.")
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
    static let codeModeTitle = "Present calendar event details"
    static let codeModeSummary = "Present system UI for an existing calendar event identifier."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "details"]
    static let codeModeExample = "await apple.calendar.presentEvent({ identifier: 'EVENT_ID', allowsEditing: false })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeResultSummary = "Object with action dismissed."

    struct Arguments: Sendable {
        @ToolParam("EventKit eventIdentifier from apple.calendar.listEvents.")
        var identifier: String
        @ToolParam("Whether the user can edit from the detail UI; default false.")
        var allowsEditing: Bool?
        @ToolParam("Whether the UI may show calendar day previews; default true.")
        var allowsCalendarPreview: Bool?
        @ToolParam("Optional timeout for waiting on dismissal.")
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
    static let codeModeTitle = "Present calendar event editor"
    static let codeModeSummary = "Present system UI to let the user create or edit a new calendar event draft."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.presentNewEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeResultSummary = "Object with action plus identifier/title when the user saves."

    struct Arguments: Sendable {
        @ToolParam("Optional event title shown in the editor.")
        var title: String?
        @ToolParam("Optional ISO8601 start timestamp.")
        var start: String?
        @ToolParam("Optional ISO8601 end timestamp.")
        var end: String?
        @ToolParam("Optional event notes/body text.")
        var notes: String?
        @ToolParam("Optional location string.")
        var location: String?
        @ToolParam("Optional timeout for waiting on user save/cancel.")
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
    static let codeModeTitle = "Read reminders"
    static let codeModeSummary = "Read incomplete reminders from EventKit."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.listReminders({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeResultSummary = "Array of reminders with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."

    struct Arguments: Sendable {
        @ToolParam("Optional ISO8601 due-date lower bound.")
        var start: Date?
        @ToolParam("Optional ISO8601 due-date upper bound.")
        var end: Date?
        @ToolParam("Whether completed reminders are included.")
        var includeCompleted: Bool = false
        @ToolParam("Optional EventKit reminder calendarIdentifier to restrict results.")
        var calendarIdentifier: String?
        @ToolParam("Optional array of EventKit reminder calendarIdentifier strings to restrict results.")
        var calendarIdentifiers: [String]?
        @ToolParam("Max number of reminder items.")
        var limit: Int = 50
    }

    let eventKit: EventKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.readReminders(arguments: arguments)
    }
}

@BuiltInCodeMode(.remindersWrite, path: "apple.reminders.createReminder", aliases: ["apple.reminders.updateReminder", "apple.reminders.completeReminder"])
struct RemindersWriteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Create or update reminder"
    static let codeModeSummary = "Create a reminder or patch an existing reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeResultSummary = "Object with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."

    struct Arguments: Sendable {
        @ToolParam("create (default without identifier), update, or complete.")
        var operation: ReminderWriteOperation?
        @ToolParam("EventKit calendarItemIdentifier to update or complete.")
        var identifier: String?
        @ToolParam("Reminder title string.")
        var title: String?
        @ToolParam("Optional ISO8601 due date timestamp.")
        var dueDate: String?
        @ToolParam("Optional reminder notes.")
        var notes: String?
        @ToolParam("Completion state for update or completeReminder; default true for completeReminder.")
        var isCompleted: Bool?
        @ToolParam("EventKit reminder priority integer.")
        var priority: Int?
        @ToolParam("Optional destination EventKit reminders calendarIdentifier.")
        var calendarIdentifier: String?
        // Presence is separate from value: null clears a patch field, omission
        // leaves it alone. No raw values escape the generated decoder.
        var providedArguments: Set<String>
    }

    let eventKit: EventKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.writeReminder(arguments: arguments)
    }
}

@BuiltInCodeMode(.remindersDelete, path: "apple.reminders.deleteReminder")
struct RemindersDeleteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete reminder"
    static let codeModeSummary = "Delete an existing EventKit reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task", "delete"]
    static let codeModeExample = "await apple.reminders.deleteReminder({ identifier: 'REMINDER_ID' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeResultSummary = "Object with identifier/deleted."

    struct Arguments: Sendable {
        @ToolParam("EventKit calendarItemIdentifier from apple.reminders.listReminders.")
        var identifier: String
    }

    let eventKit: EventKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.deleteReminder(arguments: arguments)
    }
}

// Operation inference is shared by permission selection and execution.
extension CalendarWriteEventTool.Arguments {
    var resolvedOperation: CalendarWriteOperation { operation ?? (identifier == nil ? .create : .update) }
}

extension RemindersWriteTool.Arguments {
    var resolvedOperation: ReminderWriteOperation { operation ?? (identifier == nil ? .create : .update) }
}
