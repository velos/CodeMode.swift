import Foundation

protocol BuiltInCodeModeProvider: Sendable {
    func capabilityRegistrations() -> [CapabilityRegistration]
}

struct KeychainCodeModeBuiltIns: BuiltInCodeModeProvider {
    let keychain: KeychainBridge

    func capabilityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: KeychainReadTool(keychain: keychain)),
            CapabilityRegistration(tool: KeychainWriteTool(keychain: keychain)),
            CapabilityRegistration(tool: KeychainDeleteTool(keychain: keychain)),
        ]
    }
}

struct LocationWeatherCodeModeBuiltIns: BuiltInCodeModeProvider {
    let location: LocationBridge
    let weather: WeatherBridge

    func capabilityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: LocationReadTool(location: location)),
            CapabilityRegistration(tool: LocationPermissionRequestTool(location: location)),
            CapabilityRegistration(tool: WeatherReadTool(weather: weather)),
        ]
    }
}

private struct KeychainReadTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var key: String
    }

    static let codeModeCapability: CapabilityID = .keychainRead
    static let codeModePath = "apple.keychain.get"
    static let codeModeTitle = "Read Keychain value"
    static let codeModeSummary = "Read a string value from app-scoped Keychain storage."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.get({ key: 'auth_token' })"
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

    static let codeModeCapability: CapabilityID = .keychainWrite
    static let codeModePath = "apple.keychain.set"
    static let codeModeTitle = "Write Keychain value"
    static let codeModeSummary = "Store or update a string value in app-scoped Keychain storage."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.set({ key: 'auth_token', value: token })"
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

    static let codeModeCapability: CapabilityID = .keychainDelete
    static let codeModePath = "apple.keychain.delete"
    static let codeModeTitle = "Delete Keychain value"
    static let codeModeSummary = "Delete an app-scoped Keychain value."
    static let codeModeTags = ["security", "token", "keychain"]
    static let codeModeExample = "await apple.keychain.delete({ key: 'auth_token' })"
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

private struct LocationReadTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {
        var mode: String?
    }

    static let codeModeCapability: CapabilityID = .locationRead
    static let codeModePath = "apple.location.getCurrentPosition"
    static let codeModeAliasPaths = ["apple.location.getPermissionStatus"]
    static let codeModeTitle = "Read location state or coordinates"
    static let codeModeSummary = "Read location permission status or current coordinates."
    static let codeModeTags = ["location", "permission", "geospatial"]
    static let codeModeExample = "await apple.location.getCurrentPosition()"
    static let codeModeArguments = [
        BuiltInToolArgument("mode", .string, optional: true, hint: "permissionStatus or current (default current)."),
    ]
    static let codeModeResultSummary = "Permission status string or coordinates object."

    let location: LocationBridge

    func decode(arguments: [String: JSONValue]) throws -> Arguments {
        Arguments(mode: try CodeModeArgumentDecoder.optional("mode", as: String.self, in: arguments))
    }

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        var payload: [String: JSONValue] = [:]
        if let mode = arguments.mode {
            payload["mode"] = .string(mode)
        }
        return try location.read(arguments: payload, context: context)
    }
}

private struct LocationPermissionRequestTool: BuiltInCodeModeTool {
    struct Arguments: Sendable {}

    static let codeModeCapability: CapabilityID = .locationPermissionRequest
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

    static let codeModeCapability: CapabilityID = .weatherRead
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
