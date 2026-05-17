import Foundation

#if canImport(AppKit)
@preconcurrency import AppKit
#endif
#if canImport(CloudKit)
@preconcurrency import CloudKit
#endif
#if canImport(CoreLocation)
@preconcurrency import CoreLocation
#endif
#if canImport(MapKit)
@preconcurrency import MapKit
#endif
#if canImport(UIKit)
@preconcurrency import UIKit
#endif

public struct SystemCloudKitClient: CloudKitClient {
    public var defaultContainerIdentifier: String?
    public var timeoutMs: Int

    public init(defaultContainerIdentifier: String? = nil, timeoutMs: Int = 30_000) {
        self.defaultContainerIdentifier = defaultContainerIdentifier
        self.timeoutMs = timeoutMs
    }

    public func accountStatus(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CloudKit)
        let status: CKAccountStatus = try waitForSystemClient(timeoutMs: timeoutMs, feature: "CloudKit account status") { completion in
            cloudKitContainer(arguments: arguments, defaultIdentifier: defaultContainerIdentifier).accountStatus { status, error in
                if let error {
                    completion.complete(.failure(error))
                } else {
                    completion.complete(.success(status))
                }
            }
        }
        return .object([
            "status": .string(status.codeModeString),
            "accountAvailable": .bool(status == .available),
        ])
        #else
        try unsupportedSystemClient("CloudKit account status")
        #endif
    }

    public func queryRecords(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CloudKit)
        let database = try cloudKitDatabase(arguments: arguments, defaultIdentifier: defaultContainerIdentifier)
        let recordType = try nonEmptySystemString("recordType", in: arguments, capability: "cloudkit.records.query")
        let predicate = try cloudKitPredicate(arguments: arguments, capability: "cloudkit.records.query")
        let limit = arguments.int("limit") ?? 100
        let query = CKQuery(recordType: recordType, predicate: predicate)
        let records: [CKRecord] = try waitForSystemClient(timeoutMs: timeoutMs, feature: "CloudKit record query") { completion in
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = limit
            let matchedRecords = SynchronizedBox<[CKRecord]>([])
            let matchedError = LockedBox<Error?>(nil)
            operation.recordMatchedBlock = { _, result in
                switch result {
                case let .success(record):
                    matchedRecords.mutate { $0.append(record) }
                case let .failure(error):
                    matchedError.set(error)
                }
            }
            operation.queryResultBlock = { result in
                switch result {
                case .success:
                    if let error = matchedError.get() {
                        completion.complete(.failure(error))
                    } else {
                        completion.complete(.success(matchedRecords.get()))
                    }
                case let .failure(error):
                    completion.complete(.failure(error))
                }
            }
            database.add(operation)
        }
        return .object([
            "database": .string(arguments.string("database") ?? "private"),
            "recordType": .string(recordType),
            "records": .array(records.map(cloudKitRecordJSON)),
        ])
        #else
        try unsupportedSystemClient("CloudKit record query")
        #endif
    }

    public func saveRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CloudKit)
        let database = try cloudKitDatabase(arguments: arguments, defaultIdentifier: defaultContainerIdentifier)
        let recordType = try nonEmptySystemString("recordType", in: arguments, capability: "cloudkit.record.save")
        guard let fields = arguments.object("fields"), fields.isEmpty == false else {
            throw BridgeError.invalidArguments("cloudkit.record.save requires non-empty fields")
        }
        let recordID = arguments.string("recordName")
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
            .map { CKRecord.ID(recordName: $0) }
        let record = recordID.map { CKRecord(recordType: recordType, recordID: $0) } ?? CKRecord(recordType: recordType)
        for (field, value) in fields {
            record[field] = try cloudKitRecordValue(value, field: field)
        }
        let saved: CKRecord = try waitForSystemClient(timeoutMs: timeoutMs, feature: "CloudKit record save") { completion in
            database.save(record) { record, error in
                if let error {
                    completion.complete(.failure(error))
                } else if let record {
                    completion.complete(.success(record))
                } else {
                    completion.complete(.failure(BridgeError.nativeFailure("CloudKit save returned no record")))
                }
            }
        }
        return .object([
            "database": .string(arguments.string("database") ?? "private"),
            "record": cloudKitRecordJSON(saved),
            "saved": .bool(true),
        ])
        #else
        try unsupportedSystemClient("CloudKit record save")
        #endif
    }

    public func deleteRecord(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CloudKit)
        let database = try cloudKitDatabase(arguments: arguments, defaultIdentifier: defaultContainerIdentifier)
        let recordName = try nonEmptySystemString("recordName", in: arguments, capability: "cloudkit.record.delete")
        let deletedID: CKRecord.ID = try waitForSystemClient(timeoutMs: timeoutMs, feature: "CloudKit record delete") { completion in
            database.delete(withRecordID: CKRecord.ID(recordName: recordName)) { recordID, error in
                if let error {
                    completion.complete(.failure(error))
                } else if let recordID {
                    completion.complete(.success(recordID))
                } else {
                    completion.complete(.failure(BridgeError.nativeFailure("CloudKit delete returned no record ID")))
                }
            }
        }
        return .object([
            "database": .string(arguments.string("database") ?? "private"),
            "recordName": .string(deletedID.recordName),
            "deleted": .bool(true),
        ])
        #else
        try unsupportedSystemClient("CloudKit record delete")
        #endif
    }

    public func saveSubscription(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CloudKit)
        let database = try cloudKitDatabase(arguments: arguments, defaultIdentifier: defaultContainerIdentifier)
        let subscriptionID = try nonEmptySystemString("subscriptionID", in: arguments, capability: "cloudkit.subscription.save")
        let recordType = try nonEmptySystemString("recordType", in: arguments, capability: "cloudkit.subscription.save")
        let predicate = try cloudKitPredicate(arguments: arguments, capability: "cloudkit.subscription.save")
        let subscription = CKQuerySubscription(
            recordType: recordType,
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
        )
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        let saved: CKSubscription = try waitForSystemClient(timeoutMs: timeoutMs, feature: "CloudKit subscription save") { completion in
            database.save(subscription) { subscription, error in
                if let error {
                    completion.complete(.failure(error))
                } else if let subscription {
                    completion.complete(.success(subscription))
                } else {
                    completion.complete(.failure(BridgeError.nativeFailure("CloudKit save returned no subscription")))
                }
            }
        }
        return .object([
            "database": .string(arguments.string("database") ?? "private"),
            "subscriptionID": .string(saved.subscriptionID),
            "recordType": .string(recordType),
            "saved": .bool(true),
        ])
        #else
        try unsupportedSystemClient("CloudKit subscription save")
        #endif
    }

    public func readSubscriptionEvents(arguments: [String: JSONValue]) throws -> JSONValue {
        try unsupportedSystemClient("CloudKit subscription event inbox; configure CodeModeConfiguration.eventInbox")
    }
}

