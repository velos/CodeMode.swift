import Foundation
import Testing
@testable import CodeMode

@Test func homeOperationsRequirePermission() throws {
    let bridge = HomeBridge()
    let broker = FixedPermissionBroker(statuses: [.homeKit: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: [:], context: context)
        Issue.record("Expected home.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.write(arguments: [
            "accessoryIdentifier": .string("acc-1"),
            "characteristicType": .string("HMCharacteristicTypePowerState"),
            "value": .bool(true),
        ], context: context)
        Issue.record("Expected home.write to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func homeWriteValidatesRequiredArgumentsBeforePermission() throws {
    let bridge = HomeBridge()
    let broker = FixedPermissionBroker(statuses: [.homeKit: .granted])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.write(arguments: [:], context: context)
        Issue.record("Expected home.write to require arguments")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func executeUsesHomeBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.homeKit: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.home.list({ includeCharacteristics: true, limit: 3 });
            return { ok: true };
            """,
            allowedCapabilities: [.homeRead]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}
