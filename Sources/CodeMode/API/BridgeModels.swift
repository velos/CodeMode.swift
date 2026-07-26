import Foundation

public struct CodeModeConfiguration: Sendable {
    public var pathPolicy: any PathPolicy
    public var networkAccessPolicy: NetworkAccessPolicy
    /// Host-owned ceiling on the model-authored `allowedCapabilities` /
    /// `allowedCapabilityKeys`. Defaults to `.unrestricted`; see `CapabilityGrant`.
    public var capabilityGrant: CapabilityGrant
    public var fileSystem: any CodeModeFileSystem
    /// Byte ceilings applied by the filesystem bridge to `fs.read` / `fs.write`.
    public var fileSystemLimits: FileSystemLimits
    /// Bounds on retained result/log/event volume for a single execution.
    public var executionLimits: ExecutionLimits
    public var artifactStore: any ArtifactStore
    public var permissionBroker: any PermissionBroker
    public var auditLogger: any AuditLogger
    public var systemUIPresenter: any SystemUIPresenter
    public var eventInbox: any CodeModeEventInbox
    public var cloudKitClient: any CloudKitClient
    public var remoteNotificationsClient: any RemoteNotificationsClient
    public var speechClient: any SpeechClient
    public var appIntentsClient: any AppIntentsClient
    public var foundationModelsClient: any FoundationModelsClient
    public var activityClient: any ActivityClient
    public var mapsClient: any MapsClient
    public var musicClient: any MusicClient
    public var passKitClient: any PassKitClient
    public var storeKitClient: any StoreKitClient
    public var codeModeProviders: [any CodeModeProvider]
    public var hostPlatform: HostPlatform

    public init(
        pathPolicy: any PathPolicy = DefaultPathPolicy(),
        networkAccessPolicy: NetworkAccessPolicy = .standard,
        capabilityGrant: CapabilityGrant = .unrestricted,
        fileSystem: any CodeModeFileSystem = LocalCodeModeFileSystem(),
        fileSystemLimits: FileSystemLimits = .standard,
        executionLimits: ExecutionLimits = .standard,
        artifactStore: any ArtifactStore = InMemoryArtifactStore(),
        permissionBroker: any PermissionBroker = SystemPermissionBroker(),
        auditLogger: any AuditLogger = SyncAuditLogger(),
        systemUIPresenter: any SystemUIPresenter = UnavailableSystemUIPresenter(),
        eventInbox: any CodeModeEventInbox = UnavailableCodeModeEventInbox(),
        cloudKitClient: any CloudKitClient = UnavailableCloudKitClient(),
        remoteNotificationsClient: any RemoteNotificationsClient = UnavailableRemoteNotificationsClient(),
        speechClient: any SpeechClient = UnavailableSpeechClient(),
        appIntentsClient: any AppIntentsClient = UnavailableAppIntentsClient(),
        foundationModelsClient: any FoundationModelsClient = UnavailableFoundationModelsClient(),
        activityClient: any ActivityClient = UnavailableActivityClient(),
        mapsClient: any MapsClient = UnavailableMapsClient(),
        musicClient: any MusicClient = UnavailableMusicClient(),
        passKitClient: any PassKitClient = UnavailablePassKitClient(),
        storeKitClient: any StoreKitClient = UnavailableStoreKitClient(),
        codeModeProviders: [any CodeModeProvider] = [],
        hostPlatform: HostPlatform = .current
    ) {
        self.pathPolicy = pathPolicy
        self.networkAccessPolicy = networkAccessPolicy
        self.capabilityGrant = capabilityGrant
        self.fileSystem = fileSystem
        self.fileSystemLimits = fileSystemLimits
        self.executionLimits = executionLimits
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
        self.systemUIPresenter = systemUIPresenter
        self.eventInbox = eventInbox
        self.cloudKitClient = cloudKitClient
        self.remoteNotificationsClient = remoteNotificationsClient
        self.speechClient = speechClient
        self.appIntentsClient = appIntentsClient
        self.foundationModelsClient = foundationModelsClient
        self.activityClient = activityClient
        self.mapsClient = mapsClient
        self.musicClient = musicClient
        self.passKitClient = passKitClient
        self.storeKitClient = storeKitClient
        self.codeModeProviders = codeModeProviders
        self.hostPlatform = hostPlatform
    }
}

public struct JavaScriptAPISearchRequest: Sendable, Codable, Equatable {
    public var code: String

    public init(code: String) {
        self.code = code
    }
}

