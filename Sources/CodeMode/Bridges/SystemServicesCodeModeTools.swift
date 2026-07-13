import Foundation

// Vision / notifications / alarms / health / home / media capabilities.
// No constrained argument values in this domain, so no CodeModeStringEnums and
// no bridge rewiring. Health tools intentionally declare no requiredPermissions:
// HealthKit read authorization is opaque, so HealthBridge performs its own
// per-type authorization (see noBuiltInRegistrationGatesOnHealthKitPermission).

// MARK: - Vision

@BuiltInCodeMode(.visionImageAnalyze, path: "apple.vision.analyzeImage")
struct VisionImageAnalyzeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Analyze image with Vision"
    static let codeModeSummary = "Run on-device image analysis for labels/text/barcodes on sandbox image paths."
    static let codeModeTags = ["vision", "image-analysis", "ml"]
    static let codeModeExample = "await apple.vision.analyzeImage({ path: 'tmp:receipt.jpg', features: ['text'], maxResults: 10 })"
    static let codeModeResultSummary = "Object containing requested analysis sections such as labels/text/barcodes."

    struct Arguments: Sendable {
        @ToolParam("Sandbox image path to analyze.")
        var path: String
        @ToolParam("Optional array including labels/text/barcodes.")
        var features: [String]?
        @ToolParam("Max observations returned per feature, default 5.")
        var maxResults: Int?
        var raw: [String: JSONValue]
    }

    let vision: VisionBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try vision.analyzeImage(arguments: arguments.raw, context: context)
    }
}

// MARK: - Notifications

@BuiltInCodeMode(.notificationsPermissionRequest, path: "apple.notifications.requestPermission")
struct NotificationsPermissionRequestTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Request notification permission"
    static let codeModeSummary = "Request local notification authorization from the user."
    static let codeModeTags = ["notifications", "permission"]
    static let codeModeExample = "await apple.notifications.requestPermission()"
    static let codeModeResultSummary = "Object with status/granted fields."

    struct Arguments: Sendable {}

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.requestPermission(context: context)
    }
}

