import Foundation

public struct CodeModeCapabilityKey: RawRepresentable, Sendable, Codable, Hashable, ExpressibleByStringLiteral, CustomStringConvertible {
    public var rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    public var description: String {
        rawValue
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension CapabilityID {
    var codeModeKey: CodeModeCapabilityKey {
        CodeModeCapabilityKey(rawValue: rawValue)
    }
}

public protocol CodeModeProvider: Sendable {
    var codeModePath: String { get }
    func codeModeRegistrations() -> [CodeModeRegistration]
}

public struct CodeModeRegistration: Sendable {
    public var capabilityKey: CodeModeCapabilityKey
    public var jsPath: String
    public var title: String
    public var summary: String
    public var tags: [String]
    public var example: String
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var argumentTypes: [String: CapabilityArgumentType]
    public var argumentHints: [String: String]
    public var argumentConstraints: CapabilityArgumentConstraints
    public var resultSummary: String
    public var handler: CapabilityHandler

    public init(
        capabilityKey: CodeModeCapabilityKey,
        jsPath: String,
        title: String,
        summary: String,
        tags: [String] = [],
        example: String,
        requiredArguments: [String] = [],
        optionalArguments: [String] = [],
        argumentTypes: [String: CapabilityArgumentType] = [:],
        argumentHints: [String: String] = [:],
        argumentConstraints: CapabilityArgumentConstraints = .none,
        resultSummary: String = "JSON value",
        handler: @escaping CapabilityHandler
    ) {
        self.capabilityKey = capabilityKey
        self.jsPath = jsPath
        self.title = title
        self.summary = summary
        self.tags = tags
        self.example = example
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.argumentTypes = argumentTypes.isEmpty ? Self.inferArgumentTypes(required: requiredArguments, optional: optionalArguments) : argumentTypes
        self.argumentHints = argumentHints
        self.argumentConstraints = argumentConstraints
        self.resultSummary = resultSummary
        self.handler = handler
    }

    private static func inferArgumentTypes(required: [String], optional: [String]) -> [String: CapabilityArgumentType] {
        Dictionary(uniqueKeysWithValues: Array(Set(required + optional)).map { ($0, .any) })
    }
}

public enum CodeModeFunctionError: Error, Sendable, Equatable {
    case invalidArguments(String)
    case unsupportedPlatform(String)
    case permissionDenied(String)
    case nativeFailure(String)
}

public enum CodeModeArgumentDecoder {
    public static func require<T: CodeModeJSONDecodable>(_ name: String, as type: T.Type, in arguments: [String: JSONValue]) throws -> T {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        return try T.decodeCodeModeJSON(value, argumentName: name)
    }

    public static func optional<T: CodeModeJSONDecodable>(_ name: String, as type: T.Type, in arguments: [String: JSONValue]) throws -> T? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        return try T.decodeCodeModeJSON(value, argumentName: name)
    }

    public static func requireString(_ name: String, in arguments: [String: JSONValue]) throws -> String {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        guard let string = value.stringValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as string")
        }
        return string
    }

    public static func optionalString(_ name: String, in arguments: [String: JSONValue]) throws -> String? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        guard let string = value.stringValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as string")
        }
        return string
    }

    public static func requireBool(_ name: String, in arguments: [String: JSONValue]) throws -> Bool {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        guard let bool = value.boolValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as bool")
        }
        return bool
    }

    public static func optionalBool(_ name: String, in arguments: [String: JSONValue]) throws -> Bool? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        guard let bool = value.boolValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as bool")
        }
        return bool
    }

    public static func requireInt(_ name: String, in arguments: [String: JSONValue]) throws -> Int {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        guard let int = value.intValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as number")
        }
        return int
    }

    public static func optionalInt(_ name: String, in arguments: [String: JSONValue]) throws -> Int? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        guard let int = value.intValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as number")
        }
        return int
    }

    public static func requireDouble(_ name: String, in arguments: [String: JSONValue]) throws -> Double {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        guard let double = value.doubleValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as number")
        }
        return double
    }

    public static func optionalDouble(_ name: String, in arguments: [String: JSONValue]) throws -> Double? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        guard let double = value.doubleValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(name)' as number")
        }
        return double
    }

    public static func requireFloat(_ name: String, in arguments: [String: JSONValue]) throws -> Float {
        Float(try requireDouble(name, in: arguments))
    }

    public static func optionalFloat(_ name: String, in arguments: [String: JSONValue]) throws -> Float? {
        try optionalDouble(name, in: arguments).map(Float.init)
    }

    public static func requireJSONValue(_ name: String, in arguments: [String: JSONValue]) throws -> JSONValue {
        guard let value = arguments[name] else {
            throw CodeModeFunctionError.invalidArguments("Missing required argument: \(name)")
        }
        return value
    }

    public static func optionalJSONValue(_ name: String, in arguments: [String: JSONValue]) throws -> JSONValue? {
        guard let value = arguments[name], value != .null else {
            return nil
        }
        return value
    }
}

