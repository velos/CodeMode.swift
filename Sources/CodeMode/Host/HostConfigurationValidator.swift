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

        if capabilities.contains(.contactsRead) ||
            capabilities.contains(.contactsSearch) ||
            capabilities.contains(.contactsUIPresentContact) ||
            capabilities.contains(.contactsUIPresentNewContact)
        {
            keys.insert("NSContactsUsageDescription")
        }

        if capabilities.contains(.calendarWrite) ||
            capabilities.contains(.calendarUIPresentNewEvent) ||
            capabilities.contains(.calendarUIPickCalendar)
        {
            keys.insert("NSCalendarsWriteOnlyAccessUsageDescription")
        }

        if capabilities.contains(.calendarRead) ||
            capabilities.contains(.calendarWrite) ||
            capabilities.contains(.calendarDelete) ||
            capabilities.contains(.calendarUIPresentEvent)
        {
            keys.insert("NSCalendarsFullAccessUsageDescription")
        }

        if capabilities.contains(.remindersRead) ||
            capabilities.contains(.remindersWrite) ||
            capabilities.contains(.remindersDelete)
        {
            keys.insert("NSRemindersFullAccessUsageDescription")
        }

        if capabilities.contains(.photosRead) ||
            capabilities.contains(.photosExport) ||
            capabilities.contains(.photosUIPresentLimitedLibraryPicker)
        {
            keys.insert("NSPhotoLibraryUsageDescription")
        }

        if capabilities.contains(.cameraUICapture) ||
            capabilities.contains(.documentsUIScan) ||
            capabilities.contains(.cameraUIScanData)
        {
            keys.insert("NSCameraUsageDescription")
        }

        if capabilities.contains(.cameraUICapture) {
            keys.insert("NSMicrophoneUsageDescription")
        }

        if capabilities.contains(.speechPermissionRequest) ||
            capabilities.contains(.speechFileTranscribe) ||
            capabilities.contains(.speechMicrophoneTranscribe)
        {
            keys.insert("NSSpeechRecognitionUsageDescription")
        }

        if capabilities.contains(.speechMicrophoneTranscribe) {
            keys.insert("NSMicrophoneUsageDescription")
        }

        if capabilities.contains(.musicPermissionRequest) ||
            capabilities.contains(.musicLibraryRead) ||
            capabilities.contains(.musicPlaylistWrite) ||
            capabilities.contains(.musicPlaybackControl)
        {
            keys.insert("NSAppleMusicUsageDescription")
        }

        if capabilities.contains(.homeRead) || capabilities.contains(.homeWrite) {
            keys.insert("NSHomeKitUsageDescription")
        }

        if capabilities.contains(.alarmPermissionRequest) ||
            capabilities.contains(.alarmRead) ||
            capabilities.contains(.alarmSchedule) ||
            capabilities.contains(.alarmCancel)
        {
            keys.insert("NSAlarmKitUsageDescription")
        }

        if capabilities.contains(.healthPermissionRequest) || capabilities.contains(.healthRead) {
            keys.insert("NSHealthShareUsageDescription")
        }

        if capabilities.contains(.healthPermissionRequest) || capabilities.contains(.healthWrite) {
            keys.insert("NSHealthUpdateUsageDescription")
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

        if requiredCapabilities.contains(.notificationsSchedule) ||
            requiredCapabilities.contains(.notificationsPendingRead) ||
            requiredCapabilities.contains(.notificationsPendingDelete) ||
            requiredCapabilities.contains(.notificationsDeliveredRead) ||
            requiredCapabilities.contains(.notificationsDeliveredDelete) ||
            requiredCapabilities.contains(.notificationsRemoteRegister) ||
            requiredCapabilities.contains(.notificationsRemoteTokenRead) ||
            requiredCapabilities.contains(.notificationsSettingsRead) ||
            requiredCapabilities.contains(.notificationsCategoriesSet) ||
            requiredCapabilities.contains(.notificationsResponsesRead) ||
            requiredCapabilities.contains(.notificationsPermissionRequest)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "UserNotifications authorization",
                    message: "Schedule/management calls require user authorization via notifications.permission.request at runtime."
                )
            )
        }

        if requiredCapabilities.contains(.cloudKitAccountStatus) ||
            requiredCapabilities.contains(.cloudKitRecordsQuery) ||
            requiredCapabilities.contains(.cloudKitRecordSave) ||
            requiredCapabilities.contains(.cloudKitRecordDelete) ||
            requiredCapabilities.contains(.cloudKitSubscriptionSave) ||
            requiredCapabilities.contains(.cloudKitSubscriptionEventsRead)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "CloudKit capability",
                    message: "Ensure iCloud/CloudKit entitlements, containers, and host CloudKitClient configuration are enabled before using cloudkit.* capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.notificationsRemoteRegister) ||
            requiredCapabilities.contains(.notificationsRemoteTokenRead) ||
            requiredCapabilities.contains(.notificationsCategoriesSet) ||
            requiredCapabilities.contains(.notificationsResponsesRead)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "APNs client configuration",
                    message: "Remote notification capabilities are client-side only; ensure APS environment entitlement, AppDelegate token plumbing, categories/actions, and any background modes are configured by the host."
                )
            )
        }

        if requiredCapabilities.contains(.speechPermissionRequest) ||
            requiredCapabilities.contains(.speechStatus) ||
            requiredCapabilities.contains(.speechFileTranscribe) ||
            requiredCapabilities.contains(.speechMicrophoneTranscribe)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "Speech capability",
                    message: "Ensure Speech framework availability and a host SpeechClient adapter before using speech.* transcription capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.appIntentsList) ||
            requiredCapabilities.contains(.appIntentsRun) ||
            requiredCapabilities.contains(.appIntentsDonate) ||
            requiredCapabilities.contains(.appIntentsOpen) ||
            requiredCapabilities.contains(.appIntentsHandoffsRead)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "App Intents adapters",
                    message: "App Intents capabilities require host-registered adapters; dynamic AppIntent generation from JavaScript is not supported."
                )
            )
        }

        if requiredCapabilities.contains(.foundationModelsStatus) ||
            requiredCapabilities.contains(.foundationModelsGenerate) ||
            requiredCapabilities.contains(.foundationModelsExtract)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "Foundation Models availability",
                    message: "Ensure Foundation Models platform availability and host-defined schemas/adapters before using foundationModels.* capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.activityList) ||
            requiredCapabilities.contains(.activityStart) ||
            requiredCapabilities.contains(.activityUpdate) ||
            requiredCapabilities.contains(.activityEnd) ||
            requiredCapabilities.contains(.activityPushTokenRead)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "ActivityKit adapters",
                    message: "Live Activity capabilities require ActivityKit support, host-registered activity adapters, and Widget/remote-update configuration when push tokens are used."
                )
            )
        }

        if requiredCapabilities.contains(.musicPermissionRequest) ||
            requiredCapabilities.contains(.musicSubscriptionStatus) ||
            requiredCapabilities.contains(.musicCatalogSearch) ||
            requiredCapabilities.contains(.musicCatalogDetails) ||
            requiredCapabilities.contains(.musicLibraryRead) ||
            requiredCapabilities.contains(.musicPlaylistWrite) ||
            requiredCapabilities.contains(.musicPlaybackControl)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "MusicKit capability",
                    message: "Ensure MusicKit/media-library entitlement, subscription handling, and host MusicClient configuration before using music.* capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.passKitWalletStatus) ||
            requiredCapabilities.contains(.passKitPassesRead) ||
            requiredCapabilities.contains(.passKitPassAdd) ||
            requiredCapabilities.contains(.passKitPassPresent)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "PassKit Wallet capability",
                    message: "Ensure Wallet capability, pass type identifiers, and host PassKitClient configuration before using wallet pass capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.passKitApplePayStatus) ||
            requiredCapabilities.contains(.passKitApplePayPresent)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "Apple Pay merchant configuration",
                    message: "Apple Pay capabilities must use host merchant configuration and explicit user-visible confirmation; arbitrary merchant setup is not accepted from JavaScript."
                )
            )
        }

        if requiredCapabilities.contains(.storeKitProductsRead) ||
            requiredCapabilities.contains(.storeKitEntitlementsRead) ||
            requiredCapabilities.contains(.storeKitPurchase) ||
            requiredCapabilities.contains(.storeKitRestore) ||
            requiredCapabilities.contains(.storeKitTransactionsRead)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "StoreKit configuration",
                    message: "Ensure StoreKit products are host-configured and purchase/restore flows require explicit user-visible confirmation."
                )
            )
        }

        if requiredCapabilities.contains(.homeRead) || requiredCapabilities.contains(.homeWrite) {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "HomeKit capability",
                    message: "Ensure HomeKit entitlement/capability is enabled for the target before using home.* capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.alarmPermissionRequest) ||
            requiredCapabilities.contains(.alarmRead) ||
            requiredCapabilities.contains(.alarmSchedule) ||
            requiredCapabilities.contains(.alarmCancel)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "AlarmKit platform requirement",
                    message: "AlarmKit requires iOS 26+ and runtime authorization before using alarm.* capabilities."
                )
            )
        }

        if requiredCapabilities.contains(.healthPermissionRequest) ||
            requiredCapabilities.contains(.healthRead) ||
            requiredCapabilities.contains(.healthWrite)
        {
            issues.append(
                HostConfigurationIssue(
                    severity: .warning,
                    key: "HealthKit capability",
                    message: "Ensure HealthKit capability/entitlement is enabled before using health.* capabilities."
                )
            )
        }

        return issues
    }
}
