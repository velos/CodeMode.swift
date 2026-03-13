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
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.weather.getCurrentWeather({});
            return { ok: true };
            """,
            allowedCapabilities: [.weatherRead]
        )
    )

    #if canImport(WeatherKit) && canImport(CoreLocation)
    #expect(observed.error?.code == "INVALID_ARGUMENTS")
    #else
    #expect(observed.error?.code == "UNSUPPORTED_PLATFORM")
    #endif
}
