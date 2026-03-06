import Foundation
import Testing
@testable import CodeMode

@Test func locationPermissionStatusReflectsBroker() throws {
    let bridge = LocationBridge()
    let broker = FixedPermissionBroker(statuses: [.locationWhenInUse: .unavailable])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let result = try bridge.read(arguments: ["mode": .string("permissionStatus")], context: context)
    #expect(result.stringValue == PermissionStatus.unavailable.rawValue)
}

@Test func locationCurrentPositionDeniedWithoutPermission() throws {
    let bridge = LocationBridge()
    let broker = FixedPermissionBroker(statuses: [.locationWhenInUse: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: ["mode": .string("current")], context: context)
        Issue.record("Expected permission denied")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func locationRequestPermissionUsesRequestStatus() throws {
    let bridge = LocationBridge()
    let broker = FixedPermissionBroker(
        statuses: [.locationWhenInUse: .notDetermined],
        requestStatuses: [.locationWhenInUse: .granted]
    )

    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let status = bridge.requestPermission(context: context)
    #expect(status.stringValue == PermissionStatus.granted.rawValue)
}

@Test func executeUsesLocationBridgePermissionStatus() async throws {
    let broker = FixedPermissionBroker(statuses: [.locationWhenInUse: .unavailable])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const status = await ios.location.getPermissionStatus();
            return { status };
            """,
            allowedCapabilities: [.locationRead]
        )
    )

    let payload = try requireJSONObject(from: try #require(observed.result))
    #expect(payload["status"] as? String == PermissionStatus.unavailable.rawValue)
}
