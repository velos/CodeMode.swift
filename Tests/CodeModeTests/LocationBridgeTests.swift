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
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            const status = await ios.location.getPermissionStatus();
            return { status };
            """,
            allowedCapabilities: [.locationRead]
        )
    )

    #expect(response.diagnostics.isEmpty)
    let payload = try requireJSONObject(from: response)
    #expect(payload["status"] as? String == PermissionStatus.unavailable.rawValue)
}