public struct JavaScriptAPIReference: Sendable, Codable, Equatable {
    public var capability: String
    public var capabilityKey: CodeModeCapabilityKey
    public var builtInCapability: CapabilityID?
    public var jsNames: [String]
    public var summary: String
    public var tags: [String]
    public var example: String
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var argumentTypes: [String: CapabilityArgumentType]
    public var argumentHints: [String: String]
    public var argumentConstraints: CapabilityArgumentConstraints
    public var resultSummary: String

    public init(
        capability: String,
        capabilityKey: CodeModeCapabilityKey? = nil,
        builtInCapability: CapabilityID? = nil,
        jsNames: [String],
        summary: String,
        tags: [String],
        example: String,
        requiredArguments: [String],
        optionalArguments: [String],
        argumentTypes: [String: CapabilityArgumentType],
        argumentHints: [String: String],
        argumentConstraints: CapabilityArgumentConstraints = .none,
        resultSummary: String
    ) {
        self.capability = capability
        self.capabilityKey = capabilityKey ?? CodeModeCapabilityKey(rawValue: capability)
        self.builtInCapability = builtInCapability
        self.jsNames = jsNames
        self.summary = summary
        self.tags = tags
        self.example = example
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.argumentTypes = argumentTypes
        self.argumentHints = argumentHints
        self.argumentConstraints = argumentConstraints
        self.resultSummary = resultSummary
    }
}

public struct JavaScriptAPISearchResponse: Sendable, Codable, Equatable {
    public var result: JSONValue?
    public var diagnostics: [ToolDiagnostic]

    public init(result: JSONValue?, diagnostics: [ToolDiagnostic] = []) {
        self.result = result
        self.diagnostics = diagnostics
    }
}

public struct JavaScriptExecutionRequest: Sendable, Codable, Equatable {
    /// Bounds advertised in `executeJavaScriptParameterSchema`. Values outside
    /// them are clamped rather than rejected: a model that asks for a 10-minute
    /// budget should get the ceiling and a running script, not a hard failure.
    public static let minimumTimeoutMs = 1
    public static let maximumTimeoutMs = 60_000
    public static let defaultTimeoutMs = 10_000

    public var code: String
    public var allowedCapabilities: [CapabilityID]
    public var allowedCapabilityKeys: [CodeModeCapabilityKey]
    public var timeoutMs: Int
    public var context: ExecutionContext

    public init(
        code: String,
        allowedCapabilities: [CapabilityID],
        allowedCapabilityKeys: [CodeModeCapabilityKey] = [],
        timeoutMs: Int = JavaScriptExecutionRequest.defaultTimeoutMs,
        context: ExecutionContext = .init()
    ) {
        self.code = code
        self.allowedCapabilities = allowedCapabilities
        self.allowedCapabilityKeys = allowedCapabilityKeys
        self.timeoutMs = Self.clampTimeoutMs(timeoutMs)
        self.context = context
    }

    static func clampTimeoutMs(_ value: Int) -> Int {
        min(max(value, minimumTimeoutMs), maximumTimeoutMs)
    }

    private enum CodingKeys: String, CodingKey {
        case code
        case allowedCapabilities
        case allowedCapabilityKeys
        case timeoutMs
        case context
    }

    // Custom decoding tolerant of common LLM tool-call quirks, and aligned with the
    // advertised schema where only `code` and `allowedCapabilities` are required:
    //  - `allowedCapabilityKeys`, `timeoutMs`, and `context` may be omitted (the
    //    synthesized decoder wrongly required all three, so an otherwise-valid call
    //    that left them out was rejected).
    //  - `timeoutMs` accepts a JSON number or a numeric string ("10000").
    //  - an unknown capability ID in `allowedCapabilities` produces a clear,
    //    actionable error naming the offending value(s) instead of an opaque
    //    Codable failure.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.code = try container.decode(String.self, forKey: .code)

