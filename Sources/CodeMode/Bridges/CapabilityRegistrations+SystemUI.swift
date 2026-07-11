import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func interactionUIRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: ShareUIPresentTool(systemUI: systemUI)),
            CapabilityRegistration(tool: QuickLookUIPreviewTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CameraUICaptureTool(systemUI: systemUI)),
            CapabilityRegistration(tool: CameraUIScanDataTool(systemUI: systemUI)),
            CapabilityRegistration(tool: MailUIComposeTool(systemUI: systemUI)),
            CapabilityRegistration(tool: MessagesUIComposeTool(systemUI: systemUI)),
            CapabilityRegistration(tool: PrintUIPresentTool(systemUI: systemUI)),
            CapabilityRegistration(tool: WebUIPresentTool(systemUI: systemUI)),
            CapabilityRegistration(tool: AuthUIWebAuthenticateTool(systemUI: systemUI)),
            CapabilityRegistration(tool: UIAlertPresentTool(systemUI: systemUI)),
            CapabilityRegistration(tool: UIPromptPresentTool(systemUI: systemUI)),
            CapabilityRegistration(tool: SettingsUIOpenTool(systemUI: systemUI)),
        ]
    }
}
