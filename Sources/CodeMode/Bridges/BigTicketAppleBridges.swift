import Foundation

public final class CloudKitBridge: @unchecked Sendable {
    private let client: any CloudKitClient

    public init(client: any CloudKitClient = UnavailableCloudKitClient()) {
        self.client = client
    }

    public func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.accountStatus(arguments: arguments)
    }

    public func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("recordType", in: arguments, capability: "cloudkit.records.query")
        try validateOptionalLimit(arguments)
        return try client.queryRecords(arguments: arguments)
    }

    public func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("recordType", in: arguments, capability: "cloudkit.record.save")
        guard arguments.object("fields") != nil else {
            throw BridgeError.invalidArguments("cloudkit.record.save requires fields")
        }
        return try client.saveRecord(arguments: arguments)
    }

    public func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("recordName", in: arguments, capability: "cloudkit.record.delete")
        return try client.deleteRecord(arguments: arguments)
    }

    public func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("subscriptionID", in: arguments, capability: "cloudkit.subscription.save")
        try requireNonEmptyString("recordType", in: arguments, capability: "cloudkit.subscription.save")
        return try client.saveSubscription(arguments: arguments)
    }

    public func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateOptionalLimit(arguments)
        return try client.readSubscriptionEvents(arguments: arguments)
    }
}

public final class RemoteNotificationsBridge: @unchecked Sendable {
    private let client: any RemoteNotificationsClient

    public init(client: any RemoteNotificationsClient = UnavailableRemoteNotificationsClient()) {
        self.client = client
    }

    public func register(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.register(arguments: arguments)
    }

    public func readToken(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.readToken(arguments: arguments)
    }

    public func readSettings(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.readSettings(arguments: arguments)
    }

    public func setCategories(arguments: [String: JSONValue]) throws -> JSONValue {
        guard arguments.array("categories") != nil else {
            throw BridgeError.invalidArguments("notifications.categories.set requires categories")
        }
        return try client.setCategories(arguments: arguments)
    }

    public func readResponses(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateOptionalLimit(arguments)
        return try client.readResponses(arguments: arguments)
    }
}

public final class SpeechBridge: @unchecked Sendable {
    private let client: any SpeechClient

    public init(client: any SpeechClient = UnavailableSpeechClient()) {
        self.client = client
    }

    public func requestPermission(context: BridgeInvocationContext) throws -> JSONValue {
        let status = context.permissionBroker.request(for: .speechRecognition)
        context.recordPermission(.speechRecognition, status: status)
        return permissionPayload(status)
    }

    public func status(context: BridgeInvocationContext) throws -> JSONValue {
        let status = context.permissionBroker.status(for: .speechRecognition)
        context.recordPermission(.speechRecognition, status: status)
        return permissionPayload(status)
    }

    public func transcribeFile(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try ensurePermission(.speechRecognition, context: context)
        let path = try requireNonEmptyString("path", in: arguments, capability: "speech.file.transcribe")
        let resolved = try context.pathPolicy.resolve(path: path)
        var clientArguments = arguments
        clientArguments["resolvedPath"] = .string(resolved.path)
        try validateOptionalPositiveNumber("timeoutMs", in: arguments, capability: "speech.file.transcribe")
        return try client.transcribeFile(arguments: clientArguments)
    }

    public func transcribeMicrophone(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try ensurePermission(.speechRecognition, context: context)
        try ensurePermission(.microphone, context: context)
        try validateOptionalPositiveNumber("timeoutMs", in: arguments, capability: "speech.microphone.transcribe")
        return try client.transcribeMicrophone(arguments: arguments)
    }
}

public final class AppIntentsBridge: @unchecked Sendable {
    private let client: any AppIntentsClient

    public init(client: any AppIntentsClient = UnavailableAppIntentsClient()) {
        self.client = client
    }

    public func listActions(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.listActions(arguments: arguments)
    }

    public func runAction(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "appintents.run")
        return try client.runAction(arguments: arguments)
    }

    public func donateAction(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "appintents.donate")
        return try client.donateAction(arguments: arguments)
    }

    public func openAction(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "appintents.open")
        return try client.openAction(arguments: arguments)
    }

    public func readHandoffs(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateOptionalLimit(arguments)
        return try client.readHandoffs(arguments: arguments)
    }
}

public final class FoundationModelsBridge: @unchecked Sendable {
    private let client: any FoundationModelsClient