        let rawCapabilities = try container.decode([String].self, forKey: .allowedCapabilities)
        var capabilities: [CapabilityID] = []
        var unknown: [String] = []
        for raw in rawCapabilities {
            if let id = CapabilityID(rawValue: raw) {
                capabilities.append(id)
            } else {
                unknown.append(raw)
            }
        }
        guard unknown.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .allowedCapabilities,
                in: container,
                debugDescription: "Unknown capability ID(s): \(unknown.joined(separator: ", ")). Use searchJavaScriptAPI to discover valid capability IDs."
            )
        }
        self.allowedCapabilities = capabilities

        self.allowedCapabilityKeys = try container.decodeIfPresent([CodeModeCapabilityKey].self, forKey: .allowedCapabilityKeys) ?? []
        self.timeoutMs = Self.clampTimeoutMs(try Self.decodeTimeoutMs(from: container) ?? Self.defaultTimeoutMs)
        self.context = try container.decodeIfPresent(ExecutionContext.self, forKey: .context) ?? .init()
    }

    // Every conversion here is total. `Int.init(_: Double)` traps on non-finite
    // and out-of-range input, and this runs on model-authored JSON before any
    // script does — `{"timeoutMs": 1e300}` would kill the host process in-process.
    private static func decodeTimeoutMs(from container: KeyedDecodingContainer<CodingKeys>) throws -> Int? {
        guard container.contains(.timeoutMs), try !container.decodeNil(forKey: .timeoutMs) else {
            return nil
        }
        if let value = try? container.decode(Int.self, forKey: .timeoutMs) {
            return value
        }
        if let value = try? container.decode(Double.self, forKey: .timeoutMs) {
            return try requireRepresentable(value, in: container)
        }
        if let string = try? container.decode(String.self, forKey: .timeoutMs),
           let value = Double(string.trimmingCharacters(in: .whitespaces)) {
            return try requireRepresentable(value, in: container)
        }
        throw DecodingError.dataCorruptedError(
            forKey: .timeoutMs,
            in: container,
            debugDescription: "timeoutMs must be an integer or a numeric string."
        )
    }

    private static func requireRepresentable(
        _ value: Double,
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Int {
        guard let converted = JSONValue.exactInt(from: value) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeoutMs,
                in: container,
                debugDescription: "timeoutMs must be a finite number representable as an integer; received \(value)."
            )
        }
        return converted
    }
}

public enum JavaScriptExecutionEvent: Sendable, Equatable {
    case log(ExecutionLog)
    case diagnostic(ToolDiagnostic)
    case syntaxError(CodeModeToolError)
    case functionNotFound(CodeModeToolError)
    case thrownError(CodeModeToolError)
    case toolError(CodeModeToolError)
    case finished
}

public struct JavaScriptExecutionResult: Sendable, Codable, Equatable {
    public var output: JSONValue?
    public var logs: [ExecutionLog]
    public var diagnostics: [ToolDiagnostic]
    public var permissionEvents: [PermissionEvent]

    public init(
        output: JSONValue?,
        logs: [ExecutionLog],
        diagnostics: [ToolDiagnostic],
        permissionEvents: [PermissionEvent]
    ) {
        self.output = output
        self.logs = logs
        self.diagnostics = diagnostics
        self.permissionEvents = permissionEvents
    }
}

public struct CodeModeToolError: Error, Sendable, Codable, Equatable {
    public var code: String
    public var message: String
    public var functionName: String?
    public var capability: CapabilityID?
    public var capabilityKey: CodeModeCapabilityKey?
    public var line: Int?
    public var column: Int?
    public var suggestions: [String]
    public var diagnostics: [ToolDiagnostic]
    public var logs: [ExecutionLog]
    public var permissionEvents: [PermissionEvent]

    public init(
        code: String,
        message: String,
        functionName: String? = nil,
        capability: CapabilityID? = nil,
        capabilityKey: CodeModeCapabilityKey? = nil,
        line: Int? = nil,
        column: Int? = nil,
        suggestions: [String] = [],
        diagnostics: [ToolDiagnostic] = [],
        logs: [ExecutionLog] = [],
        permissionEvents: [PermissionEvent] = []
    ) {
        self.code = code
        self.message = message
        self.functionName = functionName
        self.capability = capability
        self.capabilityKey = capabilityKey ?? capability?.codeModeKey
        self.line = line
        self.column = column
        self.suggestions = suggestions
        self.diagnostics = diagnostics
        self.logs = logs
        self.permissionEvents = permissionEvents
    }
}

extension CodeModeToolError: LocalizedError {
    public var errorDescription: String? {
        message
    }
}

public final class JavaScriptExecutionCall: @unchecked Sendable {
    public let events: AsyncStream<JavaScriptExecutionEvent>

    private let resultTask: Task<JavaScriptExecutionResult, Error>
    private let cancelImpl: @Sendable () -> Void

    init(
        events: AsyncStream<JavaScriptExecutionEvent>,
        resultTask: Task<JavaScriptExecutionResult, Error>,
        cancelImpl: @escaping @Sendable () -> Void
    ) {
        self.events = events
        self.resultTask = resultTask
        self.cancelImpl = cancelImpl
    }

