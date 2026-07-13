import Foundation

public typealias CapabilityHandler = @Sendable (_ arguments: [String: JSONValue], _ context: BridgeInvocationContext) throws -> JSONValue

public enum CapabilityArgumentType: String, Sendable, Codable, Equatable {
    case string
    case number
    case bool
    case object
    case array
    case any

    func matches(_ value: JSONValue) -> Bool {
        switch self {
        case .string:
            if case .string = value { return true }
            return false
        case .number:
            if case .number = value { return true }
            return false
        case .bool:
            if case .bool = value { return true }
            return false
        case .object:
            if case .object = value { return true }
            return false
        case .array:
            if case .array = value { return true }
            return false
        case .any:
            return true
        }
    }
}

public struct CapabilityArgumentConstraints: Sendable, Codable, Equatable {
    public var allowedStringValues: [String: [String]]

    public init(allowedStringValues: [String: [String]] = [:]) {
        self.allowedStringValues = allowedStringValues.mapValues(Self.uniqueValues)
    }

    public static let none = CapabilityArgumentConstraints()

    public static func defaults(for capability: CapabilityID) -> CapabilityArgumentConstraints {
        switch capability {
        case .networkFetch:
            return .init(allowedStringValues: [
                "options.responseEncoding": ["text", "base64"],
            ])
        // calendarWrite / calendarDelete / calendarUIPickCalendar / remindersWrite
        // constraints now come from their tools' CodeModeStringEnum arguments
        // (EventKitCodeModeTools.swift), not this table.
        // photosRead / photosUIPick (MediaTypeFilter) and contactsUIPick
        // (ContactPickerMode) constraints now come from their tools'
        // CodeModeStringEnum arguments (SystemUICodeModeTools.swift /
        // PeoplePhotosDocumentsCodeModeTools.swift), not this table.
        // cameraUICapture / cameraUIScanData / printUIPresent / uiAlertPresent
        // constraints now come from their tools' CodeModeStringEnum arguments
        // (SystemUICodeModeTools.swift), not this table.
        // cloudKit database constraint now comes from the tools' CloudKitDatabase
        // argument (CloudPushSpeechCodeModeTools.swift), not this table.
        // activityEnd (ActivityDismissalPolicy) and mapsRouteEstimate/mapsOpen
        // (MapsTransportType) constraints now come from their tools'
        // CodeModeStringEnum arguments (IntentsModelsActivityMapsCodeModeTools.swift).
        // musicPlaybackControl action constraint now comes from the tool's
        // MusicPlaybackAction argument (CommerceCodeModeTools.swift).
        default:
            return .none
        }
    }

    func validate(arguments: [String: JSONValue], capability: CapabilityID) throws {
        try validate(arguments: arguments, capabilityName: capability.rawValue)
    }

    func validate(arguments: [String: JSONValue], capabilityName: String) throws {
        for (path, allowed) in allowedStringValues.sorted(by: { $0.key < $1.key }) {
            guard let value = Self.value(atPath: path, in: arguments) else {
                continue
            }
            guard let string = value.stringValue else {
                throw BridgeError.invalidArguments("\(capabilityName) expected '\(path)' as string, received \(Self.jsonTypeName(for: value))")
            }
            // Bridges parse these values case-insensitively; match that here so the
            // registry never rejects an argument the bridge would accept.
            let normalized = string.lowercased()
            guard allowed.contains(where: { $0.lowercased() == normalized }) else {
                throw BridgeError.invalidArguments("\(capabilityName) \(path) must be one of \(allowed.joined(separator: ", "))")
            }
        }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }

    private static func value(atPath path: String, in root: [String: JSONValue]) -> JSONValue? {
        let segments = path.split(separator: ".").map(String.init)
        guard segments.isEmpty == false else { return nil }

        var current: JSONValue = .object(root)
        for segment in segments {
            guard let object = current.objectValue, let next = object[segment] else {
                return nil
            }
            current = next
        }

        return current
    }

