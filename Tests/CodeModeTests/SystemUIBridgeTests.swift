import Foundation
import Testing
@testable import CodeMode

@Test func systemUIBridgeUsesInjectedPresenterForSuccesses() throws {
    let bridge = SystemUIBridge()
    let presenter = FakeSystemUIPresenter(
        calendarResult: .object([
            "action": .string("saved"),
            "identifier": .string("event-1"),
            "title": .string("Standup"),
        ]),
        photosResult: .array([
            .object([
                "path": .string("/tmp/picked.jpg"),
                "artifactID": .string("artifact-1"),
                "mediaType": .string("image"),
                "uniformTypeIdentifier": .string("public.jpeg"),
                "bytes": .number(128),
            ]),
        ]),
        contactsResult: .array([
            .object([
                "identifier": .string("contact-1"),
                "givenName": .string("Alex"),
                "familyName": .string("Lee"),
                "organization": .string(""),
                "phones": .array([]),
                "emails": .array([.string("alex@example.com")]),
            ]),
        ]),
        extraResults: [
            .calendarUIPickCalendar: .array([.object(["identifier": .string("cal-1")])]),
            .calendarUIPresentEvent: .object(["action": .string("dismissed")]),
            .contactsUIPresentContact: .object(["action": .string("dismissed")]),
            .contactsUIPresentNewContact: .object(["action": .string("saved")]),
            .documentsUIPick: .array([.object(["artifactID": .string("document-1")])]),
            .documentsUIExport: .object(["action": .string("exported"), "count": .number(1)]),
            .documentsUIOpenIn: .object(["action": .string("sent"), "application": .string("com.example.viewer")]),
            .documentsUIScan: .array([.object(["artifactID": .string("scan-1")])]),
            .shareUIPresent: .object(["completed": .bool(true)]),
            .quickLookUIPreview: .object(["action": .string("dismissed")]),
            .cameraUICapture: .object(["artifactID": .string("camera-1")]),
            .cameraUIScanData: .object(["action": .string("recognized"), "items": .array([.object(["type": .string("barcode")])])]),
            .mailUICompose: .object(["action": .string("sent")]),
            .messagesUICompose: .object(["action": .string("sent")]),
            .printUIPresent: .object(["action": .string("completed"), "completed": .bool(true)]),
            .webUIPresent: .object(["action": .string("dismissed")]),
            .authUIWebAuthenticate: .object(["action": .string("callback")]),
            .uiAlertPresent: .object(["action": .string("selected"), "buttonID": .string("ok")]),
            .uiPromptPresent: .object(["action": .string("selected"), "values": .object(["name": .string("Alex")])]),
            .photosUIPresentLimitedLibraryPicker: .object(["action": .string("completed")]),
            .settingsUIOpen: .object(["action": .string("opened"), "opened": .bool(true)]),
        ]
    )

    let (context, sandbox) = try makeInvocationContext(systemUIPresenter: presenter)
    defer { cleanup(sandbox) }

    let calendar = try bridge.presentNewCalendarEvent(
        arguments: [
            "title": .string("Standup"),
            "start": .string("2026-02-22T16:00:00Z"),
            "end": .string("2026-02-22T16:15:00Z"),
        ],
        context: context
    )
    #expect(calendar.objectValue?.string("identifier") == "event-1")

    let photos = try requireArray(
        bridge.pickPhotos(arguments: ["mediaType": .string("image"), "limit": .number(1)], context: context)
    )
    #expect(photos.first?.objectValue?.string("artifactID") == "artifact-1")

    let contacts = try requireArray(
        bridge.pickContacts(arguments: ["mode": .string("single")], context: context)
    )
    #expect(contacts.first?.objectValue?.string("givenName") == "Alex")

    let calendars = try requireArray(bridge.pickCalendar(arguments: [:], context: context))
    #expect(calendars.first?.objectValue?.string("identifier") == "cal-1")
    let eventView = try bridge.presentCalendarEvent(arguments: ["identifier": .string("event-1")], context: context)
    #expect(eventView.objectValue?.string("action") == "dismissed")
    let contactView = try bridge.presentContact(arguments: ["identifier": .string("contact-1")], context: context)
    #expect(contactView.objectValue?.string("action") == "dismissed")
    let newContact = try bridge.presentNewContact(arguments: [:], context: context)
    #expect(newContact.objectValue?.string("action") == "saved")
    let documents = try requireArray(bridge.pickDocuments(arguments: ["contentTypes": .array([.string("public.item")])], context: context))
    #expect(documents.first?.objectValue?.string("artifactID") == "document-1")
    let export = try bridge.exportDocuments(arguments: ["path": .string("tmp:report.pdf")], context: context)
    #expect(export.objectValue?.string("action") == "exported")
    let openIn = try bridge.openDocument(arguments: ["path": .string("tmp:report.pdf")], context: context)
    #expect(openIn.objectValue?.string("application") == "com.example.viewer")
    let scans = try requireArray(bridge.scanDocuments(arguments: [:], context: context))
    #expect(scans.first?.objectValue?.string("artifactID") == "scan-1")
    let share = try bridge.presentShareSheet(arguments: ["text": .string("hello")], context: context)
    #expect(share.objectValue?.bool("completed") == true)
    let preview = try bridge.previewQuickLook(arguments: ["path": .string("tmp:report.pdf")], context: context)
    #expect(preview.objectValue?.string("action") == "dismissed")
    let camera = try bridge.captureCamera(arguments: ["mediaType": .string("image")], context: context)
    #expect(camera.objectValue?.string("artifactID") == "camera-1")
    let scanData = try bridge.scanData(arguments: ["mode": .string("barcode")], context: context)
    #expect(scanData.objectValue?.string("action") == "recognized")
    let mail = try bridge.composeMail(arguments: ["to": .array([.string("alex@example.com")])], context: context)
    #expect(mail.objectValue?.string("action") == "sent")
    let message = try bridge.composeMessage(arguments: ["recipients": .array([.string("4085551212")])], context: context)
    #expect(message.objectValue?.string("action") == "sent")
    let print = try bridge.presentPrint(arguments: ["path": .string("tmp:report.pdf")], context: context)
    #expect(print.objectValue?.bool("completed") == true)
    let web = try bridge.presentWeb(arguments: ["url": .string("https://example.com")], context: context)
    #expect(web.objectValue?.string("action") == "dismissed")
    let auth = try bridge.authenticateWeb(arguments: ["url": .string("https://example.com/oauth")], context: context)
    #expect(auth.objectValue?.string("action") == "callback")
    let alert = try bridge.presentAlert(
        arguments: ["buttons": .array([.object(["id": .string("ok"), "title": .string("OK")])])],
        context: context
    )
    #expect(alert.objectValue?.string("buttonID") == "ok")
    let prompt = try bridge.presentPrompt(
        arguments: [
            "fields": .array([.object(["id": .string("name"), "placeholder": .string("Name")])]),
            "buttons": .array([.object(["id": .string("ok"), "title": .string("OK")])]),
        ],
        context: context
    )
    #expect(prompt.objectValue?.object("values")?.string("name") == "Alex")
    let limited = try bridge.presentLimitedPhotoLibraryPicker(arguments: [:], context: context)
    #expect(limited.objectValue?.string("action") == "completed")
    let settings = try bridge.openSettings(arguments: [:], context: context)
    #expect(settings.objectValue?.bool("opened") == true)
}

