import Foundation
import JavaScriptCore
import Testing
@testable import CodeMode


private func jsNames(for capability: CapabilityID) -> [String] {
    DefaultCapabilityLoader.loadAllRegistrations()
        .first { $0.descriptor.id == capability }?
        .jsNames ?? []
}

@Test func defaultCapabilityLoaderCoversAllCapabilityIDs() {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
    let loaded = Set(registrations.map { $0.descriptor.id })
    let expected = Set(CapabilityID.allCases)

    #expect(loaded == expected)
}

@Test func defaultCapabilityRegistrationsOwnJavaScriptNames() {
    let registrations = DefaultCapabilityLoader.loadAllRegistrations()
    let missingNames = registrations
        .filter { $0.jsNames.isEmpty }
        .map(\.descriptor.id.rawValue)

    #expect(missingNames.isEmpty)
}

@Test func hardcodedBootstrapHelpersHaveRegistrationMetadata() throws {
    let context = try #require(JSContext())
    let invokeBlock: @convention(block) (String, String) -> String = { _, _ in
        #"{"ok":true,"value":null}"#
    }
    context.setObject(invokeBlock, forKeyedSubscript: "__bridgeInvokeSync" as NSString)
    #expect(context.evaluateScript(RuntimeJavaScript.bootstrap) != nil)

    let namesJSON = try #require(
        context.evaluateScript(
            """
            (function(){
                const roots = ["fetch", "apple", "ios", "fs"];
                const names = [];
                function visit(path, value) {
                    if (typeof value === "function") {
                        names.push(path);
                        return;
                    }
                    if (!value || typeof value !== "object") return;
                    Object.keys(value).forEach(function(key) {
                        visit(path ? path + "." + key : key, value[key]);
                    });
                }
                roots.forEach(function(root) { visit(root, globalThis[root]); });
                return JSON.stringify(names.sort());
            })()
            """
        )?.toString()
    )
    let hardcodedNames = try JSONDecoder().decode([String].self, from: Data(namesJSON.utf8))
    let registeredNames = Set(DefaultCapabilityLoader.loadAllRegistrations().flatMap(\.jsNames))
    let missingMetadata = hardcodedNames.filter { registeredNames.contains($0) == false }

    #expect(hardcodedNames.isEmpty == false)
    #expect(missingMetadata.isEmpty)
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
        .photosUIPresentLimitedLibraryPicker,
        .documentsUIPick,
        .documentsUIExport,
        .documentsUIOpenIn,
        .shareUIPresent,
        .quickLookUIPreview,
        .cameraUIScanData,
        .printUIPresent,
        .webUIPresent,
        .authUIWebAuthenticate,
        .uiAlertPresent,
        .uiPromptPresent,
        .settingsUIOpen,
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
    #expect(jsNames(for: .calendarUIPresentNewEvent) == ["apple.calendar.presentNewEvent"])

    let contacts = try #require(descriptors[.contactsUIPick])
    #expect(contacts.requiredPermissions.isEmpty)
    #expect(jsNames(for: .contactsUIPick) == ["apple.contacts.pick"])

    let photos = try #require(descriptors[.photosUIPick])
    #expect(photos.requiredPermissions.isEmpty)
    #expect(jsNames(for: .photosUIPick) == ["apple.photos.pick"])

    #expect(descriptors[.documentsUIPick]?.requiredPermissions.isEmpty == true)
    #expect(jsNames(for: .documentsUIPick) == ["apple.documents.pick"])
    #expect(jsNames(for: .documentsUIExport) == ["apple.documents.export", "apple.documents.save"])
    #expect(jsNames(for: .documentsUIOpenIn) == ["apple.documents.openIn"])
    #expect(jsNames(for: .documentsUIScan) == ["apple.documents.scan"])
    #expect(jsNames(for: .shareUIPresent) == ["apple.share.present"])
    #expect(jsNames(for: .quickLookUIPreview) == ["apple.quicklook.preview"])
    #expect(jsNames(for: .cameraUICapture) == ["apple.camera.capture"])
    #expect(jsNames(for: .cameraUIScanData) == ["apple.camera.scanData"])
    #expect(jsNames(for: .mailUICompose) == ["apple.mail.compose"])
    #expect(jsNames(for: .messagesUICompose) == ["apple.messages.compose"])
    #expect(jsNames(for: .printUIPresent) == ["apple.print.present"])
    #expect(jsNames(for: .webUIPresent) == ["apple.web.present"])
    #expect(jsNames(for: .authUIWebAuthenticate) == ["apple.auth.webAuthenticate"])
    #expect(jsNames(for: .uiAlertPresent) == ["apple.ui.presentAlert"])
    #expect(jsNames(for: .uiPromptPresent) == ["apple.ui.presentPrompt"])
    #expect(jsNames(for: .photosUIPresentLimitedLibraryPicker) == ["apple.photos.presentLimitedLibraryPicker"])
    #expect(jsNames(for: .settingsUIOpen) == ["apple.settings.open"])

    #expect(descriptors[.calendarUIPickCalendar]?.requiredPermissions == [.calendarWriteOnly])
    #expect(descriptors[.calendarUIPresentEvent]?.requiredPermissions == [.calendar])
    #expect(jsNames(for: .calendarUIPickCalendar) == ["apple.calendar.pickCalendar"])
    #expect(jsNames(for: .calendarUIPresentEvent) == ["apple.calendar.presentEvent"])

    #expect(descriptors[.contactsUIPresentContact]?.requiredPermissions == [.contacts])
    #expect(descriptors[.contactsUIPresentNewContact]?.requiredPermissions == [.contacts])
    #expect(jsNames(for: .contactsUIPresentContact) == ["apple.contacts.presentContact"])
    #expect(jsNames(for: .contactsUIPresentNewContact) == ["apple.contacts.presentNewContact"])
}

