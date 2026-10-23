import Foundation
import Testing
@testable import CodeMode

@Test func eventKitCalendarOperationsRequirePermission() throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let broker = FixedPermissionBroker(statuses: [
        .calendar: .denied,
        .calendarWriteOnly: .denied,
    ])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke("calendar.read", arguments: [:], context: context)
        Issue.record("Expected permission denial for calendar.read")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("calendar.write", arguments: ["title": .string("T"), "start": .string("2026-02-22T16:00:00Z"), "end": .string("2026-02-22T17:00:00Z")], context: context)
        Issue.record("Expected permission denial for calendar.write")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("calendar.write", jsName: "apple.calendar.updateEvent", arguments: [
            "identifier": .string("event-1"),
            "title": .string("Updated"),
        ], context: context)
        Issue.record("Expected permission denial for calendar.write update")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("calendar.delete", arguments: ["identifier": .string("event-1")], context: context)
        Issue.record("Expected permission denial for calendar.delete")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func eventKitReminderOperationsRequirePermission() throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let broker = FixedPermissionBroker(statuses: [.reminders: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke("reminders.read", arguments: [:], context: context)
        Issue.record("Expected permission denial for reminders.read")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("reminders.write", arguments: ["title": .string("T")], context: context)
        Issue.record("Expected permission denial for reminders.write")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("reminders.delete", arguments: ["identifier": .string("reminder-1")], context: context)
        Issue.record("Expected permission denial for reminders.delete")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func executeUsesCalendarBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.calendar: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.calendar.listEvents({});
            return { ok: true };
            """,
            allowedCapabilities: [.calendarRead]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}

@Test(arguments: [PermissionStatus.writeOnly, .notDetermined])
func executeCalendarWriteUsesWriteOnlyPermissionPath(initialStatus: PermissionStatus) async throws {
    let broker = FixedPermissionBroker(
        statuses: [.calendarWriteOnly: initialStatus],
        requestStatuses: [.calendarWriteOnly: .writeOnly]
    )
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.calendar.createEvent({ title: '', start: '2026-02-22T16:00:00Z', end: '2026-02-22T17:00:00Z' });
            return { ok: true };
            """,
            allowedCapabilities: [.calendarWrite]
        )
    )

    #if canImport(EventKit)
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #expect(observed.error?.message == "calendar.write title cannot be empty")
    #else
    #expect(observed.error?.code == "UNSUPPORTED_PLATFORM")
    #endif
}