    public var result: JavaScriptExecutionResult {
        get async throws {
            let outcome = await withTaskCancellationHandler {
                // `resultTask.result` already detaches the await from the calling
                // task's cancellation, so the previous `Task.detached` per access
                // bought nothing but an extra task.
                await resultTask.result
            } onCancel: {
                self.cancel()
            }

            switch outcome {
            case let .success(result):
                return result
            case let .failure(error as CodeModeToolError):
                throw error
            case .failure(is CancellationError):
                throw CodeModeToolError(code: "CANCELLED", message: "Execution cancelled")
            case let .failure(error):
                throw error
            }
        }
    }

    public func cancel() {
        cancelImpl()
        resultTask.cancel()
    }

    /// A dropped call must not keep running: without this, an execution whose
    /// handle nobody holds continues to completion in the background, still
    /// touching the filesystem, the network, and system UI on the user's behalf.
    deinit {
        cancelImpl()
        resultTask.cancel()
    }
}

public struct ExecutionContext: Sendable, Codable, Equatable {
    public var userID: String?
    public var sessionID: String?
    public var metadata: [String: String]

    public init(userID: String? = nil, sessionID: String? = nil, metadata: [String: String] = [:]) {
        self.userID = userID
        self.sessionID = sessionID
        self.metadata = metadata
    }
}

public struct ToolDiagnostic: Sendable, Codable, Equatable {
    public enum Severity: String, Sendable, Codable {
        case info
        case warning
        case error
    }

    public var severity: Severity
    public var code: String
    public var message: String
    public var category: String?
    public var line: Int?
    public var column: Int?
    public var functionName: String?
    public var suggestions: [String]

    public init(
        severity: Severity,
        code: String,
        message: String,
        category: String? = nil,
        line: Int? = nil,
        column: Int? = nil,
        functionName: String? = nil,
        suggestions: [String] = []
    ) {
        self.severity = severity
        self.code = code
        self.message = message
        self.category = category
        self.line = line
        self.column = column
        self.functionName = functionName
        self.suggestions = suggestions
    }
}

public struct ExecutionLog: Sendable, Codable, Equatable {
    public enum Level: String, Sendable, Codable {
        case debug
        case info
        case warning
        case error
    }

    public var level: Level
    public var message: String
    public var timestamp: Date

    public init(level: Level, message: String, timestamp: Date = Date()) {
        self.level = level
        self.message = message
        self.timestamp = timestamp
    }
}

public struct PermissionEvent: Sendable, Codable, Equatable {
    public var permission: PermissionKind
    public var status: PermissionStatus
    public var timestamp: Date

    public init(permission: PermissionKind, status: PermissionStatus, timestamp: Date = Date()) {
        self.permission = permission
        self.status = status
        self.timestamp = timestamp
    }
}

public enum CapabilityID: String, Sendable, Codable, CaseIterable, Hashable {
    case networkFetch = "network.fetch"

    case keychainRead = "keychain.read"
    case keychainWrite = "keychain.write"
    case keychainDelete = "keychain.delete"

    case locationRead = "location.read"
    case locationPermissionRequest = "location.permission.request"

    case weatherRead = "weather.read"

    case calendarRead = "calendar.read"
    case calendarWrite = "calendar.write"
    case calendarDelete = "calendar.delete"
    case calendarUIPresentNewEvent = "calendar.ui.presentNewEvent"

    case remindersRead = "reminders.read"
    case remindersWrite = "reminders.write"
    case remindersDelete = "reminders.delete"

    case contactsRead = "contacts.read"
    case contactsSearch = "contacts.search"
    case contactsUIPick = "contacts.ui.pick"

    case photosRead = "photos.read"
    case photosExport = "photos.export"
    case photosUIPick = "photos.ui.pick"
    case photosUIPresentLimitedLibraryPicker = "photos.ui.presentLimitedLibraryPicker"

    case visionImageAnalyze = "vision.image.analyze"

    case notificationsPermissionRequest = "notifications.permission.request"
    case notificationsSchedule = "notifications.schedule"
    case notificationsPendingRead = "notifications.pending.read"
    case notificationsPendingDelete = "notifications.pending.delete"
    case notificationsDeliveredRead = "notifications.delivered.read"
    case notificationsDeliveredDelete = "notifications.delivered.delete"
    case notificationsRemoteRegister = "notifications.remote.register"
    case notificationsRemoteTokenRead = "notifications.remote.token.read"
    case notificationsSettingsRead = "notifications.settings.read"
    case notificationsCategoriesSet = "notifications.categories.set"
    case notificationsResponsesRead = "notifications.responses.read"

    case alarmPermissionRequest = "alarm.permission.request"
    case alarmRead = "alarm.read"
    case alarmSchedule = "alarm.schedule"
    case alarmCancel = "alarm.cancel"

