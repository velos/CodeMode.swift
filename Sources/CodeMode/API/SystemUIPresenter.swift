import Foundation

public protocol SystemUIPresenter: Sendable {
    func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
}

public extension SystemUIPresenter {
    func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }
}

public struct UnavailableSystemUIPresenter: SystemUIPresenter {
    public init() {}
}
