import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func contactRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: ContactsReadTool(contacts: contacts)),
            CapabilityRegistration(tool: ContactsSearchTool(contacts: contacts)),
            CapabilityRegistration(tool: ContactsUIPickTool(systemUI: systemUI)),
            CapabilityRegistration(tool: ContactsUIPresentContactTool(systemUI: systemUI)),
            CapabilityRegistration(tool: ContactsUIPresentNewContactTool(systemUI: systemUI)),
        ]
    }


    func photoAndDocumentRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(tool: PhotosReadTool(photos: photos)),
            CapabilityRegistration(tool: PhotosExportTool(photos: photos)),
            CapabilityRegistration(tool: PhotosUIPickTool(systemUI: systemUI)),
            CapabilityRegistration(tool: PhotosUIPresentLimitedLibraryPickerTool(systemUI: systemUI)),
            CapabilityRegistration(tool: DocumentsUIPickTool(systemUI: systemUI)),
            CapabilityRegistration(tool: DocumentsUIExportTool(systemUI: systemUI)),
            CapabilityRegistration(tool: DocumentsUIOpenInTool(systemUI: systemUI)),
            CapabilityRegistration(tool: DocumentsUIScanTool(systemUI: systemUI)),
        ]
    }
}
