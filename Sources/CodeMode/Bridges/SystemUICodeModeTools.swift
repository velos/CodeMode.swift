import Foundation

// MARK: - Constrained argument values
//
// Single source of truth for these arguments: the catalog advertises
// `codeModeAllowedValues`, tool decode and SystemUIBridge parse through
// `codeModeValue(matching:)`, so advertised and accepted spellings cannot drift.

/// Shared by camera capture and (later) the photos pickers.
enum MediaTypeFilter: String, CodeModeStringEnum {
    case any
    case image
    case photo
    case video
}

enum CameraDevice: String, CodeModeStringEnum {
    case rear
    case front
}

enum CameraFlashMode: String, CodeModeStringEnum {
    case auto
    case on
    case off
}

enum CameraVideoQuality: String, CodeModeStringEnum {
    case high
    case medium
    case low
    case res640x480 = "640x480"
    case iFrame1280x720
    case iFrame960x540
}

enum DataScannerMode: String, CodeModeStringEnum {
    case any
    case text
    case barcode
}

enum DataScannerQualityLevel: String, CodeModeStringEnum {
    case balanced
    case fast
    case accurate
}

enum PrintOutputType: String, CodeModeStringEnum {
    case general
    case photo
    case grayscale
}

enum AlertPreferredStyle: String, CodeModeStringEnum {
    case alert
    case actionSheet

    // The bridge accepts the all-lowercase spelling; keep it advertised.
    static let codeModeAliases: [String: Self] = [
        "actionsheet": .actionSheet,
    ]
}

// MARK: - Share / Quick Look

