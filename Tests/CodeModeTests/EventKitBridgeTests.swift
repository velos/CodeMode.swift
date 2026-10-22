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
        _ = try registry.invoke("calendar.write", arguments: [:], context: context)
        Issue.record("Expected permission denial for calendar.write")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try registry.invoke("calendar.write", arguments: [
            "operation": .string("update"),
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
        _ = try registry.invoke("reminders.write", arguments: [:], context: context)
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
            await apple.calendar.createEvent({});
            return { ok: true };
            """,
            allowedCapabilities: [.calendarWrite]
        )
    )

    #if canImport(EventKit)
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #expect(observed.error?.message == "calendar.write create requires title/start/end ISO8601")
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

    let json = try #require(EventKitBridge.eventJSONForTesting(event).objectValue)
    #expect(json.string("title") == "Orphaned")
    #expect(json.string("calendarIdentifier") == "")
    #expect(json.string("calendarTitle") == "")
    #expect(json.string("notes") == "")
}

@Test func reminderSerializationSurvivesAMissingTitle() throws {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)

    // `EKReminder.title` is `String!`.
    let json = try #require(EventKitBridge.reminderJSONForTesting(reminder).objectValue)
    #expect(json.string("title") == "")
    #expect(json.string("calendarIdentifier") == "")
    #expect(json.bool("isCompleted") == false)
}
#endif

@Test func eventKitOmittedArgumentsUseDeclaredDefaults() throws {
    let bridge = EventKitBridge()
    let events = try CalendarListEventsTool(eventKit: bridge).decode(arguments: [:])
    #expect(events.limit == 50)
    #expect(events.start == nil)
    #expect(events.end == nil)
    let reminders = try RemindersListTool(eventKit: bridge).decode(arguments: [:])
    #expect(reminders.limit == 50)
    #expect(reminders.includeCompleted == false)
    let deletion = try CalendarDeleteEventTool(eventKit: bridge).decode(arguments: ["identifier": .string("E1")])
    #expect(deletion.span == .thisEvent)

    let overrides = try RemindersListTool(eventKit: bridge).decode(arguments: ["limit": .number(3), "includeCompleted": .bool(true)])
    #expect(overrides.limit == 3)
    #expect(overrides.includeCompleted)
    let blank = try CalendarListEventsTool(eventKit: bridge).decode(arguments: ["start": .string("  "), "end": .string("")])
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
    (nil, nil, PermissionKind.calendarWriteOnly),
    (nil, "E1", .calendar),
    (nil, "", .calendar),
    ("create", "E1", .calendarWriteOnly),
    ("update", nil, .calendar),
    ("UPDATE", "E1", .calendar),
])
func eventKitWriteSelectsPermissionFromOperation(operation: String?, identifier: String?, expected: PermissionKind) throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let (context, sandbox) = try makeInvocationContext(permissionBroker: FixedPermissionBroker(statuses: [
        .calendar: .denied, .calendarWriteOnly: .denied,
    ]))
    defer { cleanup(sandbox) }
    var arguments: [String: JSONValue] = [:]
    arguments["operation"] = operation.map(JSONValue.string)
    arguments["identifier"] = identifier.map(JSONValue.string)
    do {
        _ = try registry.invoke("calendar.write", arguments: arguments, context: context)
        Issue.record("Expected operation-specific permission denial")
    } catch let error as BridgeError {
        #expect(error.diagnosticCode == "PERMISSION_DENIED")
        #expect(error.localizedDescription == "Permission denied: \(expected.rawValue)")
        #expect(context.allPermissionEvents().map(\.permission) == [expected])
    }
}

#if canImport(EventKit)
@Test func eventUpdatePatchDistinguishesNullFromOmission() throws {
    let bridge = EventKitBridge()
    let tool = CalendarWriteEventTool(eventKit: bridge)
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
    try bridge.applyEventPatch(arguments: omitted, to: event, in: store)
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
    try bridge.applyEventPatch(arguments: cleared, to: event, in: store)
    #expect(event.notes == nil)
    #expect(event.location == nil)
    #expect(event.url == nil)
    #expect(event.isAllDay == false)
    #expect(event.title == "Keep title")
}

@Test func reminderUpdatePatchDistinguishesNullFromOmission() throws {
    let bridge = EventKitBridge()
    let tool = RemindersWriteTool(eventKit: bridge)
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
    try bridge.applyReminderPatch(arguments: omitted, to: reminder, in: store)
    #expect(reminder.notes == "Keep notes")
    #expect(reminder.dueDateComponents != nil)
    #expect(reminder.isCompleted)
    #expect(reminder.completionDate == date)
    #expect(reminder.priority == 7)

    let cleared = try tool.decode(arguments: [
        "identifier": .string("R1"), "notes": .null, "dueDate": .null,
        "isCompleted": .null, "priority": .null,
    ])
    try bridge.applyReminderPatch(arguments: cleared, to: reminder, in: store)
    #expect(reminder.notes == nil)
    #expect(reminder.dueDateComponents == nil)
    #expect(reminder.isCompleted == false)
    #expect(reminder.completionDate == nil)
    #expect(reminder.priority == 7)
    #expect(reminder.title == "Keep title")
}

@Test(arguments: ["start", "end", "dueDate"])
func eventKitWriteDateErrorsRetainTheirOperationSpecificMessages(argument: String) throws {
    let bridge = EventKitBridge()
    let store = EKEventStore()
    do {
        if argument == "dueDate" {
            let decoded = try RemindersWriteTool(eventKit: bridge).decode(arguments: [argument: .string("soon")])
            try bridge.applyReminderPatch(arguments: decoded, to: EKReminder(eventStore: store), in: store)
        } else {
            let decoded = try CalendarWriteEventTool(eventKit: bridge).decode(arguments: [argument: .string("soon")])
            try bridge.applyEventPatch(arguments: decoded, to: EKEvent(eventStore: store), in: store)
        }
        Issue.record("Expected an invalid patch date")
    } catch let error as BridgeError {
        let capability = argument == "dueDate" ? "reminders.write" : "calendar.write"
        #expect(error.diagnosticCode == "INVALID_ARGUMENTS")
        #expect(error.localizedDescription == "\(capability) \(argument) must be ISO8601 when provided")
    }
}
#endif
