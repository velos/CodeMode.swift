import Foundation

/// Constrained CloudKit database selector; shared by the four database ops.
enum CloudKitDatabase: String, CodeModeStringEnum {
    case `private`
    case shared
    case `public`
}

// MARK: - CloudKit

@BuiltInCodeMode(.cloudKitAccountStatus, path: "apple.cloudkit.getAccountStatus")
struct CloudKitAccountStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read CloudKit account status"
    static let codeModeSummary = "Read iCloud account availability for CloudKit-backed agent state."
    static let codeModeTags = ["cloudkit", "icloud", "sync", "account"]
    static let codeModeExample = "await apple.cloudkit.getAccountStatus({ containerIdentifier: 'iCloud.com.example.app' })"
    static let codeModeResultSummary = "Object with status/accountAvailable and containerIdentifier when available."

    struct Arguments: Sendable {
        @ToolParam("Optional iCloud container identifier; defaults to the host client's configured container.")
        var containerIdentifier: String?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.accountStatus(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.cloudKitRecordsQuery, path: "apple.cloudkit.queryRecords")
struct CloudKitRecordsQueryTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Query CloudKit records"
    static let codeModeSummary = "Query records from a private/shared/public CloudKit database for synced agent state."
    static let codeModeTags = ["cloudkit", "icloud", "database", "query"]
    static let codeModeExample = "await apple.cloudkit.queryRecords({ database: 'private', recordType: 'Task', limit: 20 })"
    static let codeModeResultSummary = "Array of records with recordName/recordType/fields/modifiedAt/database."

    struct Arguments: Sendable {
        @ToolParam("CloudKit record type to query.")
        var recordType: String
        @ToolParam("private (default), shared, or public.")
        var database: CloudKitDatabase?
        @ToolParam("Optional iCloud container identifier.")
        var containerIdentifier: String?
        @ToolParam("Optional custom zone identifier.")
        var zoneID: String?
        @ToolParam("Host-supported predicate object or string; keep predicates bounded and repairable.")
        var predicate: JSONValue?
        @ToolParam("Optional array of sort descriptor objects.")
        var sortDescriptors: [JSONValue]?
        @ToolParam("Optional array of field keys to return.")
        var desiredKeys: [String]?
        @ToolParam("Max records to return; default is host-defined.")
        var limit: Int?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.queryRecords(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.cloudKitRecordSave, path: "apple.cloudkit.saveRecord")
struct CloudKitRecordSaveTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Save CloudKit record"
    static let codeModeSummary = "Create or update a CloudKit record in a private/shared/public database."
    static let codeModeTags = ["cloudkit", "icloud", "database", "write"]
    static let codeModeExample = "await apple.cloudkit.saveRecord({ database: 'private', recordType: 'Task', recordName: 'task-1', fields: { title: 'Review' } })"
    static let codeModeResultSummary = "Saved record object with recordName/recordType/fields/changeTag/database."

    struct Arguments: Sendable {
        @ToolParam("CloudKit record type to create or update.")
        var recordType: String
        @ToolParam("JSON object mapped by the host client into supported CloudKit field values.")
        var fields: [String: JSONValue]
        @ToolParam("Optional CloudKit recordName; omitted means create a new record.")
        var recordName: String?
        @ToolParam("private (default), shared, or public.")
        var database: CloudKitDatabase?
        @ToolParam("Optional iCloud container identifier.")
        var containerIdentifier: String?
        @ToolParam("Optional custom zone identifier.")
        var zoneID: String?
        @ToolParam("Host-supported save policy such as changedKeys or allKeys.")
        var savePolicy: String?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.saveRecord(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.cloudKitRecordDelete, path: "apple.cloudkit.deleteRecord")
struct CloudKitRecordDeleteTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Delete CloudKit record"
    static let codeModeSummary = "Delete a CloudKit record by recordName from a configured database."
    static let codeModeTags = ["cloudkit", "icloud", "database", "delete"]
    static let codeModeExample = "await apple.cloudkit.deleteRecord({ database: 'private', recordName: 'task-1' })"
    static let codeModeResultSummary = "Object with recordName/deleted/database."

    struct Arguments: Sendable {
        @ToolParam("CloudKit recordName to delete.")
        var recordName: String
        @ToolParam("private (default), shared, or public.")
        var database: CloudKitDatabase?
        @ToolParam("Optional iCloud container identifier.")
        var containerIdentifier: String?
        @ToolParam("Optional custom zone identifier.")
        var zoneID: String?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.deleteRecord(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.cloudKitSubscriptionSave, path: "apple.cloudkit.subscribe")
struct CloudKitSubscriptionSaveTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Save CloudKit subscription"
    static let codeModeSummary = "Register a bounded CloudKit query subscription so the host can enqueue subscription events later."
    static let codeModeTags = ["cloudkit", "icloud", "subscription", "inbox"]
    static let codeModeExample = "await apple.cloudkit.subscribe({ subscriptionID: 'tasks', database: 'private', recordType: 'Task' })"
    static let codeModeResultSummary = "Object with subscriptionID/saved/database."

    struct Arguments: Sendable {
        @ToolParam("Stable host-visible subscription identifier.")
        var subscriptionID: String
        @ToolParam("CloudKit record type to observe.")
        var recordType: String
        @ToolParam("private (default), shared, or public.")
        var database: CloudKitDatabase?
        @ToolParam("Optional iCloud container identifier.")
        var containerIdentifier: String?
        @ToolParam("Optional custom zone identifier.")
        var zoneID: String?
        @ToolParam("Host-supported predicate object or string.")
        var predicate: JSONValue?
        @ToolParam("Whether creation events are enqueued; default true.")
        var firesOnRecordCreation: Bool?
        @ToolParam("Whether update events are enqueued; default true.")
        var firesOnRecordUpdate: Bool?
        @ToolParam("Whether delete events are enqueued; default true.")
        var firesOnRecordDeletion: Bool?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.saveSubscription(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.cloudKitSubscriptionEventsRead, path: "apple.cloudkit.listEvents")
struct CloudKitSubscriptionEventsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read CloudKit subscription inbox"
    static let codeModeSummary = "Read bounded CloudKit subscription events previously received by the host."
    static let codeModeTags = ["cloudkit", "icloud", "subscription", "inbox", "events"]
    static let codeModeExample = "await apple.cloudkit.listEvents({ subscriptionID: 'tasks', limit: 20 })"
    static let codeModeResultSummary = "Array of subscription event objects with cursor/subscriptionID/recordName/reason/database."

    struct Arguments: Sendable {
        @ToolParam("Optional subscription filter.")
        var subscriptionID: String?
        @ToolParam("Maximum number of inbox events to read.")
        var limit: Int?
        @ToolParam("Optional host-provided cursor for incremental reads.")
        var afterCursor: String?
        var raw: [String: JSONValue]
    }

    let cloudKit: CloudKitBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try cloudKit.readSubscriptionEvents(arguments: arguments.raw)
    }
}

// MARK: - Remote notifications

@BuiltInCodeMode(.notificationsRemoteRegister, path: "apple.notifications.registerRemote")
struct NotificationsRemoteRegisterTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Register for remote notifications"
    static let codeModeSummary = "Ask the host app to register with APNs and record the client device-token lifecycle."
    static let codeModeTags = ["notifications", "apns", "remote", "registration"]
    static let codeModeExample = "await apple.notifications.registerRemote()"
    static let codeModeResultSummary = "Object with registered/status and deviceToken when already available."

    struct Arguments: Sendable {
        @ToolParam("Optional host-supported notification types; APNs provider sending is intentionally out of scope.")
        var types: [String]?
        var raw: [String: JSONValue]
    }

    let remoteNotifications: RemoteNotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try remoteNotifications.register(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.notificationsRemoteTokenRead, path: "apple.notifications.getRemoteToken")
struct NotificationsRemoteTokenReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read APNs device token"
    static let codeModeSummary = "Read the latest APNs device token captured by the host app."
    static let codeModeTags = ["notifications", "apns", "remote", "token"]
    static let codeModeExample = "await apple.notifications.getRemoteToken()"
    static let codeModeResultSummary = "Object with token/environment/updatedAt or null token when registration has not completed."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let remoteNotifications: RemoteNotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try remoteNotifications.readToken(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.notificationsSettingsRead, path: "apple.notifications.getSettings")
struct NotificationsSettingsReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read notification settings"
    static let codeModeSummary = "Read UserNotifications/APNs client settings exposed by the host."
    static let codeModeTags = ["notifications", "apns", "settings", "permission"]
    static let codeModeExample = "await apple.notifications.getSettings()"
    static let codeModeResultSummary = "Object with authorizationStatus/alert/badge/sound/criticalAlert/providesAppNotificationSettings."

    struct Arguments: Sendable {
        var raw: [String: JSONValue]
    }

    let remoteNotifications: RemoteNotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try remoteNotifications.readSettings(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.notificationsCategoriesSet, path: "apple.notifications.setCategories")
struct NotificationsCategoriesSetTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Set notification categories"
    static let codeModeSummary = "Register host-approved notification categories and actions for push/local response handling."
    static let codeModeTags = ["notifications", "apns", "categories", "actions"]
    static let codeModeExample = "await apple.notifications.setCategories({ categories: [{ identifier: 'task', actions: [{ identifier: 'done', title: 'Done' }] }] })"
    static let codeModeResultSummary = "Object with registered category identifiers."

    struct Arguments: Sendable {
        @ToolParam("Array of category definitions with identifier/actions/options approved by the host.")
        var categories: [JSONValue]
        var raw: [String: JSONValue]
    }

    let remoteNotifications: RemoteNotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try remoteNotifications.setCategories(arguments: arguments.raw)
    }
}

@BuiltInCodeMode(.notificationsResponsesRead, path: "apple.notifications.listResponses")
struct NotificationsResponsesReadTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read notification response inbox"
    static let codeModeSummary = "Read bounded notification action/open responses captured by the host for later agent handling."
    static let codeModeTags = ["notifications", "apns", "response", "inbox", "events"]
    static let codeModeExample = "await apple.notifications.listResponses({ limit: 20 })"
    static let codeModeResultSummary = "Array of response events with cursor/identifier/actionIdentifier/categoryIdentifier/userText/userInfo/date."

    struct Arguments: Sendable {
        @ToolParam("Maximum number of response events to read.")
        var limit: Int?
        @ToolParam("Optional category filter.")
        var categoryIdentifier: String?
        @ToolParam("Optional action filter.")
        var actionIdentifier: String?
        @ToolParam("Optional host-provided cursor for incremental reads.")
        var afterCursor: String?
        var raw: [String: JSONValue]
    }

    let remoteNotifications: RemoteNotificationsBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try remoteNotifications.readResponses(arguments: arguments.raw)
    }
}

