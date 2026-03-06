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
        self.resultSummary = resultSummary
    }

    private static func inferArgumentTypes(required: [String], optional: [String]) -> [String: CapabilityArgumentType] {
        let known: [String: CapabilityArgumentType] = [
            "url": .string,
            "options": .object,
            "options.method": .string,
            "options.headers": .object,
            "options.body": .string,

            "key": .string,
            "value": .string,

            "mode": .string,

            "latitude": .number,
            "longitude": .number,

            "start": .string,
            "end": .string,
            "title": .string,
            "notes": .string,
            "dueDate": .string,
            "query": .string,
            "limit": .number,
            "identifiers": .array,
            "localIdentifier": .string,
            "mediaType": .string,
            "features": .array,
            "maxResults": .number,
            "identifier": .string,
            "subtitle": .string,
            "body": .string,
            "secondsFromNow": .number,
            "fireDate": .string,
            "repeats": .bool,
            "includeCharacteristics": .bool,
            "accessoryIdentifier": .string,
            "serviceType": .string,
            "characteristicType": .string,

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
    public var handler: CapabilityHandler

    public init(descriptor: CapabilityDescriptor, handler: @escaping CapabilityHandler) {
        self.descriptor = descriptor
        self.handler = handler
    }
}

public final class CapabilityRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var registrations: [CapabilityID: CapabilityRegistration] = [:]

    public init(registrations: [CapabilityRegistration] = []) {
        for registration in registrations {
            self.registrations[registration.descriptor.id] = registration
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

    public func descriptor(for capability: CapabilityID) -> CapabilityDescriptor? {
        lock.lock()
        defer { lock.unlock() }
        return registrations[capability]?.descriptor
    }

    public func allDescriptors() -> [CapabilityDescriptor] {
        lock.lock()
        defer { lock.unlock() }
        return registrations.values.map(\.descriptor)
    }

    public func invoke(_ capabilityID: String, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try context.checkCancellation()

        guard let capability = CapabilityID(rawValue: capabilityID) else {
            throw BridgeError.capabilityNotFound(capabilityID)
        }

        guard context.allowedCapabilities.contains(capability) else {
            throw BridgeError.capabilityDenied(capability)
        }

        lock.lock()
        let registration = registrations[capability]
        lock.unlock()

        guard let registration else {
            throw BridgeError.capabilityNotFound(capabilityID)
        }

        try validateArguments(arguments, for: capability, descriptor: registration.descriptor)

        for permission in registration.descriptor.requiredPermissions {
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

            guard resolvedStatus == .granted else {
                throw BridgeError.permissionDenied(permission)
            }

            context.markPermissionValidated(permission)
        }

        try context.checkCancellation()
        return try registration.handler(arguments, context)
    }

    private func validateArguments(_ arguments: [String: JSONValue], for capability: CapabilityID, descriptor: CapabilityDescriptor) throws {
        let required = descriptor.requiredArguments
        let optional = descriptor.optionalArguments
        let typed = descriptor.argumentTypes

        let missing = required.filter { value(atPath: $0, in: arguments) == nil }
        if missing.isEmpty == false {
            let names = missing.joined(separator: ", ")
            throw BridgeError.invalidArguments("\(capability.rawValue) missing required arguments: \(names)")
        }

        for (path, expectedType) in typed.sorted(by: { $0.key < $1.key }) {
            guard let value = value(atPath: path, in: arguments) else {
                continue
            }

            guard expectedType.matches(value) else {
                throw BridgeError.invalidArguments(
                    "\(capability.rawValue) expected '\(path)' as \(expectedType.rawValue), received \(jsonTypeName(for: value))"
                )
            }
        }

        let allowedNames = Set(required + optional + Array(typed.keys))
        if allowedNames.isEmpty == false {
            let allowedTopLevel = Set(allowedNames.map(firstPathSegment))
            let unknown = arguments.keys.sorted().filter { allowedTopLevel.contains($0) == false }
            if unknown.isEmpty == false {
                throw BridgeError.invalidArguments("\(capability.rawValue) received unknown arguments: \(unknown.joined(separator: ", "))")
            }
        }
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
