import Foundation
import Testing
@testable import CodeMode

@Test func alarmOperationsRequirePermission() throws {
    let bridge = AlarmBridge()
    let broker = FixedPermissionBroker(statuses: [.alarmKit: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: [:], context: context)
        Issue.record("Expected alarm.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.schedule(arguments: ["title": .string("Wake up")], context: context)
        Issue.record("Expected alarm.schedule to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.cancel(arguments: [:], context: context)
        Issue.record("Expected alarm.cancel to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func alarmRequestPermissionUsesBrokerRequestStatus() throws {
    let bridge = AlarmBridge()
    let broker = FixedPermissionBroker(
        statuses: [.alarmKit: .notDetermined],
        requestStatuses: [.alarmKit: .granted]
    )
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let value = try bridge.requestPermission(context: context)
    let object = try requireObject(value)
    #expect(object.string("status") == PermissionStatus.granted.rawValue)
    #expect(object.bool("granted") == true)
}

@Test func executeUsesAlarmBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.alarmKit: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let response = try await tools.searchJavaScriptAPI(
        JavaScriptAPISearchRequest(
            code: """
            async () => {
                return {
                    capability: api.byCapability["alarm.schedule"] ?? null,
                    helper: api.byJSName["ios.alarm.schedule"] ?? null
                };
            }
            """
        )
    )

    let payload = try #require(response.result?.objectValue)

    if CapabilityPlatformSupport.isSupported(.alarmSchedule, for: .current) {
        #expect(payload["capability"] != .null)
        #expect(payload["helper"] != .null)

        let observed = try await execute(
            tools,
            request: JavaScriptExecutionRequest(
                code: """
                await ios.alarm.schedule({ title: 'Wake up', secondsFromNow: 60 });
                return { ok: true };
                """,
                allowedCapabilities: [.alarmSchedule]
            )
        )

        #expect(observed.error?.code == "PERMISSION_DENIED")
    } else {
        #expect(payload["capability"] == .null)
        #expect(payload["helper"] == .null)
    }
}