    private static func jsonTypeName(for value: JSONValue) -> String {
        switch value {
        case .string:
            return "string"
        case .number:
            return "number"
        case .bool:
            return "bool"
        case .object:
            return "object"
        case .array:
            return "array"
        case .null:
            return "null"
        }
    }
}

public struct CapabilityDescriptor: Sendable, Equatable {
    public var id: CapabilityID
    public var title: String
    public var summary: String
    public var tags: [String]
    public var example: String
    public var requiredPermissions: [PermissionKind]
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var argumentTypes: [String: CapabilityArgumentType]
    public var argumentHints: [String: String]
    public var argumentConstraints: CapabilityArgumentConstraints
    public var resultSummary: String

    public init(
        id: CapabilityID,
        title: String,
        summary: String,
        tags: [String],
        example: String,
        requiredPermissions: [PermissionKind] = [],
        requiredArguments: [String] = [],
        optionalArguments: [String] = [],
        argumentTypes: [String: CapabilityArgumentType] = [:],
        argumentHints: [String: String] = [:],
        argumentConstraints: CapabilityArgumentConstraints? = nil,
        resultSummary: String = "JSON value"
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.tags = tags
        self.example = example
        self.requiredPermissions = requiredPermissions
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.argumentTypes = argumentTypes.isEmpty ? CapabilityDescriptor.inferArgumentTypes(required: requiredArguments, optional: optionalArguments) : argumentTypes
        self.argumentHints = argumentHints
        self.argumentConstraints = argumentConstraints ?? CapabilityArgumentConstraints.defaults(for: id)
        self.resultSummary = resultSummary
    }

