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

    public func presentLimitedPhotoLibraryPicker(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateTimeoutMs(arguments, capability: "photos.ui.presentLimitedLibraryPicker")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentLimitedPhotoLibraryPicker(arguments: arguments, context: context)
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

    public func exportDocuments(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePathOrPaths(arguments, capability: "documents.ui.export")
        try validateTimeoutMs(arguments, capability: "documents.ui.export")
        try context.checkCancellation()
        return try context.systemUIPresenter.exportDocuments(arguments: arguments, context: context)
    }

    public func openDocument(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateNonemptyString(arguments, key: "path", capability: "documents.ui.openIn")
        try validateTimeoutMs(arguments, capability: "documents.ui.openIn")
        try context.checkCancellation()
        return try context.systemUIPresenter.openDocument(arguments: arguments, context: context)
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
        try validateCameraCaptureArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.captureCamera(arguments: arguments, context: context)
    }

    public func scanData(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateDataScannerArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.scanData(arguments: arguments, context: context)
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

    public func presentPrint(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePathOrPaths(arguments, capability: "print.ui.present")
        if let outputType = arguments.string("outputType")?.lowercased(),
           ["general", "photo", "grayscale"].contains(outputType) == false
        {
            throw BridgeError.invalidArguments("print.ui.present outputType must be general, photo, or grayscale")
        }
        try validateTimeoutMs(arguments, capability: "print.ui.present")
        try context.checkCancellation()
        return try context.systemUIPresenter.presentPrint(arguments: arguments, context: context)
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

    public func presentPrompt(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validatePromptArguments(arguments)
        try context.checkCancellation()
        return try context.systemUIPresenter.presentPrompt(arguments: arguments, context: context)
    }

    public func openSettings(arguments: [String: JSONValue], context: BridgeInvocationContext) throws -> JSONValue {
        try validateTimeoutMs(arguments, capability: "settings.ui.open")
        try context.checkCancellation()
        return try context.systemUIPresenter.openSettings(arguments: arguments, context: context)
    }

    private func validateCalendarPickerArguments(_ arguments: [String: JSONValue]) throws {
        if let selectionStyle = arguments.string("selectionStyle"),
           CalendarPickerSelectionStyle.codeModeValue(matching: selectionStyle) == nil
        {
            throw BridgeError.invalidArguments("calendar.ui.pickCalendar selectionStyle must be one of \(CalendarPickerSelectionStyle.codeModeAllowedValues.joined(separator: ", "))")
        }

        if let displayStyle = arguments.string("displayStyle"),
           CalendarPickerDisplayStyle.codeModeValue(matching: displayStyle) == nil
        {
            throw BridgeError.invalidArguments("calendar.ui.pickCalendar displayStyle must be one of \(CalendarPickerDisplayStyle.codeModeAllowedValues.joined(separator: ", "))")
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
        try validateTimeoutMs(arguments, capability: "calendar.ui.presentNewEvent")
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

    private func validateCameraCaptureArguments(_ arguments: [String: JSONValue]) throws {
        try validatePhotoPickerArguments(arguments, capability: "camera.ui.capture")
        try validateOptionalBool(arguments, key: "allowsEditing", capability: "camera.ui.capture")

        if let cameraDevice = arguments.string("cameraDevice")?.lowercased(),
           ["rear", "front"].contains(cameraDevice) == false
        {
            throw BridgeError.invalidArguments("camera.ui.capture cameraDevice must be rear or front")
        }

        if let flashMode = arguments.string("flashMode")?.lowercased(),
           ["auto", "on", "off"].contains(flashMode) == false
        {
            throw BridgeError.invalidArguments("camera.ui.capture flashMode must be auto, on, or off")
        }

        if let videoQuality = arguments.string("videoQuality")?.lowercased(),
           ["high", "medium", "low", "640x480", "iframe1280x720", "iframe960x540"].contains(videoQuality) == false
        {
            throw BridgeError.invalidArguments("camera.ui.capture videoQuality must be high, medium, low, 640x480, iFrame1280x720, or iFrame960x540")
        }

        if let maximumDurationSeconds = arguments.double("maximumDurationSeconds"), maximumDurationSeconds <= 0 {
            throw BridgeError.invalidArguments("camera.ui.capture maximumDurationSeconds must be greater than 0")
        }
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

        try validateSourceRect(arguments, capability: "ui.alert.present")
        try validateTimeoutMs(arguments, capability: "ui.alert.present")
    }

    private func validatePromptArguments(_ arguments: [String: JSONValue]) throws {
        try validateAlertArguments(arguments, capability: "ui.prompt.present")
        if let preferredStyle = arguments.string("preferredStyle")?.lowercased(),
           ["actionSheet", "actionsheet"].contains(preferredStyle)
        {
            throw BridgeError.invalidArguments("ui.prompt.present preferredStyle must be alert")
        }

        guard let fields = arguments.array("fields"), fields.isEmpty == false else {
            throw BridgeError.invalidArguments("ui.prompt.present requires a non-empty fields array")
        }

        for (index, field) in fields.enumerated() {
            guard let object = field.objectValue else {
                throw BridgeError.invalidArguments("ui.prompt.present fields must contain objects")
            }
            try validateNonemptyOptionalString(object, key: "id", capability: "ui.prompt.present field \(index)")
            try validateNonemptyOptionalString(object, key: "placeholder", capability: "ui.prompt.present field \(index)")
            try validateNonemptyOptionalString(object, key: "text", capability: "ui.prompt.present field \(index)")
            try validateNonemptyOptionalString(object, key: "defaultValue", capability: "ui.prompt.present field \(index)")
            if let keyboardType = object.string("keyboardType")?.lowercased(),
               ["default", "email", "number", "phone", "url"].contains(keyboardType) == false
            {
                throw BridgeError.invalidArguments("ui.prompt.present field keyboardType must be default, email, number, phone, or url")
            }
        }
    }

    private func validateAlertArguments(_ arguments: [String: JSONValue], capability: String) throws {
        if let preferredStyle = arguments.string("preferredStyle")?.lowercased(),
           ["alert", "actionSheet", "actionsheet"].contains(preferredStyle) == false
        {
            throw BridgeError.invalidArguments("\(capability) preferredStyle must be alert or actionSheet")
        }

        guard let buttons = arguments.array("buttons"), buttons.isEmpty == false else {
            throw BridgeError.invalidArguments("\(capability) requires a non-empty buttons array")
        }

        var cancelCount = 0
        for (index, button) in buttons.enumerated() {
            guard let object = button.objectValue else {
                throw BridgeError.invalidArguments("\(capability) buttons must contain objects")
            }
            try validateNonemptyString(object, key: "title", capability: "\(capability) button \(index)")
            try validateNonemptyOptionalString(object, key: "id", capability: "\(capability) button \(index)")
            if let style = object.string("style")?.lowercased() {
                guard ["default", "cancel", "destructive"].contains(style) else {
                    throw BridgeError.invalidArguments("\(capability) button style must be default, cancel, or destructive")
                }
                if style == "cancel" {
                    cancelCount += 1
                }
            }
        }

        if cancelCount > 1 {
            throw BridgeError.invalidArguments("\(capability) supports at most one cancel button")
        }

        try validateTimeoutMs(arguments, capability: capability)
    }

    private func validateDataScannerArguments(_ arguments: [String: JSONValue]) throws {
        if let mode = arguments.string("mode")?.lowercased(),
           ["any", "text", "barcode"].contains(mode) == false
        {
            throw BridgeError.invalidArguments("camera.ui.scanData mode must be any, text, or barcode")
        }

        try validateStringArray(arguments, key: "recognizedDataTypes", capability: "camera.ui.scanData")
        for value in arguments.array("recognizedDataTypes") ?? [] {
            guard let type = value.stringValue?.lowercased(),
                  ["text", "barcode"].contains(type)
            else {
                throw BridgeError.invalidArguments("camera.ui.scanData recognizedDataTypes must contain text or barcode")
            }
        }

        try validateStringArray(arguments, key: "languages", capability: "camera.ui.scanData")
        if let qualityLevel = arguments.string("qualityLevel")?.lowercased(),
           ["balanced", "fast", "accurate"].contains(qualityLevel) == false
        {
            throw BridgeError.invalidArguments("camera.ui.scanData qualityLevel must be balanced, fast, or accurate")
        }
        for key in ["recognizesMultipleItems", "returnsOnFirstResult", "isGuidanceEnabled", "isHighlightingEnabled", "isPinchToZoomEnabled", "isHighFrameRateTrackingEnabled"] {
            try validateOptionalBool(arguments, key: key, capability: "camera.ui.scanData")
        }
        try validateTimeoutMs(arguments, capability: "camera.ui.scanData")
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

    private func validateOptionalBool(_ arguments: [String: JSONValue], key: String, capability: String) throws {
        guard arguments.keys.contains(key) else {
            return
        }

        if arguments.bool(key) == nil {
            throw BridgeError.invalidArguments("\(capability) \(key) must be a boolean")
        }
    }

    private func validateSourceRect(_ arguments: [String: JSONValue], capability: String) throws {
        guard arguments.keys.contains("sourceRect") else {
            return
        }

        guard let sourceRect = arguments.object("sourceRect") else {
            throw BridgeError.invalidArguments("\(capability) sourceRect must be an object")
        }
        for key in ["x", "y", "width", "height"] where sourceRect.double(key) == nil {
            throw BridgeError.invalidArguments("\(capability) sourceRect requires numeric x/y/width/height")
        }

        if let width = sourceRect.double("width"), width < 0 {
            throw BridgeError.invalidArguments("\(capability) sourceRect width must be greater than or equal to 0")
        }
        if let height = sourceRect.double("height"), height < 0 {
            throw BridgeError.invalidArguments("\(capability) sourceRect height must be greater than or equal to 0")
        }
    }

    private func validateTimeoutMs(_ arguments: [String: JSONValue], capability: String) throws {
        if let timeoutMs = arguments.int("timeoutMs"), timeoutMs <= 0 {
            throw BridgeError.invalidArguments("\(capability) timeoutMs must be greater than 0")
        }
    }
}