public enum CodeModeValueEncoder {
    public static func encode(_ value: Void) -> JSONValue {
        .null
    }

    public static func encode(_ value: JSONValue) -> JSONValue {
        value
    }

    public static func encode(_ value: String) -> JSONValue {
        .string(value)
    }

    public static func encode(_ value: Bool) -> JSONValue {
        .bool(value)
    }

    public static func encode(_ value: Int) -> JSONValue {
        .number(Double(value))
    }

    public static func encode(_ value: Double) -> JSONValue {
        .number(value)
    }

    public static func encode(_ value: Float) -> JSONValue {
        .number(Double(value))
    }

    public static func encode<T>(_ value: T) -> JSONValue where T: CodeModeJSONEncodable {
        value.codeModeJSONValue
    }

    public static func encode<T>(_ value: T?) -> JSONValue where T: CodeModeJSONEncodable {
        value.map { $0.codeModeJSONValue } ?? .null
    }
}

public protocol CodeModeJSONDecodable {
    static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Self
}

public protocol CodeModeJSONEncodable {
    var codeModeJSONValue: JSONValue { get }
}

extension JSONValue: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { self }
}

extension JSONValue: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> JSONValue {
        value
    }
}

extension String: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { .string(self) }
}

extension String: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> String {
        guard let string = value.stringValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as string")
        }
        return string
    }
}

extension Bool: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { .bool(self) }
}

extension Bool: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Bool {
        guard let bool = value.boolValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as bool")
        }
        return bool
    }
}

extension Int: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { .number(Double(self)) }
}

extension Int: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Int {
        guard let int = value.intValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as number")
        }
        return int
    }
}

extension Double: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { .number(self) }
}

extension Double: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Double {
        guard let double = value.doubleValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as number")
        }
        return double
    }
}

extension Float: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue { .number(Double(self)) }
}

extension Float: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> Float {
        Float(try Double.decodeCodeModeJSON(value, argumentName: argumentName))
    }
}

extension Array: CodeModeJSONEncodable where Element: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue {
        .array(map(\.codeModeJSONValue))
    }
}

extension Array: CodeModeJSONDecodable where Element: CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> [Element] {
        guard let array = value.arrayValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as array")
        }
        return try array.enumerated().map { index, value in
            try Element.decodeCodeModeJSON(value, argumentName: "\(argumentName)[\(index)]")
        }
    }
}

extension Dictionary: CodeModeJSONEncodable where Key == String, Value: CodeModeJSONEncodable {
    public var codeModeJSONValue: JSONValue {
        .object(mapValues(\.codeModeJSONValue))
    }
}

extension Dictionary: CodeModeJSONDecodable where Key == String, Value: CodeModeJSONEncodable & CodeModeJSONDecodable {
    public static func decodeCodeModeJSON(_ value: JSONValue, argumentName: String) throws -> [String: Value] {
        guard let object = value.objectValue else {
            throw CodeModeFunctionError.invalidArguments("Expected '\(argumentName)' as object")
        }
        return try object.reduce(into: [String: Value]()) { partial, pair in
            partial[pair.key] = try Value.decodeCodeModeJSON(pair.value, argumentName: "\(argumentName).\(pair.key)")
        }
    }
}

public enum CodeModeAsyncBridge {
    public static func run(
        timeoutMs: Int = 30_000,
        operation: @escaping @Sendable () async throws -> JSONValue
    ) throws -> JSONValue {
        let semaphore = DispatchSemaphore(value: 0)
        let result = LockedBox<Result<JSONValue, Error>?>(nil)
        let task = Task {
            do {
                result.set(.success(try await operation()))
            } catch {
                result.set(.failure(error))
            }
            semaphore.signal()
        }

        let deadline = DispatchTime.now() + .milliseconds(timeoutMs)
        if semaphore.wait(timeout: deadline) == .timedOut {
            task.cancel()
            throw CodeModeFunctionError.nativeFailure("CodeMode function timed out after \(timeoutMs)ms")
        }

        return try result.get()!.get()
    }
}