    private static func inferArgumentTypes(required: [String], optional: [String]) -> [String: CapabilityArgumentType] {
        let known: [String: CapabilityArgumentType] = [
            "url": .string,
            "options": .object,
            "options.method": .string,
            "options.headers": .object,
            "options.body": .string,
            "options.bodyBase64": .string,
            "options.timeoutMs": .number,
            "options.responseEncoding": .string,

            "key": .string,
            "value": .string,

            "mode": .string,

            "latitude": .number,
            "longitude": .number,

            "start": .string,
            "end": .string,
            "title": .string,
            "notes": .string,
            "location": .string,
            "calendarIdentifier": .string,
            "calendarIdentifiers": .array,
            "isAllDay": .bool,
            "span": .string,
            "operation": .string,
            "selectionStyle": .string,
            "displayStyle": .string,
            "allowsEditing": .bool,
            "allowsCalendarPreview": .bool,
            "dueDate": .string,
            "includeCompleted": .bool,
            "isCompleted": .bool,
            "priority": .number,
            "query": .string,
            "limit": .number,
            "identifiers": .array,
            "localIdentifier": .string,
            "mediaType": .string,
            "outputDirectory": .string,
            "timeoutMs": .number,
            "cameraDevice": .string,
            "flashMode": .string,
            "videoQuality": .string,
            "maximumDurationSeconds": .number,
            "isGuidanceEnabled": .bool,
            "isHighlightingEnabled": .bool,
            "isPinchToZoomEnabled": .bool,
            "isHighFrameRateTrackingEnabled": .bool,
            "displayedPropertyKeys": .array,
            "allowsActions": .bool,
            "givenName": .string,
            "familyName": .string,
            "organization": .string,
            "phoneNumbers": .array,
            "emailAddresses": .array,
            "contentTypes": .array,
            "allowMultiple": .bool,
            "text": .string,
            "paths": .array,
            "subject": .string,
            "excludedActivityTypes": .array,
            "cc": .array,
            "bcc": .array,
            "isHTML": .bool,
            "attachments": .array,
            "recipients": .array,
            "entersReaderIfAvailable": .bool,
            "callbackURLScheme": .string,
            "prefersEphemeralSession": .bool,
            "preferredStyle": .string,
            "buttons": .array,
            "sourceRect": .object,
            "features": .array,
            "maxResults": .number,
            "identifier": .string,
            "subtitle": .string,
            "body": .string,
            "secondsFromNow": .number,
            "fireDate": .string,
            "repeats": .bool,
            "sound": .string,
            "badge": .number,
            "userInfo": .object,
            "threadIdentifier": .string,
            "categoryIdentifier": .string,
            "includeCharacteristics": .bool,
            "accessoryIdentifier": .string,
            "serviceType": .string,
            "characteristicType": .string,
            "containerIdentifier": .string,
            "database": .string,
            "recordType": .string,
            "recordName": .string,
            "fields": .object,
            "zoneID": .string,
            "predicate": .any,
            "sortDescriptors": .array,
            "desiredKeys": .array,
            "savePolicy": .string,
            "subscriptionID": .string,
            "firesOnRecordCreation": .bool,
            "firesOnRecordUpdate": .bool,
            "firesOnRecordDeletion": .bool,
            "afterCursor": .string,
            "types": .array,
            "categories": .array,
            "actionIdentifier": .string,
            "locale": .string,
            "requiresOnDeviceRecognition": .bool,
            "taskHint": .string,
            "partialResults": .bool,
            "domain": .string,
            "parameters": .object,
            "instructions": .string,
            "temperature": .number,
            "maxTokens": .number,
            "schema": .object,
            "schemaIdentifier": .string,
            "input": .string,
            "activityType": .string,
            "attributes": .object,
            "contentState": .object,
            "pushType": .string,
            "staleDate": .string,
            "alert": .object,
            "dismissalPolicy": .string,
            "address": .string,
            "region": .object,
            "resultTypes": .array,
            "origin": .object,
            "destination": .object,
            "transportType": .string,
            "departureDate": .string,
            "arrivalDate": .string,
            "term": .string,
            "countryCode": .string,
            "type": .string,
            "catalogIDs": .array,
            "libraryIDs": .array,
            "description": .string,
            "playlistID": .string,
            "catalogID": .string,
            "libraryID": .string,
            "action": .string,
            "queue": .object,
            "startPlaying": .bool,
            "passTypeIdentifier": .string,
            "serialNumber": .string,
            "paymentRequestID": .string,
            "networks": .array,
            "confirmed": .bool,
            "productID": .string,
            "productIDs": .array,
            "appAccountToken": .string,

            "path": .string,
            "encoding": .string,
            "data": .string,
            "from": .string,
            "to": .string,
            "recursive": .bool,

            "timeMs": .number,
            "outputPath": .string,
            "preset": .string,
        ]

        let names = Array(Set(required + optional))
        return Dictionary(uniqueKeysWithValues: names.map { name in
            (name, known[name] ?? .any)
        })
    }
}

public struct CapabilityRegistration: Sendable {
    public var descriptor: CapabilityDescriptor
    public var jsNames: [String]
    public var handler: CapabilityHandler

    public init(jsNames: [String] = [], descriptor: CapabilityDescriptor, handler: @escaping CapabilityHandler) {
        self.descriptor = descriptor
        self.jsNames = jsNames
        self.handler = handler
    }
}

struct RegisteredCodeModeFunction: Sendable {
    var capabilityKey: CodeModeCapabilityKey
    var builtInCapability: CapabilityID?
    var jsNames: [String]
    var title: String
    var summary: String
    var tags: [String]
    var example: String
    var requiredPermissions: [PermissionKind]
    var requiredArguments: [String]
    var optionalArguments: [String]
    var argumentTypes: [String: CapabilityArgumentType]
    var argumentHints: [String: String]
    var argumentConstraints: CapabilityArgumentConstraints
    var resultSummary: String
    var handler: CapabilityHandler

    var catalogCapability: String {
        builtInCapability?.rawValue ?? capabilityKey.rawValue
    }

