import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func visionRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: VisionImageAnalyzeTool(vision: vision)),
        ]
    }


    func notificationRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: NotificationsPermissionRequestTool(notifications: notifications)),
            CapabilityRegistration(tool: NotificationsScheduleTool(notifications: notifications)),
            CapabilityRegistration(tool: NotificationsPendingReadTool(notifications: notifications)),
            CapabilityRegistration(tool: NotificationsPendingDeleteTool(notifications: notifications)),
            CapabilityRegistration(tool: NotificationsDeliveredReadTool(notifications: notifications)),
            CapabilityRegistration(tool: NotificationsDeliveredDeleteTool(notifications: notifications)),
        ]
    }


    func alarmRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: AlarmPermissionRequestTool(alarm: alarm)),
            CapabilityRegistration(tool: AlarmReadTool(alarm: alarm)),
            CapabilityRegistration(tool: AlarmScheduleTool(alarm: alarm)),
            CapabilityRegistration(tool: AlarmCancelTool(alarm: alarm)),
        ]
    }


    func healthRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: HealthPermissionRequestTool(health: health)),
            CapabilityRegistration(tool: HealthReadTool(health: health)),
            CapabilityRegistration(tool: HealthWriteTool(health: health)),
        ]
    }


    func homeRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: HomeReadTool(home: home)),
            CapabilityRegistration(tool: HomeWriteTool(home: home)),
        ]
    }


    func mediaRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: MediaMetadataReadTool(media: media)),
            CapabilityRegistration(tool: MediaFrameExtractTool(media: media)),
            CapabilityRegistration(tool: MediaTranscodeTool(media: media)),
        ]
    }
}
