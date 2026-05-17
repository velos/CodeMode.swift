import Foundation

public struct CodeModeInboxEvent: Sendable, Codable, Equatable {
    public var id: String
    public var source: String
    public var timestamp: Date
    public var payload: JSONValue
    public var metadata: [String: JSONValue]

    public init(
        id: String = UUID().uuidString,
        source: String,
        timestamp: Date = Date(),
        payload: JSONValue,
        metadata: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.source = source
        self.timestamp = timestamp
        self.payload = payload
        self.metadata = metadata
    }

    var jsonValue: JSONValue {
        .object([
            "id": .string(id),
            "source": .string(source),
            "timestamp": .string(ISO8601DateFormatter().string(from: timestamp)),
            "payload": payload,
            "metadata": .object(metadata),
        ])
    }
}

public protocol CodeModeEventInbox: Sendable {
    func appendEvent(_ event: CodeModeInboxEvent) throws
    func readEvents(source: String, arguments: [String: JSONValue]) throws -> JSONValue
}

public extension CodeModeEventInbox {
    func appendEvent(_ event: CodeModeInboxEvent) throws {
        throw BridgeError.unsupportedPlatform("\(event.source) event inbox append; configure a host client on CodeModeConfiguration")
    }
}

public final class BoundedCodeModeEventInbox: CodeModeEventInbox, @unchecked Sendable {
    private let lock = NSLock()
    private let maxEventsPerSource: Int
    private var eventsBySource: [String: [CodeModeInboxEvent]] = [:]

    public init(maxEventsPerSource: Int = 100) {
        self.maxEventsPerSource = max(1, maxEventsPerSource)
    }

    public func appendEvent(_ event: CodeModeInboxEvent) throws {
        let source = event.source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false else {
            throw BridgeError.invalidArguments("event inbox source must not be empty")
        }

        var normalizedEvent = event
        normalizedEvent.source = source

        lock.lock()
        defer { lock.unlock() }
        var events = eventsBySource[source] ?? []
        events.insert(normalizedEvent, at: 0)
        if events.count > maxEventsPerSource {
            events.removeSubrange(maxEventsPerSource..<events.count)
        }
        eventsBySource[source] = events
    }

    public func readEvents(source: String, arguments: [String: JSONValue]) throws -> JSONValue {
        let source = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false else {
            throw BridgeError.invalidArguments("event inbox source must not be empty")
        }
        if let limit = arguments.int("limit"), limit <= 0 {
            throw BridgeError.invalidArguments("event inbox limit must be greater than 0")
        }
        let limit = arguments.int("limit") ?? maxEventsPerSource

        lock.lock()
        defer { lock.unlock() }
        let events = eventsBySource[source] ?? []

        return .array(events.prefix(limit).map(\.jsonValue))
    }
}

public struct UnavailableCodeModeEventInbox: CodeModeEventInbox {
    public init() {}

    public func readEvents(source: String, arguments: [String: JSONValue]) throws -> JSONValue {
        try unavailable("\(source) event inbox")
    }
}

