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
            return { recordType: records.recordType, database: records.database, query: places.query, limit: places.limit };
            """,
            allowedCapabilities: [.cloudKitRecordsQuery, .mapsSearch]
        )
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output["recordType"]?.stringValue == "Task")
    #expect(output["database"]?.stringValue == "private")
    #expect(output["query"]?.stringValue == "coffee")
    #expect(output["limit"]?.intValue == 3)
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
        .object(["distanceMeters": .number(1_000), "expectedTravelTimeSeconds": .number(600)])
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