@Test func expandedAPIDescriptorsExposeExpectedJavaScriptNames() throws {
    let descriptors = Dictionary(
        uniqueKeysWithValues: DefaultCapabilityLoader.loadAllRegistrations().map { ($0.descriptor.id, $0.descriptor) }
    )

    let calendarWrite = try #require(descriptors[.calendarWrite])
    #expect(calendarWrite.requiredPermissions.isEmpty)
    #expect(calendarWrite.optionalArguments.contains("calendarIdentifier"))
    #expect(jsNames(for: .calendarWrite) == ["apple.calendar.createEvent", "apple.calendar.updateEvent"])

    let calendarDelete = try #require(descriptors[.calendarDelete])
    #expect(calendarDelete.requiredPermissions == [.calendar])
    #expect(calendarDelete.requiredArguments == ["identifier"])
    #expect(jsNames(for: .calendarDelete) == ["apple.calendar.deleteEvent"])

    let remindersWrite = try #require(descriptors[.remindersWrite])
    #expect(remindersWrite.optionalArguments.contains("isCompleted"))
    #expect(jsNames(for: .remindersWrite) == [
        "apple.reminders.createReminder",
        "apple.reminders.updateReminder",
        "apple.reminders.completeReminder",
    ])

    let remindersDelete = try #require(descriptors[.remindersDelete])
    #expect(remindersDelete.requiredArguments == ["identifier"])
    #expect(jsNames(for: .remindersDelete) == ["apple.reminders.deleteReminder"])

    let networkFetch = try #require(descriptors[.networkFetch])
    #expect(networkFetch.optionalArguments.contains("options.timeoutMs"))
    #expect(networkFetch.optionalArguments.contains("options.bodyBase64"))
    #expect(networkFetch.optionalArguments.contains("options.responseEncoding"))

    let notificationsSchedule = try #require(descriptors[.notificationsSchedule])
    #expect(notificationsSchedule.optionalArguments.contains("userInfo"))
    #expect(notificationsSchedule.optionalArguments.contains("threadIdentifier"))
    #expect(jsNames(for: .notificationsDeliveredRead) == ["apple.notifications.listDelivered"])
    #expect(jsNames(for: .notificationsDeliveredDelete) == ["apple.notifications.removeDelivered"])

    let cameraCapture = try #require(descriptors[.cameraUICapture])
    #expect(cameraCapture.optionalArguments.contains("cameraDevice"))
    #expect(cameraCapture.optionalArguments.contains("maximumDurationSeconds"))

    let scanData = try #require(descriptors[.cameraUIScanData])
    #expect(scanData.optionalArguments.contains("isGuidanceEnabled"))

    let alert = try #require(descriptors[.uiAlertPresent])
    #expect(alert.optionalArguments.contains("sourceRect"))
}

