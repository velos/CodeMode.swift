import Foundation

public struct CodeModeConfiguration: Sendable {
    public var pathPolicy: any PathPolicy
    public var artifactStore: any ArtifactStore
    public var permissionBroker: any PermissionBroker
    public var auditLogger: any AuditLogger

    public init(
        pathPolicy: any PathPolicy = DefaultPathPolicy(),
        artifactStore: any ArtifactStore = InMemoryArtifactStore(),
        permissionBroker: any PermissionBroker = SystemPermissionBroker(),
        auditLogger: any AuditLogger = SyncAuditLogger()
    ) {
        self.pathPolicy = pathPolicy
        self.artifactStore = artifactStore
        self.permissionBroker = permissionBroker
        self.auditLogger = auditLogger
    }
}

public struct JavaScriptAPISearchRequest: Sendable, Codable, Equatable {
    public var code: String

    public init(code: String) {
        self.code = code
    }
}

public struct JavaScriptAPIReference: Sendable, Codable, Equatable {
    public var capability: CapabilityID
    public var jsNames: [String]
    public var summary: String
    public var tags: [String]
    public var example: String
    public var requiredArguments: [String]
    public var optionalArguments: [String]
    public var argumentTypes: [String: CapabilityArgumentType]
    public var argumentHints: [String: String]
    public var resultSummary: String

    public init(
        capability: CapabilityID,
        jsNames: [String],
        summary: String,
        tags: [String],
        example: String,
        requiredArguments: [String],
        optionalArguments: [String],
        argumentTypes: [String: CapabilityArgumentType],
        argumentHints: [String: String],
        resultSummary: String
    ) {
        self.capability = capability
        self.jsNames = jsNames
        self.summary = summary
        self.tags = tags
        self.example = example
        self.requiredArguments = requiredArguments
        self.optionalArguments = optionalArguments
        self.argumentTypes = argumentTypes
        self.argumentHints = argumentHints
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
    public var code: String
    public var allowedCapabilities: [CapabilityID]
    public var timeoutMs: Int
    public var context: ExecutionContext

    public init(
        code: String,
        allowedCapabilities: [CapabilityID],
        timeoutMs: Int = 10_000,
        context: ExecutionContext = .init()
    ) {
        self.code = code
        self.allowedCapabilities = allowedCapabilities
        self.timeoutMs = timeoutMs
        self.context = context
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
                await waitForResultOutcome()
            } onCancel: {
                self.cancel()
            }

            switch outcome {
            case let .success(result):
                return result
            case let .failure(error as CodeModeToolError):
                throw error
            case let .failure(error as CancellationError):
                _ = error
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

    private func waitForResultOutcome() async -> Result<JavaScriptExecutionResult, Error> {
        await withCheckedContinuation { continuation in
            Task.detached {
                do {
                    continuation.resume(returning: .success(try await self.resultTask.value))
                } catch {
                    continuation.resume(returning: .failure(error))
                }
            }
        }
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

    case healthPermissionRequest = "health.permission.request"
    case healthRead = "health.read"
    case healthWrite = "health.write"

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