public protocol CloudKitClient: Sendable {
    func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue
    func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue
    func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue
    func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue
    func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue
    func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol RemoteNotificationsClient: Sendable {
    func register(arguments: [String: JSONValue]) throws -> JSONValue
    func readToken(arguments: [String: JSONValue]) throws -> JSONValue
    func readSettings(arguments: [String: JSONValue]) throws -> JSONValue
    func setCategories(arguments: [String: JSONValue]) throws -> JSONValue
    func readResponses(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol SpeechClient: Sendable {
    func transcribeFile(arguments: [String: JSONValue]) throws -> JSONValue
    func transcribeMicrophone(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol AppIntentsClient: Sendable {
    func listActions(arguments: [String: JSONValue]) throws -> JSONValue
    func runAction(arguments: [String: JSONValue]) throws -> JSONValue
    func donateAction(arguments: [String: JSONValue]) throws -> JSONValue
    func openAction(arguments: [String: JSONValue]) throws -> JSONValue
    func readHandoffs(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol FoundationModelsClient: Sendable {
    func status(arguments: [String: JSONValue]) throws -> JSONValue
    func generateText(arguments: [String: JSONValue]) throws -> JSONValue
    func extract(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol ActivityClient: Sendable {
    func listActivities(arguments: [String: JSONValue]) throws -> JSONValue
    func startActivity(arguments: [String: JSONValue]) throws -> JSONValue
    func updateActivity(arguments: [String: JSONValue]) throws -> JSONValue
    func endActivity(arguments: [String: JSONValue]) throws -> JSONValue
    func readPushToken(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol MapsClient: Sendable {
    func geocode(arguments: [String: JSONValue]) throws -> JSONValue
    func reverseGeocode(arguments: [String: JSONValue]) throws -> JSONValue
    func search(arguments: [String: JSONValue]) throws -> JSONValue
    func routeEstimate(arguments: [String: JSONValue]) throws -> JSONValue
    func open(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol MusicClient: Sendable {
    func requestAuthorization(arguments: [String: JSONValue]) throws -> JSONValue
    func subscriptionStatus(arguments: [String: JSONValue]) throws -> JSONValue
    func searchCatalog(arguments: [String: JSONValue]) throws -> JSONValue
    func catalogDetails(arguments: [String: JSONValue]) throws -> JSONValue
    func readLibrary(arguments: [String: JSONValue]) throws -> JSONValue
    func writePlaylist(arguments: [String: JSONValue]) throws -> JSONValue
    func controlPlayback(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol PassKitClient: Sendable {
    func walletStatus(arguments: [String: JSONValue]) throws -> JSONValue
    func listPasses(arguments: [String: JSONValue]) throws -> JSONValue
    func addPass(arguments: [String: JSONValue]) throws -> JSONValue
    func presentPass(arguments: [String: JSONValue]) throws -> JSONValue
    func applePayStatus(arguments: [String: JSONValue]) throws -> JSONValue
    func presentApplePay(arguments: [String: JSONValue]) throws -> JSONValue
}

public protocol StoreKitClient: Sendable {
    func products(arguments: [String: JSONValue]) throws -> JSONValue
    func currentEntitlements(arguments: [String: JSONValue]) throws -> JSONValue
    func purchase(arguments: [String: JSONValue]) throws -> JSONValue
    func restore(arguments: [String: JSONValue]) throws -> JSONValue
    func transactionUpdates(arguments: [String: JSONValue]) throws -> JSONValue
}

public struct UnavailableCloudKitClient: CloudKitClient {
    public init() {}

    public func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit account status") }
    public func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit record query") }
    public func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit record save") }
    public func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit record delete") }
    public func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit subscription save") }
    public func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("CloudKit subscription event inbox") }
}

public struct UnavailableRemoteNotificationsClient: RemoteNotificationsClient {
    public init() {}

    public func register(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("remote notification registration") }
    public func readToken(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("remote notification token read") }
    public func readSettings(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("remote notification settings") }
    public func setCategories(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("remote notification categories") }
    public func readResponses(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("remote notification response inbox") }
}

public struct UnavailableSpeechClient: SpeechClient {
    public init() {}

    public func transcribeFile(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Speech file transcription") }
    public func transcribeMicrophone(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Speech microphone transcription") }
}

public struct UnavailableAppIntentsClient: AppIntentsClient {
    public init() {}

    public func listActions(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("App Intents action listing") }
    public func runAction(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("App Intents action execution") }
    public func donateAction(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("App Intents donation") }
    public func openAction(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("App Intents open action") }
    public func readHandoffs(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("App Intents handoff inbox") }
}

public struct UnavailableFoundationModelsClient: FoundationModelsClient {
    public init() {}

    public func status(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Foundation Models status") }
    public func generateText(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Foundation Models text generation") }
    public func extract(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Foundation Models structured extraction") }
}

public struct UnavailableActivityClient: ActivityClient {
    public init() {}

    public func listActivities(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("ActivityKit activity listing") }
    public func startActivity(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("ActivityKit activity start") }
    public func updateActivity(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("ActivityKit activity update") }
    public func endActivity(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("ActivityKit activity end") }
    public func readPushToken(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("ActivityKit push token read") }
}

public struct UnavailableMapsClient: MapsClient {
    public init() {}

    public func geocode(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("MapKit geocoding") }
    public func reverseGeocode(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("MapKit reverse geocoding") }
    public func search(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("MapKit local search") }
    public func routeEstimate(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("MapKit route estimates") }
    public func open(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Maps opening") }
}

public struct UnavailableMusicClient: MusicClient {
    public init() {}

    public func requestAuthorization(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music authorization") }
    public func subscriptionStatus(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music subscription status") }
    public func searchCatalog(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music catalog search") }
    public func catalogDetails(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music catalog details") }
    public func readLibrary(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music library read") }
    public func writePlaylist(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music playlist write") }
    public func controlPlayback(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Music playback control") }
}

public struct UnavailablePassKitClient: PassKitClient {
    public init() {}

    public func walletStatus(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("PassKit Wallet status") }
    public func listPasses(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("PassKit pass listing") }
    public func addPass(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("PassKit pass add") }
    public func presentPass(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("PassKit pass presentation") }
    public func applePayStatus(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Apple Pay status") }
    public func presentApplePay(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("Apple Pay presentation") }
}

public struct UnavailableStoreKitClient: StoreKitClient {
    public init() {}

    public func products(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("StoreKit product lookup") }
    public func currentEntitlements(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("StoreKit current entitlements") }
    public func purchase(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("StoreKit purchase") }
    public func restore(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("StoreKit restore") }
    public func transactionUpdates(arguments: [String: JSONValue]) throws -> JSONValue { try unavailable("StoreKit transaction inbox") }
}

private func unavailable(_ feature: String) throws -> JSONValue {
    throw BridgeError.unsupportedPlatform("\(feature); configure a host client on CodeModeConfiguration")
}
