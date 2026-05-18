import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func calendarAndReminderRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                jsNames: ["apple.calendar.listEvents"],
                descriptor: .init(
                    id: .calendarRead,
                    title: "Read calendar events",
                    summary: "List events in a date range from EventKit.",
                    tags: ["calendar", "eventkit", "schedule"],
                    example: "await apple.calendar.listEvents({ start: '2026-02-21T00:00:00Z', end: '2026-03-01T00:00:00Z' })",
                    requiredPermissions: [.calendar],
                    optionalArguments: ["start", "end", "limit", "calendarIdentifier", "calendarIdentifiers"],
                    argumentHints: [
                        "start": "ISO8601 timestamp; defaults to now.",
                        "end": "ISO8601 timestamp; defaults to start + 14 days.",
                        "limit": "Max number of items, default 50.",
                        "calendarIdentifier": "Optional EventKit calendarIdentifier to restrict results.",
                        "calendarIdentifiers": "Optional array of EventKit calendarIdentifier strings to restrict results.",
                    ],
                    resultSummary: "Array of events with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."
                ),
                handler: { args, context in
                    try eventKit.readEvents(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.calendar.createEvent", "apple.calendar.updateEvent"],
                descriptor: .init(
                    id: .calendarWrite,
                    title: "Create or update calendar event",
                    summary: "Create a calendar event or patch an existing event by identifier.",
                    tags: ["calendar", "eventkit", "schedule"],
                    example: "await apple.calendar.createEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })",
                    requiredPermissions: [],
                    optionalArguments: [
                        "operation",
                        "identifier",
                        "title",
                        "start",
                        "end",
                        "notes",
                        "location",
                        "url",
                        "isAllDay",
                        "calendarIdentifier",
                    ],
                    argumentHints: [
                        "operation": "create (default without identifier) or update (default with identifier).",
                        "identifier": "EventKit eventIdentifier to update. Updates require full calendar access at runtime.",
                        "title": "Event title string.",
                        "start": "ISO8601 start timestamp.",
                        "end": "ISO8601 end timestamp.",
                        "notes": "Optional notes/body string.",
                        "location": "Optional location string.",
                        "url": "Optional absolute URL string attached to the event.",
                        "isAllDay": "Whether the event is all-day.",
                        "calendarIdentifier": "Optional destination EventKit calendarIdentifier.",
                    ],
                    resultSummary: "Object with identifier/title/startDate/endDate/notes/calendarIdentifier/calendarTitle/location/url/isAllDay."
                ),
                handler: { args, context in
                    try eventKit.writeEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.calendar.deleteEvent"],
                descriptor: .init(
                    id: .calendarDelete,
                    title: "Delete calendar event",
                    summary: "Delete an existing EventKit event by identifier.",
                    tags: ["calendar", "eventkit", "schedule", "delete"],
                    example: "await apple.calendar.deleteEvent({ identifier: 'EVENT_ID', span: 'thisEvent' })",
                    requiredPermissions: [.calendar],
                    requiredArguments: ["identifier"],
                    optionalArguments: ["span"],
                    argumentHints: [
                        "identifier": "EventKit eventIdentifier from apple.calendar.listEvents.",
                        "span": "thisEvent (default) or futureEvents for recurring events.",
                    ],
                    resultSummary: "Object with identifier/deleted."
                ),
                handler: { args, context in
                    try eventKit.deleteEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.calendar.pickCalendar"],
                descriptor: .init(
                    id: .calendarUIPickCalendar,
                    title: "Pick calendar with system UI",
                    summary: "Present EventKit calendar chooser UI and return the user-selected writable calendars.",
                    tags: ["calendar", "eventkit", "system-ui", "picker"],
                    example: "await apple.calendar.pickCalendar({ selectionStyle: 'single' })",
                    requiredPermissions: [.calendarWriteOnly],
                    optionalArguments: ["selectionStyle", "displayStyle", "timeoutMs"],
                    argumentTypes: [
                        "selectionStyle": .string,
                        "displayStyle": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "selectionStyle": "single (default) or multiple.",
                        "displayStyle": "writable (default) or all.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Array of selected calendars with identifier/title/type/allowsContentModifications."
                ),
                handler: { args, context in
                    try systemUI.pickCalendar(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.calendar.presentEvent"],
                descriptor: .init(
                    id: .calendarUIPresentEvent,
                    title: "Present calendar event details",
                    summary: "Present system UI for an existing calendar event identifier.",
                    tags: ["calendar", "eventkit", "system-ui", "details"],
                    example: "await apple.calendar.presentEvent({ identifier: 'EVENT_ID', allowsEditing: false })",
                    requiredPermissions: [.calendar],
                    requiredArguments: ["identifier"],
                    optionalArguments: ["allowsEditing", "allowsCalendarPreview", "timeoutMs"],
                    argumentTypes: [
                        "identifier": .string,
                        "allowsEditing": .bool,
                        "allowsCalendarPreview": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "identifier": "EventKit eventIdentifier from apple.calendar.listEvents.",
                        "allowsEditing": "Whether the user can edit from the detail UI; default false.",
                        "allowsCalendarPreview": "Whether the UI may show calendar day previews; default true.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed."
                ),
                handler: { args, context in
                    try systemUI.presentCalendarEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.calendar.presentNewEvent"],
                descriptor: .init(
                    id: .calendarUIPresentNewEvent,
                    title: "Present calendar event editor",
                    summary: "Present system UI to let the user create or edit a new calendar event draft.",
                    tags: ["calendar", "eventkit", "system-ui", "picker"],
                    example: "await apple.calendar.presentNewEvent({ title: 'Standup', start: '2026-02-22T16:00:00Z', end: '2026-02-22T16:15:00Z' })",
                    requiredPermissions: [.calendarWriteOnly],
                    optionalArguments: ["title", "start", "end", "notes", "location", "timeoutMs"],
                    argumentTypes: [
                        "title": .string,
                        "start": .string,
                        "end": .string,
                        "notes": .string,
                        "location": .string,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "title": "Optional event title shown in the editor.",
                        "start": "Optional ISO8601 start timestamp.",
                        "end": "Optional ISO8601 end timestamp.",
                        "notes": "Optional event notes/body text.",
                        "location": "Optional location string.",
                        "timeoutMs": "Optional timeout for waiting on user save/cancel.",
                    ],
                    resultSummary: "Object with action plus identifier/title when the user saves."
                ),
                handler: { args, context in
                    try systemUI.presentNewCalendarEvent(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.reminders.listReminders"],
                descriptor: .init(
                    id: .remindersRead,
                    title: "Read reminders",
                    summary: "Read incomplete reminders from EventKit.",
                    tags: ["reminders", "eventkit", "task"],
                    example: "await apple.reminders.listReminders({ limit: 20 })",
                    requiredPermissions: [.reminders],
                    optionalArguments: ["start", "end", "includeCompleted", "calendarIdentifier", "calendarIdentifiers", "limit"],
                    argumentHints: [
                        "start": "Optional ISO8601 due-date lower bound.",
                        "end": "Optional ISO8601 due-date upper bound.",
                        "includeCompleted": "Whether completed reminders are included; default false.",
                        "calendarIdentifier": "Optional EventKit reminder calendarIdentifier to restrict results.",
                        "calendarIdentifiers": "Optional array of EventKit reminder calendarIdentifier strings to restrict results.",
                        "limit": "Max number of reminder items, default 50.",
                    ],
                    resultSummary: "Array of reminders with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."
                ),
                handler: { args, context in
                    try eventKit.readReminders(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.reminders.createReminder", "apple.reminders.updateReminder", "apple.reminders.completeReminder"],
                descriptor: .init(
                    id: .remindersWrite,
                    title: "Create or update reminder",
                    summary: "Create a reminder or patch an existing reminder by identifier.",
                    tags: ["reminders", "eventkit", "task"],
                    example: "await apple.reminders.createReminder({ title: 'Buy batteries', dueDate: '2026-02-22T18:00:00Z' })",
                    requiredPermissions: [.reminders],
                    optionalArguments: ["operation", "identifier", "title", "dueDate", "notes", "isCompleted", "priority", "calendarIdentifier"],
                    argumentHints: [
                        "operation": "create (default without identifier), update, or complete.",
                        "identifier": "EventKit calendarItemIdentifier to update or complete.",
                        "title": "Reminder title string.",
                        "dueDate": "Optional ISO8601 due date timestamp.",
                        "notes": "Optional reminder notes.",
                        "isCompleted": "Completion state for update or completeReminder; default true for completeReminder.",
                        "priority": "EventKit reminder priority integer.",
                        "calendarIdentifier": "Optional destination EventKit reminders calendarIdentifier.",
                    ],
                    resultSummary: "Object with identifier/title/isCompleted/dueDate/completionDate/notes/priority/calendarIdentifier/calendarTitle."
                ),
                handler: { args, context in
                    try eventKit.writeReminder(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                jsNames: ["apple.reminders.deleteReminder"],
                descriptor: .init(
                    id: .remindersDelete,
                    title: "Delete reminder",
                    summary: "Delete an existing EventKit reminder by identifier.",
                    tags: ["reminders", "eventkit", "task", "delete"],
                    example: "await apple.reminders.deleteReminder({ identifier: 'REMINDER_ID' })",
                    requiredPermissions: [.reminders],
                    requiredArguments: ["identifier"],
                    argumentHints: [
                        "identifier": "EventKit calendarItemIdentifier from apple.reminders.listReminders.",
                    ],
                    resultSummary: "Object with identifier/deleted."
                ),
                handler: { args, context in
                    try eventKit.deleteReminder(arguments: args, context: context)
                }
            ),
        ]
    }
}