    public init(client: any FoundationModelsClient = UnavailableFoundationModelsClient()) {
        self.client = client
    }

    public func status(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.status(arguments: arguments)
    }

    public func generateText(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("prompt", in: arguments, capability: "foundationModels.generate")
        try validateOptionalPositiveNumber("maxTokens", in: arguments, capability: "foundationModels.generate")
        return try client.generateText(arguments: arguments)
    }

    public func extract(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("input", in: arguments, capability: "foundationModels.extract")
        guard arguments.object("schema") != nil || arguments.string("schemaIdentifier") != nil else {
            throw BridgeError.invalidArguments("foundationModels.extract requires schema or schemaIdentifier")
        }
        return try client.extract(arguments: arguments)
    }
}

public final class ActivityBridge: @unchecked Sendable {
    private let client: any ActivityClient

    public init(client: any ActivityClient = UnavailableActivityClient()) {
        self.client = client
    }

    public func listActivities(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.listActivities(arguments: arguments)
    }

    public func startActivity(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("activityType", in: arguments, capability: "activity.start")
        guard arguments.object("attributes") != nil else {
            throw BridgeError.invalidArguments("activity.start requires attributes")
        }
        return try client.startActivity(arguments: arguments)
    }

    public func updateActivity(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "activity.update")
        guard arguments.object("contentState") != nil else {
            throw BridgeError.invalidArguments("activity.update requires contentState")
        }
        return try client.updateActivity(arguments: arguments)
    }

    public func endActivity(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "activity.end")
        return try client.endActivity(arguments: arguments)
    }

    public func readPushToken(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "activity.pushToken.read")
        return try client.readPushToken(arguments: arguments)
    }
}

public final class MapsBridge: @unchecked Sendable {
    private let client: any MapsClient

    public init(client: any MapsClient = UnavailableMapsClient()) {
        self.client = client
    }

    public func geocode(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("address", in: arguments, capability: "maps.geocode")
        try validateOptionalLimit(arguments)
        return try client.geocode(arguments: arguments)
    }

    public func reverseGeocode(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireCoordinateArguments(arguments, capability: "maps.reverseGeocode")
        return try client.reverseGeocode(arguments: arguments)
    }

    public func search(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("query", in: arguments, capability: "maps.search")
        try validateOptionalLimit(arguments)
        return try client.search(arguments: arguments)
    }

    public func routeEstimate(arguments: [String: JSONValue]) throws -> JSONValue {
        guard arguments.object("origin") != nil else {
            throw BridgeError.invalidArguments("maps.route.estimate requires origin")
        }
        guard arguments.object("destination") != nil else {
            throw BridgeError.invalidArguments("maps.route.estimate requires destination")
        }
        return try client.routeEstimate(arguments: arguments)
    }

    public func open(arguments: [String: JSONValue]) throws -> JSONValue {
        guard arguments.string("query") != nil ||
            arguments.string("url") != nil ||
            (arguments.double("latitude") != nil && arguments.double("longitude") != nil)
        else {
            throw BridgeError.invalidArguments("maps.open requires query, url, or latitude/longitude")
        }
        return try client.open(arguments: arguments)
    }
}

public final class MusicBridge: @unchecked Sendable {
    private let client: any MusicClient

    public init(client: any MusicClient = UnavailableMusicClient()) {
        self.client = client
    }

    public func requestPermission(context: BridgeInvocationContext) throws -> JSONValue {
        let status = context.permissionBroker.request(for: .music)
        context.recordPermission(.music, status: status)
        return permissionPayload(status)
    }

    public func subscriptionStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.subscriptionStatus(arguments: arguments)
    }

    public func searchCatalog(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("term", in: arguments, capability: "music.catalog.search")
        try validateOptionalLimit(arguments)
        return try client.searchCatalog(arguments: arguments)
    }

    public func catalogDetails(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "music.catalog.details")
        return try client.catalogDetails(arguments: arguments)
    }

    public func readLibrary(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try ensurePermission(.music, context: context)
        try validateOptionalLimit(arguments)
        return try client.readLibrary(arguments: arguments)
    }

    public func writePlaylist(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try ensurePermission(.music, context: context)
        try requireNonEmptyString("name", in: arguments, capability: "music.playlist.write")
        return try client.writePlaylist(arguments: arguments)
    }

    public func controlPlayback(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try ensurePermission(.music, context: context)
        try requireNonEmptyString("action", in: arguments, capability: "music.playback.control")
        return try client.controlPlayback(arguments: arguments)
    }
}

