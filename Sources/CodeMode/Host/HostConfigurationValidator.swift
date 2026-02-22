import Foundation

public struct HostConfigurationIssue: Sendable, Codable, Equatable {
    public enum Severity: String, Sendable, Codable {
        case error
        case warning
    }

    public var severity: Severity
    public var key: String
    public var message: String

    public init(severity: Severity, key: String, message: String) {
        self.severity = severity
        self.key = key
        self.message = message
    }
}

public enum HostConfigurationValidator {
    public static func requiredInfoPlistKeys(for capabilities: Set<CapabilityID>) -> Set<String> {
        var keys: Set<String> = []

        if capabilities.contains(.locationRead) || capabilities.contains(.locationPermissionRequest) {
            keys.insert("NSLocationWhenInUseUsageDescription")
        }

        if capabilities.contains(.contactsRead) || capabilities.contains(.contactsSearch) {
            keys.insert("NSContactsUsageDescription")
        }

        if capabilities.contains(.calendarRead) || capabilities.contains(.calendarWrite) {
            keys.insert("NSCalendarsWriteOnlyAccessUsageDescription")
        }

        if capabilities.contains(.calendarRead) {
            keys.insert("NSCalendarsFullAccessUsageDescription")
        }

        if capabilities.contains(.remindersRead) || capabilities.contains(.remindersWrite) {
            keys.insert("NSRemindersFullAccessUsageDescription")
        }

        return keys
    }

    public static func validate(requiredCapabilities: Set<CapabilityID>, bundle: Bundle = .main) -> [HostConfigurationIssue] {
        validate(requiredCapabilities: requiredCapabilities, infoPlist: bundle.infoDictionary ?? [:])
    }

    public static func validate(requiredCapabilities: Set<CapabilityID>, infoPlist: [String: Any]) -> [HostConfigurationIssue] {
        var issues: [HostConfigurationIssue] = []
        let keys = requiredInfoPlistKeys(for: requiredCapabilities)

        for key in keys.sorted() {
            let value = infoPlist[key] as? String
            if value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(
                    HostConfigurationIssue(
                        severity: .error,
                        key: key,
                        message: "Missing Info.plist privacy usage description string for \(key)."
                    )
                )
            }
        }

        if requiredCapabilities.contains(.weatherRead) {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "WeatherKit capability",
                    message: "Ensure WeatherKit is enabled for the App ID and target capability before using weather.read."
                )
            )
        }

        return issues
    }
}
