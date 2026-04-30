import Foundation
import Testing
@testable import CodeMode

@Test func defaultCapabilityLoaderCoversAllCapabilityIDs() {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
    let loaded = Set(registrations.map { $0.descriptor.id })
    let expected = Set(CapabilityID.allCases)

    #expect(loaded == expected)
}

@Test func platformSupportFilterMatchesCurrentPlatform() {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
    let filtered = CapabilityPlatformSupport.filter(registrations, for: .current)
    let loaded = Set(filtered.map { $0.descriptor.id })
    let expected = CapabilityPlatformSupport.supportedCapabilities(for: .current)

    #expect(loaded == expected)
}

@Test func systemUICapabilitiesArePlatformScoped() {
    let sharedUICapabilities: Set<CapabilityID> = [
        .calendarUIPickCalendar,
        .calendarUIPresentEvent,
        .calendarUIPresentNewEvent,
        .contactsUIPick,
        .contactsUIPresentContact,
        .contactsUIPresentNewContact,
        .photosUIPick,
        .documentsUIPick,
        .shareUIPresent,
        .quickLookUIPreview,
        .webUIPresent,
        .authUIWebAuthenticate,
        .uiAlertPresent,
    ]
    let iOSOnlyUICapabilities: Set<CapabilityID> = [
        .documentsUIScan,
        .cameraUICapture,
        .mailUICompose,
        .messagesUICompose,
    ]
    let allUICapabilities = sharedUICapabilities.union(iOSOnlyUICapabilities)

    #expect(allUICapabilities.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .iOS)))
    #expect(sharedUICapabilities.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .visionOS)))
    #expect(CapabilityPlatformSupport.supportedCapabilities(for: .visionOS).isDisjoint(with: iOSOnlyUICapabilities))
    #expect(CapabilityPlatformSupport.supportedCapabilities(for: .macOS).isDisjoint(with: allUICapabilities))
    #expect(CapabilityPlatformSupport.supportedCapabilities(for: .watchOS).isDisjoint(with: allUICapabilities))
}

@Test func systemUIDescriptorsExposeExpectedJavaScriptNames() throws {
    let descriptors = Dictionary(
        uniqueKeysWithValues: DefaultCapabilityLoader.loadAllRegistrations().map { ($0.descriptor.id, $0.descriptor) }
    )

    let calendar = try #require(descriptors[.calendarUIPresentNewEvent])
    #expect(calendar.requiredPermissions == [.calendarWriteOnly])
    #expect(JavaScriptBindingCatalog.names(for: .calendarUIPresentNewEvent) == ["apple.calendar.presentNewEvent"])

    let contacts = try #require(descriptors[.contactsUIPick])
    #expect(contacts.requiredPermissions.isEmpty)
    #expect(JavaScriptBindingCatalog.names(for: .contactsUIPick) == ["apple.contacts.pick"])

    let photos = try #require(descriptors[.photosUIPick])
    #expect(photos.requiredPermissions.isEmpty)
    #expect(JavaScriptBindingCatalog.names(for: .photosUIPick) == ["apple.photos.pick"])

    #expect(descriptors[.documentsUIPick]?.requiredPermissions.isEmpty == true)
    #expect(JavaScriptBindingCatalog.names(for: .documentsUIPick) == ["apple.documents.pick"])
    #expect(JavaScriptBindingCatalog.names(for: .documentsUIScan) == ["apple.documents.scan"])
    #expect(JavaScriptBindingCatalog.names(for: .shareUIPresent) == ["apple.share.present"])
    #expect(JavaScriptBindingCatalog.names(for: .quickLookUIPreview) == ["apple.quicklook.preview"])
    #expect(JavaScriptBindingCatalog.names(for: .cameraUICapture) == ["apple.camera.capture"])
    #expect(JavaScriptBindingCatalog.names(for: .mailUICompose) == ["apple.mail.compose"])
    #expect(JavaScriptBindingCatalog.names(for: .messagesUICompose) == ["apple.messages.compose"])
    #expect(JavaScriptBindingCatalog.names(for: .webUIPresent) == ["apple.web.present"])
    #expect(JavaScriptBindingCatalog.names(for: .authUIWebAuthenticate) == ["apple.auth.webAuthenticate"])
    #expect(JavaScriptBindingCatalog.names(for: .uiAlertPresent) == ["apple.ui.presentAlert"])

    #expect(descriptors[.calendarUIPickCalendar]?.requiredPermissions == [.calendarWriteOnly])
    #expect(descriptors[.calendarUIPresentEvent]?.requiredPermissions == [.calendar])
    #expect(JavaScriptBindingCatalog.names(for: .calendarUIPickCalendar) == ["apple.calendar.pickCalendar"])
    #expect(JavaScriptBindingCatalog.names(for: .calendarUIPresentEvent) == ["apple.calendar.presentEvent"])

    #expect(descriptors[.contactsUIPresentContact]?.requiredPermissions == [.contacts])
    #expect(descriptors[.contactsUIPresentNewContact]?.requiredPermissions == [.contacts])
    #expect(JavaScriptBindingCatalog.names(for: .contactsUIPresentContact) == ["apple.contacts.presentContact"])
    #expect(JavaScriptBindingCatalog.names(for: .contactsUIPresentNewContact) == ["apple.contacts.presentNewContact"])
}

@Test func filesystemListDescriptorDocumentsEntryObjects() throws {
    let descriptor = try #require(
        DefaultCapabilityLoader.loadAllRegistrations()
            .map(\.descriptor)
            .first { $0.id == .fsList }
    )

    #expect(descriptor.summary.contains("entry objects"))
    #expect(descriptor.resultSummary.contains("entry.name"))
    #expect(descriptor.resultSummary.contains("fs.promises.readdir"))
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
