import Foundation

protocol BuiltInCodeModeProvider: Sendable {
    func capabilityRegistrations() -> [CapabilityRegistration]
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
}

struct KeychainCodeModeBuiltIns: BuiltInCodeModeProvider {
    let keychain: KeychainBridge

    func capabilityRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                builtInCapability: .keychainRead,
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.keychainRead.codeModeKey,
                    jsPath: "apple.keychain.get",
                    title: "Read Keychain value",
                    summary: "Read a string value from app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.get('auth_token')",
                    requiredArguments: ["key"],
                    argumentTypes: ["key": .string],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                    ],
                    resultSummary: "Object { key, value } or null when the key does not exist."
                ) { args, _ in
                    try keychain.read(arguments: args)
                }
            ),
            CapabilityRegistration(
                builtInCapability: .keychainWrite,
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.keychainWrite.codeModeKey,
                    jsPath: "apple.keychain.set",
                    title: "Write Keychain value",
                    summary: "Store or update a string value in app-scoped Keychain storage.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.set('auth_token', token)",
                    requiredArguments: ["key"],
                    optionalArguments: ["value"],
                    argumentTypes: [
                        "key": .string,
                        "value": .string,
                    ],
                    argumentHints: [
                        "key": "Logical key for this secret value.",
                        "value": "Secret string value. Defaults to empty string when omitted.",
                    ],
                    resultSummary: "Object { key, written: true }."
                ) { args, _ in
                    try keychain.write(arguments: args)
                }
            ),
            CapabilityRegistration(
                builtInCapability: .keychainDelete,
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.keychainDelete.codeModeKey,
                    jsPath: "apple.keychain.delete",
                    title: "Delete Keychain value",
                    summary: "Delete an app-scoped Keychain value.",
                    tags: ["security", "token", "keychain"],
                    example: "await apple.keychain.delete('auth_token')",
                    requiredArguments: ["key"],
                    argumentTypes: ["key": .string],
                    argumentHints: [
                        "key": "Logical key for value removal.",
                    ],
                    resultSummary: "Object { key, deleted: true }."
                ) { args, _ in
                    try keychain.delete(arguments: args)
                }
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
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.locationPermissionRequest.codeModeKey,
                    jsPath: "apple.location.requestPermission",
                    title: "Request location permission",
                    summary: "Trigger location when-in-use permission request flow.",
                    tags: ["location", "permission"],
                    example: "await apple.location.requestPermission()",
                    resultSummary: "Permission status string."
                ) { _, context in
                    location.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                builtInCapability: .weatherRead,
                registration: CodeModeRegistration(
                    capabilityKey: CapabilityID.weatherRead.codeModeKey,
                    jsPath: "apple.weather.getCurrentWeather",
                    title: "Read WeatherKit weather",
                    summary: "Fetch current weather for a latitude/longitude pair.",
                    tags: ["weather", "forecast", "weatherkit"],
                    example: "await apple.weather.getCurrentWeather({ latitude: 37.77, longitude: -122.41 })",
                    requiredArguments: ["latitude", "longitude"],
                    argumentTypes: [
                        "latitude": .number,
                        "longitude": .number,
                    ],
                    argumentHints: [
                        "latitude": "Latitude in decimal degrees.",
                        "longitude": "Longitude in decimal degrees.",
                    ],
                    resultSummary: "Object with temperatureCelsius/condition/symbolName/date."
                ) { args, _ in
                    try weather.read(arguments: args)
                }
            ),
        ]
    }
}
