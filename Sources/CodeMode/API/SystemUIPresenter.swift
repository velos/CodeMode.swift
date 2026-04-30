import Foundation

public protocol SystemUIPresenter: Sendable {
    func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
    func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue
}

public struct UnavailableSystemUIPresenter: SystemUIPresenter {
    public init() {}

    public func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    public func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }

    public func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        _ = arguments
        _ = context
        throw BridgeError.uiPresenterUnavailable
    }
}
