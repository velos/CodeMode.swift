import Foundation
import Testing
@testable import CodeMode

@Test func notificationsScheduleReadDeleteRequirePermission() throws {
    let bridge = NotificationsBridge()
    let broker = FixedPermissionBroker(statuses: [.notifications: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.schedule(arguments: ["title": .string("hello")], context: context)
        Issue.record("Expected notifications.schedule to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.readPending(arguments: [:], context: context)
        Issue.record("Expected notifications.pending.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.deletePending(arguments: [:], context: context)
        Issue.record("Expected notifications.pending.delete to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func notificationsRequestPermissionUsesBrokerRequestStatus() throws {
    let bridge = NotificationsBridge()
    let broker = FixedPermissionBroker(
        statuses: [.notifications: .notDetermined],
        requestStatuses: [.notifications: .granted]
    )
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let value = try bridge.requestPermission(context: context)
    let object = try requireObject(value)
    #expect(object.string("status") == PermissionStatus.granted.rawValue)
    #expect(object.bool("granted") == true)
}

@Test func executeUsesNotificationsBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.notifications: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await ios.notifications.schedule({ title: 'Hydrate', body: 'Drink water', secondsFromNow: 60 });
            return { ok: true };
            """,
            allowedCapabilities: [.notificationsSchedule]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}
