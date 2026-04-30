import Foundation

public final class SystemUIBridge: @unchecked Sendable {
    public init() {}

    public func pickCalendar(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateCalendarPickerArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.pickCalendar(arguments: arguments, context: context)
    }

    public func presentCalendarEvent(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateNonemptyString(arguments, key: "identifier", capability: "calendar.ui.presentEvent")
        try validateTimeoutMs(arguments, capability: "calendar.ui.presentEvent")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentCalendarEvent(arguments: arguments, context: context)
    }

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

    public func presentContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateNonemptyString(arguments, key: "identifier", capability: "contacts.ui.presentContact")
        try validateStringArray(arguments, key: "displayedPropertyKeys", capability: "contacts.ui.presentContact")
        try validateTimeoutMs(arguments, capability: "contacts.ui.presentContact")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentContact(arguments: arguments, context: context)
    }

    public func presentNewContact(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateStringArray(arguments, key: "phoneNumbers", capability: "contacts.ui.presentNewContact")
        try validateStringArray(arguments, key: "emailAddresses", capability: "contacts.ui.presentNewContact")
        try validateTimeoutMs(arguments, capability: "contacts.ui.presentNewContact")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentNewContact(arguments: arguments, context: context)
    }

    public func pickDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateStringArray(arguments, key: "contentTypes", capability: "documents.ui.pick")
        try validateNonemptyOptionalString(arguments, key: "outputDirectory", capability: "documents.ui.pick")
        try validateTimeoutMs(arguments, capability: "documents.ui.pick")
        try context.checkCancellation()
        return try context.systemUIPresenter.pickDocuments(arguments: arguments, context: context)
    }

    public func scanDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateNonemptyOptionalString(arguments, key: "outputDirectory", capability: "documents.ui.scan")
        try validateTimeoutMs(arguments, capability: "documents.ui.scan")
        try context.checkCancellation()
        return try context.systemUIPresenter.scanDocuments(arguments: arguments, context: context)
    }

    public func presentShareSheet(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateShareArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.presentShareSheet(arguments: arguments, context: context)
    }

    public func previewQuickLook(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePathOrPaths(arguments, capability: "quicklook.ui.preview")
        try validateTimeoutMs(arguments, capability: "quicklook.ui.preview")
        try context.checkCancellation()
        return try context.systemUIPresenter.previewQuickLook(arguments: arguments, context: context)
    }

    public func captureCamera(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePhotoPickerArguments(arguments, capability: "camera.ui.capture")
        try context.checkCancellation()
        return try context.systemUIPresenter.captureCamera(arguments: arguments, context: context)
    }

    public func composeMail(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateMessageRecipients(arguments, keys: ["to", "cc", "bcc"], capability: "mail.ui.compose")
        try validateAttachmentObjects(arguments, capability: "mail.ui.compose")
        try validateTimeoutMs(arguments, capability: "mail.ui.compose")
        try context.checkCancellation()
        return try context.systemUIPresenter.composeMail(arguments: arguments, context: context)
    }

    public func composeMessage(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateMessageRecipients(arguments, keys: ["recipients"], capability: "messages.ui.compose")
        try validateAttachmentObjects(arguments, capability: "messages.ui.compose")
        try validateTimeoutMs(arguments, capability: "messages.ui.compose")
        try context.checkCancellation()
        return try context.systemUIPresenter.composeMessage(arguments: arguments, context: context)
    }

    public func presentWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateHTTPURL(arguments, key: "url", capability: "web.ui.present")
        try validateTimeoutMs(arguments, capability: "web.ui.present")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentWeb(arguments: arguments, context: context)
    }

    public func authenticateWeb(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateHTTPURL(arguments, key: "url", capability: "auth.ui.webAuthenticate")
        try validateNonemptyOptionalString(arguments, key: "callbackURLScheme", capability: "auth.ui.webAuthenticate")
        try validateTimeoutMs(arguments, capability: "auth.ui.webAuthenticate")
        try context.checkCancellation()
        return try context.systemUIPresenter.authenticateWeb(arguments: arguments, context: context)
    }

    public func presentAlert(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateAlertArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.presentAlert(arguments: arguments, context: context)
    }

    private func validateCalendarPickerArguments(_ arguments: [String: JSONValue]) throws {
        if let selectionStyle = arguments.string("selectionStyle")?.lowercased(),
           ["single", "multiple"].contains(selectionStyle) == false
        {
            throw BridgeError.invalidArguments("calendar.ui.pickCalendar selectionStyle must be single or multiple")
        }

        if let displayStyle = arguments.string("displayStyle")?.lowercased(),
           ["writable", "all"].contains(displayStyle) == false
        {
            throw BridgeError.invalidArguments("calendar.ui.pickCalendar displayStyle must be writable or all")
        }

        try validateTimeoutMs(arguments, capability: "calendar.ui.pickCalendar")
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

    private func validatePhotoPickerArguments(_ arguments: [String: JSONValue], capability: String = "photos.ui.pick") throws {
        if let mediaType = arguments.string("mediaType")?.lowercased(),
           ["any", "image", "photo", "video"].contains(mediaType) == false
        {
            throw BridgeError.invalidArguments("\(capability) mediaType must be any, image, photo, or video")
        }

        if let limit = arguments.int("limit"), limit <= 0 {
            throw BridgeError.invalidArguments("\(capability) limit must be greater than 0")
        }

        try validateNonemptyOptionalString(arguments, key: "outputDirectory", capability: capability)
        try validateTimeoutMs(arguments, capability: capability)
    }

    private func validateContactPickerArguments(_ arguments: [String: JSONValue]) throws {
        if let mode = arguments.string("mode")?.lowercased(),
           ["single", "multiple"].contains(mode) == false
        {
            throw BridgeError.invalidArguments("contacts.ui.pick mode must be single or multiple")
        }

        try validateStringArray(arguments, key: "displayedPropertyKeys", capability: "contacts.ui.pick")
        try validateTimeoutMs(arguments, capability: "contacts.ui.pick")
    }

    private func validateAlertArguments(_ arguments: [String: JSONValue]) throws {
        if let preferredStyle = arguments.string("preferredStyle")?.lowercased(),
           ["alert", "actionSheet", "actionsheet"].contains(preferredStyle) == false
        {
            throw BridgeError.invalidArguments("ui.alert.present preferredStyle must be alert or actionSheet")
        }

        guard let buttons = arguments.array("buttons"), buttons.isEmpty == false else {
            throw BridgeError.invalidArguments("ui.alert.present requires a non-empty buttons array")
        }

        var cancelCount = 0
        for (index, button) in buttons.enumerated() {
            guard let object = button.objectValue else {
                throw BridgeError.invalidArguments("ui.alert.present buttons must contain objects")
            }
            try validateNonemptyString(object, key: "title", capability: "ui.alert.present button \(index)")
            try validateNonemptyOptionalString(object, key: "id", capability: "ui.alert.present button \(index)")
            if let style = object.string("style")?.lowercased() {
                guard ["default", "cancel", "destructive"].contains(style) else {
                    throw BridgeError.invalidArguments("ui.alert.present button style must be default, cancel, or destructive")
                }
                if style == "cancel" {
                    cancelCount += 1
                }
            }
        }

        if cancelCount > 1 {
            throw BridgeError.invalidArguments("ui.alert.present supports at most one cancel button")
        }

        try validateTimeoutMs(arguments, capability: "ui.alert.present")
    }

    private func validateShareArguments(_ arguments: [String: JSONValue]) throws {
        try validateHTTPURL(arguments, key: "url", capability: "share.ui.present", required: false)
        try validateStringArray(arguments, key: "paths", capability: "share.ui.present")
        try validateStringArray(arguments, key: "excludedActivityTypes", capability: "share.ui.present")
        try validateNonemptyOptionalString(arguments, key: "path", capability: "share.ui.present")
        try validateTimeoutMs(arguments, capability: "share.ui.present")

        let hasItems =
            arguments.string("text") != nil ||
            arguments.string("url") != nil ||
            arguments.string("path") != nil ||
            arguments.array("paths")?.isEmpty == false
        if hasItems == false {
            throw BridgeError.invalidArguments("share.ui.present requires text, url, path, or paths")
        }
    }

    private func validatePathOrPaths(_ arguments: [String: JSONValue], capability: String) throws {
        try validateNonemptyOptionalString(arguments, key: "path", capability: capability)
        try validateStringArray(arguments, key: "paths", capability: capability)

        let hasPath = arguments.string("path") != nil
        let hasPaths = arguments.array("paths")?.isEmpty == false
        guard hasPath || hasPaths else {
            throw BridgeError.invalidArguments("\(capability) requires path or paths")
        }
    }

    private func validateMessageRecipients(_ arguments: [String: JSONValue], keys: [String], capability: String) throws {
        for key in keys {
            try validateStringArray(arguments, key: key, capability: capability)
        }
    }

    private func validateAttachmentObjects(_ arguments: [String: JSONValue], capability: String) throws {
        guard let attachments = arguments.array("attachments") else {
            return
        }

        for attachment in attachments {
            guard let object = attachment.objectValue else {
                throw BridgeError.invalidArguments("\(capability) attachments must contain objects")
            }
            try validateNonemptyString(object, key: "path", capability: capability)
            try validateNonemptyOptionalString(object, key: "mimeType", capability: capability)
            try validateNonemptyOptionalString(object, key: "filename", capability: capability)
        }
    }

    private func validateHTTPURL(
        _ arguments: [String: JSONValue],
        key: String,
        capability: String,
        required: Bool = true
    ) throws {
        guard let value = arguments.string(key) else {
            if required {
                throw BridgeError.invalidArguments("\(capability) requires \(key)")
            }
            return
        }

        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false
        else {
            throw BridgeError.invalidArguments("\(capability) \(key) must be an absolute HTTP(S) URL")
        }
    }

    private func validateNonemptyString(_ arguments: [String: JSONValue], key: String, capability: String) throws {
        guard let value = arguments.string(key)?.trimmingCharacters(in: .whitespacesAndNewlines), value.isEmpty == false else {
            throw BridgeError.invalidArguments("\(capability) requires non-empty \(key)")
        }
    }

    private func validateNonemptyOptionalString(_ arguments: [String: JSONValue], key: String, capability: String) throws {
        guard let value = arguments.string(key) else {
            return
        }

        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw BridgeError.invalidArguments("\(capability) \(key) cannot be empty")
        }
    }

    private func validateStringArray(_ arguments: [String: JSONValue], key: String, capability: String) throws {
        guard let values = arguments.array(key) else {
            return
        }

        if values.contains(where: { $0.stringValue == nil }) {
            throw BridgeError.invalidArguments("\(capability) \(key) must contain only strings")
        }
    }

    private func validateTimeoutMs(_ arguments: [String: JSONValue], capability: String) throws {
        if let timeoutMs = arguments.int("timeoutMs"), timeoutMs <= 0 {
            throw BridgeError.invalidArguments("\(capability) timeoutMs must be greater than 0")
        }
    }
}
