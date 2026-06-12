import Foundation
@testable import CodeMode

struct FakeSystemUIPresenter: SystemUIPresenter {
    var calendarResult: JSONValue
    var photosResult: JSONValue
    var contactsResult: JSONValue
    var extraResults: [CapabilityID: JSONValue]
    var expectedArguments: [CapabilityID: [String: JSONValue]]
    var error: BridgeError?

    init(
        calendarResult: JSONValue = .object(["action": .string("cancelled")]),
        photosResult: JSONValue = .array([]),
        contactsResult: JSONValue = .array([]),
        extraResults: [CapabilityID: JSONValue] = [:],
        expectedArguments: [CapabilityID: [String: JSONValue]] = [:],
        error: BridgeError? = nil
    ) {
        self.calendarResult = calendarResult
        self.photosResult = photosResult
        self.contactsResult = contactsResult
        self.extraResults = extraResults
        self.expectedArguments = expectedArguments
        self.error = error
    }

    func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try assertArguments(arguments, for: .calendarUIPresentNewEvent)
        _ = context
        if let error { throw error }
        return calendarResult
    }

    func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try assertArguments(arguments, for: .photosUIPick)
        _ = context
        if let error { throw error }
        return photosResult
    }

    func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try assertArguments(arguments, for: .contactsUIPick)
        _ = context
        if let error { throw error }
        return contactsResult
    }

    func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .calendarUIPickCalendar, arguments: arguments, context: context)
    }

    func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .calendarUIPresentEvent, arguments: arguments, context: context)
    }

    func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .contactsUIPresentContact, arguments: arguments, context: context)
    }

    func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .contactsUIPresentNewContact, arguments: arguments, context: context)
    }

    func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIPick, arguments: arguments, context: context)
    }

    func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIExport, arguments: arguments, context: context)
    }

    func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIOpenIn, arguments: arguments, context: context)
    }

    func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .documentsUIScan, arguments: arguments, context: context)
    }

    func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .shareUIPresent, arguments: arguments, context: context)
    }

    func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .quickLookUIPreview, arguments: arguments, context: context)
    }

    func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .cameraUICapture, arguments: arguments, context: context)
    }

    func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .cameraUIScanData, arguments: arguments, context: context)
    }

    func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .mailUICompose, arguments: arguments, context: context)
    }

    func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .messagesUICompose, arguments: arguments, context: context)
    }

    func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .printUIPresent, arguments: arguments, context: context)
    }

    func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .webUIPresent, arguments: arguments, context: context)
    }

    func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .authUIWebAuthenticate, arguments: arguments, context: context)
    }

    func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .uiAlertPresent, arguments: arguments, context: context)
    }

    func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .uiPromptPresent, arguments: arguments, context: context)
    }

    func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .photosUIPresentLimitedLibraryPicker, arguments: arguments, context: context)
    }

    func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try result(for: .settingsUIOpen, arguments: arguments, context: context)
    }

    private func result(for capability: CapabilityID, arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try assertArguments(arguments, for: capability)
        _ = context
        if let error { throw error }
        return extraResults[capability] ?? .object(["action": .string("cancelled")])
    }

    private func assertArguments(_ arguments: [String: JSONValue], for capability: CapabilityID) throws {
        guard let expected = expectedArguments[capability] else {
            return
        }

        guard arguments == expected else {
            throw BridgeError.nativeFailure("Expected \(capability.rawValue) arguments \(expected), received \(arguments)")
        }
    }
}