public struct SystemMapsClient: MapsClient {
    public var timeoutMs: Int

    public init(timeoutMs: Int = 30_000) {
        self.timeoutMs = timeoutMs
    }

    public func geocode(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CoreLocation)
        let address = try nonEmptySystemString("address", in: arguments, capability: "maps.geocode")
        let limit = arguments.int("limit") ?? 10
        let geocoder = CLGeocoder()
        let placemarks: [CLPlacemark] = try waitForSystemClient(timeoutMs: timeoutMs, feature: "MapKit geocoding") { completion in
            geocoder.geocodeAddressString(address, in: coreLocationRegion(arguments.object("region"))) { placemarks, error in
                if let error {
                    completion.complete(.failure(error))
                } else {
                    completion.complete(.success(placemarks ?? []))
                }
            }
        }
        return .array(placemarks.prefix(limit).map(placemarkJSON))
        #else
        try unsupportedSystemClient("MapKit geocoding")
        #endif
    }

    public func reverseGeocode(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(CoreLocation)
        let location = CLLocation(
            latitude: arguments.double("latitude") ?? 0,
            longitude: arguments.double("longitude") ?? 0
        )
        let geocoder = CLGeocoder()
        let placemarks: [CLPlacemark] = try waitForSystemClient(timeoutMs: timeoutMs, feature: "MapKit reverse geocoding") { completion in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    completion.complete(.failure(error))
                } else {
                    completion.complete(.success(placemarks ?? []))
                }
            }
        }
        return .array(placemarks.map(placemarkJSON))
        #else
        try unsupportedSystemClient("MapKit reverse geocoding")
        #endif
    }

    public func search(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(MapKit)
        let query = try nonEmptySystemString("query", in: arguments, capability: "maps.search")
        let limit = arguments.int("limit") ?? 10
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region = mapKitRegion(arguments.object("region")) {
            request.region = region
        }
        let response: MKLocalSearch.Response = try waitForSystemClient(timeoutMs: timeoutMs, feature: "MapKit local search") { completion in
            MKLocalSearch(request: request).start { response, error in
                if let error {
                    completion.complete(.failure(error))
                } else if let response {
                    completion.complete(.success(response))
                } else {
                    completion.complete(.failure(BridgeError.nativeFailure("MapKit search returned no response")))
                }
            }
        }
        return .object([
            "query": .string(query),
            "results": .array(response.mapItems.prefix(limit).map(mapItemJSON)),
        ])
        #else
        try unsupportedSystemClient("MapKit local search")
        #endif
    }

    public func routeEstimate(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(MapKit)
        guard let origin = arguments.object("origin"), let destination = arguments.object("destination") else {
            throw BridgeError.invalidArguments("maps.route.estimate requires origin and destination")
        }
        let transportType = arguments.string("transportType") ?? "automobile"
        let request = MKDirections.Request()
        request.source = mapItem(coordinate: origin)
        request.destination = mapItem(coordinate: destination)
        request.transportType = mapKitTransportType(transportType)
        let response: MKDirections.ETAResponse = try waitForSystemClient(timeoutMs: timeoutMs, feature: "MapKit route estimate") { completion in
            MKDirections(request: request).calculateETA { response, error in
                if let error {
                    completion.complete(.failure(error))
                } else if let response {
                    completion.complete(.success(response))
                } else {
                    completion.complete(.failure(BridgeError.nativeFailure("MapKit route estimate returned no response")))
                }
            }
        }
        return .object([
            "distanceMeters": .number(response.distance),
            "expectedTravelTimeSeconds": .number(response.expectedTravelTime),
            "transportType": .string(transportType),
        ])
        #else
        try unsupportedSystemClient("MapKit route estimate")
        #endif
    }

    public func open(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(MapKit)
        if let urlString = arguments.string("url") {
            guard let url = URL(string: urlString) else {
                throw BridgeError.invalidArguments("maps.open url must be valid")
            }
            return .object(["opened": .bool(openSystemURL(url)), "url": .string(urlString)])
        }

        if let query = arguments.string("query"), query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            var components = URLComponents(string: "https://maps.apple.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: query)]
            guard let url = components.url else {
                throw BridgeError.invalidArguments("maps.open query could not be encoded")
            }
            return .object(["opened": .bool(openSystemURL(url)), "query": .string(query)])
        }

        let coordinateArguments = arguments.object("destination") ?? arguments
        let item = mapItem(coordinate: coordinateArguments)
        let launchOptions = mapsLaunchOptions(arguments)
        return .object([
            "opened": .bool(item.openInMaps(launchOptions: launchOptions)),
            "latitude": .number(coordinateArguments.double("latitude") ?? 0),
            "longitude": .number(coordinateArguments.double("longitude") ?? 0),
        ])
        #else
        try unsupportedSystemClient("Maps opening")
        #endif
    }
}

