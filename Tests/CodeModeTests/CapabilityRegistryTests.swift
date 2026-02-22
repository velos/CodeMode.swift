import Foundation
import Testing
@testable import CodeMode

@Test func defaultCapabilityLoaderCoversAllCapabilityIDs() {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
    let loaded = Set(registrations.map { $0.descriptor.id })
    let expected = Set(CapabilityID.allCases)

    #expect(loaded == expected)
}

@Test func registryRequestsPermissionWhenNotDetermined() throws {
    let descriptor = CapabilityDescriptor(
        id: .contactsRead,
        title: "Contacts",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredPermissions: [.contacts]
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let broker = FixedPermissionBroker(
        statuses: [.contacts: .notDetermined],
        requestStatuses: [.contacts: .granted]
    )

    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: [.contactsRead]
    )
    defer { cleanup(sandbox) }

    let value = try registry.invoke("contacts.read", arguments: [:], context: context)
    #expect(value.stringValue == "ok")

    let statuses = context.allPermissionEvents().map { $0.status }
    #expect(statuses == [.notDetermined, .granted])
}

@Test func registryValidationBlocksMissingRequiredArgsBeforePermissionChecks() throws {
    let descriptor = CapabilityDescriptor(
        id: .contactsSearch,
        title: "Contacts Search",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredPermissions: [.contacts],
        requiredArguments: ["query"]
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let broker = FixedPermissionBroker(
        statuses: [.contacts: .notDetermined],
        requestStatuses: [.contacts: .granted]
    )

    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: [.contactsSearch]
    )
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke("contacts.search", arguments: [:], context: context)
        Issue.record("Expected missing required argument validation to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    #expect(context.allPermissionEvents().isEmpty)
}

@Test func registryValidationRejectsWrongArgumentType() throws {
    let descriptor = CapabilityDescriptor(
        id: .weatherRead,
        title: "Weather",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredArguments: ["latitude", "longitude"],
        argumentTypes: [
            "latitude": .number,
            "longitude": .number,
        ]
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let (context, sandbox) = try makeInvocationContext(
        allowedCapabilities: [.weatherRead]
    )
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke(
            "weather.read",
            arguments: ["latitude": .string("37.0"), "longitude": .number(-122.0)],
            context: context
        )
        Issue.record("Expected type mismatch validation to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func registryValidationRejectsUnknownArguments() throws {
    let descriptor = CapabilityDescriptor(
        id: .fsRead,
        title: "Read file",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredArguments: ["path"],
        optionalArguments: ["encoding"],
        argumentTypes: [
            "path": .string,
            "encoding": .string,
        ]
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let (context, sandbox) = try makeInvocationContext(
        allowedCapabilities: [.fsRead]
    )
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke(
            "fs.read",
            arguments: ["path": .string("tmp:file.txt"), "extra": .string("boom")],
            context: context
        )
        Issue.record("Expected unknown argument validation to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}