// MARK: - Speech

@BuiltInCodeMode(.speechPermissionRequest, path: "apple.speech.requestPermission")
struct SpeechPermissionRequestTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Request speech recognition permission"
    static let codeModeSummary = "Trigger the Speech recognition permission prompt."
    static let codeModeTags = ["speech", "permission", "transcription"]
    static let codeModeExample = "await apple.speech.requestPermission()"
    static let codeModeResultSummary = "Object with status/granted."

    struct Arguments: Sendable {}

    let speech: SpeechBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try speech.requestPermission(context: context)
    }
}

@BuiltInCodeMode(.speechStatus, path: "apple.speech.getStatus")
struct SpeechStatusTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Read speech recognition permission status"
    static let codeModeSummary = "Read Speech recognition permission status without starting capture."
    static let codeModeTags = ["speech", "permission", "transcription"]
    static let codeModeExample = "await apple.speech.getStatus()"
    static let codeModeResultSummary = "Object with status/granted."

    struct Arguments: Sendable {}

    let speech: SpeechBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try speech.status(context: context)
    }
}

@BuiltInCodeMode(.speechFileTranscribe, path: "apple.speech.transcribeFile")
struct SpeechFileTranscribeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Transcribe audio file"
    static let codeModeSummary = "Transcribe a sandbox audio file through the host Speech adapter."
    static let codeModeTags = ["speech", "transcription", "audio"]
    static let codeModeExample = "await apple.speech.transcribeFile({ path: 'tmp:meeting.m4a', locale: 'en-US', timeoutMs: 60000 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.speechRecognition]
    static let codeModeResultSummary = "Object with transcript/segments/locale/isFinal/durationSeconds."

    struct Arguments: Sendable {
        @ToolParam("Sandbox audio file path.")
        var path: String
        @ToolParam("BCP-47 locale identifier such as en-US.")
        var locale: String?
        @ToolParam("Maximum transcription wait time in milliseconds.")
        var timeoutMs: Double?
        @ToolParam("Whether to require on-device recognition when the host supports it.")
        var requiresOnDeviceRecognition: Bool?
        @ToolParam("Speech task hint such as dictation, search, or confirmation.")
        var taskHint: String?
        var raw: [String: JSONValue]
    }

    let speech: SpeechBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try speech.transcribeFile(arguments: arguments.raw, context: context)
    }
}