    var validationName: String {
        catalogCapability
    }

    init(_ registration: CapabilityRegistration) {
        let descriptor = registration.descriptor
        self.capabilityKey = descriptor.id.codeModeKey
        self.builtInCapability = descriptor.id
        self.jsNames = registration.jsNames
        self.title = descriptor.title
        self.summary = descriptor.summary
        self.tags = descriptor.tags
        self.example = descriptor.example
        self.requiredPermissions = descriptor.requiredPermissions
        self.requiredArguments = descriptor.requiredArguments
        self.optionalArguments = descriptor.optionalArguments
        self.argumentTypes = descriptor.argumentTypes
        self.argumentHints = descriptor.argumentHints
        self.argumentConstraints = descriptor.argumentConstraints
        self.resultSummary = descriptor.resultSummary
        self.handler = registration.handler
    }

    init(_ registration: CodeModeRegistration) {
        self.capabilityKey = registration.capabilityKey
        self.builtInCapability = nil
        self.jsNames = [registration.jsPath]
        self.title = registration.title
        self.summary = registration.summary
        self.tags = registration.tags
        self.example = registration.example
        self.requiredPermissions = []
        self.requiredArguments = registration.requiredArguments
        self.optionalArguments = registration.optionalArguments
        self.argumentTypes = registration.argumentTypes
        self.argumentHints = registration.argumentHints
        self.argumentConstraints = registration.argumentConstraints
        self.resultSummary = registration.resultSummary
        self.handler = registration.handler
    }
}