@BuiltInCodeMode(.shareUIPresent, path: "apple.share.present")
struct ShareUIPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present share sheet"
    static let codeModeSummary = "Present system share sheet for text, URLs, and sandbox file artifacts."
    static let codeModeTags = ["share", "export", "system-ui"]
    static let codeModeExample = "await apple.share.present({ text: 'Report ready', paths: ['tmp:report.pdf'] })"
    static let codeModeResultSummary = "Object with completed/activityType/action."

    struct Arguments: Sendable {
        @ToolParam("Optional text item to share.")
        var text: String?
        @ToolParam("Optional absolute HTTP(S) URL to share.")
        var url: String?
        @ToolParam("Optional single sandbox file path to share.")
        var path: String?
        @ToolParam("Optional array of sandbox file paths to share.")
        var paths: [String]?
        @ToolParam("Optional subject for services that support it.")
        var subject: String?
        @ToolParam("Optional array of UIActivity.ActivityType raw value strings to hide.")
        var excludedActivityTypes: [String]?
        @ToolParam("Optional timeout for waiting on share completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentShareSheet(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.quickLookUIPreview, path: "apple.quicklook.preview")
struct QuickLookUIPreviewTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Preview files with Quick Look"
    static let codeModeSummary = "Present Quick Look preview UI for one or more sandbox file artifacts."
    static let codeModeTags = ["quicklook", "preview", "documents", "system-ui"]
    static let codeModeExample = "await apple.quicklook.preview({ path: 'tmp:report.pdf' })"
    static let codeModeResultSummary = "Object with action dismissed and count."

    struct Arguments: Sendable {
        @ToolParam("Single sandbox file path to preview.")
        var path: String?
        @ToolParam("Optional array of sandbox file paths to preview.")
        var paths: [String]?
        @ToolParam("Optional timeout for waiting on dismissal.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.previewQuickLook(arguments: arguments.raw, context: context)
    }
}

// MARK: - Camera

@BuiltInCodeMode(.cameraUICapture, path: "apple.camera.capture")
struct CameraUICaptureTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Capture photo or video with camera UI"
    static let codeModeSummary = "Present system camera UI and export captured media into the sandbox artifact store."
    static let codeModeTags = ["camera", "capture", "photos", "system-ui", "artifact"]
    static let codeModeExample = "await apple.camera.capture({ mediaType: 'image', outputDirectory: 'tmp:camera' })"
    static let codeModeResultSummary = "Object with path/artifactID/mediaType/uniformTypeIdentifier/bytes."

    struct Arguments: Sendable {
        @ToolParam("any (default), image/photo, or video.")
        var mediaType: MediaTypeFilter?
        @ToolParam("Optional sandbox directory for captured media; defaults to tmp:.")
        var outputDirectory: String?
        @ToolParam("Optional timeout for waiting on capture/export.")
        var timeoutMs: Double?
        @ToolParam("Whether the system editor is shown before returning media; default false.")
        var allowsEditing: Bool?
        @ToolParam("rear (default) or front.")
        var cameraDevice: CameraDevice?
        @ToolParam("auto (default), on, or off.")
        var flashMode: CameraFlashMode?
        @ToolParam("UIImagePickerController quality name such as high, medium, low, 640x480, iFrame1280x720, or iFrame960x540.")
        var videoQuality: CameraVideoQuality?
        @ToolParam("Optional maximum duration for video capture.")
        var maximumDurationSeconds: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.captureCamera(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.cameraUIScanData, path: "apple.camera.scanData")
struct CameraUIScanDataTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Scan text or barcodes with camera UI"
    static let codeModeSummary = "Present VisionKit live data scanner UI and return recognized text or barcode payloads."
    static let codeModeTags = ["camera", "scan", "barcode", "text", "visionkit", "system-ui"]
    static let codeModeExample = "await apple.camera.scanData({ mode: 'barcode', returnsOnFirstResult: true })"
    static let codeModeResultSummary = "Object with action and items containing text transcripts or barcode payloads."

    struct Arguments: Sendable {
        @ToolParam("any (default), text, or barcode.")
        var mode: DataScannerMode?
        @ToolParam("Optional array containing text and/or barcode; overrides mode.")
        var recognizedDataTypes: [String]?
        @ToolParam("Optional text recognition language identifiers.")
        var languages: [String]?
        @ToolParam("balanced (default), fast, or accurate.")
        var qualityLevel: DataScannerQualityLevel?
        @ToolParam("Whether the scanner tracks multiple items at once; default false.")
        var recognizesMultipleItems: Bool?
        @ToolParam("Whether to dismiss as soon as data is recognized; default true.")
        var returnsOnFirstResult: Bool?
        @ToolParam("Whether VisionKit guidance UI is shown; default true.")
        var isGuidanceEnabled: Bool?
        @ToolParam("Whether recognized items are highlighted; default true.")
        var isHighlightingEnabled: Bool?
        @ToolParam("Whether pinch-to-zoom is enabled; default true.")
        var isPinchToZoomEnabled: Bool?
        @ToolParam("Whether high-frame-rate tracking is enabled; default true.")
        var isHighFrameRateTrackingEnabled: Bool?
        @ToolParam("Optional timeout for waiting on a scan result or cancellation.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.scanData(arguments: arguments.raw, context: context)
    }
}

// MARK: - Mail / Messages / Print

@BuiltInCodeMode(.mailUICompose, path: "apple.mail.compose")
struct MailUIComposeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Compose mail with system UI"
    static let codeModeSummary = "Present system mail compose UI with optional recipients, body, and sandbox file attachments."
    static let codeModeTags = ["mail", "compose", "system-ui", "share"]
    static let codeModeExample = "await apple.mail.compose({ to: ['alex@example.com'], subject: 'Report', body: 'Attached.', attachments: [{ path: 'tmp:report.pdf' }] })"
    static let codeModeResultSummary = "Object with action sent/saved/cancelled/failed."

    struct Arguments: Sendable {
        @ToolParam("Optional array of recipient email strings.")
        var to: [String]?
        @ToolParam("Optional array of CC email strings.")
        var cc: [String]?
        @ToolParam("Optional array of BCC email strings.")
        var bcc: [String]?
        @ToolParam("Optional subject.")
        var subject: String?
        @ToolParam("Optional message body.")
        var body: String?
        @ToolParam("Whether body should be treated as HTML; default false.")
        var isHTML: Bool?
        @ToolParam("Optional array of { path, mimeType?, filename? } sandbox file attachments.")
        var attachments: [JSONValue]?
        @ToolParam("Optional timeout for waiting on user completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.composeMail(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.messagesUICompose, path: "apple.messages.compose")
struct MessagesUIComposeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Compose message with system UI"
    static let codeModeSummary = "Present system Messages compose UI with optional recipients, body, and sandbox file attachments."
    static let codeModeTags = ["messages", "sms", "compose", "system-ui", "share"]
    static let codeModeExample = "await apple.messages.compose({ recipients: ['4085551212'], body: 'Report ready' })"
    static let codeModeResultSummary = "Object with action sent/cancelled/failed."

    struct Arguments: Sendable {
        @ToolParam("Optional array of phone number or address strings.")
        var recipients: [String]?
        @ToolParam("Optional subject on devices/accounts that support it.")
        var subject: String?
        @ToolParam("Optional message body.")
        var body: String?
        @ToolParam("Optional array of { path, filename? } sandbox file attachments.")
        var attachments: [JSONValue]?
        @ToolParam("Optional timeout for waiting on user completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.composeMessage(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.printUIPresent, path: "apple.print.present")
struct PrintUIPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present print UI"
    static let codeModeSummary = "Present the system print sheet for one or more sandbox files."
    static let codeModeTags = ["print", "documents", "system-ui", "export"]
    static let codeModeExample = "await apple.print.present({ path: 'tmp:report.pdf', jobName: 'Report' })"
    static let codeModeResultSummary = "Object with action/completed for the print interaction."

    struct Arguments: Sendable {
        @ToolParam("Single sandbox file path to print.")
        var path: String?
        @ToolParam("Optional array of sandbox file paths to print.")
        var paths: [String]?
        @ToolParam("Optional print job name.")
        var jobName: String?
        @ToolParam("general (default), photo, or grayscale.")
        var outputType: PrintOutputType?
        @ToolParam("Whether copy count controls are shown; default true.")
        var showsNumberOfCopies: Bool?
        @ToolParam("Optional timeout for waiting on print completion/cancellation.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentPrint(arguments: arguments.raw, context: context)
    }
}

// MARK: - Web / Auth

@BuiltInCodeMode(.webUIPresent, path: "apple.web.present")
struct WebUIPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present web page with system UI"
    static let codeModeSummary = "Present an HTTP(S) URL with the system Safari view controller."
    static let codeModeTags = ["web", "safari", "browser", "system-ui"]
    static let codeModeExample = "await apple.web.present({ url: 'https://example.com' })"
    static let codeModeResultSummary = "Object with action dismissed."

    struct Arguments: Sendable {
        @ToolParam("Absolute HTTP(S) URL to present.")
        var url: String
        @ToolParam("Whether Safari may enter Reader automatically; default false.")
        var entersReaderIfAvailable: Bool?
        @ToolParam("Optional timeout for waiting on dismissal.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentWeb(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.authUIWebAuthenticate, path: "apple.auth.webAuthenticate")
struct AuthUIWebAuthenticateTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Authenticate with system web UI"
    static let codeModeSummary = "Start an ASWebAuthenticationSession for OAuth-style browser authentication."
    static let codeModeTags = ["auth", "oauth", "web", "browser", "system-ui"]
    static let codeModeExample = "await apple.auth.webAuthenticate({ url: 'https://example.com/oauth', callbackURLScheme: 'myapp' })"
    static let codeModeResultSummary = "Object with action callback/cancelled and callbackURL when available."

    struct Arguments: Sendable {
        @ToolParam("Absolute HTTP(S) authentication URL.")
        var url: String
        @ToolParam("Optional custom URL scheme that completes the session.")
        var callbackURLScheme: String?
        @ToolParam("Whether to prefer a private browser session; default false.")
        var prefersEphemeralSession: Bool?
        @ToolParam("Optional timeout for waiting on callback/cancellation.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.authenticateWeb(arguments: arguments.raw, context: context)
    }
}

// MARK: - Alerts / Prompts / Settings

@BuiltInCodeMode(.uiAlertPresent, path: "apple.ui.presentAlert")
struct UIAlertPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present alert with custom buttons"
    static let codeModeSummary = "Present a system alert or action sheet and return the button the user selects."
    static let codeModeTags = ["ui", "alert", "dialog", "system-ui"]
    static let codeModeExample = "await apple.ui.presentAlert({ title: 'Delete draft?', message: 'This cannot be undone.', buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'delete', title: 'Delete', style: 'destructive' }] })"
    static let codeModeResultSummary = "Object with action/buttonID/buttonTitle/buttonIndex/style for the selected button."

    struct Arguments: Sendable {
        @ToolParam("Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.")
        var buttons: [JSONValue]
        @ToolParam("Optional alert title.")
        var title: String?
        @ToolParam("Optional alert message.")
        var message: String?
        @ToolParam("alert (default) or actionSheet.")
        var preferredStyle: AlertPreferredStyle?
        @ToolParam("Optional { x, y, width, height } anchor for action sheets.")
        var sourceRect: [String: JSONValue]?
        @ToolParam("Optional timeout for waiting on user selection.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentAlert(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.uiPromptPresent, path: "apple.ui.presentPrompt")
struct UIPromptPresentTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Present prompt with text fields"
    static let codeModeSummary = "Present a system alert with one or more text fields and custom buttons."
    static let codeModeTags = ["ui", "alert", "prompt", "input", "system-ui"]
    static let codeModeExample = "await apple.ui.presentPrompt({ title: 'Name', fields: [{ id: 'name', placeholder: 'Name' }], buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'ok', title: 'OK' }] })"
    static let codeModeResultSummary = "Object with selected button metadata and values keyed by field id."

    struct Arguments: Sendable {
        @ToolParam("Array of { id?, placeholder?, text?/defaultValue?, secure?, keyboardType? }. keyboardType is default, email, number, phone, or url.")
        var fields: [JSONValue]
        @ToolParam("Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.")
        var buttons: [JSONValue]
        @ToolParam("Optional alert title.")
        var title: String?
        @ToolParam("Optional alert message.")
        var message: String?
        @ToolParam("Optional timeout for waiting on user selection.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.presentPrompt(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.settingsUIOpen, path: "apple.settings.open")
struct SettingsUIOpenTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Open app settings"
    static let codeModeSummary = "Open the host app's Settings page so the user can recover denied permissions."
    static let codeModeTags = ["settings", "permissions", "system-ui"]
    static let codeModeExample = "await apple.settings.open()"
    static let codeModeResultSummary = "Object with action opened/failed and opened boolean."

    struct Arguments: Sendable {
        @ToolParam("Optional timeout for waiting on UIApplication.open completion.")
        var timeoutMs: Double?
        var raw: [String: JSONValue]
    }

    let systemUI: SystemUIBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try systemUI.openSettings(arguments: arguments.raw, context: context)
    }
}