@BuiltInCodeMode(.notificationsSchedule, path: "apple.notifications.schedule")
struct NotificationsScheduleTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Schedule local notification"
    static let codeModeSummary = "Schedule a local notification using time interval or fireDate trigger."
    static let codeModeTags = ["notifications", "local", "schedule"]
    static let codeModeExample = "await apple.notifications.schedule({ title: 'Stand up', body: 'Stretch break', secondsFromNow: 900 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.notifications]
    static let codeModeResultSummary = "Object with identifier/scheduled/repeats."

    struct Arguments: Sendable {
        @ToolParam("Notification title text.")
        var title: String
        @ToolParam("Optional request identifier; defaults to codemode UUID.")
        var identifier: String?
        @ToolParam("Optional subtitle text.")
        var subtitle: String?
        @ToolParam("Optional body text.")
        var body: String?
        @ToolParam("Delay in seconds for time interval trigger (default 5).")
        var secondsFromNow: Double?
        @ToolParam("Optional ISO8601 timestamp for calendar trigger.")
        var fireDate: String?
        @ToolParam("Boolean repeat flag (time interval requires >= 60 seconds).")
        var repeats: Bool?
        @ToolParam("default (default), none, or a bundled custom sound name.")
        var sound: String?
        @ToolParam("Optional app icon badge number.")
        var badge: Int?
        @ToolParam("Optional property-list-safe userInfo object.")
        var userInfo: [String: JSONValue]?
        @ToolParam("Optional thread identifier for notification grouping.")
        var threadIdentifier: String?
        @ToolParam("Optional category identifier for notification actions.")
        var categoryIdentifier: String?
        var raw: [String: JSONValue]
    }

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.schedule(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.notificationsPendingRead, path: "apple.notifications.listPending")
struct NotificationsPendingReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List pending local notifications"
    static let codeModeSummary = "List pending local notification requests."
    static let codeModeTags = ["notifications", "local", "schedule"]
    static let codeModeExample = "await apple.notifications.listPending({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.notifications]
    static let codeModeResultSummary = "Array of pending requests with identifiers/content/trigger metadata."

    struct Arguments: Sendable {
        @ToolParam("Max number of pending requests to return, default 50.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.readPending(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.notificationsPendingDelete, path: "apple.notifications.cancelPending")
struct NotificationsPendingDeleteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete pending local notifications"
    static let codeModeSummary = "Delete pending local notifications by identifier list or clear all."
    static let codeModeTags = ["notifications", "local", "schedule"]
    static let codeModeExample = "await apple.notifications.cancelPending({ identifiers: ['codemode.1', 'codemode.2'] })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.notifications]
    static let codeModeResultSummary = "Object with deleted/count fields."

    struct Arguments: Sendable {
        @ToolParam("Single pending request identifier to remove.")
        var identifier: String?
        @ToolParam("Array of pending request identifiers to remove. Omit both to clear all pending requests.")
        var identifiers: [String]?
        var raw: [String: JSONValue]
    }

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.deletePending(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.notificationsDeliveredRead, path: "apple.notifications.listDelivered")
struct NotificationsDeliveredReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List delivered local notifications"
    static let codeModeSummary = "List notifications currently delivered in Notification Center."
    static let codeModeTags = ["notifications", "local", "delivered"]
    static let codeModeExample = "await apple.notifications.listDelivered({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.notifications]
    static let codeModeResultSummary = "Array of delivered notifications with identifiers/content/date metadata."

    struct Arguments: Sendable {
        @ToolParam("Max number of delivered notifications to return, default 50.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.readDelivered(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.notificationsDeliveredDelete, path: "apple.notifications.removeDelivered")
struct NotificationsDeliveredDeleteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete delivered local notifications"
    static let codeModeSummary = "Delete delivered notifications by identifier list or clear all."
    static let codeModeTags = ["notifications", "local", "delivered", "delete"]
    static let codeModeExample = "await apple.notifications.removeDelivered({ identifiers: ['codemode.1', 'codemode.2'] })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.notifications]
    static let codeModeResultSummary = "Object with deleted/count fields."

    struct Arguments: Sendable {
        @ToolParam("Single delivered notification identifier to remove.")
        var identifier: String?
        @ToolParam("Array of delivered notification identifiers to remove. Omit both to clear all delivered notifications.")
        var identifiers: [String]?
        var raw: [String: JSONValue]
    }

    let notifications: NotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try notifications.deleteDelivered(arguments: arguments.raw, context: context)
    }
}

// MARK: - Alarms

@BuiltInCodeMode(.alarmPermissionRequest, path: "ios.alarm.requestPermission")
struct AlarmPermissionRequestTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Request AlarmKit permission"
    static let codeModeSummary = "Request AlarmKit authorization from the user."
    static let codeModeTags = ["alarmkit", "permission", "alarms"]
    static let codeModeExample = "await ios.alarm.requestPermission()"
    static let codeModeResultSummary = "Object with status/granted fields."

    struct Arguments: Sendable {}

    let alarm: AlarmBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try alarm.requestPermission(context: context)
    }
}

@BuiltInCodeMode(.alarmRead, path: "ios.alarm.list")
struct AlarmReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "List scheduled alarms"
    static let codeModeSummary = "List scheduled alarms known to the bridge runtime."
    static let codeModeTags = ["alarmkit", "alarms", "schedule"]
    static let codeModeExample = "await ios.alarm.list({ limit: 20 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.alarmKit]
    static let codeModeResultSummary = "Array of scheduled alarms with identifier/title/timing fields."

    struct Arguments: Sendable {
        @ToolParam("Max number of scheduled alarms returned, default 50.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let alarm: AlarmBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try alarm.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.alarmSchedule, path: "ios.alarm.schedule")
struct AlarmScheduleTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Schedule AlarmKit alarm"
    static let codeModeSummary = "Schedule an AlarmKit alarm using secondsFromNow or fireDate."
    static let codeModeTags = ["alarmkit", "alarms", "schedule"]
    static let codeModeExample = "await ios.alarm.schedule({ title: 'Wake up', secondsFromNow: 1800 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.alarmKit]
    static let codeModeResultSummary = "Object with identifier/scheduled/title."

    struct Arguments: Sendable {
        @ToolParam("Alarm title shown in presentation.")
        var title: String
        @ToolParam("Optional UUID string; generated when omitted.")
        var identifier: String?
        @ToolParam("Fallback relative delay in seconds, default 60.")
        var secondsFromNow: Double?
        @ToolParam("Optional absolute ISO8601 date; used when provided.")
        var fireDate: String?
        var raw: [String: JSONValue]
    }

    let alarm: AlarmBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try alarm.schedule(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.alarmCancel, path: "ios.alarm.cancel")
struct AlarmCancelTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Cancel scheduled alarms"
    static let codeModeSummary = "Cancel one or more scheduled alarms by identifier, or clear all known alarms."
    static let codeModeTags = ["alarmkit", "alarms", "schedule"]
    static let codeModeExample = "await ios.alarm.cancel({ identifiers: ['8F11679B-92E8-4D2F-84B4-4D0A7C95E3C3'] })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.alarmKit]
    static let codeModeResultSummary = "Object with deleted/count fields."

    struct Arguments: Sendable {
        @ToolParam("Single alarm identifier UUID string.")
        var identifier: String?
        @ToolParam("Array of alarm identifier UUID strings. Omit both to cancel all known alarms.")
        var identifiers: [String]?
        var raw: [String: JSONValue]
    }

    let alarm: AlarmBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try alarm.cancel(arguments: arguments.raw, context: context)
    }
}

