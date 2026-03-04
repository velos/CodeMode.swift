import Foundation

public enum SearchMode: String, Sendable, Codable {
    case discover
    case describe
}

public struct SearchRequest: Sendable, Codable {
    public var mode: SearchMode = .discover
    public var query: String?
    public var capability: CapabilityID?
    public var limit: Int
    public var tags: [String]?
    public var code: String?

    public init(
        mode: SearchMode = .discover,
        query: String? = nil,
        capability: CapabilityID? = nil,
        limit: Int = 10,
        tags: [String]? = nil,
        code: String? = nil
    ) {
        self.mode = mode
        self.query = query
        self.capability = capability
        self.limit = limit
        self.tags = tags
        self.code = code
    }

    public init(query: String, limit: Int = 10, tags: [String]? = nil) {
        self.init(mode: .discover, query: query, limit: limit, tags: tags)
    }

    public init(describe capability: CapabilityID) {
        self.init(mode: .describe, capability: capability, limit: 1)
    }

    public init(code: String, limit: Int = 10, tags: [String]? = nil) {
        self.init(mode: .discover, query: code, limit: limit, tags: tags, code: code)
    }
}

public struct SearchResponse: Sendable, Codable {
    public var items: [BridgeAPIDoc]
    public var detail: CapabilityDetail?
    public var diagnostics: [ToolDiagnostic]

    public init(items: [BridgeAPIDoc], detail: CapabilityDetail? = nil, diagnostics: [ToolDiagnostic] = []) {
        self.items = items
        self.detail = detail
        self.diagnostics = diagnostics
    }
}

public struct ExecuteRequest: Sendable, Codable {
    public var code: String
    public var allowedCapabilities: [CapabilityID]
    public var timeoutMs: Int
    public var context: ExecutionContext

    public init(code: String, allowedCapabilities: [CapabilityID], timeoutMs: Int = 10_000, context: ExecutionContext = .init()) {
        self.code = code
        self.allowedCapabilities = allowedCapabilities
        self.timeoutMs = timeoutMs
        self.context = context
    }
}

public struct ExecuteResponse: Sendable, Codable {
    public var resultJSON: String?
    public var logs: [ExecutionLog]
    public var diagnostics: [ToolDiagnostic]
    public var permissionEvents: [PermissionEvent]

    public init(resultJSON: String?, logs: [ExecutionLog], diagnostics: [ToolDiagnostic], permissionEvents: [PermissionEvent]) {
        self.resultJSON = resultJSON
        self.logs = logs
        self.diagnostics = diagnostics
        self.permissionEvents = permissionEvents
    }
}

public struct ExecutionContext: Sendable, Codable {
    public var userID: String?
    public var sessionID: String?
    public var metadata: [String: String]

    public init(userID: String? = nil, sessionID: String? = nil, metadata: [String: String] = [:]) {
        self.userID = userID
        self.sessionID = sessionID
        self.metadata = metadata
    }
}

public struct BridgeAPIDoc: Sendable, Codable, Equatable {
    public var capability: CapabilityID
    public var title: String
    public var summary: String
    public var tags: [String]
    public var example: String

    public init(capability: CapabilityID, title: String, summary: String, tags: [String], example: String) {
        self.capability = capability
        self.title = title
        self.summary = summary
        self.tags = tags
        self.example = example
    }
}

public struct CapabilityDetail: Sendable, Codable, Equatable {
    public var capability: CapabilityID
    public var title: String
    public var summary: String
    public var tags: [String]
    public var example: String
    public var requiredPermissions: [PermissionKind]
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var argumentTypes: [String: CapabilityArgumentType]
    public var argumentHints: [String: String]
    public var resultSummary: String

    public init(
        capability: CapabilityID,
        title: String,
        summary: String,
        tags: [String],
        example: String,
        requiredPermissions: [PermissionKind],
        requiredArguments: [String],
        optionalArguments: [String],
        argumentTypes: [String: CapabilityArgumentType],
        argumentHints: [String: String],
        resultSummary: String
    ) {
        self.capability = capability
        self.title = title
        self.summary = summary
        self.tags = tags
        self.example = example
        self.requiredPermissions = requiredPermissions
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.argumentTypes = argumentTypes
        self.argumentHints = argumentHints
        self.resultSummary = resultSummary
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

    public init(severity: Severity, code: String, message: String) {
        self.severity = severity
        self.code = code
        self.message = message
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

    case remindersRead = "reminders.read"
    case remindersWrite = "reminders.write"

    case contactsRead = "contacts.read"
    case contactsSearch = "contacts.search"

    case photosRead = "photos.read"
    case photosExport = "photos.export"

    case visionImageAnalyze = "vision.image.analyze"

    case notificationsPermissionRequest = "notifications.permission.request"
    case notificationsSchedule = "notifications.schedule"
    case notificationsPendingRead = "notifications.pending.read"
    case notificationsPendingDelete = "notifications.pending.delete"

    case alarmPermissionRequest = "alarm.permission.request"
    case alarmRead = "alarm.read"
    case alarmSchedule = "alarm.schedule"
    case alarmCancel = "alarm.cancel"

    case homeRead = "home.read"
    case homeWrite = "home.write"

    case mediaMetadataRead = "media.metadata.read"
    case mediaFrameExtract = "media.frame.extract"
    case mediaTranscode = "media.transcode"

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
}
