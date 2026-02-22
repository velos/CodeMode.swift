import Foundation
import Testing
@testable import CodeMode

@Test func weatherBridgeValidatesRequiredCoordinates() {
    let bridge = WeatherBridge()

    do {
        _ = try bridge.read(arguments: [:])
        Issue.record("Expected weather.read to fail without coordinates")
    } catch {
        #if canImport(WeatherKit) && canImport(CoreLocation)
        #expect(requireBridgeErrorCode(error) == "INVALID_ARGUMENTS")
        #else
        #expect(requireBridgeErrorCode(error) == "UNSUPPORTED_PLATFORM")
        #endif
    }
}

@Test func executeUsesWeatherBridgeValidation() async throws {
    let (host, sandbox) = try makeHost()
    defer { cleanup(sandbox) }

    let response = try await host.execute(
        ExecuteRequest(
            code: """
            await ios.weather.getCurrentWeather({});
            return { ok: true };
            """,
            allowedCapabilities: [.weatherRead]
        )
    )

    #if canImport(WeatherKit) && canImport(CoreLocation)
    #expect(response.diagnostics.contains(where: { $0.code == "INVALID_ARGUMENTS" }))
    #else
    #expect(response.diagnostics.contains(where: { $0.code == "UNSUPPORTED_PLATFORM" }))
    #endif
}