private func waitForSystemClient<T>(
    timeoutMs: Int,
    feature: String,
    _ start: (SystemClientCallback<T>) -> Void
) throws -> T {
    guard timeoutMs > 0 else {
        throw BridgeError.invalidArguments("\(feature) timeoutMs must be greater than 0")
    }
    let callback = SystemClientCallback<T>()
    start(callback)
    return try callback.wait(timeoutMs: timeoutMs, feature: feature)
}

private final class SystemClientCallback<T>: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let result = LockedBox<Result<T, Error>?>(nil)

    func complete(_ value: Result<T, Error>) {
        result.set(value)
        semaphore.signal()
    }

    func wait(timeoutMs: Int, feature: String) throws -> T {
        if semaphore.wait(timeout: .now() + .milliseconds(timeoutMs)) == .timedOut {
            throw BridgeError.timeout(milliseconds: timeoutMs)
        }
        switch result.get() {
        case let .success(value):
            return value
        case let .failure(error):
            throw BridgeError.nativeFailure("\(feature) failed: \(error.localizedDescription)")
        case .none:
            throw BridgeError.nativeFailure("\(feature) finished without result")
        }
    }
}

private func nonEmptySystemString(_ name: String, in arguments: [String: JSONValue], capability: String) throws -> String {
    guard let value = arguments.string(name)?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
        throw BridgeError.invalidArguments("\(capability) requires \(name)")
    }
    return value
}

