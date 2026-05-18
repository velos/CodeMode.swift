import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func locationAndWeatherRegistrations() -> [CapabilityRegistration] {
        LocationWeatherCodeModeBuiltIns(location: location, weather: weather).capabilityRegistrations()
    }
}