@Test func bigTicketAPIDescriptorsExposeExpectedJavaScriptNames() throws {
    let descriptors = Dictionary(
        uniqueKeysWithValues: DefaultCapabilityLoader.loadAllRegistrations().map { ($0.descriptor.id, $0.descriptor) }
    )

    let cloudKit = try #require(descriptors[.cloudKitRecordsQuery])
    #expect(cloudKit.requiredArguments == ["recordType"])
    #expect(cloudKit.optionalArguments.contains("database"))
    #expect(jsNames(for: .cloudKitRecordsQuery) == ["apple.cloudkit.queryRecords"])
    #expect(jsNames(for: .cloudKitSubscriptionEventsRead) == ["apple.cloudkit.listEvents"])

    let remote = try #require(descriptors[.notificationsRemoteRegister])
    #expect(remote.summary.contains("APNs"))
    #expect(jsNames(for: .notificationsRemoteTokenRead) == ["apple.notifications.getRemoteToken"])
    #expect(jsNames(for: .notificationsResponsesRead) == ["apple.notifications.listResponses"])

    let speechFile = try #require(descriptors[.speechFileTranscribe])
    #expect(speechFile.requiredPermissions == [.speechRecognition])
    #expect(speechFile.optionalArguments.contains("locale"))
    #expect(jsNames(for: .speechMicrophoneTranscribe) == ["apple.speech.transcribeMicrophone"])

    let appIntentRun = try #require(descriptors[.appIntentsRun])
    #expect(appIntentRun.requiredArguments == ["identifier"])
    #expect(jsNames(for: .appIntentsHandoffsRead) == ["apple.appIntents.listHandoffs"])

    let foundationGenerate = try #require(descriptors[.foundationModelsGenerate])
    #expect(foundationGenerate.requiredArguments == ["prompt"])
    #expect(jsNames(for: .foundationModelsExtract) == ["apple.foundationModels.extract"])

    let activityStart = try #require(descriptors[.activityStart])
    #expect(activityStart.requiredArguments == ["activityType", "attributes"])
    #expect(jsNames(for: .activityPushTokenRead) == ["apple.activity.getPushToken"])

    let mapsSearch = try #require(descriptors[.mapsSearch])
    #expect(mapsSearch.requiredArguments == ["query"])
    #expect(jsNames(for: .mapsRouteEstimate) == ["apple.maps.routeEstimate"])

    let musicLibrary = try #require(descriptors[.musicLibraryRead])
    #expect(musicLibrary.requiredPermissions == [.music])
    #expect(jsNames(for: .musicPlaybackControl) == ["apple.music.play"])

    let walletPayment = try #require(descriptors[.passKitApplePayPresent])
    #expect(walletPayment.argumentHints["confirmed"]?.contains("explicit user-visible confirmation") == true)
    #expect(jsNames(for: .passKitPassAdd) == ["apple.wallet.addPass"])

    let storePurchase = try #require(descriptors[.storeKitPurchase])
    #expect(storePurchase.requiredArguments == ["productID", "confirmed"])
    #expect(storePurchase.argumentHints["confirmed"]?.contains("explicit user-visible confirmation") == true)
    #expect(jsNames(for: .storeKitTransactionsRead) == ["apple.storekit.listTransactions"])
}

