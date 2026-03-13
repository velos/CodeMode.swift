import Foundation
import Testing
@testable import CodeMode

@Test func contactsOperationsRequirePermission() throws {
    let bridge = ContactsBridge()
    let broker = FixedPermissionBroker(statuses: [.contacts: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: [:], context: context)
        Issue.record("Expected contacts.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.search(arguments: ["query": .string("alex")], context: context)
        Issue.record("Expected contacts.search to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func contactsSearchValidatesQueryWhenAuthorized() throws {
    let bridge = ContactsBridge()
    let broker = FixedPermissionBroker(statuses: [.contacts: .granted])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.search(arguments: [:], context: context)
        Issue.record("Expected query validation failure")
    } catch {
        #if canImport(Contacts)
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
        #else
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
        #endif
    }
}

@Test func executeUsesContactsBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.contacts: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.contacts.search({ query: 'alex' });
            return { ok: true };
            """,
            allowedCapabilities: [.contactsSearch]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}
