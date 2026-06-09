import Foundation

protocol BuiltInCodeModeProvider: Sendable {
    func capabilityRegistrations() -> [CapabilityRegistration]
}

private struct BuiltInToolArgument {
    var name: String
    var type: CapabilityArgumentType
    var optional: Bool
    var hint: String

    init(_ name: String, _ type: CapabilityArgumentType, optional: Bool = false, hint: String) {
        self.name = name
        self.type = type
        self.optional = optional
        self.hint = hint
    }
}

private protocol BuiltInCodeModeTool: Sendable {
    associatedtype Arguments: Sendable

    static var codeModePath: String { get }
    static var codeModeTitle: String { get }
    static var codeModeSummary: String { get }
    static var codeModeTags: [String] { get }
    static var codeModeExample: String { get }
    static var codeModeArguments: [BuiltInToolArgument] { get }
    static var codeModeResultSummary: String { get }

    func decode(arguments: [String: JSONValue]) throws -> Arguments
    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue
}

private extension BuiltInCodeModeTool {
    static var requiredArguments: [String] {
        codeModeArguments.filter { $0.optional == false }.map(\.name)
    }

    static var optionalArguments: [String] {
        codeModeArguments.filter(\.optional).map(\.name)
    }

    static var argumentTypes: [String: CapabilityArgumentType] {
        Dictionary(uniqueKeysWithValues: codeModeArguments.map { ($0.name, $0.type) })
    }

    static var argumentHints: [String: String] {
        Dictionary(uniqueKeysWithValues: codeModeArguments.map { ($0.name, $0.hint) })
    }

    func codeModeRegistration(capabilityKey: CodeModeCapabilityKey) -> CodeModeRegistration {
        CodeModeRegistration(
            capabilityKey: capabilityKey,
            jsPath: Self.codeModePath,
            title: Self.codeModeTitle,
            summary: Self.codeModeSummary,
            tags: Self.codeModeTags,
            example: Self.codeModeExample,
            requiredArguments: Self.requiredArguments,
            optionalArguments: Self.optionalArguments,
            argumentTypes: Self.argumentTypes,
            argumentHints: Self.argumentHints,
            resultSummary: Self.codeModeResultSummary
        ) { rawArguments, context in
            let decodedArguments = try decode(arguments: rawArguments)
            return try call(arguments: decodedArguments, context: context)
        }
    }
}

extension CapabilityRegistration {
    init(
        builtInCapability: CapabilityID,
        jsNames: [String]? = nil,
        registration: CodeModeRegistration,
        requiredPermissions: [PermissionKind] = []
    ) {
        self.init(
            jsNames: jsNames ?? [registration.jsPath],
            descriptor: CapabilityDescriptor(
                id: builtInCapability,
                title: registration.title,
                summary: registration.summary,
                tags: registration.tags,
                example: registration.example,
                requiredPermissions: requiredPermissions,
                requiredArguments: registration.requiredArguments,
                optionalArguments: registration.optionalArguments,
                argumentTypes: registration.argumentTypes,
                argumentHints: registration.argumentHints,
                argumentConstraints: registration.argumentConstraints == .none ? nil : registration.argumentConstraints,
                resultSummary: registration.resultSummary
            ),
            handler: registration.handler
        )
    }

    fileprivate init<Tool: BuiltInCodeModeTool>(
        builtInCapability: CapabilityID,
        jsNames: [String]? = nil,
        tool: Tool,
        requiredPermissions: [PermissionKind] = []
    ) {
        self.init(
            builtInCapability: builtInCapability,
            jsNames: jsNames,
            registration: tool.codeModeRegistration(capabilityKey: builtInCapability.codeModeKey),
            requiredPermissions: requiredPermissions
        )
    }
}

struct KeychainCodeModeBuiltIns: BuiltInCodeModeProvider {
    let keychain: KeychainBridge

    func capabilityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                builtInCapability: .keychainRead,
                tool: KeychainReadTool(keychain: keychain)
            ),
            CapabilityRegistration(
                builtInCapability: .keychainWrite,
                tool: KeychainWriteTool(keychain: keychain)
            ),
            CapabilityRegistration(
                builtInCapability: .keychainDelete,
                tool: KeychainDeleteTool(keychain: keychain)
            ),
        ]
    }
}

struct LocationWeatherCodeModeBuiltIns: BuiltInCodeModeProvider {
    let location: LocationBridge
    let weather: WeatherBridge