@Test func executeUsesReminderBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.reminders: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.reminders.listReminders({});
            return { ok: true };
            """,
            allowedCapabilities: [.remindersRead]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}

// MARK: - Serialization of degenerate items

#if canImport(EventKit)
import EventKit

// EventKit's serialization logic executes nowhere today — not in unit tests, not
// in CI, not in evals — because the bridge hard-instantiates EKEventStore and the
// tests can only reach permission denial. These construct the model objects
// directly, which needs no permission, and cover the two implicitly-unwrapped
// fields that crashed the execution thread.

@Test func eventSerializationSurvivesAnEventWithNoCalendar() throws {
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    event.title = "Orphaned"
    event.startDate = Date(timeIntervalSince1970: 1_700_000_000)
    event.endDate = event.startDate.addingTimeInterval(3_600)

    // `EKEvent.calendar` is `EKCalendar!` and is nil for an orphaned event, while
    // every neighbouring field was nil-coalesced.
    #expect(event.calendar == nil)

    #expect(CalendarEvent(event).codeModeJSONValue == .object([
        "identifier": .string(""), "title": .string("Orphaned"),
        "startDate": .string("2023-11-14T22:13:20Z"),
        "endDate": .string("2023-11-14T23:13:20Z"),
        "notes": .string(""), "calendarIdentifier": .string(""),
        "calendarTitle": .string(""), "location": .string(""),
        "url": .string(""), "isAllDay": .bool(false),
    ]))
}

@Test func reminderSerializationSurvivesAMissingTitle() throws {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)

    // `EKReminder.title` is `String!`.
    #expect(Reminder(reminder).codeModeJSONValue == .object([
        "identifier": .string(reminder.calendarItemIdentifier), "title": .string(""),
        "isCompleted": .bool(false), "dueDate": .string(""), "completionDate": .string(""),
        "notes": .string(""), "priority": .number(0),
        "calendarIdentifier": .string(""), "calendarTitle": .string(""),
    ]))
}
#endif

@Test func eventKitOmittedArgumentsUseDeclaredDefaults() throws {
    let events = try CalendarListEventsTool().decode(arguments: [:])
    #expect(events.limit == 50)
    #expect(events.start == nil)
    #expect(events.end == nil)
    let reminders = try RemindersListTool().decode(arguments: [:])
    #expect(reminders.limit == 50)
    #expect(reminders.includeCompleted == false)
    let deletion = try CalendarDeleteEventTool().decode(arguments: ["identifier": .string("E1")])
    #expect(deletion.span == .thisEvent)

    let overrides = try RemindersListTool().decode(arguments: ["limit": .number(3), "includeCompleted": .bool(true)])
    #expect(overrides.limit == 3)
    #expect(overrides.includeCompleted)
    let blank = try CalendarListEventsTool().decode(arguments: ["start": .string("  "), "end": .string("")])
    #expect(blank.start == nil)
    #expect(blank.end == nil)
}

@Test(arguments: [
    ("calendar.read", "start"), ("calendar.read", "end"),
    ("reminders.read", "start"), ("reminders.read", "end"),
])
func eventKitReadDateErrorsRetainScriptMessages(capability: String, argument: String) throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .granted, .reminders: .granted,
    ]))
    defer { cleanup(sandbox) }
    do {
        _ = try registry.invoke(capability, arguments: [argument: .string("soon")], context: context)
        Issue.record("Expected an invalid timestamp error")
    } catch let error as BridgeError {
        #expect(error.diagnosticCode == "INVALID_ARGUMENTS")
        #expect(error.localizedDescription == "\(capability) could not parse '\(argument)' as an ISO 8601 timestamp: \"soon\". Use a form like 2026-07-24T10:00:00Z.")
    }
}

@Test(arguments: [
    ("apple.calendar.createEvent", PermissionKind.calendarWriteOnly),
    ("apple.calendar.updateEvent", .calendar),
])
func eventKitWritesRequireTheirOwnStaticPermissions(helper: String, expected: PermissionKind) async throws {
    let (tools, sandbox) = try makeTools(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .denied, .calendarWriteOnly: .denied,
    ]))
    defer { cleanup(sandbox) }
    let args = helper.hasSuffix("createEvent")
        ? "{ title: 'T', start: '2026-02-22T16:00:00Z', end: '2026-02-22T17:00:00Z' }"
        : "{ identifier: 'E1', notes: null }"
    let observed = try await execute(tools, request: JavaScriptExecutionRequest(
        code: "await \(helper)(\(args));", allowedCapabilities: [.calendarWrite]
    ))
    #expect(observed.error?.code == "PERMISSION_DENIED")
    #expect(observed.error?.message == "Permission denied: \(expected.rawValue)")
}

#if canImport(EventKit)
@Test func eventUpdatePatchDistinguishesNullFromOmission() throws {
    let tool = CalendarUpdateEventTool()
    let store = EKEventStore()
    let event = EKEvent(eventStore: store)
    event.title = "Keep title"
    event.notes = "Keep notes"
    event.location = "Keep location"
    event.url = URL(string: "https://example.com")
    event.isAllDay = true
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    event.startDate = start
    event.endDate = start.addingTimeInterval(3_600)
    // EventKit normalizes all-day dates itself; compare its stored values.
    let originalStart = event.startDate
    let originalEnd = event.endDate

    let omitted = try tool.decode(arguments: ["identifier": .string("E1")])
    try omitted.apply(to: event, in: store)
    #expect(event.notes == "Keep notes")
    #expect(event.location == "Keep location")
    #expect(event.url?.absoluteString == "https://example.com")
    #expect(event.isAllDay)
    #expect(event.startDate == originalStart)
    #expect(event.endDate == originalEnd)

    let cleared = try tool.decode(arguments: [
        "identifier": .string("E1"), "notes": .null, "location": .null,
        "url": .null, "isAllDay": .null,
    ])
    try cleared.apply(to: event, in: store)
    #expect(event.notes == nil)
    #expect(event.location == nil)
    #expect(event.url == nil)
    #expect(event.isAllDay == false)
    #expect(event.title == "Keep title")

    let updated = try tool.decode(arguments: [
        "identifier": .string("E1"), "title": .string("New title"),
        "start": .string("2026-02-22T16:00:00Z"), "end": .string("2026-02-22T17:00:00Z"),
        "notes": .string("New notes"), "location": .string("New location"),
        "url": .string("https://example.org"),
    ])
    try updated.apply(to: event, in: store)
    #expect(event.title == "New title")
    #expect(event.startDate == CodeModeDate.parse("2026-02-22T16:00:00Z"))
    #expect(event.endDate == CodeModeDate.parse("2026-02-22T17:00:00Z"))
    #expect(event.notes == "New notes")
    #expect(event.location == "New location")
    #expect(event.url?.absoluteString == "https://example.org")
}

@Test func reminderUpdatePatchDistinguishesNullFromOmission() throws {
    let tool = RemindersUpdateTool()
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.title = "Keep title"
    reminder.notes = "Keep notes"
    reminder.priority = 7
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    reminder.dueDateComponents = Calendar.current.dateComponents(in: .current, from: date)
    reminder.isCompleted = true
    reminder.completionDate = date

    let omitted = try tool.decode(arguments: ["identifier": .string("R1")])
    try omitted.apply(to: reminder, in: store)
    #expect(reminder.notes == "Keep notes")
    #expect(reminder.dueDateComponents != nil)
    #expect(reminder.isCompleted)
    #expect(reminder.completionDate == date)
    #expect(reminder.priority == 7)

    let cleared = try tool.decode(arguments: [
        "identifier": .string("R1"), "notes": .null, "dueDate": .null,
        "isCompleted": .null, "priority": .null,
    ])
    try cleared.apply(to: reminder, in: store)
    #expect(reminder.notes == nil)
    #expect(reminder.dueDateComponents == nil)
    #expect(reminder.isCompleted == false)
    #expect(reminder.completionDate == nil)
    #expect(reminder.priority == 0)
    #expect(reminder.title == "Keep title")

    let updated = try tool.decode(arguments: [
        "identifier": .string("R1"), "title": .string("New title"), "notes": .string("New notes"),
        "dueDate": .string("2026-02-22T16:00:00Z"), "isCompleted": .bool(true), "priority": .number(9),
    ])
    try updated.apply(to: reminder, in: store)
    #expect(reminder.title == "New title")
    #expect(reminder.notes == "New notes")
    #expect(reminder.dueDateComponents?.date == CodeModeDate.parse("2026-02-22T16:00:00Z"))
    #expect(reminder.isCompleted)
    #expect(reminder.completionDate != nil)
    #expect(reminder.priority == 9)
}

@Test(arguments: ["start", "end", "dueDate"])
func eventKitWriteDateErrorsUseStandardRepairableMessages(argument: String) throws {
    let store = EKEventStore()
    do {
        if argument == "dueDate" {
            let decoded = try RemindersUpdateTool().decode(arguments: ["identifier": .string("ID"), argument: .string("soon")])
            try decoded.apply(to: EKReminder(eventStore: store), in: store)
        } else {
            let decoded = try CalendarUpdateEventTool().decode(arguments: ["identifier": .string("ID"), argument: .string("soon")])
            try decoded.apply(to: EKEvent(eventStore: store), in: store)
        }
        Issue.record("Expected an invalid patch date")
    } catch let error as BridgeError {
        let capability = argument == "dueDate" ? "reminders.write" : "calendar.write"
        #expect(error.diagnosticCode == "INVALID_ARGUMENTS")
        #expect(error.localizedDescription == "\(capability) could not parse '\(argument)' as an ISO 8601 timestamp: \"soon\". Use a form like 2026-07-24T10:00:00Z.")
    }
}
#endif

@Test(arguments: ["apple.calendar.updateEvent", "apple.reminders.updateReminder", "apple.reminders.completeReminder"])
func writeHelpersRequireIdentifiersBeforePermissions(helper: String) async throws {
    let (tools, sandbox) = try makeTools(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .denied, .calendarWriteOnly: .denied, .reminders: .denied,
    ]))
    defer { cleanup(sandbox) }
    let observed = try await execute(tools, request: JavaScriptExecutionRequest(
        code: "await \(helper)({ title: 'T', start: '2026-02-22T16:00:00Z', end: '2026-02-22T17:00:00Z' });",
        allowedCapabilities: [.calendarWrite, .remindersWrite]
    ))
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #expect(observed.error?.message.contains("missing required arguments: identifier") == true)
}

@Test func completeReminderDefaultsToCompletedAndAllowsReopening() throws {
    let tool = RemindersCompleteTool()
    #expect(try tool.decode(arguments: ["identifier": .string("R1")]).isCompleted)
    #expect(try tool.decode(arguments: ["identifier": .string("R1"), "isCompleted": .bool(false)]).isCompleted == false)
}

@Test(arguments: [
    ("apple.calendar.updateEvent", "title"),
    ("apple.calendar.updateEvent", "start"),
    ("apple.calendar.updateEvent", "end"),
    ("apple.calendar.updateEvent", "calendarIdentifier"),
    ("apple.reminders.updateReminder", "title"),
])
func updateFieldsThatCannotBeClearedRejectNullInJavaScript(helper: String, field: String) async throws {
    let (tools, sandbox) = try makeTools(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .denied, .reminders: .denied,
    ]))
    defer { cleanup(sandbox) }
    let observed = try await execute(tools, request: JavaScriptExecutionRequest(
        code: "await \(helper)({ identifier: 'ID', \(field): null });",
        allowedCapabilities: [.calendarWrite, .remindersWrite]
    ))
    let capability = helper.contains("calendar") ? "calendar.write" : "reminders.write"
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #expect(observed.error?.message == "\(capability) expected '\(field)' as string, received null")
    #expect(observed.error?.permissionEvents.isEmpty == true)
    let reference = try #require(tools.capabilities().first { $0.jsNames.contains(helper) })
    #expect(!reference.nullableArguments.contains(field))
    #expect(reference.dts.contains("\(field)?: string;"))
    #expect(!reference.dts.contains("\(field)?: string | null;"))
}

#if canImport(EventKit)
@Test(arguments: ["calendar", "reminders"])
func updateHelpersRequireAChangeAndCountPlainOptionalFields(family: String) async throws {
    let (tools, sandbox) = try makeTools(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .granted, .reminders: .granted,
    ]))
    defer { cleanup(sandbox) }
    let isCalendar = family == "calendar"
    let helper = isCalendar ? "apple.calendar.updateEvent" : "apple.reminders.updateReminder"
    let identifier = isCalendar ? "E1" : "R1"
    let item = isCalendar ? "event" : "reminder"
    for title in ["", ", title: 'T'"] {
        let observed = try await execute(tools, request: JavaScriptExecutionRequest(
            code: "await \(helper)({ identifier: '\(identifier)'\(title) });",
            allowedCapabilities: [.calendarWrite, .remindersWrite]
        ))
        #expect(observed.error?.code == "INVALID_ARGUMENTS")
        // These identifiers cannot resolve to native items. A title-only update
        // must pass change detection and reach lookup, without saving anything.
        let expected = title.isEmpty
            ? "\(family).write update requires at least one patch field"
            : "\(family).write could not find \(item) identifier \(identifier)"
        #expect(observed.error?.message == expected)
    }
}
#endif