private func unsupportedSystemClient(_ feature: String) throws -> JSONValue {
    throw BridgeError.unsupportedPlatform(feature)
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

#if canImport(CloudKit)
private func cloudKitContainer(arguments: [String: JSONValue], defaultIdentifier: String?) -> CKContainer {
    let identifier = arguments.string("containerIdentifier")?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .nilIfEmpty ?? defaultIdentifier
    if let identifier {
        return CKContainer(identifier: identifier)
    }
    return CKContainer.default()
}

private func cloudKitDatabase(arguments: [String: JSONValue], defaultIdentifier: String?) throws -> CKDatabase {
    let container = cloudKitContainer(arguments: arguments, defaultIdentifier: defaultIdentifier)
    switch arguments.string("database") ?? "private" {
    case "private":
        return container.privateCloudDatabase
    case "shared":
        return container.sharedCloudDatabase
    case "public":
        return container.publicCloudDatabase
    default:
        throw BridgeError.invalidArguments("CloudKit database must be one of private, shared, public")
    }
}

private func cloudKitPredicate(arguments: [String: JSONValue], capability: String) throws -> NSPredicate {
    guard let predicate = arguments["predicate"] else {
        return NSPredicate(value: true)
    }
    guard let object = predicate.objectValue else {
        throw BridgeError.invalidArguments("\(capability) predicate must be an object shaped as { field, equals }; raw predicate strings are not supported")
    }
    let field = try nonEmptySystemString("field", in: object, capability: "\(capability) predicate")
    guard let equals = object["equals"] else {
        throw BridgeError.invalidArguments("\(capability) predicate requires equals")
    }
    guard let value = try cloudKitPredicateValue(equals) else {
        throw BridgeError.invalidArguments("\(capability) predicate.equals must not be null")
    }
    return NSPredicate(format: "%K == %@", argumentArray: [field, value])
}

private func cloudKitPredicateValue(_ value: JSONValue) throws -> Any? {
    switch value {
    case let .string(value):
        return value as NSString
    case let .number(value):
        return NSNumber(value: value)
    case let .bool(value):
        return NSNumber(value: value)
    case .null:
        return nil
    case .object, .array:
        throw BridgeError.invalidArguments("CloudKit predicate.equals must be a scalar value")
    }
}

private func cloudKitRecordValue(_ value: JSONValue, field: String) throws -> (any CKRecordValue)? {
    switch value {
    case let .string(value):
        return value as NSString
    case let .number(value):
        return NSNumber(value: value)
    case let .bool(value):
        return NSNumber(value: value)
    case .null:
        return nil
    case let .array(values):
        let array = NSMutableArray()
        for element in values {
            guard let scalar = try cloudKitRecordScalarValue(element, field: field) else {
                throw BridgeError.invalidArguments("cloudkit.record.save fields.\(field) arrays cannot contain null")
            }
            array.add(scalar)
        }
        return array
    case .object:
        throw BridgeError.invalidArguments("cloudkit.record.save fields.\(field) must be a scalar or array of scalars")
    }
}

private func cloudKitRecordScalarValue(_ value: JSONValue, field: String) throws -> (any CKRecordValue)? {
    switch value {
    case let .string(value):
        return value as NSString
    case let .number(value):
        return NSNumber(value: value)
    case let .bool(value):
        return NSNumber(value: value)
    case .null:
        return nil
    case .object, .array:
        throw BridgeError.invalidArguments("cloudkit.record.save fields.\(field) arrays can only contain scalar values")
    }
}

private func cloudKitRecordJSON(_ record: CKRecord) -> JSONValue {
    var fields: [String: JSONValue] = [:]
    for key in record.allKeys() {
        if let value = record[key] {
            fields[key] = cloudKitJSONValue(value)
        }
    }

    var object: [String: JSONValue] = [
        "recordName": .string(record.recordID.recordName),
        "recordType": .string(record.recordType),
        "fields": .object(fields),
    ]
    if let creationDate = record.creationDate {
        object["creationDate"] = .string(ISO8601DateFormatter().string(from: creationDate))
    }
    if let modificationDate = record.modificationDate {
        object["modificationDate"] = .string(ISO8601DateFormatter().string(from: modificationDate))
    }
    return .object(object)
}

private func cloudKitJSONValue(_ value: Any) -> JSONValue {
    switch value {
    case let value as String:
        return .string(value)
    case let value as NSNumber:
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return .bool(value.boolValue)
        }
        return .number(value.doubleValue)
    case let value as Date:
        return .string(ISO8601DateFormatter().string(from: value))
    case let value as [Any]:
        return .array(value.map(cloudKitJSONValue))
    #if canImport(CoreLocation)
    case let value as CLLocation:
        return .object([
            "latitude": .number(value.coordinate.latitude),
            "longitude": .number(value.coordinate.longitude),
        ])
    #endif
    default:
        return .string(String(describing: value))
    }
}

private extension CKAccountStatus {
    var codeModeString: String {
        switch self {
        case .available:
            return "available"
        case .noAccount:
            return "noAccount"
        case .restricted:
            return "restricted"
        case .couldNotDetermine:
            return "couldNotDetermine"
        case .temporarilyUnavailable:
            return "temporarilyUnavailable"
        @unknown default:
            return "unknown"
        }
    }
}
#endif