@BuiltInCodeMode(.speechMicrophoneTranscribe, path: "apple.speech.transcribeMicrophone")
struct SpeechMicrophoneTranscribeTool: BuiltInCodeModeTool {
    static let codeModeTitle = "Transcribe microphone audio"
    static let codeModeSummary = "Run live microphone transcription through a host-mediated session with an explicit timeout."
    static let codeModeTags = ["speech", "transcription", "audio", "microphone"]
    static let codeModeExample = "await apple.speech.transcribeMicrophone({ locale: 'en-US', timeoutMs: 15000 })"
    static let codeModeRequiredPermissions: [PermissionKind] = [.speechRecognition, .microphone]
    static let codeModeResultSummary = "Object with transcript/segments/locale/isFinal/timedOut."

    struct Arguments: Sendable {
        @ToolParam("BCP-47 locale identifier such as en-US.")
        var locale: String?
        @ToolParam("Maximum microphone capture/transcription time in milliseconds.")
        var timeoutMs: Double?
        @ToolParam("Whether to require on-device recognition when the host supports it.")
        var requiresOnDeviceRecognition: Bool?
        @ToolParam("Speech task hint such as dictation, search, or confirmation.")
        var taskHint: String?
        @ToolParam("Whether partial transcripts may be returned.")
        var partialResults: Bool?
        var raw: [String: JSONValue]
    }

    let speech: SpeechBridge

    func call(arguments: Arguments, context: BridgeInvocationContext) throws -> JSONValue {
        try speech.transcribeMicrophone(arguments: arguments.raw, context: context)
    }
}