    func capabilityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                builtInCapability: .locationRead,
                jsNames: ["apple.location.getPermissionStatus", "apple.location.getCurrentPosition"],
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.locationRead.codeModeKey,
                    jsPath: "apple.location.getCurrentPosition",
                    title: "Read location state or coordinates",
                    summary: "Read location permission status or current coordinates.",
                    tags: ["location", "permission", "geospatial"],
                    example: "await apple.location.getCurrentPosition()",
                    optionalArguments: ["mode"],
                    argumentTypes: ["mode": .string],
                    argumentHints: [
                        "mode": "permissionStatus or current (default current).",
                    ],
                    resultSummary: "Permission status string or coordinates object."
                ) { args, context in
                    try location.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                builtInCapability: .locationPermissionRequest,
                tool: LocationPermissionRequestTool(location: location)
            ),
            CapabilityRegistration(
                builtInCapability: .weatherRead,
                tool: WeatherReadTool(weather: weather)
            ),
        ]
    }
}

private struct KeychainReadTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var key: String
    }

    static let codeModePath = "apple.keychain.get"
    static let codeModeTitle = "Read Keychain value"
    static let codeModeSummary = "Read a string value from app-scoped Keychain storage."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.get('auth_token')"
    static let codeModeArguments = [
        BuiltInToolArgument("key", .string, hint: "Logical key for this secret value."),
    ]
    static let codeModeResultSummary = "Object { key, value } or null when the key does not exist."

    let keychain: KeychainBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(key: try CodeModeArgumentDecoder.require("key", as: String.self, in: arguments))
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try keychain.read(arguments: ["key": .string(arguments.key)])
    }
}

private struct KeychainWriteTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var key: String
        var value: String?
    }

    static let codeModePath = "apple.keychain.set"
    static let codeModeTitle = "Write Keychain value"
    static let codeModeSummary = "Store or update a string value in app-scoped Keychain storage."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.set('auth_token', token)"
    static let codeModeArguments = [
        BuiltInToolArgument("key", .string, hint: "Logical key for this secret value."),
        BuiltInToolArgument("value", .string, optional: true, hint: "Secret string value. Defaults to empty string when omitted."),
    ]
    static let codeModeResultSummary = "Object { key, written: true }."

    let keychain: KeychainBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(
            key: try CodeModeArgumentDecoder.require("key", as: String.self, in: arguments),
            value: try CodeModeArgumentDecoder.optional("value", as: String.self, in: arguments)
        )
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        var payload: [String: JSONValue] = ["key": .string(arguments.key)]
        if let value = arguments.value {
            payload["value"] = .string(value)
        }
        return try keychain.write(arguments: payload)
    }
}

private struct KeychainDeleteTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var key: String
    }

    static let codeModePath = "apple.keychain.delete"
    static let codeModeTitle = "Delete Keychain value"
    static let codeModeSummary = "Delete an app-scoped Keychain value."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.delete('auth_token')"
    static let codeModeArguments = [
        BuiltInToolArgument("key", .string, hint: "Logical key for value removal."),
    ]
    static let codeModeResultSummary = "Object { key, deleted: true }."

    let keychain: KeychainBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(key: try CodeModeArgumentDecoder.require("key", as: String.self, in: arguments))
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try keychain.delete(arguments: ["key": .string(arguments.key)])
    }
}

private struct LocationPermissionRequestTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {}

    static let codeModePath = "apple.location.requestPermission"
    static let codeModeTitle = "Request location permission"
    static let codeModeSummary = "Trigger location when-in-use permission request flow."
    static let codeModeTags = ["location", "permission"]
    static let codeModeExample = "await apple.location.requestPermission()"
    static let codeModeArguments: [BuiltInToolArgument] = []
    static let codeModeResultSummary = "Permission status string."

    let location: LocationBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments()
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        location.requestPermission(context: context)
    }
}

private struct WeatherReadTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var latitude: Double
        var longitude: Double
    }

    static let codeModePath = "apple.weather.getCurrentWeather"
    static let codeModeTitle = "Read WeatherKit weather"
    static let codeModeSummary = "Fetch current weather for a latitude/longitude pair."
    static let codeModeTags = ["weather", "forecast", "weatherkit"]
    static let codeModeExample = "await apple.weather.getCurrentWeather({ latitude: 37.77, longitude: -122.41 })"
    static let codeModeArguments = [
        BuiltInToolArgument("latitude", .number, hint: "Latitude in decimal degrees."),
        BuiltInToolArgument("longitude", .number, hint: "Longitude in decimal degrees."),
    ]
    static let codeModeResultSummary = "Object with temperatureCelsius/condition/symbolName/date."

    let weather: WeatherBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(
            latitude: try CodeModeArgumentDecoder.require("latitude", as: Double.self, in: arguments),
            longitude: try CodeModeArgumentDecoder.require("longitude", as: Double.self, in: arguments)
        )
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try weather.read(arguments: [
            "latitude": .number(arguments.latitude),
            "longitude": .number(arguments.longitude),
        ])
    }
}
