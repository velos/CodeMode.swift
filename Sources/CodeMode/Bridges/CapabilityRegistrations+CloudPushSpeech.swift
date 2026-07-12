import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func bigTicketAppleRegistrations() -> [CapabilityRegistration] {
        [
            cloudKitRegistrations(),
            remoteNotificationRegistrations(),
            speechRegistrations(),
            appIntentsRegistrations(),
            foundationModelsRegistrations(),
            activityRegistrations(),
            mapsRegistrations(),
            musicRegistrations(),
            passKitRegistrations(),
            storeKitRegistrations(),
        ].flatMap { $0 }
    }


    func cloudKitRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: CloudKitAccountStatusTool(cloudKit: cloudKit)),
            CapabilityRegistration(tool: CloudKitRecordsQueryTool(cloudKit: cloudKit)),
            CapabilityRegistration(tool: CloudKitRecordSaveTool(cloudKit: cloudKit)),
            CapabilityRegistration(tool: CloudKitRecordDeleteTool(cloudKit: cloudKit)),
            CapabilityRegistration(tool: CloudKitSubscriptionSaveTool(cloudKit: cloudKit)),
            CapabilityRegistration(tool: CloudKitSubscriptionEventsReadTool(cloudKit: cloudKit)),
        ]
    }


    func remoteNotificationRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: NotificationsRemoteRegisterTool(remoteNotifications: remoteNotifications)),
            CapabilityRegistration(tool: NotificationsRemoteTokenReadTool(remoteNotifications: remoteNotifications)),
            CapabilityRegistration(tool: NotificationsSettingsReadTool(remoteNotifications: remoteNotifications)),
            CapabilityRegistration(tool: NotificationsCategoriesSetTool(remoteNotifications: remoteNotifications)),
            CapabilityRegistration(tool: NotificationsResponsesReadTool(remoteNotifications: remoteNotifications)),
        ]
    }


    func speechRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: SpeechPermissionRequestTool(speech: speech)),
            CapabilityRegistration(tool: SpeechStatusTool(speech: speech)),
            CapabilityRegistration(tool: SpeechFileTranscribeTool(speech: speech)),
            CapabilityRegistration(tool: SpeechMicrophoneTranscribeTool(speech: speech)),
        ]
    }
}
