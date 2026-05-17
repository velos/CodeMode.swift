import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func locationAndWeatherRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .locationRead,
                    title: "Read location state or coordinates",
                    summary: "Read location permission status or current coordinates.",
                    tags: ["location", "permission", "geospatial"],
                    example: "await apple.location.getCurrentPosition()",
                    requiredPermissions: [],
                    optionalArguments: ["mode"],
                    argumentHints: [
                        "mode": "permissionStatus or current (default current).",
                    ],
                    resultSummary: "Permission status string or coordinates object."
                ),
                handler: { args, context in
                    try location.read(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .locationPermissionRequest,
                    title: "Request location permission",
                    summary: "Trigger location when-in-use permission request flow.",
                    tags: ["location", "permission"],
                    example: "await apple.location.requestPermission()",
                    resultSummary: "Permission status string."
                ),
                handler: { _, context in
                    location.requestPermission(context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .weatherRead,
                    title: "Read WeatherKit weather",
                    summary: "Fetch current weather for a latitude/longitude pair.",
                    tags: ["weather", "forecast", "weatherkit"],
                    example: "await apple.weather.getCurrentWeather({ latitude: 37.77, longitude: -122.41 })",
                    requiredArguments: ["latitude", "longitude"],
                    argumentHints: [
                        "latitude": "Latitude in decimal degrees.",
                        "longitude": "Longitude in decimal degrees.",
                    ],
                    resultSummary: "Object with temperatureCelsius/condition/symbolName/date."
                ),
                handler: { args, _ in
                    try weather.read(arguments: args)
                }
            ),
        ]
    }
}