public final class CapabilityRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [CapabilityID: CapabilityRegistration] = [:]
    private var codeModeRegistrations: [CodeModeCapabilityKey: CodeModeRegistration] = [:]

    public init(registrations: [CapabilityRegistration] = [], codeModeRegistrations: [CodeModeRegistration] = []) {
        for registration in registrations {
            self.registrations[registration.descriptor.id] = registration
        }
        for registration in codeModeRegistrations {
            self.codeModeRegistrations[registration.capabilityKey] = registration
        }
    }

    public func register(_ registration: CapabilityRegistration) {
        lock.lock()
        registrations[registration.descriptor.id] = registration
        lock.unlock()
    }

    public func register(_ registrations: [CapabilityRegistration]) {
        lock.lock()
        for registration in registrations {
            self.registrations[registration.descriptor.id] = registration
        }
        lock.unlock()
    }

    public func register(_ registration: CodeModeRegistration) {
        lock.lock()
        codeModeRegistrations[registration.capabilityKey] = registration
        lock.unlock()
    }

    public func register(_ registrations: [CodeModeRegistration]) {
        lock.lock()
        for registration in registrations {
            self.codeModeRegistrations[registration.capabilityKey] = registration
        }
        lock.unlock()
    }

    public func descriptor(for capability: CapabilityID) -> CapabilityDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return registrations[capability]?.descriptor
    }

    public func registration(for capability: CapabilityID) -> CapabilityRegistration? {
        lock.lock()
        defer { lock.unlock() }
        return registrations[capability]
    }

    public func allCapabilityRegistrations() -> [CapabilityRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.map { $0 }
    }

    public func allDescriptors() -> [CapabilityDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.map(\.descriptor)
    }

    public func allCodeModeRegistrations() -> [CodeModeRegistration] {
        lock.lock()
        defer { lock.unlock() }
        return codeModeRegistrations.values.map { $0 }
    }

    func registeredFunction(for capability: CapabilityID) -> RegisteredCodeModeFunction? {
        lock.lock()
        defer { lock.unlock() }
        return registrations[capability].map(RegisteredCodeModeFunction.init)
    }

    func registeredFunction(for capabilityKey: CodeModeCapabilityKey) -> RegisteredCodeModeFunction? {
        lock.lock()
        defer { lock.unlock() }
        if let builtIn = CapabilityID(rawValue: capabilityKey.rawValue),
           let registration = registrations[builtIn]
        {
            return RegisteredCodeModeFunction(registration)
        }
        return codeModeRegistrations[capabilityKey].map(RegisteredCodeModeFunction.init)
    }

    func allRegisteredFunctions() -> [RegisteredCodeModeFunction] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.map(RegisteredCodeModeFunction.init)
            + codeModeRegistrations.values.map(RegisteredCodeModeFunction.init)
    }

    public func invoke(_ capabilityID: String, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try context.checkCancellation()

        if let capability = CapabilityID(rawValue: capabilityID) {
            return try invokeBuiltIn(capability, arguments: arguments, context: context)
        }

        return try invokeCodeMode(CodeModeCapabilityKey(rawValue: capabilityID), arguments: arguments, context: context)
    }

    private func invokeBuiltIn(_ capability: CapabilityID, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard context.allowedCapabilities.contains(capability) || context.allowedCapabilityKeys.contains(capability.codeModeKey) else {
            throw BridgeError.capabilityDenied(capability)
        }

        guard let function = registeredFunction(for: capability) else {
            throw BridgeError.capabilityNotFound(capability.rawValue)
        }

        return try invoke(function, arguments: arguments, context: context)
    }

    private func invokeCodeMode(_ capabilityKey: CodeModeCapabilityKey, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        guard context.allowedCapabilityKeys.contains(capabilityKey) else {
            throw BridgeError.capabilityKeyDenied(capabilityKey)
        }

        guard let function = registeredFunction(for: capabilityKey) else {
            throw BridgeError.capabilityNotFound(capabilityKey.rawValue)
        }

        return try invoke(function, arguments: arguments, context: context)
    }

    private func invoke(_ function: RegisteredCodeModeFunction, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        // Coerce common LLM output quirks (a number sent as a string, a bool sent
        // as "true"/"false") into the declared type before validation, so both the
        // type check and the bridge see canonical values instead of rejecting the
        // call. Only declared `.number`/`.bool` arguments are touched.
        let normalized = normalizedArguments(arguments, for: function)
        try validateArguments(normalized, for: function)
        try validatePermissions(function.requiredPermissions, context: context)
        try context.checkCancellation()
        return try mapCodeModeFunctionError {
            try function.handler(normalized, context)
        }
    }

    private func normalizedArguments(_ arguments: [String: JSONValue], for function: RegisteredCodeModeFunction) -> [String: JSONValue] {
        var result = arguments
        for (path, expectedType) in function.argumentTypes where expectedType == .number || expectedType == .bool {
            guard let value = value(atPath: path, in: result),
                  let coerced = Self.coerceScalarString(value, to: expectedType)
            else {
                continue
            }
            result = Self.setValue(coerced, atPath: path, in: result)
        }
        return result
    }

    /// Coerces a JSON string into the declared scalar type. JSON numbers/bools are
    /// already the right type and are left untouched (returns nil). Booleans accept
    /// only case-insensitive "true"/"false" — not 1/0 or "yes"/"no" — so safety
    /// gates like `confirmed` still require an explicit affirmative.
    private static func coerceScalarString(_ value: JSONValue, to type: CapabilityArgumentType) -> JSONValue? {
        guard case let .string(raw) = value else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        switch type {
        case .number:
            guard let number = Double(trimmed) else { return nil }
            return .number(number)
        case .bool:
            switch trimmed.lowercased() {
            case "true": return .bool(true)
            case "false": return .bool(false)
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Replaces the value at a dotted path (e.g. `options.timeoutMs`), rebuilding
    /// the intermediate objects. Missing intermediates are treated as empty objects.
    private static func setValue(_ newValue: JSONValue, atPath path: String, in root: [String: JSONValue]) -> [String: JSONValue] {
        let segments = path.split(separator: ".").map(String.init)
        guard let first = segments.first else { return root }
        var result = root
        if segments.count == 1 {
            result[first] = newValue
        } else {
            let rest = segments.dropFirst().joined(separator: ".")
            let child = result[first]?.objectValue ?? [:]
            result[first] = .object(setValue(newValue, atPath: rest, in: child))
        }
        return result
    }

    private func mapCodeModeFunctionError(_ body: () throws -> JSONValue) throws -> JSONValue {
        do {
            return try body()
        } catch let error as CodeModeFunctionError {
            switch error {
            case let .invalidArguments(message):
                throw BridgeError.invalidArguments(message)
            case let .unsupportedPlatform(feature):
                throw BridgeError.unsupportedPlatform(feature)
            case let .permissionDenied(message):
                throw BridgeError.customPermissionDenied(message)
            case let .nativeFailure(message):
                throw BridgeError.nativeFailure(message)
            }
        }
    }

    private func validateArguments(_ arguments: [String: JSONValue], for function: RegisteredCodeModeFunction) throws {
        let required = function.requiredArguments
        let optional = function.optionalArguments
        let typed = function.argumentTypes
        let name = function.validationName

        let missing = required.filter { value(atPath: $0, in: arguments) == nil }
        if missing.isEmpty == false {
            throw BridgeError.invalidArguments("\(name) missing required arguments: \(missing.joined(separator: ", "))")
        }

        for (path, expectedType) in typed.sorted(by: { $0.key < $1.key }) {
            guard let value = value(atPath: path, in: arguments) else {
                continue
            }

            guard expectedType.matches(value) else {
                throw BridgeError.invalidArguments(
                    "\(name) expected '\(path)' as \(expectedType.rawValue), received \(jsonTypeName(for: value))"
                )
            }
        }

        try function.argumentConstraints.validate(arguments: arguments, capabilityName: name)

        let allowedNames = Set(required + optional + Array(typed.keys))
        if allowedNames.isEmpty == false {
            let allowedTopLevel = Set(allowedNames.map(firstPathSegment))
            let unknown = arguments.keys.sorted().filter { allowedTopLevel.contains($0) == false }
            if unknown.isEmpty == false {
                throw BridgeError.invalidArguments("\(name) received unknown arguments: \(unknown.joined(separator: ", "))")
            }
        }
    }

    private func validatePermissions(_ permissions: [PermissionKind], context: BridgeInvocationContext) throws {
        for permission in permissions {
            try context.checkCancellation()
            let status = context.permissionBroker.status(for: permission)
            context.recordPermission(permission, status: status)

            let resolvedStatus: PermissionStatus
            if status == .notDetermined {
                let requested = context.permissionBroker.request(for: permission)
                context.recordPermission(permission, status: requested)
                resolvedStatus = requested
            } else {
                resolvedStatus = status
            }

            guard permissionStatus(resolvedStatus, satisfies: permission) else {
                throw BridgeError.permissionDenied(permission)
            }

            context.markPermissionValidated(permission)
        }
    }

    private func permissionStatus(_ status: PermissionStatus, satisfies permission: PermissionKind) -> Bool {
        if permission == .calendarWriteOnly, status == .writeOnly {
            return true
        }
        return status == .granted
    }

    private func value(atPath path: String, in root: [String: JSONValue]) -> JSONValue? {
        let segments = path.split(separator: ".").map(String.init)
        guard segments.isEmpty == false else { return nil }

        var current: JSONValue = .object(root)
        for segment in segments {
            guard let object = current.objectValue, let next = object[segment] else {
                return nil
            }
            current = next
        }

        return current
    }

    private func firstPathSegment(_ path: String) -> String {
        path.split(separator: ".").first.map(String.init) ?? path
    }

    private func jsonTypeName(for value: JSONValue) -> String {
        switch value {
        case .string:
            return "string"
        case .number:
            return "number"
        case .bool:
            return "bool"
        case .object:
            return "object"
        case .array:
            return "array"
        case .null:
            return "null"
        }
    }
}
