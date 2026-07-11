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

struct CalendarListEventsTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarRead
    static let codeModePath = "apple.calendar.listEvents"
    static let codeModeTitle = "Read calendar events"
    static let codeModeSummary = "List events in a date range from EventKit."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeArguments = [
        BuiltInToolArgument("start", .string, optional: true, hint: "ISO8601 timestamp; defaults to now."),
        BuiltInToolArgument("end", .string, optional: true, hint: "ISO8601 timestamp; defaults to start + 14 days."),
        BuiltInToolArgument("limit", .number, optional: true, hint: "Max number of items, default 50."),
        BuiltInToolArgument("calendarIdentifier", .string, optional: true, hint: "Optional EventKit calendarIdentifier to restrict results."),
        BuiltInToolArgument("calendarIdentifiers", .array, optional: true, hint: "Optional array of EventKit calendarIdentifier strings to restrict results."),
    ]
    static let codeModeResultSummary = "Array of events with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(raw: arguments)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.readEvents(arguments: arguments.raw, context: context)
    }
}

struct CalendarWriteEventTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var operation: CalendarWriteOperation?
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarWrite
    static let codeModePath = "apple.calendar.createEvent"
    static let codeModeAliasPaths = ["apple.calendar.updateEvent"]
    static let codeModeTitle = "Create or update calendar event"
    static let codeModeSummary = "Create a calendar event or patch an existing event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule"]
    static let codeModeExample = "await apple.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeArguments = [
        BuiltInToolArgument("operation", oneOf: CalendarWriteOperation.self, optional: true, hint: "create (default without identifier) or update (default with identifier)."),
        BuiltInToolArgument("identifier", .string, optional: true, hint: "EventKit eventIdentifier to update. Updates require full calendar access at runtime."),
        BuiltInToolArgument("title", .string, optional: true, hint: "Event title string."),
        BuiltInToolArgument("start", .string, optional: true, hint: "ISO8601 start timestamp."),
        BuiltInToolArgument("end", .string, optional: true, hint: "ISO8601 end timestamp."),
        BuiltInToolArgument("notes", .string, optional: true, hint: "Optional notes/body string."),
        BuiltInToolArgument("location", .string, optional: true, hint: "Optional location string."),
        BuiltInToolArgument("url", .string, optional: true, hint: "Optional absolute URL string attached to the event."),
        BuiltInToolArgument("isAllDay", .bool, optional: true, hint: "Whether the event is all-day."),
        BuiltInToolArgument("calendarIdentifier", .string, optional: true, hint: "Optional destination EventKit calendarIdentifier."),
    ]
    static let codeModeResultSummary = "Object with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        var raw = arguments
        let operation = try CodeModeArgumentDecoder.optional("operation", as: CalendarWriteOperation.self, in: arguments)
        if let operation {
            raw["operation"] = .string(operation.rawValue)
        }
        return Arguments(operation: operation, raw: raw)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.writeEvent(arguments: arguments.raw, context: context)
    }
}

struct CalendarDeleteEventTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var identifier: String
        var span: CalendarEventSpan?
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarDelete
    static let codeModePath = "apple.calendar.deleteEvent"
    static let codeModeTitle = "Delete calendar event"
    static let codeModeSummary = "Delete an existing EventKit event by identifier."
    static let codeModeTags = ["calendar", "eventkit", "schedule", "delete"]
    static let codeModeExample = "await apple.calendar.deleteEvent({ identifier: 'EVENT_ID', span: 'thisEvent' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeArguments = [
        BuiltInToolArgument("identifier", .string, hint: "EventKit eventIdentifier from apple.calendar.listEvents."),
        BuiltInToolArgument("span", oneOf: CalendarEventSpan.self, optional: true, hint: "thisEvent (default) or futureEvents for recurring events."),
    ]
    static let codeModeResultSummary = "Object with identifier/deleted."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        var raw = arguments
        let span = try CodeModeArgumentDecoder.optional("span", as: CalendarEventSpan.self, in: arguments)
        if let span {
            raw["span"] = .string(span.rawValue)
        }
        return Arguments(
            identifier: try CodeModeArgumentDecoder.require("identifier", as: String.self, in: arguments),
            span: span,
            raw: raw
        )
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.deleteEvent(arguments: arguments.raw, context: context)
    }
}

