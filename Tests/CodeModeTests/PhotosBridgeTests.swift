import Foundation
import Testing
@testable import CodeMode

@Test func photosOperationsRequirePermission() throws {
    let bridge = PhotosBridge()
    let broker = FixedPermissionBroker(statuses: [.photoLibrary: .denied])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.read(arguments: [:], context: context)
        Issue.record("Expected photos.read to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }

    do {
        _ = try bridge.export(arguments: ["localIdentifier": .string("asset-1")], context: context)
        Issue.record("Expected photos.export to require permission")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func photosExportValidatesLocalIdentifierWhenAuthorized() throws {
    let bridge = PhotosBridge()
    let broker = FixedPermissionBroker(statuses: [.photoLibrary: .granted])
    let (context, sandbox) = try makeInvocationContext(permissionBroker: broker)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.export(arguments: [:], context: context)
        Issue.record("Expected photos.export localIdentifier validation failure")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func executeUsesPhotosBridgeWithPermissionDenial() async throws {
    let broker = FixedPermissionBroker(statuses: [.photoLibrary: .denied])
    let (tools, sandbox) = try makeTools(permissionBroker: broker)
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.photos.list({ limit: 1 });
            return { ok: true };
            """,
            allowedCapabilities: [.photosRead]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
}