// MARK: - Health

@BuiltInCodeMode(.healthPermissionRequest, path: "apple.health.requestPermission")
struct HealthPermissionRequestTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Request HealthKit permission"
    static let codeModeSummary = "Request HealthKit authorization for requested read/write types."
    static let codeModeTags = ["healthkit", "health", "permission"]
    static let codeModeExample = "await apple.health.requestPermission({ readTypes: ['stepCount', 'heartRate'], writeTypes: ['stepCount'] })"
    static let codeModeResultSummary = "Object with status/granted fields and requested type arrays."

    struct Arguments: Sendable {
        @ToolParam("Optional array of type names to read, e.g. stepCount, heartRate, activeEnergyBurned.")
        var readTypes: [String]?
        @ToolParam("Optional array of type names to write (quantity types only).")
        var writeTypes: [String]?
        var raw: [String: JSONValue]
    }

    let health: HealthBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try health.requestPermission(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.healthRead, path: "apple.health.read")
struct HealthReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read HealthKit samples"
    static let codeModeSummary = "Read HealthKit samples for a supported type and date range."
    static let codeModeTags = ["healthkit", "health", "query"]
    static let codeModeExample = "await apple.health.read({ type: 'stepCount', start: '2026-03-03T00:00:00Z', end: '2026-03-04T00:00:00Z', limit: 25, unit: 'count' })"
    static let codeModeResultSummary = "Array of samples with identifier/type/value and timing metadata."

    struct Arguments: Sendable {
        @ToolParam("Supported: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning, sleepAnalysis, workout.")
        var type: String
        @ToolParam("Optional ISO8601 start timestamp; defaults to last 24h.")
        var start: String?
        @ToolParam("Optional ISO8601 end timestamp; defaults to now.")
        var end: String?
        @ToolParam("Max number of samples, default 50.")
        var limit: Int?
        @ToolParam("Optional unit override for quantity types (count, bpm, kcal, kg, m).")
        var unit: String?
        var raw: [String: JSONValue]
    }

    let health: HealthBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try health.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.healthWrite, path: "apple.health.write")
struct HealthWriteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Write HealthKit quantity sample"
    static let codeModeSummary = "Write a HealthKit quantity sample for supported writable quantity types."
    static let codeModeTags = ["healthkit", "health", "write"]
    static let codeModeExample = "await apple.health.write({ type: 'stepCount', value: 1200, unit: 'count', start: '2026-03-04T08:00:00Z', end: '2026-03-04T08:30:00Z' })"
    static let codeModeResultSummary = "Object with identifier/type/value/unit and written=true."

    struct Arguments: Sendable {
        @ToolParam("Writable types: stepCount, heartRate, activeEnergyBurned, bodyMass, distanceWalkingRunning.")
        var type: String
        @ToolParam("Numeric sample value.")
        var value: Double
        @ToolParam("Optional unit (count, bpm, kcal, kg, m).")
        var unit: String?
        @ToolParam("Optional ISO8601 start timestamp; defaults to now.")
        var start: String?
        @ToolParam("Optional ISO8601 end timestamp; defaults to start.")
        var end: String?
        var raw: [String: JSONValue]
    }

    let health: HealthBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try health.write(arguments: arguments.raw, context: context)
    }
}

