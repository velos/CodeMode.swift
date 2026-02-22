import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(WeatherKit)
import WeatherKit
#endif

public final class WeatherBridge: @unchecked Sendable {
    public init() {}

    public func read(arguments: [String: JSONValue]) throws -> JSONValue {
        #if canImport(WeatherKit) && canImport(CoreLocation)
        guard let latitude = arguments.double("latitude"), let longitude = arguments.double("longitude") else {
            throw BridgeError.invalidArguments("weather.read requires 'latitude' and 'longitude'")
        }

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = SynchronizedBox<Result<JSONValue, Error>?>(nil)

        Task {
            do {
                let weather = try await WeatherService.shared.weather(for: location)
                resultBox.set(.success(.object([
                    "temperatureCelsius": .number(weather.currentWeather.temperature.converted(to: .celsius).value),
                    "condition": .string(weather.currentWeather.condition.description),
                    "symbolName": .string(weather.currentWeather.symbolName),
                    "date": .string(weather.currentWeather.date.ISO8601Format()),
                ])))
            } catch {
                resultBox.set(.failure(error))
            }
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 30)

        switch resultBox.get() {
        case let .success(payload):
            return payload
        case let .failure(error):
            throw BridgeError.nativeFailure("weather.read failed: \(error.localizedDescription)")
        case .none:
            throw BridgeError.timeout(milliseconds: 30_000)
        }
        #else
        _ = arguments
        throw BridgeError.unsupportedPlatform("WeatherKit")
        #endif
    }
}
