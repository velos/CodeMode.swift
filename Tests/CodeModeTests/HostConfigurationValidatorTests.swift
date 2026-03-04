import Foundation
import Testing
@testable import CodeMode

@Test func requiredInfoPlistKeysMatchCapabilitySet() {
    let keys = HostConfigurationValidator.requiredInfoPlistKeys(
        for: [.locationRead, .contactsSearch, .calendarRead, .remindersWrite, .photosRead, .homeWrite, .alarmSchedule]
    )

    #expect(keys.contains("NSLocationWhenInUseUsageDescription"))
    #expect(keys.contains("NSContactsUsageDescription"))
    #expect(keys.contains("NSCalendarsFullAccessUsageDescription"))
    #expect(keys.contains("NSCalendarsWriteOnlyAccessUsageDescription"))
    #expect(keys.contains("NSRemindersFullAccessUsageDescription"))
    #expect(keys.contains("NSPhotoLibraryUsageDescription"))
    #expect(keys.contains("NSHomeKitUsageDescription"))
    #expect(keys.contains("NSAlarmKitUsageDescription"))
}

@Test func validatorReportsMissingUsageDescriptions() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.locationRead, .contactsRead],
        infoPlist: [:]
    )

    #expect(issues.contains(where: { $0.key == "NSLocationWhenInUseUsageDescription" && $0.severity == .error }))
    #expect(issues.contains(where: { $0.key == "NSContactsUsageDescription" && $0.severity == .error }))
}

@Test func validatorPassesWhenUsageDescriptionsExist() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.locationRead, .contactsRead, .calendarRead, .calendarWrite],
        infoPlist: [
            "NSLocationWhenInUseUsageDescription": "Need location for nearby weather",
            "NSContactsUsageDescription": "Need contacts for lookup",
            "NSCalendarsFullAccessUsageDescription": "Need full calendar access for reading events",
            "NSCalendarsWriteOnlyAccessUsageDescription": "Need write-only calendar access for adding events",
        ]
    )

    #expect(issues.isEmpty)
}

@Test func validatorAddsWeatherKitWarning() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.weatherRead],
        infoPlist: [:]
    )

    #expect(issues.contains(where: { $0.key == "WeatherKit capability" && $0.severity == .warning }))
}

@Test func validatorRequiresWriteOnlyCalendarKeyForCalendarWrite() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.calendarWrite],
        infoPlist: [:]
    )

    #expect(issues.contains(where: { $0.key == "NSCalendarsWriteOnlyAccessUsageDescription" && $0.severity == .error }))
    #expect(issues.contains(where: { $0.key == "NSCalendarsFullAccessUsageDescription" }) == false)
}

@Test func validatorReportsPhotosAndHomeKitMissingUsageDescriptions() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.photosRead, .homeRead],
        infoPlist: [:]
    )

    #expect(issues.contains(where: { $0.key == "NSPhotoLibraryUsageDescription" && $0.severity == .error }))
    #expect(issues.contains(where: { $0.key == "NSHomeKitUsageDescription" && $0.severity == .error }))
}

@Test func validatorAddsNotificationsAndHomeWarnings() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.notificationsSchedule, .homeRead],
        infoPlist: [
            "NSHomeKitUsageDescription": "Need HomeKit to read home accessories",
        ]
    )

    #expect(issues.contains(where: { $0.key == "UserNotifications authorization" && $0.severity == .warning }))
    #expect(issues.contains(where: { $0.key == "HomeKit capability" && $0.severity == .warning }))
}

@Test func validatorRequiresAlarmKitUsageAndAddsPlatformWarning() {
    let issues = HostConfigurationValidator.validate(
        requiredCapabilities: [.alarmSchedule],
        infoPlist: [:]
    )

    #expect(issues.contains(where: { $0.key == "NSAlarmKitUsageDescription" && $0.severity == .error }))
    #expect(issues.contains(where: { $0.key == "AlarmKit platform requirement" && $0.severity == .warning }))
}