// MARK: - Home

@BuiltInCodeMode(.homeRead, path: "apple.home.list")
struct HomeReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read HomeKit graph"
    static let codeModeSummary = "Read homes/accessories/services (and optional characteristics) from HomeKit."
    static let codeModeTags = ["homekit", "iot", "devices"]
    static let codeModeExample = "await apple.home.list({ includeCharacteristics: true, limit: 5 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.homeKit]
    static let codeModeResultSummary = "Array of homes with accessories/services snapshot."

    struct Arguments: Sendable {
        @ToolParam("Boolean; include characteristic details when true.")
        var includeCharacteristics: Bool?
        @ToolParam("Max number of homes to return, default 10.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let home: HomeBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try home.read(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.homeWrite, path: "apple.home.writeCharacteristic")
struct HomeWriteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Write HomeKit characteristic"
    static let codeModeSummary = "Write a value to a writable HomeKit characteristic for a target accessory."
    static let codeModeTags = ["homekit", "iot", "devices", "control"]
    static let codeModeExample = "await apple.home.writeCharacteristic({ accessoryIdentifier: 'UUID', characteristicType: 'HMCharacteristicTypePowerState', value: true })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.homeKit]
    static let codeModeResultSummary = "Object with accessoryIdentifier/characteristicType/written."

    struct Arguments: Sendable {
        @ToolParam("Accessory UUID string from home.read output.")
        var accessoryIdentifier: String
        @ToolParam("Characteristic type identifier (e.g. HMCharacteristicTypePowerState).")
        var characteristicType: String
        @ToolParam("Target value; string/number/bool/null.")
        var value: JSONValue
        @ToolParam("Optional service type filter for characteristic lookup.")
        var serviceType: String?
        var raw: [String: JSONValue]
    }

    let home: HomeBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try home.write(arguments: arguments.raw, context: context)
    }
}

// MARK: - Media

@BuiltInCodeMode(.mediaMetadataRead, path: "apple.media.metadata")
struct MediaMetadataReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read media metadata"
    static let codeModeSummary = "Read duration and track metadata from media files."
    static let codeModeTags = ["media", "avfoundation", "metadata"]
    static let codeModeExample = "await apple.media.metadata({ path: 'tmp:video.mov' })"
    static let codeModeResultSummary = "Object with path/durationSeconds/tracks."

    struct Arguments: Sendable {
        @ToolParam("Sandbox path like tmp:clip.mov.")
        var path: String
        var raw: [String: JSONValue]
    }

    let media: MediaBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try media.metadata(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.mediaFrameExtract, path: "apple.media.extractFrame")
struct MediaFrameExtractTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Extract video frame"
    static let codeModeSummary = "Extract frame at time offset and persist JPEG output."
    static let codeModeTags = ["media", "avfoundation", "thumbnail"]
    static let codeModeExample = "await apple.media.extractFrame({ path: 'tmp:video.mov', timeMs: 1500 })"
    static let codeModeResultSummary = "Object with output path and artifactID."

    struct Arguments: Sendable {
        @ToolParam("Input video sandbox path.")
        var path: String
        @ToolParam("Frame timestamp in milliseconds; default 0.")
        var timeMs: Double?
        @ToolParam("Optional output sandbox path; defaults to tmp-generated JPEG.")
        var outputPath: String?
        var raw: [String: JSONValue]
    }

    let media: MediaBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try media.extractFrame(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.mediaTranscode, path: "apple.media.transcode")
struct MediaTranscodeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Transcode media"
    static let codeModeSummary = "Transcode media into MP4 with preset quality."
    static let codeModeTags = ["media", "avfoundation", "transcode"]
    static let codeModeExample = "await apple.media.transcode({ path: 'tmp:input.mov', preset: 'AVAssetExportPresetMediumQuality' })"
    static let codeModeResultSummary = "Object with output path/artifactID/preset."

    struct Arguments: Sendable {
        @ToolParam("Input media sandbox path.")
        var path: String
        @ToolParam("Optional output sandbox path; defaults to tmp-generated mp4.")
        var outputPath: String?
        @ToolParam("AVAssetExportSession preset string; default AVAssetExportPresetMediumQuality.")
        var preset: String?
        var raw: [String: JSONValue]
    }

    let media: MediaBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try media.transcode(arguments: arguments.raw, context: context)
    }
}