@Test func bigTicketCapabilitiesHaveExpectedPlatformScope() {
    let crossApple: Set<CapabilityID> = [
        .cloudKitRecordsQuery,
        .notificationsRemoteRegister,
        .speechFileTranscribe,
        .appIntentsRun,
        .foundationModelsGenerate,
        .mapsSearch,
        .musicCatalogSearch,
        .storeKitProductsRead,
    ]
    let iOSOnly: Set<CapabilityID> = [
        .activityStart,
        .activityPushTokenRead,
        .passKitPassAdd,
        .passKitApplePayPresent,
    ]

    #expect(crossApple.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .iOS)))
    #expect(crossApple.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .macOS)))
    #expect(crossApple.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .visionOS)))
    #expect(iOSOnly.isSubset(of: CapabilityPlatformSupport.supportedCapabilities(for: .iOS)))
    #expect(CapabilityPlatformSupport.supportedCapabilities(for: .macOS).isDisjoint(with: iOSOnly))
    #expect(CapabilityPlatformSupport.supportedCapabilities(for: .visionOS).isDisjoint(with: iOSOnly))
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

@Test func registryAcceptsCalendarWriteOnlyStatusForCalendarWriteOnlyPermission() throws {
    let descriptor = CapabilityDescriptor(
        id: .calendarWrite,
        title: "Calendar Write",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredPermissions: [.calendarWriteOnly]
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let broker = FixedPermissionBroker(statuses: [.calendarWriteOnly: .writeOnly])
    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: [.calendarWrite]
    )
    defer { cleanup(sandbox) }

    let value = try registry.invoke("calendar.write", arguments: [:], context: context)
    #expect(value.stringValue == "ok")
    #expect(context.allPermissionEvents().map(\.status) == [.writeOnly])
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

@Test func registryValidationRejectsDescriptorConstrainedValuesBeforePermissions() throws {
    let descriptor = CapabilityDescriptor(
        id: .musicPlaybackControl,
        title: "Music Playback",
        summary: "Test capability",
        tags: ["test"],
        example: "noop",
        requiredPermissions: [.music],
        requiredArguments: ["action"],
        // Explicit constraint so the test verifies constraint-before-permission
        // ordering without depending on any capability's central table row.
        argumentConstraints: CapabilityArgumentConstraints(allowedStringValues: ["action": ["play", "pause"]])
    )

    let registry = CapabilityRegistry(
        registrations: [
            CapabilityRegistration(descriptor: descriptor) { _, _ in
                .string("ok")
            }
        ]
    )

    let broker = FixedPermissionBroker(statuses: [.music: .denied])
    let (context, sandbox) = try makeInvocationContext(
        permissionBroker: broker,
        allowedCapabilities: [.musicPlaybackControl]
    )
    defer { cleanup(sandbox) }

    do {
        _ = try registry.invoke(
            "music.playback.control",
            arguments: ["action": .string("shuffleEverything")],
            context: context
        )
        Issue.record("Expected descriptor constraint validation to throw")
    } catch {
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
    }

    #expect(context.allPermissionEvents().isEmpty)
}

@Test func descriptorConstraintsAreExposedThroughCatalogReferences() throws {
    let registry = CapabilityRegistry(registrations: DefaultCapabilityLoader.loadAllRegistrations())
    let catalog = BridgeCatalog(registry: registry)

    let music = try #require(catalog.reference(for: .musicPlaybackControl))
    #expect(music.argumentConstraints.allowedStringValues["action"]?.contains("playCatalog") == true)

    let maps = try #require(catalog.reference(for: .mapsRouteEstimate))
    #expect(maps.argumentConstraints.allowedStringValues["transportType"] == ["automobile", "walking", "transit", "any"])

    let network = try #require(catalog.reference(for: .networkFetch))
    #expect(network.argumentConstraints.allowedStringValues["options.responseEncoding"] == ["text", "base64"])
}

@Test func noBuiltInRegistrationGatesOnHealthKitPermission() {
    // The default broker can never report .granted for HealthKit (read authorization
    // is opaque by design), so any registration declaring .healthKit in
    // requiredPermissions would fail closed unconditionally through the registry.
    // HealthBridge performs its own per-type authorization instead.
    for registration in DefaultCapabilityLoader.loadAllRegistrations() {
        #expect(
            registration.descriptor.requiredPermissions.contains(.healthKit) == false,
            "\(registration.descriptor.id.rawValue) must not gate on .healthKit via the registry"
        )
    }
}

@Test func constraintValidationMatchesCaseInsensitively() throws {
    // Exercises the generic CapabilityArgumentConstraints.validate matching,
    // constructed inline so it does not depend on any capability's table row
    // (those migrate to per-tool CodeModeStringEnums over time).
    let constraints = CapabilityArgumentConstraints(allowedStringValues: ["mode": ["single", "multiple"]])

    try constraints.validate(arguments: ["mode": .string("single")], capabilityName: "contacts.ui.pick")
    try constraints.validate(arguments: ["mode": .string("Single")], capabilityName: "contacts.ui.pick")
    try constraints.validate(arguments: ["mode": .string("MULTIPLE")], capabilityName: "contacts.ui.pick")

    #expect(throws: (any Error).self) {
        try constraints.validate(arguments: ["mode": .string("triple")], capabilityName: "contacts.ui.pick")
    }
}

