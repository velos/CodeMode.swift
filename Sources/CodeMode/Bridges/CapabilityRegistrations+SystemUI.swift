import Foundation

extension DefaultCapabilityRegistrationBuilder {
    func interactionUIRegistrations() -> [CapabilityRegistration] {
        [
            CapabilityRegistration(
                descriptor: .init(
                    id: .shareUIPresent,
                    title: "Present share sheet",
                    summary: "Present system share sheet for text, URLs, and sandbox file artifacts.",
                    tags: ["share", "export", "system-ui"],
                    example: "await apple.share.present({ text: 'Report ready', paths: ['tmp:report.pdf'] })",
                    optionalArguments: ["text", "url", "path", "paths", "subject", "excludedActivityTypes", "timeoutMs"],
                    argumentTypes: [
                        "text": .string,
                        "url": .string,
                        "path": .string,
                        "paths": .array,
                        "subject": .string,
                        "excludedActivityTypes": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "text": "Optional text item to share.",
                        "url": "Optional absolute HTTP(S) URL to share.",
                        "path": "Optional single sandbox file path to share.",
                        "paths": "Optional array of sandbox file paths to share.",
                        "subject": "Optional subject for services that support it.",
                        "excludedActivityTypes": "Optional array of UIActivity.ActivityType raw value strings to hide.",
                        "timeoutMs": "Optional timeout for waiting on share completion.",
                    ],
                    resultSummary: "Object with completed/activityType/action."
                ),
                handler: { args, context in
                    try systemUI.presentShareSheet(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .quickLookUIPreview,
                    title: "Preview files with Quick Look",
                    summary: "Present Quick Look preview UI for one or more sandbox file artifacts.",
                    tags: ["quicklook", "preview", "documents", "system-ui"],
                    example: "await apple.quicklook.preview({ path: 'tmp:report.pdf' })",
                    optionalArguments: ["path", "paths", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "paths": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Single sandbox file path to preview.",
                        "paths": "Optional array of sandbox file paths to preview.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed and count."
                ),
                handler: { args, context in
                    try systemUI.previewQuickLook(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .cameraUICapture,
                    title: "Capture photo or video with camera UI",
                    summary: "Present system camera UI and export captured media into the sandbox artifact store.",
                    tags: ["camera", "capture", "photos", "system-ui", "artifact"],
                    example: "await apple.camera.capture({ mediaType: 'image', outputDirectory: 'tmp:camera' })",
                    optionalArguments: [
                        "mediaType",
                        "outputDirectory",
                        "timeoutMs",
                        "allowsEditing",
                        "cameraDevice",
                        "flashMode",
                        "videoQuality",
                        "maximumDurationSeconds",
                    ],
                    argumentTypes: [
                        "mediaType": .string,
                        "outputDirectory": .string,
                        "timeoutMs": .number,
                        "allowsEditing": .bool,
                        "cameraDevice": .string,
                        "flashMode": .string,
                        "videoQuality": .string,
                        "maximumDurationSeconds": .number,
                    ],
                    argumentHints: [
                        "mediaType": "any (default), image/photo, or video.",
                        "outputDirectory": "Optional sandbox directory for captured media; defaults to tmp:.",
                        "timeoutMs": "Optional timeout for waiting on capture/export.",
                        "allowsEditing": "Whether the system editor is shown before returning media; default false.",
                        "cameraDevice": "rear (default) or front.",
                        "flashMode": "auto (default), on, or off.",
                        "videoQuality": "UIImagePickerController quality name such as high, medium, low, 640x480, iFrame1280x720, or iFrame960x540.",
                        "maximumDurationSeconds": "Optional maximum duration for video capture.",
                    ],
                    resultSummary: "Object with path/artifactID/mediaType/uniformTypeIdentifier/bytes."
                ),
                handler: { args, context in
                    try systemUI.captureCamera(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .cameraUIScanData,
                    title: "Scan text or barcodes with camera UI",
                    summary: "Present VisionKit live data scanner UI and return recognized text or barcode payloads.",
                    tags: ["camera", "scan", "barcode", "text", "visionkit", "system-ui"],
                    example: "await apple.camera.scanData({ mode: 'barcode', returnsOnFirstResult: true })",
                    optionalArguments: [
                        "mode",
                        "recognizedDataTypes",
                        "languages",
                        "qualityLevel",
                        "recognizesMultipleItems",
                        "returnsOnFirstResult",
                        "isGuidanceEnabled",
                        "isHighlightingEnabled",
                        "isPinchToZoomEnabled",
                        "isHighFrameRateTrackingEnabled",
                        "timeoutMs",
                    ],
                    argumentTypes: [
                        "mode": .string,
                        "recognizedDataTypes": .array,
                        "languages": .array,
                        "qualityLevel": .string,
                        "recognizesMultipleItems": .bool,
                        "returnsOnFirstResult": .bool,
                        "isGuidanceEnabled": .bool,
                        "isHighlightingEnabled": .bool,
                        "isPinchToZoomEnabled": .bool,
                        "isHighFrameRateTrackingEnabled": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "mode": "any (default), text, or barcode.",
                        "recognizedDataTypes": "Optional array containing text and/or barcode; overrides mode.",
                        "languages": "Optional text recognition language identifiers.",
                        "qualityLevel": "balanced (default), fast, or accurate.",
                        "recognizesMultipleItems": "Whether the scanner tracks multiple items at once; default false.",
                        "returnsOnFirstResult": "Whether to dismiss as soon as data is recognized; default true.",
                        "isGuidanceEnabled": "Whether VisionKit guidance UI is shown; default true.",
                        "isHighlightingEnabled": "Whether recognized items are highlighted; default true.",
                        "isPinchToZoomEnabled": "Whether pinch-to-zoom is enabled; default true.",
                        "isHighFrameRateTrackingEnabled": "Whether high-frame-rate tracking is enabled; default true.",
                        "timeoutMs": "Optional timeout for waiting on a scan result or cancellation.",
                    ],
                    resultSummary: "Object with action and items containing text transcripts or barcode payloads."
                ),
                handler: { args, context in
                    try systemUI.scanData(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .mailUICompose,
                    title: "Compose mail with system UI",
                    summary: "Present system mail compose UI with optional recipients, body, and sandbox file attachments.",
                    tags: ["mail", "compose", "system-ui", "share"],
                    example: "await apple.mail.compose({ to: ['alex@example.com'], subject: 'Report', body: 'Attached.', attachments: [{ path: 'tmp:report.pdf' }] })",
                    optionalArguments: ["to", "cc", "bcc", "subject", "body", "isHTML", "attachments", "timeoutMs"],
                    argumentTypes: [
                        "to": .array,
                        "cc": .array,
                        "bcc": .array,
                        "subject": .string,
                        "body": .string,
                        "isHTML": .bool,
                        "attachments": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "to": "Optional array of recipient email strings.",
                        "cc": "Optional array of CC email strings.",
                        "bcc": "Optional array of BCC email strings.",
                        "subject": "Optional subject.",
                        "body": "Optional message body.",
                        "isHTML": "Whether body should be treated as HTML; default false.",
                        "attachments": "Optional array of { path, mimeType?, filename? } sandbox file attachments.",
                        "timeoutMs": "Optional timeout for waiting on user completion.",
                    ],
                    resultSummary: "Object with action sent/saved/cancelled/failed."
                ),
                handler: { args, context in
                    try systemUI.composeMail(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .messagesUICompose,
                    title: "Compose message with system UI",
                    summary: "Present system Messages compose UI with optional recipients, body, and sandbox file attachments.",
                    tags: ["messages", "sms", "compose", "system-ui", "share"],
                    example: "await apple.messages.compose({ recipients: ['4085551212'], body: 'Report ready' })",
                    optionalArguments: ["recipients", "subject", "body", "attachments", "timeoutMs"],
                    argumentTypes: [
                        "recipients": .array,
                        "subject": .string,
                        "body": .string,
                        "attachments": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "recipients": "Optional array of phone number or address strings.",
                        "subject": "Optional subject on devices/accounts that support it.",
                        "body": "Optional message body.",
                        "attachments": "Optional array of { path, filename? } sandbox file attachments.",
                        "timeoutMs": "Optional timeout for waiting on user completion.",
                    ],
                    resultSummary: "Object with action sent/cancelled/failed."
                ),
                handler: { args, context in
                    try systemUI.composeMessage(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .printUIPresent,
                    title: "Present print UI",
                    summary: "Present the system print sheet for one or more sandbox files.",
                    tags: ["print", "documents", "system-ui", "export"],
                    example: "await apple.print.present({ path: 'tmp:report.pdf', jobName: 'Report' })",
                    optionalArguments: ["path", "paths", "jobName", "outputType", "showsNumberOfCopies", "timeoutMs"],
                    argumentTypes: [
                        "path": .string,
                        "paths": .array,
                        "jobName": .string,
                        "outputType": .string,
                        "showsNumberOfCopies": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "path": "Single sandbox file path to print.",
                        "paths": "Optional array of sandbox file paths to print.",
                        "jobName": "Optional print job name.",
                        "outputType": "general (default), photo, or grayscale.",
                        "showsNumberOfCopies": "Whether copy count controls are shown; default true.",
                        "timeoutMs": "Optional timeout for waiting on print completion/cancellation.",
                    ],
                    resultSummary: "Object with action/completed for the print interaction."
                ),
                handler: { args, context in
                    try systemUI.presentPrint(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .webUIPresent,
                    title: "Present web page with system UI",
                    summary: "Present an HTTP(S) URL with the system Safari view controller.",
                    tags: ["web", "safari", "browser", "system-ui"],
                    example: "await apple.web.present({ url: 'https://example.com' })",
                    requiredArguments: ["url"],
                    optionalArguments: ["entersReaderIfAvailable", "timeoutMs"],
                    argumentTypes: [
                        "url": .string,
                        "entersReaderIfAvailable": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) URL to present.",
                        "entersReaderIfAvailable": "Whether Safari may enter Reader automatically; default false.",
                        "timeoutMs": "Optional timeout for waiting on dismissal.",
                    ],
                    resultSummary: "Object with action dismissed."
                ),
                handler: { args, context in
                    try systemUI.presentWeb(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .authUIWebAuthenticate,
                    title: "Authenticate with system web UI",
                    summary: "Start an ASWebAuthenticationSession for OAuth-style browser authentication.",
                    tags: ["auth", "oauth", "web", "browser", "system-ui"],
                    example: "await apple.auth.webAuthenticate({ url: 'https://example.com/oauth', callbackURLScheme: 'myapp' })",
                    requiredArguments: ["url"],
                    optionalArguments: ["callbackURLScheme", "prefersEphemeralSession", "timeoutMs"],
                    argumentTypes: [
                        "url": .string,
                        "callbackURLScheme": .string,
                        "prefersEphemeralSession": .bool,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "url": "Absolute HTTP(S) authentication URL.",
                        "callbackURLScheme": "Optional custom URL scheme that completes the session.",
                        "prefersEphemeralSession": "Whether to prefer a private browser session; default false.",
                        "timeoutMs": "Optional timeout for waiting on callback/cancellation.",
                    ],
                    resultSummary: "Object with action callback/cancelled and callbackURL when available."
                ),
                handler: { args, context in
                    try systemUI.authenticateWeb(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .uiAlertPresent,
                    title: "Present alert with custom buttons",
                    summary: "Present a system alert or action sheet and return the button the user selects.",
                    tags: ["ui", "alert", "dialog", "system-ui"],
                    example: "await apple.ui.presentAlert({ title: 'Delete draft?', message: 'This cannot be undone.', buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'delete', title: 'Delete', style: 'destructive' }] })",
                    requiredArguments: ["buttons"],
                    optionalArguments: ["title", "message", "preferredStyle", "sourceRect", "timeoutMs"],
                    argumentTypes: [
                        "title": .string,
                        "message": .string,
                        "preferredStyle": .string,
                        "buttons": .array,
                        "sourceRect": .object,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "title": "Optional alert title.",
                        "message": "Optional alert message.",
                        "preferredStyle": "alert (default) or actionSheet.",
                        "sourceRect": "Optional { x, y, width, height } anchor for action sheets.",
                        "buttons": "Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Object with action/buttonID/buttonTitle/buttonIndex/style for the selected button."
                ),
                handler: { args, context in
                    try systemUI.presentAlert(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .uiPromptPresent,
                    title: "Present prompt with text fields",
                    summary: "Present a system alert with one or more text fields and custom buttons.",
                    tags: ["ui", "alert", "prompt", "input", "system-ui"],
                    example: "await apple.ui.presentPrompt({ title: 'Name', fields: [{ id: 'name', placeholder: 'Name' }], buttons: [{ id: 'cancel', title: 'Cancel', style: 'cancel' }, { id: 'ok', title: 'OK' }] })",
                    requiredArguments: ["fields", "buttons"],
                    optionalArguments: ["title", "message", "timeoutMs"],
                    argumentTypes: [
                        "title": .string,
                        "message": .string,
                        "fields": .array,
                        "buttons": .array,
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "fields": "Array of { id?, placeholder?, text?/defaultValue?, secure?, keyboardType? }. keyboardType is default, email, number, phone, or url.",
                        "buttons": "Array of { id?, title, style? }; style is default, cancel, or destructive. At most one cancel button.",
                        "timeoutMs": "Optional timeout for waiting on user selection.",
                    ],
                    resultSummary: "Object with selected button metadata and values keyed by field id."
                ),
                handler: { args, context in
                    try systemUI.presentPrompt(arguments: args, context: context)
                }
            ),
            CapabilityRegistration(
                descriptor: .init(
                    id: .settingsUIOpen,
                    title: "Open app settings",
                    summary: "Open the host app's Settings page so the user can recover denied permissions.",
                    tags: ["settings", "permissions", "system-ui"],
                    example: "await apple.settings.open()",
                    optionalArguments: ["timeoutMs"],
                    argumentTypes: [
                        "timeoutMs": .number,
                    ],
                    argumentHints: [
                        "timeoutMs": "Optional timeout for waiting on UIApplication.open completion.",
                    ],
                    resultSummary: "Object with action opened/failed and opened boolean."
                ),
                handler: { args, context in
                    try systemUI.openSettings(arguments: args, context: context)
                }
            ),
        ]
    }
}