#if canImport(CoreLocation)
private func coreLocationRegion(_ arguments: [String: JSONValue]?) -> CLRegion? {
    guard let arguments else {
        return nil
    }
    if let latitude = arguments.double("latitude"),
       let longitude = arguments.double("longitude"),
       let radius = arguments.double("radiusMeters") {
        return CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: "codemode.search.region"
        )
    }
    if let center = arguments.object("center"),
       let latitude = center.double("latitude"),
       let longitude = center.double("longitude"),
       let latitudeDelta = arguments.double("latitudeDelta"),
       let longitudeDelta = arguments.double("longitudeDelta") {
        let radius = max(latitudeDelta, longitudeDelta) * 111_000 / 2
        return CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radius: radius,
            identifier: "codemode.search.region"
        )
    }
    return nil
}

private func placemarkJSON(_ placemark: CLPlacemark) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let name = placemark.name {
        object["name"] = .string(name)
    }
    if let thoroughfare = placemark.thoroughfare {
        object["thoroughfare"] = .string(thoroughfare)
    }
    if let locality = placemark.locality {
        object["locality"] = .string(locality)
    }
    if let administrativeArea = placemark.administrativeArea {
        object["administrativeArea"] = .string(administrativeArea)
    }
    if let country = placemark.country {
        object["country"] = .string(country)
    }
    if let postalCode = placemark.postalCode {
        object["postalCode"] = .string(postalCode)
    }
    if let location = placemark.location {
        object["latitude"] = .number(location.coordinate.latitude)
        object["longitude"] = .number(location.coordinate.longitude)
    }
    return .object(object)
}
#endif

#if canImport(MapKit)
private func mapKitRegion(_ arguments: [String: JSONValue]?) -> MKCoordinateRegion? {
    guard let arguments else {
        return nil
    }
    if let latitude = arguments.double("latitude"),
       let longitude = arguments.double("longitude"),
       let radius = arguments.double("radiusMeters") {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: radius * 2,
            longitudinalMeters: radius * 2
        )
    }
    if let center = arguments.object("center"),
       let latitude = center.double("latitude"),
       let longitude = center.double("longitude"),
       let latitudeDelta = arguments.double("latitudeDelta"),
       let longitudeDelta = arguments.double("longitudeDelta") {
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
    return nil
}

private func mapItem(coordinate arguments: [String: JSONValue]) -> MKMapItem {
    let coordinate = CLLocationCoordinate2D(
        latitude: arguments.double("latitude") ?? 0,
        longitude: arguments.double("longitude") ?? 0
    )
    let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
    if let name = arguments.string("name") {
        item.name = name
    }
    return item
}

private func mapKitTransportType(_ value: String) -> MKDirectionsTransportType {
    switch value {
    case "walking":
        return .walking
    case "transit":
        return .transit
    case "any":
        return .any
    default:
        return .automobile
    }
}

private func mapsLaunchOptions(_ arguments: [String: JSONValue]) -> [String: Any]? {
    guard let transportType = arguments.string("transportType") else {
        return nil
    }
    let mode: String
    switch transportType {
    case "walking":
        mode = MKLaunchOptionsDirectionsModeWalking
    case "transit":
        mode = MKLaunchOptionsDirectionsModeTransit
    default:
        mode = MKLaunchOptionsDirectionsModeDriving
    }
    return [MKLaunchOptionsDirectionsModeKey: mode]
}

private func mapItemJSON(_ item: MKMapItem) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let name = item.name {
        object["name"] = .string(name)
    }
    if let phoneNumber = item.phoneNumber {
        object["phoneNumber"] = .string(phoneNumber)
    }
    if let url = item.url?.absoluteString {
        object["url"] = .string(url)
    }
    object["latitude"] = .number(item.placemark.coordinate.latitude)
    object["longitude"] = .number(item.placemark.coordinate.longitude)
    object["placemark"] = placemarkJSON(item.placemark)
    return .object(object)
}

private func openSystemURL(_ url: URL) -> Bool {
    #if canImport(UIKit)
    if Thread.isMainThread {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
        return true
    }
    let semaphore = DispatchSemaphore(value: 0)
    let opened = LockedBox(false)
    DispatchQueue.main.async {
        UIApplication.shared.open(url) { success in
            opened.set(success)
            semaphore.signal()
        }
    }
    if semaphore.wait(timeout: .now() + .seconds(10)) == .timedOut {
        return false
    }
    return opened.get()
    #elseif canImport(AppKit)
    return NSWorkspace.shared.open(url)
    #else
    return false
    #endif
}
#endif
