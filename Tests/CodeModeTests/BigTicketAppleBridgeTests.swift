import Foundation
import Testing
@testable import CodeMode

@Test func defaultCloudKitClientReportsUnsupportedPlatform() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.cloudkit.getAccountStatus();",
            allowedCapabilities: [.cloudKitAccountStatus]
        )
    )

    #expect(observed.error?.code == "UNSUPPORTED_PLATFORM")
}

@Test func systemCloudKitAndMapsClientsAreOptInConfigurationValues() {
    let configuration = CodeModeConfiguration(
        cloudKitClient: SystemCloudKitClient(),
        mapsClient: SystemMapsClient()
    )

    #expect(configuration.cloudKitClient is SystemCloudKitClient)
    #expect(configuration.mapsClient is SystemMapsClient)
}

@Test func eventInboxRoutesExistingInboxStyleReads() async throws {
    let (tools, sandbox) = try makeTools(eventInbox: FakeEventInbox())
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const cloud = await apple.cloudkit.listEvents({ limit: 2 });
            const notifications = await apple.notifications.listResponses({ limit: 3 });
            const handoffs = await apple.appIntents.listHandoffs({ limit: 4 });
            const transactions = await apple.storekit.listTransactions({ limit: 5 });
            return {
                cloud: cloud.source,
                notifications: notifications.source,
                handoffs: handoffs.source,
                transactions: transactions.source,
                transactionLimit: transactions.limit
            };
            """,
            allowedCapabilities: [
                .cloudKitSubscriptionEventsRead,
                .notificationsResponsesRead,
                .appIntentsHandoffsRead,
                .storeKitTransactionsRead,
            ]
        )
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["cloud"]?.stringValue == "cloudkit.subscription")
    #expect(output["notifications"]?.stringValue == "notifications.response")
    #expect(output["handoffs"]?.stringValue == "appintents.handoff")
    #expect(output["transactions"]?.stringValue == "storekit.transaction")
    #expect(output["transactionLimit"]?.intValue == 5)
}

@Test func unavailableEventInboxFallsBackToClientUnsupportedPlatform() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.cloudkit.listEvents({ limit: 1 });",
            allowedCapabilities: [.cloudKitSubscriptionEventsRead]
        )
    )

    #expect(observed.error?.code == "UNSUPPORTED_PLATFORM")
}

@Test func cloudKitAndMapsAdaptersForwardValidatedArguments() async throws {
    let (tools, sandbox) = try makeTools(
        cloudKitClient: FakeCloudKitClient(),
        mapsClient: FakeMapsClient()
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const records = await apple.cloudkit.queryRecords({ database: "private", recordType: "Task", limit: 2 });
            const places = await apple.maps.search({ query: "coffee", limit: 3 });
            const route = await apple.maps.routeEstimate({
                origin: { latitude: 37.33, longitude: -122.03 },
                destination: { latitude: 37.77, longitude: -122.42 },
                transportType: "walking"
            });
            return { recordType: records.recordType, database: records.database, query: places.query, limit: places.limit, transportType: route.transportType };
            """,
            allowedCapabilities: [.cloudKitRecordsQuery, .mapsSearch, .mapsRouteEstimate]
        )
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["recordType"]?.stringValue == "Task")
    #expect(output["database"]?.stringValue == "private")
    #expect(output["query"]?.stringValue == "coffee")
    #expect(output["limit"]?.intValue == 3)
    #expect(output["transportType"]?.stringValue == "walking")
}

@Test func cloudKitValidationHappensBeforeClientCalls() async throws {
    let (tools, sandbox) = try makeTools(cloudKitClient: FailingCloudKitClient())
    defer { cleanup(sandbox) }

    let invalidDatabase = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.cloudkit.queryRecords({ database: 'archive', recordType: 'Task' });",
            allowedCapabilities: [.cloudKitRecordsQuery]
        )
    )
    #expect(invalidDatabase.error?.code == "INVALID_ARGUMENTS")

    let invalidFields = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.cloudkit.saveRecord({ recordType: 'Task', fields: {} });",
            allowedCapabilities: [.cloudKitRecordSave]
        )
    )
    #expect(invalidFields.error?.code == "INVALID_ARGUMENTS")

    let invalidPredicate = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.cloudkit.queryRecords({ recordType: 'Task', predicate: 'TRUEPREDICATE' });",
            allowedCapabilities: [.cloudKitRecordsQuery]
        )
    )
    #expect(invalidPredicate.error?.code == "INVALID_ARGUMENTS")
}