@Test func calendarDeleteSpanConstraintAcceptsEverySpellingTheBridgeAccepts() throws {
    // The constraint now comes from CalendarEventSpan on the tool; the bridge
    // parses through the same enum, so advertised and accepted cannot drift.
    let registration = try #require(
        DefaultCapabilityLoader.loadAllRegistrations().first { $0.descriptor.id == .calendarDelete }
    )
    let constraints = registration.descriptor.argumentConstraints
    let advertised = try #require(constraints.allowedStringValues["span"])
    #expect(advertised.contains("thisEvent"))
    #expect(advertised.contains("futureEvents"))
    #expect(advertised.contains("this_event"))
    #expect(advertised.contains("future"))

    for spelling in advertised {
        try constraints.validate(
            arguments: ["span": .string(spelling)],
            capabilityName: "calendar.delete"
        )
        #expect(CalendarEventSpan.codeModeValue(matching: spelling) != nil)
        #expect(CalendarEventSpan.codeModeValue(matching: spelling.uppercased()) != nil)
    }

    #expect(throws: (any Error).self) {
        try constraints.validate(arguments: ["span": .string("allEvents")], capabilityName: "calendar.delete")
    }
    #expect(CalendarEventSpan.codeModeValue(matching: "allEvents") == nil)
}

@Test func constrainedArgumentMetadataIsCoherentForAllRegistrations() {
    // Every constrained top-level argument a registration advertises must be a
    // declared argument of that registration — catches metadata typos and
    // constraint entries that outlive a renamed argument.
    for registration in DefaultCapabilityLoader.loadAllRegistrations() {
        let descriptor = registration.descriptor
        let declared = Set(descriptor.requiredArguments + descriptor.optionalArguments)
        for (path, allowed) in descriptor.argumentConstraints.allowedStringValues {
            #expect(
                allowed.isEmpty == false,
                "\(descriptor.id.rawValue) advertises an empty allowed-value list for \(path)"
            )
            guard path.contains(".") == false else { continue }
            #expect(
                declared.contains(path),
                "\(descriptor.id.rawValue) constrains '\(path)' but does not declare it as an argument"
            )
        }
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