struct CalendarPickCalendarTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var selectionStyle: CalendarPickerSelectionStyle?
        var displayStyle: CalendarPickerDisplayStyle?
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarUIPickCalendar
    static let codeModePath = "apple.calendar.pickCalendar"
    static let codeModeTitle = "Pick calendar with system UI"
    static let codeModeSummary = "Present EventKit calendar chooser UI and return the user-selected writable calendars."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.pickCalendar({ selectionStyle: 'single' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeArguments = [
        BuiltInToolArgument("selectionStyle", oneOf: CalendarPickerSelectionStyle.self, optional: true, hint: "single (default) or multiple."),
        BuiltInToolArgument("displayStyle", oneOf: CalendarPickerDisplayStyle.self, optional: true, hint: "writable (default) or all."),
        BuiltInToolArgument("timeoutMs", .number, optional: true, hint: "Optional timeout for waiting on user selection."),
    ]
    static let codeModeResultSummary = "Array of selected calendars with identifier/title/type/allowsContentModifications."

    let systemUI: SystemUIBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        var raw = arguments
        let selectionStyle = try CodeModeArgumentDecoder.optional("selectionStyle", as: CalendarPickerSelectionStyle.self, in: arguments)
        let displayStyle = try CodeModeArgumentDecoder.optional("displayStyle", as: CalendarPickerDisplayStyle.self, in: arguments)
        if let selectionStyle {
            raw["selectionStyle"] = .string(selectionStyle.rawValue)
        }
        if let displayStyle {
            raw["displayStyle"] = .string(displayStyle.rawValue)
        }
        return Arguments(selectionStyle: selectionStyle, displayStyle: displayStyle, raw: raw)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.pickCalendar(arguments: arguments.raw, context: context)
    }
}

struct CalendarPresentEventTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var identifier: String
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarUIPresentEvent
    static let codeModePath = "apple.calendar.presentEvent"
    static let codeModeTitle = "Present calendar event details"
    static let codeModeSummary = "Present system UI for an existing calendar event identifier."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "details"]
    static let codeModeExample = "await apple.calendar.presentEvent({ identifier: 'EVENT_ID', allowsEditing: false })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendar]
    static let codeModeArguments = [
        BuiltInToolArgument("identifier", .string, hint: "EventKit eventIdentifier from apple.calendar.listEvents."),
        BuiltInToolArgument("allowsEditing", .bool, optional: true, hint: "Whether the user can edit from the detail UI; default false."),
        BuiltInToolArgument("allowsCalendarPreview", .bool, optional: true, hint: "Whether the UI may show calendar day previews; default true."),
        BuiltInToolArgument("timeoutMs", .number, optional: true, hint: "Optional timeout for waiting on dismissal."),
    ]
    static let codeModeResultSummary = "Object with action dismissed."

    let systemUI: SystemUIBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(
            identifier: try CodeModeArgumentDecoder.require("identifier", as: String.self, in: arguments),
            raw: arguments
        )
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentCalendarEvent(arguments: arguments.raw, context: context)
    }
}

struct CalendarPresentNewEventTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .calendarUIPresentNewEvent
    static let codeModePath = "apple.calendar.presentNewEvent"
    static let codeModeTitle = "Present calendar event editor"
    static let codeModeSummary = "Present system UI to let the user create or edit a new calendar event draft."
    static let codeModeTags = ["calendar", "eventkit", "system-ui", "picker"]
    static let codeModeExample = "await apple.calendar.presentNewEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.calendarWriteOnly]
    static let codeModeArguments = [
        BuiltInToolArgument("title", .string, optional: true, hint: "Optional event title shown in the editor."),
        BuiltInToolArgument("start", .string, optional: true, hint: "Optional ISO8601 start timestamp."),
        BuiltInToolArgument("end", .string, optional: true, hint: "Optional ISO8601 end timestamp."),
        BuiltInToolArgument("notes", .string, optional: true, hint: "Optional event notes/body text."),
        BuiltInToolArgument("location", .string, optional: true, hint: "Optional location string."),
        BuiltInToolArgument("timeoutMs", .number, optional: true, hint: "Optional timeout for waiting on user save/cancel."),
    ]
    static let codeModeResultSummary = "Object with action plus identifier/title when the user saves."

    let systemUI: SystemUIBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(raw: arguments)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentNewCalendarEvent(arguments: arguments.raw, context: context)
    }
}

