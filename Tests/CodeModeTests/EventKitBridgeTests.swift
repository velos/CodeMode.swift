import Foundation
import Testing
@testable import CodeMode

@Test func eventKitCalendarOperationsRequirePermission() throws {
    let bridge = EventKitBridge()
    let broker = FixedPermissionBroker(statuses: [
        .calendar: .denied,
        .calendarWriteOnly: .denied,
    ])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.readEvents(arguments: [:], context: context)
        Issue.record("Expected permission denial for calendar.read")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.writeEvent(arguments: [:], context: context)
        Issue.record("Expected permission denial for calendar.write")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.writeEvent(arguments: [
            "operation": .string("update"),
            "identifier": .string("event-1"),
            "title": .string("Updated"),
        ], context: context)
        Issue.record("Expected permission denial for calendar.write update")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.deleteEvent(arguments: ["identifier": .string("event-1")], context: context)
        Issue.record("Expected permission denial for calendar.delete")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func eventKitReminderOperationsRequirePermission() throws {
    let bridge = EventKitBridge()
    let broker = FixedPermissionBroker(statuses: [.reminders: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.readReminders(arguments: [:], context: context)
        Issue.record("Expected permission denial for reminders.read")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.writeReminder(arguments: [:], context: context)
        Issue.record("Expected permission denial for reminders.write")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.deleteReminder(arguments: ["identifier": .string("reminder-1")], context: context)
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

@Test func executeCalendarWriteUsesWriteOnlyPermissionPath() async throws {
    let broker = FixedPermissionBroker(
        statuses: [.calendarWriteOnly: .notDetermined],
        requestStatuses: [.calendarWriteOnly: .granted]
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