    case healthPermissionRequest = "health.permission.request"
    case healthRead = "health.read"
    case healthWrite = "health.write"

    case homeRead = "home.read"
    case homeWrite = "home.write"

    case mediaMetadataRead = "media.metadata.read"
    case mediaFrameExtract = "media.frame.extract"
    case mediaTranscode = "media.transcode"

    case cloudKitAccountStatus = "cloudkit.account.status"
    case cloudKitRecordsQuery = "cloudkit.records.query"
    case cloudKitRecordSave = "cloudkit.record.save"
    case cloudKitRecordDelete = "cloudkit.record.delete"
    case cloudKitSubscriptionSave = "cloudkit.subscription.save"
    case cloudKitSubscriptionEventsRead = "cloudkit.subscriptionEvents.read"

    case speechPermissionRequest = "speech.permission.request"
    case speechStatus = "speech.status"
    case speechFileTranscribe = "speech.file.transcribe"
    case speechMicrophoneTranscribe = "speech.microphone.transcribe"

    case appIntentsList = "appintents.list"
    case appIntentsRun = "appintents.run"
    case appIntentsDonate = "appintents.donate"
    case appIntentsOpen = "appintents.open"
    case appIntentsHandoffsRead = "appintents.handoffs.read"

    case foundationModelsStatus = "foundationModels.status"
    case foundationModelsGenerate = "foundationModels.generate"
    case foundationModelsExtract = "foundationModels.extract"

    case activityList = "activity.list"
    case activityStart = "activity.start"
    case activityUpdate = "activity.update"
    case activityEnd = "activity.end"
    case activityPushTokenRead = "activity.pushToken.read"

    case mapsGeocode = "maps.geocode"
    case mapsReverseGeocode = "maps.reverseGeocode"
    case mapsSearch = "maps.search"
    case mapsRouteEstimate = "maps.route.estimate"
    case mapsOpen = "maps.open"

    case musicPermissionRequest = "music.permission.request"
    case musicSubscriptionStatus = "music.subscription.status"
    case musicCatalogSearch = "music.catalog.search"
    case musicCatalogDetails = "music.catalog.details"
    case musicLibraryRead = "music.library.read"
    case musicPlaylistWrite = "music.playlist.write"
    case musicPlaybackControl = "music.playback.control"

    case passKitWalletStatus = "passkit.wallet.status"
    case passKitPassesRead = "passkit.passes.read"
    case passKitPassAdd = "passkit.pass.add"
    case passKitPassPresent = "passkit.pass.present"
    case passKitApplePayStatus = "passkit.applePay.status"
    case passKitApplePayPresent = "passkit.applePay.present"

    case storeKitProductsRead = "storekit.products.read"
    case storeKitEntitlementsRead = "storekit.entitlements.read"
    case storeKitPurchase = "storekit.purchase"
    case storeKitRestore = "storekit.restore"
    case storeKitTransactionsRead = "storekit.transactions.read"

    case fsList = "fs.list"
    case fsRead = "fs.read"
    case fsWrite = "fs.write"
    case fsMove = "fs.move"
    case fsCopy = "fs.copy"
    case fsDelete = "fs.delete"
    case fsStat = "fs.stat"
    case fsMkdir = "fs.mkdir"
    case fsExists = "fs.exists"
    case fsAccess = "fs.access"

    case calendarUIPickCalendar = "calendar.ui.pickCalendar"
    case calendarUIPresentEvent = "calendar.ui.presentEvent"
    case contactsUIPresentContact = "contacts.ui.presentContact"
    case contactsUIPresentNewContact = "contacts.ui.presentNewContact"
    case documentsUIPick = "documents.ui.pick"
    case documentsUIExport = "documents.ui.export"
    case documentsUIOpenIn = "documents.ui.openIn"
    case documentsUIScan = "documents.ui.scan"
    case shareUIPresent = "share.ui.present"
    case quickLookUIPreview = "quicklook.ui.preview"
    case cameraUICapture = "camera.ui.capture"
    case cameraUIScanData = "camera.ui.scanData"
    case mailUICompose = "mail.ui.compose"
    case messagesUICompose = "messages.ui.compose"
    case printUIPresent = "print.ui.present"
    case webUIPresent = "web.ui.present"
    case authUIWebAuthenticate = "auth.ui.webAuthenticate"
    case uiAlertPresent = "ui.alert.present"
    case uiPromptPresent = "ui.prompt.present"
    case settingsUIOpen = "settings.ui.open"
}
