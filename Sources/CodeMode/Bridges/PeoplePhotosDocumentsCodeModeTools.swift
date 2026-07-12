import Foundation

// Constrained argument value for the contacts picker; MediaTypeFilter (shared
// with camera/photos) lives in SystemUICodeModeTools.swift.
enum ContactPickerMode: String, CodeModeStringEnum {
    case single
    case multiple
}

// MARK: - Contacts

@BuiltInCodeMode(.contactsRead, path: "apple.contacts.list")
struct ContactsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read contacts"
    static let codeModeSummary = "Read contacts with bounded fields."
    static let codeModeTags = ["contacts", "address-book", "people"]
    static let codeModeExample = "await apple.contacts.list({ limit: 25 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.contacts]
    static let codeModeResultSummary = "Array of contacts with identifier/name/organization/phones/emails."

    struct Arguments: Sendable {
        @ToolParam("Max number of contacts, default 50.")
        var limit: Int?
        @ToolParam("Optional array of contact identifiers for targeted read.")
        var identifiers: [String]?
        var raw: [String: JSONValue]
    }

    let contacts: ContactsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try contacts.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.contactsSearch, path: "apple.contacts.search")
struct ContactsSearchTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Search contacts"
    static let codeModeSummary = "Search contacts by name."
    static let codeModeTags = ["contacts", "search", "people"]
    static let codeModeExample = "await apple.contacts.search({ query: 'Alex', limit: 10 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.contacts]
    static let codeModeResultSummary = "Array of contact objects."

    struct Arguments: Sendable {
        @ToolParam("Name text to match.")
        var query: String
        @ToolParam("Max number of contacts, default 20.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let contacts: ContactsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try contacts.search(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.contactsUIPick, path: "apple.contacts.pick")
struct ContactsUIPickTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Pick contacts with system UI"
    static let codeModeSummary = "Present system contact picker UI and return selected contacts without requiring full Contacts permission."
    static let codeModeTags = ["contacts", "people", "system-ui", "picker"]
    static let codeModeExample = "await apple.contacts.pick({ mode: 'single', displayedPropertyKeys: ['phoneNumbers', 'emailAddresses'] })"
    static let codeModeResultSummary = "Array of selected contacts with identifier/name/organization/phones/emails."

    struct Arguments: Sendable {
        @ToolParam("single (default) or multiple.")
        var mode: ContactPickerMode?
        @ToolParam("Optional array of CNContact property key strings to display.")
        var displayedPropertyKeys: [String]?
        @ToolParam("Optional timeout for waiting on user selection.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.pickContacts(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.contactsUIPresentContact, path: "apple.contacts.presentContact")
struct ContactsUIPresentContactTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present contact card"
    static let codeModeSummary = "Present system contact card UI for a contact identifier."
    static let codeModeTags = ["contacts", "people", "system-ui", "details"]
    static let codeModeExample = "await apple.contacts.presentContact({ identifier: 'CONTACT_ID', allowsEditing: false })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.contacts]
    static let codeModeResultSummary = "Object with action and contact when available."

    struct Arguments: Sendable {
        @ToolParam("Contact identifier from apple.contacts.list/search/pick.")
        var identifier: String
        @ToolParam("Whether the user can edit the contact; default false.")
        var allowsEditing: Bool?
        @ToolParam("Whether built-in actions like call/message are shown; default true.")
        var allowsActions: Bool?
        @ToolParam("Optional array of CNContact property key strings to display.")
        var displayedPropertyKeys: [String]?
        @ToolParam("Optional timeout for waiting on dismissal.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentContact(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.contactsUIPresentNewContact, path: "apple.contacts.presentNewContact")
struct ContactsUIPresentNewContactTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present new contact editor"
    static let codeModeSummary = "Present system UI for creating a new contact draft."
    static let codeModeTags = ["contacts", "people", "system-ui", "create"]
    static let codeModeExample = "await apple.contacts.presentNewContact({ givenName: 'Alex', familyName: 'Lee', emailAddresses: ['alex@example.com'] })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.contacts]
    static let codeModeResultSummary = "Object with action and contact when the user saves."

    struct Arguments: Sendable {
        @ToolParam("Optional given name to prefill.")
        var givenName: String?
        @ToolParam("Optional family name to prefill.")
        var familyName: String?
        @ToolParam("Optional organization to prefill.")
        var organization: String?
        @ToolParam("Optional array of phone number strings.")
        var phoneNumbers: [String]?
        @ToolParam("Optional array of email address strings.")
        var emailAddresses: [String]?
        @ToolParam("Optional timeout for waiting on user completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentNewContact(arguments: arguments.raw, context: context)
    }
}

// MARK: - Photos

@BuiltInCodeMode(.photosRead, path: "apple.photos.list")
struct PhotosReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List photo library assets"
    static let codeModeSummary = "List photos/videos from the user photo library."
    static let codeModeTags = ["photos", "photo-library", "media"]
    static let codeModeExample = "await apple.photos.list({ mediaType: 'image', limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.photoLibrary]
    static let codeModeResultSummary = "Array of assets with localIdentifier/mediaType/dimensions/date metadata."

    struct Arguments: Sendable {
        @ToolParam("any (default), image, or video.")
        var mediaType: MediaTypeFilter?
        @ToolParam("Max number of results, default 50.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let photos: PhotosBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try photos.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.photosExport, path: "apple.photos.export")
struct PhotosExportTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Export photo library asset"
    static let codeModeSummary = "Export a photo/video asset to sandbox file path and register artifact handle."
    static let codeModeTags = ["photos", "photo-library", "artifact"]
    static let codeModeExample = "await apple.photos.export({ localIdentifier: 'ABC/L0/001', outputPath: 'tmp:exported.jpg' })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.photoLibrary]
    static let codeModeResultSummary = "Object with path/artifactID/localIdentifier/mediaType/bytes."

    struct Arguments: Sendable {
        @ToolParam("PHAsset localIdentifier from photos.read result.")
        var localIdentifier: String
        @ToolParam("Optional sandbox output path; defaults to tmp-generated file.")
        var outputPath: String?
        var raw: [String: JSONValue]
    }

    let photos: PhotosBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try photos.export(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.photosUIPick, path: "apple.photos.pick")
struct PhotosUIPickTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Pick photos with system UI"
    static let codeModeSummary = "Present system photo picker UI and export selected assets into the sandbox artifact store."
    static let codeModeTags = ["photos", "photo-library", "system-ui", "picker", "artifact"]
    static let codeModeExample = "await apple.photos.pick({ mediaType: 'image', limit: 3, outputDirectory: 'tmp:picks' })"
    static let codeModeResultSummary = "Array of selected assets with path/artifactID/mediaType/uniformTypeIdentifier/bytes."

    struct Arguments: Sendable {
        @ToolParam("any (default), image/photo, or video.")
        var mediaType: MediaTypeFilter?
        @ToolParam("Maximum number of selectable items; default 1.")
        var limit: Int?
        @ToolParam("Optional sandbox directory for exported picker files; defaults to tmp:.")
        var outputDirectory: String?
        @ToolParam("Optional timeout for waiting on user selection/export.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.pickPhotos(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.photosUIPresentLimitedLibraryPicker, path: "apple.photos.presentLimitedLibraryPicker")
struct PhotosUIPresentLimitedLibraryPickerTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present limited Photos picker"
    static let codeModeSummary = "Present the Photos limited-library management UI so the user can update the app's selected photo set."
    static let codeModeTags = ["photos", "photo-library", "system-ui", "permission", "picker"]
    static let codeModeExample = "await apple.photos.presentLimitedLibraryPicker()"
    static let codeModeResultSummary = "Object with action/status and selectedIdentifiers when the limited selection changes."

    struct Arguments: Sendable {
        @ToolParam("Optional timeout for waiting on the limited-library picker completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentLimitedPhotoLibraryPicker(arguments: arguments.raw, context: context)
    }
}

// MARK: - Documents

@BuiltInCodeMode(.documentsUIPick, path: "apple.documents.pick")
struct DocumentsUIPickTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Pick documents with system UI"
    static let codeModeSummary = "Present Files document picker UI and copy selected documents into the sandbox artifact store."
    static let codeModeTags = ["documents", "files", "system-ui", "picker", "artifact"]
    static let codeModeExample = "await apple.documents.pick({ contentTypes: ['public.item'], allowMultiple: true, outputDirectory: 'tmp:imports' })"
    static let codeModeResultSummary = "Array of selected documents with path/artifactID/filename/uniformTypeIdentifier/bytes."

    struct Arguments: Sendable {
        @ToolParam("Optional array of UTType identifiers; defaults to public.item.")
        var contentTypes: [String]?
        @ToolParam("Whether multiple files may be selected; default false.")
        var allowMultiple: Bool?
        @ToolParam("Optional sandbox directory for copied files; defaults to tmp:.")
        var outputDirectory: String?
        @ToolParam("Optional timeout for waiting on user selection/copy.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.pickDocuments(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.documentsUIExport, path: "apple.documents.export", aliases: ["apple.documents.save"])
struct DocumentsUIExportTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Export documents with system UI"
    static let codeModeSummary = "Present Files export UI to save one or more sandbox files to a user-selected destination."
    static let codeModeTags = ["documents", "files", "system-ui", "export", "save"]
    static let codeModeExample = "await apple.documents.export({ path: 'tmp:report.pdf' })"
    static let codeModeResultSummary = "Object with action/count and destination URLs when the provider returns them."

    struct Arguments: Sendable {
        @ToolParam("Single sandbox file path to export.")
        var path: String?
        @ToolParam("Optional array of sandbox file paths to export.")
        var paths: [String]?
        @ToolParam("Whether to export as a copy; default true.")
        var asCopy: Bool?
        @ToolParam("Optional timeout for waiting on export completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.exportDocuments(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.documentsUIOpenIn, path: "apple.documents.openIn")
struct DocumentsUIOpenInTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Open document in another app"
    static let codeModeSummary = "Present the system Open In menu for a sandbox file."
    static let codeModeTags = ["documents", "files", "system-ui", "open-in", "handoff"]
    static let codeModeExample = "await apple.documents.openIn({ path: 'tmp:report.pdf' })"
    static let codeModeResultSummary = "Object with action and application bundle identifier when the user hands off the file."

    struct Arguments: Sendable {
        @ToolParam("Sandbox file path to hand off.")
        var path: String
        @ToolParam("Optional display name for the document interaction controller.")
        var name: String?
        @ToolParam("Optional uniform type identifier override.")
        var uti: String?
        @ToolParam("Optional timeout for waiting on the Open In menu dismissal.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.openDocument(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.documentsUIScan, path: "apple.documents.scan")
struct DocumentsUIScanTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Scan documents with system UI"
    static let codeModeSummary = "Present VisionKit document scanner UI and export scanned pages into the sandbox artifact store."
    static let codeModeTags = ["documents", "scan", "camera", "system-ui", "artifact"]
    static let codeModeExample = "await apple.documents.scan({ outputDirectory: 'tmp:scans' })"
    static let codeModeResultSummary = "Array of scanned page artifacts with path/artifactID/pageIndex/mediaType/bytes."

    struct Arguments: Sendable {
        @ToolParam("Optional sandbox directory for scanned page images; defaults to tmp:.")
        var outputDirectory: String?
        @ToolParam("Optional timeout for waiting on user scanning/export.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.scanDocuments(arguments: arguments.raw, context: context)
    }
}
