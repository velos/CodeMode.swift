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
        ])
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

private struct FakeSystemUIPresenter: SystemUIPresenter {
    var calendarResult: JSONValue
    var photosResult: JSONValue
    var contactsResult: JSONValue
    var error: BridgeError?

    init(
        calendarResult: JSONValue = .object(["action": .string("cancelled")]),
        photosResult: JSONValue = .array([]),
        contactsResult: JSONValue = .array([]),
        error: BridgeError? = nil
    ) {
        self.calendarResult = calendarResult
        self.photosResult = photosResult
        self.contactsResult = contactsResult
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
}
