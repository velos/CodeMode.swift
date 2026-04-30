import Foundation

public final class SystemUIBridge: @unchecked Sendable {
    public init() {}

    public func presentNewCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateCalendarEventArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.presentNewCalendarEvent(arguments: arguments, context: context)
    }

    public func pickPhotos(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePhotoPickerArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.pickPhotos(arguments: arguments, context: context)
    }

    public func pickContacts(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateContactPickerArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.pickContacts(arguments: arguments, context: context)
    }

    private func validateCalendarEventArguments(_ arguments: [String: JSONValue]) throws {
        let formatter = ISO8601DateFormatter()
        for key in ["start", "end"] {
            guard let value = arguments.string(key) else {
                continue
            }
            guard formatter.date(from: value) != nil else {
                throw BridgeError.invalidArguments("calendar.ui.presentNewEvent requires \(key) to be an ISO8601 timestamp when provided")
            }
        }
    }

    private func validatePhotoPickerArguments(_ arguments: [String: JSONValue]) throws {
        if let mediaType = arguments.string("mediaType")?.lowercased(),
           ["any", "image", "photo", "video"].contains(mediaType) == false
        {
            throw BridgeError.invalidArguments("photos.ui.pick mediaType must be any, image, photo, or video")
        }

        if let limit = arguments.int("limit"), limit <= 0 {
            throw BridgeError.invalidArguments("photos.ui.pick limit must be greater than 0")
        }

        if let outputDirectory = arguments.string("outputDirectory"),
           outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            throw BridgeError.invalidArguments("photos.ui.pick outputDirectory cannot be empty")
        }

        try validateTimeoutMs(arguments, capability: "photos.ui.pick")
    }

    private func validateContactPickerArguments(_ arguments: [String: JSONValue]) throws {
        if let mode = arguments.string("mode")?.lowercased(),
           ["single", "multiple"].contains(mode) == false
        {
            throw BridgeError.invalidArguments("contacts.ui.pick mode must be single or multiple")
        }

        if let keys = arguments.array("displayedPropertyKeys"),
           keys.contains(where: { $0.stringValue == nil })
        {
            throw BridgeError.invalidArguments("contacts.ui.pick displayedPropertyKeys must contain only strings")
        }

        try validateTimeoutMs(arguments, capability: "contacts.ui.pick")
    }

    private func validateTimeoutMs(_ arguments: [String: JSONValue], capability: String) throws {
        if let timeoutMs = arguments.int("timeoutMs"), timeoutMs <= 0 {
            throw BridgeError.invalidArguments("\(capability) timeoutMs must be greater than 0")
        }
    }
}