@Test func systemUIBridgeDefaultPresenterIsStructuredFailure() throws {
    let bridge = SystemUIBridge()
    let (context, sandbox) = try makeInvocationContext()
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.pickContacts(arguments: [:], context: context)
        Issue.record("Expected missing presenter to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "UI_PRESENTER_UNAVAILABLE")
    }
}

@Test func systemUICapabilitiesRespectRegistryAllowlist() throws {
    let registration = try #require(
        DefaultCapabilityLoader.loadAllRegistrations()
            .first { $0.descriptor.id == .photosUIPick }
    )
    let registry = CapabilityRegistry(registrations: [registration])
    let (context, sandbox) = try makeInvocationContext(allowedCapabilities: [])
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke(CapabilityID.photosUIPick.rawValue, arguments: [:], context: context)
        Issue.record("Expected photos.ui.pick to require explicit allowlisting")
    } catch {
        #expect(requireBridgeErrorCode(error) == "CAPABILITY_DENIED")
    }
}

@Test func systemUIBridgeValidatesArgumentsBeforePresenter() throws {
    let bridge = SystemUIBridge()
    let presenter = FakeSystemUIPresenter()
    let (context, sandbox) = try makeInvocationContext(systemUIPresenter: presenter)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.presentNewCalendarEvent(arguments: ["start": .string("soon")], context: context)
        Issue.record("Expected invalid calendar start to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.pickPhotos(arguments: ["mediaType": .string("audio")], context: context)
        Issue.record("Expected invalid mediaType to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.pickContacts(arguments: ["displayedPropertyKeys": .array([.number(1)])], context: context)
        Issue.record("Expected invalid displayedPropertyKeys to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.pickCalendar(arguments: ["selectionStyle": .string("both")], context: context)
        Issue.record("Expected invalid calendar selectionStyle to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.pickDocuments(arguments: ["contentTypes": .array([.number(1)])], context: context)
        Issue.record("Expected invalid contentTypes to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.exportDocuments(arguments: [:], context: context)
        Issue.record("Expected document export with no path to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.openDocument(arguments: [:], context: context)
        Issue.record("Expected document openIn with no path to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentShareSheet(arguments: [:], context: context)
        Issue.record("Expected share sheet with no items to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.previewQuickLook(arguments: [:], context: context)
        Issue.record("Expected Quick Look with no path to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentPrint(arguments: ["path": .string("tmp:report.pdf"), "outputType": .string("thermal")], context: context)
        Issue.record("Expected invalid print outputType to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.scanData(arguments: ["mode": .string("qr")], context: context)
        Issue.record("Expected invalid scanData mode to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentWeb(arguments: ["url": .string("file:///tmp/a.html")], context: context)
        Issue.record("Expected non-HTTP web URL to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.composeMail(arguments: ["attachments": .array([.string("tmp:file.txt")])], context: context)
        Issue.record("Expected invalid attachment shape to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentAlert(arguments: ["buttons": .array([])], context: context)
        Issue.record("Expected empty alert buttons to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentAlert(
            arguments: [
                "buttons": .array([
                    .object(["title": .string("Cancel"), "style": .string("cancel")]),
                    .object(["title": .string("Stop"), "style": .string("cancel")]),
                ]),
            ],
            context: context
        )
        Issue.record("Expected duplicate cancel alert buttons to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    do {
        _ = try bridge.presentPrompt(
            arguments: [
                "fields": .array([]),
                "buttons": .array([.object(["title": .string("OK")])]),
            ],
            context: context
        )
        Issue.record("Expected prompt with no fields to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }
}

@Test func systemUIBridgeHonorsCancellationBeforePresentation() throws {
    let sandbox = try makeTestSandbox()
    defer { cleanup(sandbox) }

    let cancellationController = ExecutionCancellationController()
    cancellationController.cancel()
    let context = BridgeInvocationContext(
        executionContext: .init(userID: "test-user", sessionID: "test-session"),
        allowedCapabilities: Set(CapabilityID.allCases),
        pathPolicy: DefaultPathPolicy(
            config: PathPolicyConfig(tmpRoot: sandbox.tmp, cachesRoot: sandbox.caches, documentsRoot: sandbox.documents)
        ),
        artifactStore: InMemoryArtifactStore(),
        permissionBroker: NoopPermissionBroker(),
        auditLogger: SyncAuditLogger(),
        systemUIPresenter: FakeSystemUIPresenter(),
        transcript: ExecutionTranscript(),
        cancellationController: cancellationController
    )

    do {
        _ = try SystemUIBridge().pickPhotos(arguments: [:], context: context)
        Issue.record("Expected cancellation to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "CANCELLED")
    }
}

@Test func systemUIBridgePropagatesPresenterTimeout() throws {
    let bridge = SystemUIBridge()
    let presenter = FakeSystemUIPresenter(error: BridgeError.timeout(milliseconds: 10))
    let (context, sandbox) = try makeInvocationContext(systemUIPresenter: presenter)
    defer { cleanup(sandbox) }

    do {
        _ = try bridge.pickContacts(arguments: [:], context: context)
        Issue.record("Expected timeout to fail")
    } catch {
        #expect(requireBridgeErrorCode(error) == "EXECUTION_TIMEOUT")
    }
}

@Test func calendarUIPresentationRequiresWriteOnlyCalendarPermission() throws {
    let registration = try #require(
        DefaultCapabilityLoader.loadAllRegistrations()
            .first { $0.descriptor.id == .calendarUIPresentNewEvent }
    )
    let registry = CapabilityRegistry(registrations: [registration])
    let broker = FixedPermissionBroker(statuses: [.calendarWriteOnly: .denied])
    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: [.calendarUIPresentNewEvent],
        systemUIPresenter: FakeSystemUIPresenter()
    )
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke(
            CapabilityID.calendarUIPresentNewEvent.rawValue,
            arguments: [:],
            context: context
        )
        Issue.record("Expected calendar write-only permission denial")
    } catch {
        #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
    }
}

@Test func expandedSystemUIPermissionsAreCheckedByRegistry() throws {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations().filter {
        [.calendarUIPickCalendar, .calendarUIPresentEvent, .contactsUIPresentContact, .contactsUIPresentNewContact].contains($0.descriptor.id)
    }
    let registry = CapabilityRegistry(registrations: registrations)
    let broker = FixedPermissionBroker(statuses: [
        .calendarWriteOnly: .denied,
        .calendar: .denied,
        .contacts: .denied,
    ])
    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: Set(registrations.map(\.descriptor.id)),
        systemUIPresenter: FakeSystemUIPresenter()
    )
    defer { cleanup(sandbox) }

    let argumentsByCapability: [CapabilityID: [String: JSONValue]] = [
        .calendarUIPickCalendar: [:],
        .calendarUIPresentEvent: ["identifier": .string("event-id")],
        .contactsUIPresentContact: ["identifier": .string("contact-id")],
        .contactsUIPresentNewContact: [:],
    ]

    for capability in registrations.map(\.descriptor.id) {
        do {
            _ = try registry.invoke(capability.rawValue, arguments: argumentsByCapability[capability] ?? [:], context: context)
            Issue.record("Expected permission denial for \(capability.rawValue)")
        } catch {
            #expect(requireBridgeErrorCode(error) == "PERMISSION_DENIED")
        }
    }
}

private struct FakeSystemUIPresenter: SystemUIPresenter {
    var calendarResult: JSONValue
    var photosResult: JSONValue
    var contactsResult: JSONValue
    var extraResults: [CapabilityID: JSONValue]
    var error: BridgeError?

    init(
        calendarResult: JSONValue = .object(["action": .string("cancelled")]),
        photosResult: JSONValue = .array([]),
        contactsResult: JSONValue = .array([]),
        extraResults: [CapabilityID: JSONValue] = [:],
        error: BridgeError? = nil
    ) {
        self.calendarResult = calendarResult
        self.photosResult = photosResult
        self.contactsResult = contactsResult
        self.extraResults = extraResults
        self.error = error
    }

    func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        if let error { throw error }
        return calendarResult
    }

    func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        if let error { throw error }
        return photosResult
    }

    func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        if let error { throw error }
        return contactsResult
    }

    func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .calendarUIPickCalendar, arguments: arguments, context: context)
    }

    func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .calendarUIPresentEvent, arguments: arguments, context: context)
    }

    func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .contactsUIPresentContact, arguments: arguments, context: context)
    }

    func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .contactsUIPresentNewContact, arguments: arguments, context: context)
    }

    func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIPick, arguments: arguments, context: context)
    }

    func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIExport, arguments: arguments, context: context)
    }

    func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIOpenIn, arguments: arguments, context: context)
    }

    func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIScan, arguments: arguments, context: context)
    }

    func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .shareUIPresent, arguments: arguments, context: context)
    }

    func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .quickLookUIPreview, arguments: arguments, context: context)
    }

    func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .cameraUICapture, arguments: arguments, context: context)
    }

    func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .cameraUIScanData, arguments: arguments, context: context)
    }

    func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .mailUICompose, arguments: arguments, context: context)
    }

    func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .messagesUICompose, arguments: arguments, context: context)
    }

    func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .printUIPresent, arguments: arguments, context: context)
    }

    func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .webUIPresent, arguments: arguments, context: context)
    }

    func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .authUIWebAuthenticate, arguments: arguments, context: context)
    }

    func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .uiAlertPresent, arguments: arguments, context: context)
    }

    func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .uiPromptPresent, arguments: arguments, context: context)
    }

    func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .photosUIPresentLimitedLibraryPicker, arguments: arguments, context: context)
    }

    func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .settingsUIOpen, arguments: arguments, context: context)
    }

    private func result(for capability: CapabilityID, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        if let error { throw error }
        return extraResults[capability] ?? .object(["action": .string("cancelled")])
    }
}
