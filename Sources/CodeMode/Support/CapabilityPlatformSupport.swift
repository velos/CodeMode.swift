import Foundation

enum CapabilityPlatformSupport {
    static func supportedCapabilities(for platform: HostPlatform = .current) -> Set<CapabilityID> {
        let common: Set<CapabilityID> = [
            .networkFetch,
            .keychainRead,
            .keychainWrite,
            .keychainDelete,
            .fsList,
            .fsRead,
            .fsWrite,
            .fsMove,
            .fsCopy,
            .fsDelete,
            .fsStat,
            .fsMkdir,
            .fsExists,
            .fsAccess,
        ]

        switch platform {
        case .iOS:
            return common.union(iOSCapabilities)
        case .macOS:
            return common.union(macOSCapabilities)
        case .watchOS:
            return []
        case .visionOS:
            return common.union(visionOSCapabilities)
        }
    }

    static func isSupported(_ capability: CapabilityID, for platform: HostPlatform = .current) -> Bool {
        supportedCapabilities(for: platform).contains(capability)
    }

    static func filter(_ registrations: [CapabilityRegistration], for platform: HostPlatform = .current) -> [CapabilityRegistration] {
        let supported = supportedCapabilities(for: platform)
        return registrations.filter { supported.contains($0.descriptor.id) }
    }

    private static let crossAppleCapabilities: Set<CapabilityID> = [
        .locationRead,
        .weatherRead,
        .calendarRead,
        .calendarWrite,
        .remindersRead,
        .remindersWrite,
        .contactsRead,
        .contactsSearch,
        .photosRead,
        .photosExport,
        .visionImageAnalyze,
        .notificationsPermissionRequest,
        .notificationsSchedule,
        .notificationsPendingRead,
        .notificationsPendingDelete,
        .healthPermissionRequest,
        .healthRead,
        .healthWrite,
        .homeRead,
        .homeWrite,
        .mediaMetadataRead,
        .mediaFrameExtract,
        .mediaTranscode,
    ]

    private static let iOSCapabilities = crossAppleCapabilities.union([
        .calendarUIPickCalendar,
        .calendarUIPresentEvent,
        .calendarUIPresentNewEvent,
        .contactsUIPick,
        .contactsUIPresentContact,
        .contactsUIPresentNewContact,
        .photosUIPick,
        .photosUIPresentLimitedLibraryPicker,
        .documentsUIPick,
        .documentsUIExport,
        .documentsUIOpenIn,
        .documentsUIScan,
        .shareUIPresent,
        .quickLookUIPreview,
        .cameraUICapture,
        .cameraUIScanData,
        .mailUICompose,
        .messagesUICompose,
        .printUIPresent,
        .webUIPresent,
        .authUIWebAuthenticate,
        .uiAlertPresent,
        .uiPromptPresent,
        .settingsUIOpen,
        .locationPermissionRequest,
        .alarmPermissionRequest,
        .alarmRead,
        .alarmSchedule,
        .alarmCancel,
    ])

    private static let macOSCapabilities = crossAppleCapabilities

    private static let visionOSCapabilities = crossAppleCapabilities.union([
        .calendarUIPickCalendar,
        .calendarUIPresentEvent,
        .calendarUIPresentNewEvent,
        .contactsUIPick,
        .contactsUIPresentContact,
        .contactsUIPresentNewContact,
        .photosUIPick,
        .photosUIPresentLimitedLibraryPicker,
        .documentsUIPick,
        .documentsUIExport,
        .documentsUIOpenIn,
        .shareUIPresent,
        .quickLookUIPreview,
        .cameraUIScanData,
        .printUIPresent,
        .webUIPresent,
        .authUIWebAuthenticate,
        .uiAlertPresent,
        .uiPromptPresent,
        .settingsUIOpen,
    ])

}