public final class PassKitBridge: @unchecked Sendable {
    private let client: any PassKitClient

    public init(client: any PassKitClient = UnavailablePassKitClient()) {
        self.client = client
    }

    public func walletStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.walletStatus(arguments: arguments)
    }

    public func listPasses(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateOptionalLimit(arguments)
        return try client.listPasses(arguments: arguments)
    }

    public func addPass(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        let path = try requireNonEmptyString("path", in: arguments, capability: "passkit.pass.add")
        let resolved = try context.pathPolicy.resolve(path: path)
        var clientArguments = arguments
        clientArguments["resolvedPath"] = .string(resolved.path)
        return try client.addPass(arguments: clientArguments)
    }

    public func presentPass(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("identifier", in: arguments, capability: "passkit.pass.present")
        return try client.presentPass(arguments: arguments)
    }

    public func applePayStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.applePayStatus(arguments: arguments)
    }

    public func presentApplePay(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("paymentRequestID", in: arguments, capability: "passkit.applePay.present")
        try requireConfirmation(arguments, capability: "passkit.applePay.present")
        return try client.presentApplePay(arguments: arguments)
    }
}

public final class StoreKitBridge: @unchecked Sendable {
    private let client: any StoreKitClient

    public init(client: any StoreKitClient = UnavailableStoreKitClient()) {
        self.client = client
    }

    public func products(arguments: [String: JSONValue]) throws -> JSONValue {
        guard arguments.array("productIDs") != nil else {
            throw BridgeError.invalidArguments("storekit.products.read requires productIDs")
        }
        return try client.products(arguments: arguments)
    }

    public func currentEntitlements(arguments: [String: JSONValue]) throws -> JSONValue {
        try client.currentEntitlements(arguments: arguments)
    }

    public func purchase(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireNonEmptyString("productID", in: arguments, capability: "storekit.purchase")
        try requireConfirmation(arguments, capability: "storekit.purchase")
        return try client.purchase(arguments: arguments)
    }

    public func restore(arguments: [String: JSONValue]) throws -> JSONValue {
        try requireConfirmation(arguments, capability: "storekit.restore")
        return try client.restore(arguments: arguments)
    }

    public func transactionUpdates(arguments: [String: JSONValue]) throws -> JSONValue {
        try validateOptionalLimit(arguments)
        return try client.transactionUpdates(arguments: arguments)
    }
}

@discardableResult
private func requireNonEmptyString(_ name: String, in arguments: [String: JSONValue], capability: String) throws -> String {
    guard let value = arguments.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
        throw BridgeError.invalidArguments("\(capability) requires \(name)")
    }
    return value
}

private func requireCoordinateArguments(_ arguments: [String: JSONValue], capability: String) throws {
    guard arguments.double("latitude") != nil else {
        throw BridgeError.invalidArguments("\(capability) requires latitude")
    }
    guard arguments.double("longitude") != nil else {
        throw BridgeError.invalidArguments("\(capability) requires longitude")
    }
}

private func validateOptionalLimit(_ arguments: [String: JSONValue]) throws {
    if let limit = arguments.int("limit"), limit <= 0 {
        throw BridgeError.invalidArguments("limit must be greater than 0")
    }
}

private func validateOptionalPositiveNumber(_ name: String, in arguments: [String: JSONValue], capability: String) throws {
    if let value = arguments.double(name), value <= 0 {
        throw BridgeError.invalidArguments("\(capability) \(name) must be greater than 0")
    }
}

private func requireConfirmation(_ arguments: [String: JSONValue], capability: String) throws {
    guard arguments.bool("confirmed") == true else {
        throw BridgeError.invalidArguments("\(capability) requires confirmed: true after explicit user-visible confirmation")
    }
}

private func ensurePermission(_ permission: PermissionKind, context: BridgeInvocationContext) throws {
    let status = context.resolvedPermission(for: permission)
    guard status == .granted else {
        throw BridgeError.permissionDenied(permission)
    }
}

private func permissionPayload(_ status: PermissionStatus) -> JSONValue {
    .object([
        "status": .string(status.rawValue),
        "granted": .bool(status == .granted),
    ])
}