// MARK: - Reminder tools

struct RemindersListTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .remindersRead
    static let codeModePath = "apple.reminders.listReminders"
    static let codeModeTitle = "Read reminders"
    static let codeModeSummary = "Read incomplete reminders from EventKit."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.listReminders({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeArguments = [
        BuiltInToolArgument("start", .string, optional: true, hint: "Optional ISO8601 due-date lower bound."),
        BuiltInToolArgument("end", .string, optional: true, hint: "Optional ISO8601 due-date upper bound."),
        BuiltInToolArgument("includeCompleted", .bool, optional: true, hint: "Whether completed reminders are included; default false."),
        BuiltInToolArgument("calendarIdentifier", .string, optional: true, hint: "Optional EventKit reminder calendarIdentifier to restrict results."),
        BuiltInToolArgument("calendarIdentifiers", .array, optional: true, hint: "Optional array of EventKit reminder calendarIdentifier strings to restrict results."),
        BuiltInToolArgument("limit", .number, optional: true, hint: "Max number of reminder items, default 50."),
    ]
    static let codeModeResultSummary = "Array of reminders with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(raw: arguments)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.readReminders(arguments: arguments.raw, context: context)
    }
}

struct RemindersWriteTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var operation: ReminderWriteOperation?
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .remindersWrite
    static let codeModePath = "apple.reminders.createReminder"
    static let codeModeAliasPaths = ["apple.reminders.updateReminder", "apple.reminders.completeReminder"]
    static let codeModeTitle = "Create or update reminder"
    static let codeModeSummary = "Create a reminder or patch an existing reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task"]
    static let codeModeExample = "await apple.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeArguments = [
        BuiltInToolArgument("operation", oneOf: ReminderWriteOperation.self, optional: true, hint: "create (default without identifier), update, or complete."),
        BuiltInToolArgument("identifier", .string, optional: true, hint: "EventKit calendarItemIdentifier to update or complete."),
        BuiltInToolArgument("title", .string, optional: true, hint: "Reminder title string."),
        BuiltInToolArgument("dueDate", .string, optional: true, hint: "Optional ISO8601 due date timestamp."),
        BuiltInToolArgument("notes", .string, optional: true, hint: "Optional reminder notes."),
        BuiltInToolArgument("isCompleted", .bool, optional: true, hint: "Completion state for update or completeReminder; default true for completeReminder."),
        BuiltInToolArgument("priority", .number, optional: true, hint: "EventKit reminder priority integer."),
        BuiltInToolArgument("calendarIdentifier", .string, optional: true, hint: "Optional destination EventKit reminders calendarIdentifier."),
    ]
    static let codeModeResultSummary = "Object with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        var raw = arguments
        let operation = try CodeModeArgumentDecoder.optional("operation", as: ReminderWriteOperation.self, in: arguments)
        if let operation {
            raw["operation"] = .string(operation.rawValue)
        }
        return Arguments(operation: operation, raw: raw)
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.writeReminder(arguments: arguments.raw, context: context)
    }
}

struct RemindersDeleteTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var identifier: String
        var raw: [String: JSONValue]
    }

    static let codeModeCapability: CapabilityID = .remindersDelete
    static let codeModePath = "apple.reminders.deleteReminder"
    static let codeModeTitle = "Delete reminder"
    static let codeModeSummary = "Delete an existing EventKit reminder by identifier."
    static let codeModeTags = ["reminders", "eventkit", "task", "delete"]
    static let codeModeExample = "await apple.reminders.deleteReminder({ identifier: 'REMINDER_ID' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.reminders]
    static let codeModeArguments = [
        BuiltInToolArgument("identifier", .string, hint: "EventKit calendarItemIdentifier from apple.reminders.listReminders."),
    ]
    static let codeModeResultSummary = "Object with identifier/deleted."

    let eventKit: EventKitBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(
            identifier: try CodeModeArgumentDecoder.require("identifier", as: String.self, in: arguments),
            raw: arguments
        )
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try eventKit.deleteReminder(arguments: arguments.raw, context: context)
    }
}
