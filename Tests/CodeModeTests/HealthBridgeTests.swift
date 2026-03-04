import Foundation
import Testing
@testable import CodeMode

@Test func healthOperationsRequirePermission() throws {
    let bridge = HealthBridge()
    let broker = FixedPermissionBroker(statuses: [.healthKit: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: ["type": .string("stepCount")], context: context)
        Issue.record("Expected health.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.write(arguments: ["type": .string("stepCount"), "value": .number(1200)], context: context)
        Issue.record("Expected health.write to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func healthReadAndWriteValidateRequiredArguments() throws {
    let bridge = HealthBridge()
    let broker = FixedPermissionBroker(statuses: [.healthKit: .granted])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: [:], context: context)
        Issue.record("Expected health.read to require type")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.write(arguments: ["type": .string("stepCount")], context: context)
        Issue.record("Expected health.write to require numeric value")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func executeUsesHealthBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.healthKit: .denied])
    let (host, sandbox) = try makeHost(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.health.read({ type: 'stepCount', limit: 1 });
            return { ok: true };
            """,
            allowedCapabilities: [.healthRead]
        )
    )

    #expect(response.diagnostics.contains(where: { $0.code == "PERMISSION_DENIED" }))
}