@Test func bigTicketValidationRejectsMalformedArgumentsBeforePermissionsOrClients() async throws {
    let (tools, sandbox) = try makeTools(
        permissionBroker: FixedPermissionBroker(statuses: [.music: .denied]),
        hostPlatform: .iOS
    )
    defer { cleanup(sandbox) }

    let badCategories = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.notifications.setCategories({ categories: [{ actions: [{ identifier: 'done', title: 'Done' }] }] });",
            allowedCapabilities: [.notificationsCategoriesSet]
        )
    )
    #expect(badCategories.error?.code == "INVALID_ARGUMENTS")

    let badTransport = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            return await apple.maps.routeEstimate({
                origin: { latitude: 37.33, longitude: -122.03 },
                destination: { latitude: 37.77, longitude: -122.42 },
                transportType: "hoverboard"
            });
            """,
            allowedCapabilities: [.mapsRouteEstimate]
        )
    )
    #expect(badTransport.error?.code == "INVALID_ARGUMENTS")

    let emptyProducts = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.storekit.listProducts({ productIDs: [] });",
            allowedCapabilities: [.storeKitProductsRead]
        )
    )
    #expect(emptyProducts.error?.code == "INVALID_ARGUMENTS")

    let badDismissal = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.activity.end({ identifier: 'activity-1', dismissalPolicy: 'later' });",
            allowedCapabilities: [.activityEnd]
        )
    )
    #expect(badDismissal.error?.code == "INVALID_ARGUMENTS")

    let badMusic = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.music.play({ action: 'shuffleEverything' });",
            allowedCapabilities: [.musicPlaybackControl]
        )
    )
    #expect(badMusic.error?.code == "INVALID_ARGUMENTS")
}

@Test func speechTranscriptionRequiresPermissionAndResolvesSandboxPath() async throws {
    let (tools, sandbox) = try makeTools(
        permissionBroker: FixedPermissionBroker(statuses: [.speechRecognition: .granted]),
        speechClient: FakeSpeechClient()
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.speech.transcribeFile({ path: 'tmp:audio.m4a', locale: 'en-US' });",
            allowedCapabilities: [.speechFileTranscribe]
        )
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["transcript"]?.stringValue == "hello")
    #expect(output["resolvedPath"]?.stringValue == sandbox.tmp.appendingPathComponent("audio.m4a").path)
}

@Test func speechPermissionDeniedStaysStructured() async throws {
    let (tools, sandbox) = try makeTools(
        permissionBroker: FixedPermissionBroker(statuses: [.speechRecognition: .denied]),
        speechClient: FakeSpeechClient()
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.speech.transcribeFile({ path: 'tmp:audio.m4a' });",
            allowedCapabilities: [.speechFileTranscribe]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
    #expect(observed.error?.message.contains("speech.recognition") == true)
}

@Test func musicLibraryRequiresMusicPermission() async throws {
    let (tools, sandbox) = try makeTools(
        permissionBroker: FixedPermissionBroker(statuses: [.music: .denied]),
        musicClient: FakeMusicClient()
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.music.readLibrary({ type: 'playlists' });",
            allowedCapabilities: [.musicLibraryRead]
        )
    )

    #expect(observed.error?.code == "PERMISSION_DENIED")
    #expect(observed.error?.message.contains("music") == true)
}

@Test func storeKitPurchaseRequiresExplicitConfirmation() async throws {
    let (tools, sandbox) = try makeTools(storeKitClient: FakeStoreKitClient())
    defer { cleanup(sandbox) }

    let denied = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.storekit.purchase({ productID: 'pro.monthly', confirmed: false });",
            allowedCapabilities: [.storeKitPurchase]
        )
    )
    #expect(denied.error?.code == "INVALID_ARGUMENTS")
    #expect(denied.error?.message.contains("confirmed: true") == true)

    let purchased = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.storekit.purchase({ productID: 'pro.monthly', confirmed: true });",
            allowedCapabilities: [.storeKitPurchase]
        )
    )
    let output = try #require(purchased.result?.output?.objectValue)
    #expect(output["productID"]?.stringValue == "pro.monthly")
    #expect(output["status"]?.stringValue == "success")
}

@Test func walletAddPassIsIOSScopedAndResolvesSandboxPath() async throws {
    let (tools, sandbox) = try makeTools(
        passKitClient: FakePassKitClient(),
        hostPlatform: .iOS
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return await apple.wallet.addPass({ path: 'tmp:ticket.pkpass' });",
            allowedCapabilities: [.passKitPassAdd]
        )
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["resolvedPath"]?.stringValue == sandbox.tmp.appendingPathComponent("ticket.pkpass").path)
    #expect(output["added"]?.boolValue == true)
}

private struct FakeCloudKitClient: CloudKitClient {
    func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["status": .string("available"), "accountAvailable": .bool(true)])
    }

    func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "recordType": .string(arguments.string("recordType") ?? ""),
            "database": .string(arguments.string("database") ?? "private"),
            "limit": .number(Double(arguments.int("limit") ?? 0)),
        ])
    }

    func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["recordName": .string(arguments.string("recordName") ?? "new-record"), "saved": .bool(true)])
    }

    func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["recordName": .string(arguments.string("recordName") ?? ""), "deleted": .bool(true)])
    }

    func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["subscriptionID": .string(arguments.string("subscriptionID") ?? ""), "saved": .bool(true)])
    }

    func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([])
    }
}

private struct FailingCloudKitClient: CloudKitClient {
    func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }

    func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }

    func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }

    func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }

    func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }

    func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue {
        throw BridgeError.nativeFailure("CloudKit client should not be called")
    }
}

private struct FakeEventInbox: CodeModeEventInbox {
    func readEvents(source: String, arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "source": .string(source),
            "limit": .number(Double(arguments.int("limit") ?? 0)),
        ])
    }
}

private struct FakeMapsClient: MapsClient {
    func geocode(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([.object(["address": .string(arguments.string("address") ?? "")])])
    }

    func reverseGeocode(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([.object(["latitude": arguments["latitude"] ?? .null, "longitude": arguments["longitude"] ?? .null])])
    }

    func search(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "query": .string(arguments.string("query") ?? ""),
            "limit": .number(Double(arguments.int("limit") ?? 0)),
        ])
    }

    func routeEstimate(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "distanceMeters": .number(1_000),
            "expectedTravelTimeSeconds": .number(600),
            "transportType": .string(arguments.string("transportType") ?? "automobile"),
        ])
    }

    func open(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["opened": .bool(true)])
    }
}

private struct FakeSpeechClient: SpeechClient {
    func transcribeFile(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "transcript": .string("hello"),
            "resolvedPath": .string(arguments.string("resolvedPath") ?? ""),
        ])
    }

    func transcribeMicrophone(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["transcript": .string("live")])
    }
}

private struct FakeMusicClient: MusicClient {
    func requestAuthorization(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["status": .string("granted")])
    }

    func subscriptionStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["canPlayCatalogContent": .bool(true)])
    }

    func searchCatalog(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["term": .string(arguments.string("term") ?? "")])
    }

    func catalogDetails(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["identifier": .string(arguments.string("identifier") ?? "")])
    }

    func readLibrary(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([])
    }

    func writePlaylist(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["name": .string(arguments.string("name") ?? ""), "written": .bool(true)])
    }

    func controlPlayback(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["action": .string(arguments.string("action") ?? ""), "status": .string("ok")])
    }
}

private struct FakePassKitClient: PassKitClient {
    func walletStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["available": .bool(true)])
    }

    func listPasses(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([])
    }

    func addPass(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "added": .bool(true),
            "resolvedPath": .string(arguments.string("resolvedPath") ?? ""),
        ])
    }

    func presentPass(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["presented": .bool(true), "identifier": .string(arguments.string("identifier") ?? "")])
    }

    func applePayStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["canMakePayments": .bool(true)])
    }

    func presentApplePay(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["authorized": .bool(true)])
    }
}

private struct FakeStoreKitClient: StoreKitClient {
    func products(arguments: [String: JSONValue]) throws -> JSONValue {
        .array(arguments.array("productIDs") ?? [])
    }

    func currentEntitlements(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([])
    }

    func purchase(arguments: [String: JSONValue]) throws -> JSONValue {
        .object([
            "productID": .string(arguments.string("productID") ?? ""),
            "status": .string("success"),
        ])
    }

    func restore(arguments: [String: JSONValue]) throws -> JSONValue {
        .object(["restored": .bool(true)])
    }

    func transactionUpdates(arguments: [String: JSONValue]) throws -> JSONValue {
        .array([])
    }
}
