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
}

@Test func executeUsesCalendarBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.calendar: .denied])
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.calendar.listEvents({});
            return { ok: true };
            """,
            allowedCapabilities: [.calendarRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "PERMISSION_DENIED" }))
}

@Test func executeCalendarWriteUsesWriteOnlyPermissionPath() async throws {
    let broker = FixedPermissionBroker(
        statuses: [.calendarWriteOnly: .notDetermined],
        requestStatuses: [.calendarWriteOnly: .granted]
    )
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.calendar.createEvent({});
            return { ok: true };
            """,
            allowedCapabilities: [.calendarWrite]
        )
    )

    #if canImport(EventKit)
    #expect(response.diagnostics.contains(where: { $0.code == "INVALID_ARGUMENTS" }))
    #expect(response.diagnostics.contains(where: { $0.code == "PERMISSION_DENIED" }) == false)
    #else
    #expect(response.diagnostics.contains(where: { $0.code == "UNSUPPORTED_PLATFORM" }))
    #endif
}

@Test func executeUsesReminderBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.reminders: .denied])
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.reminders.listReminders({});
            return { ok: true };
            """,
            allowedCapabilities: [.remindersRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "PERMISSION_DENIED" }))
}
