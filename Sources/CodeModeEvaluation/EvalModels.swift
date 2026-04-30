import CodeMode
import Foundation

public enum CodeModeEvalToolName: String, Codable, Sendable, Equatable {
    case searchJavaScriptAPI
    case executeJavaScript
}

public struct CodeModeEvalToolCall: Codable, Sendable, Equatable {
    public var tool: CodeModeEvalToolName
    public var code: String
    public var allowedCapabilities: [CapabilityID]

    public init(tool: CodeModeEvalToolName, code: String, allowedCapabilities: [CapabilityID] = []) {
        self.tool = tool
        self.code = code
        self.allowedCapabilities = allowedCapabilities
    }
}

public struct CodeModeEvalSeedFile: Codable, Sendable, Equatable {
    public var path: String
    public var text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

public struct CodeModeEvalExecuteStep: Codable, Sendable, Equatable {
    public var code: String
    public var allowedCapabilities: [CapabilityID]
    public var timeoutMs: Int?

    public init(
        code: String,
        allowedCapabilities: [CapabilityID] = [],
        timeoutMs: Int? = nil
    ) {
        self.code = code
        self.allowedCapabilities = allowedCapabilities
        self.timeoutMs = timeoutMs
    }
}

public struct CodeModeEvalPermissions: Codable, Sendable, Equatable {
    public var statuses: [PermissionKind: PermissionStatus]
    public var requestStatuses: [PermissionKind: PermissionStatus]

    public init(
        statuses: [PermissionKind: PermissionStatus] = [:],
        requestStatuses: [PermissionKind: PermissionStatus] = [:]
    ) {
        self.statuses = statuses
        self.requestStatuses = requestStatuses
    }
}

public struct CodeModeEvalExpectation: Codable, Sendable, Equatable {
    public var toolOrder: [CodeModeEvalToolName]
    public var exactAllowedCapabilities: [CapabilityID]?
    public var forbiddenCapabilities: [CapabilityID]
    public var requiredSearchResultFragments: [String]
    public var requiredOutputFragments: [String]
    public var requiredErrorSuggestionFragments: [String]
    public var requiredExecuteCodeFragments: [String]
    public var requiredExecuteCodeAlternativeFragments: [[String]]
    public var requiredSearchDiagnosticFragments: [String]
    public var requiredExecutionLogFragments: [String]
    public var requiredExecutionDiagnosticFragments: [String]
    public var expectedOutput: JSONValue?
    public var expectedErrorCode: String?
    public var expectedFunctionName: String?

    public init(
        toolOrder: [CodeModeEvalToolName],
        exactAllowedCapabilities: [CapabilityID]? = nil,
        forbiddenCapabilities: [CapabilityID] = [],
        requiredSearchResultFragments: [String] = [],
        requiredOutputFragments: [String] = [],
        requiredErrorSuggestionFragments: [String] = [],
        requiredExecuteCodeFragments: [String] = [],
        requiredExecuteCodeAlternativeFragments: [[String]] = [],
        requiredSearchDiagnosticFragments: [String] = [],
        requiredExecutionLogFragments: [String] = [],
        requiredExecutionDiagnosticFragments: [String] = [],
        expectedOutput: JSONValue? = nil,
        expectedErrorCode: String? = nil,
        expectedFunctionName: String? = nil
    ) {
        self.toolOrder = toolOrder
        self.exactAllowedCapabilities = exactAllowedCapabilities
        self.forbiddenCapabilities = forbiddenCapabilities
        self.requiredSearchResultFragments = requiredSearchResultFragments
        self.requiredOutputFragments = requiredOutputFragments
        self.requiredErrorSuggestionFragments = requiredErrorSuggestionFragments
        self.requiredExecuteCodeFragments = requiredExecuteCodeFragments
        self.requiredExecuteCodeAlternativeFragments = requiredExecuteCodeAlternativeFragments
        self.requiredSearchDiagnosticFragments = requiredSearchDiagnosticFragments
        self.requiredExecutionLogFragments = requiredExecutionLogFragments
        self.requiredExecutionDiagnosticFragments = requiredExecutionDiagnosticFragments
        self.expectedOutput = expectedOutput
        self.expectedErrorCode = expectedErrorCode
        self.expectedFunctionName = expectedFunctionName
    }
}

public struct CodeModeEvalScenario: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var task: String
    public var searchCode: String?
    public var executeCode: String?
    public var executeSteps: [CodeModeEvalExecuteStep]?
    public var allowedCapabilities: [CapabilityID]
    public var timeoutMs: Int
    public var seedFiles: [CodeModeEvalSeedFile]
    public var permissions: CodeModeEvalPermissions
    public var catalogPlatform: HostPlatform?
    public var expectation: CodeModeEvalExpectation

    public init(
        id: String,
        title: String,
        task: String,
        catalogPlatform: HostPlatform? = nil,
        searchCode: String? = nil,
        executeCode: String? = nil,
        executeSteps: [CodeModeEvalExecuteStep] = [],
        allowedCapabilities: [CapabilityID] = [],
        timeoutMs: Int = 2_000,
        seedFiles: [CodeModeEvalSeedFile] = [],
        permissions: CodeModeEvalPermissions = .init(),
        expectation: CodeModeEvalExpectation
    ) {
        self.id = id
        self.title = title
        self.task = task
        self.searchCode = searchCode
        self.executeCode = executeCode
        self.executeSteps = executeSteps
        self.allowedCapabilities = allowedCapabilities
        self.timeoutMs = timeoutMs
        self.seedFiles = seedFiles
        self.permissions = permissions
        self.catalogPlatform = catalogPlatform
        self.expectation = expectation
    }
}

public struct CodeModeEvalResult: Codable, Sendable, Equatable {
    public var scenarioID: String
    public var title: String
    public var passed: Bool
    public var failures: [String]
    public var toolCalls: [CodeModeEvalToolCall]
    public var searchResult: JSONValue?
    public var searchDiagnostics: [ToolDiagnostic]
    public var executionOutput: JSONValue?
    public var executionLogs: [ExecutionLog]
    public var executionDiagnostics: [ToolDiagnostic]
    public var error: CodeModeToolError?

    public init(
        scenarioID: String,
        title: String,
        passed: Bool,
        failures: [String],
        toolCalls: [CodeModeEvalToolCall],
        searchResult: JSONValue? = nil,
        searchDiagnostics: [ToolDiagnostic] = [],
        executionOutput: JSONValue? = nil,
        executionLogs: [ExecutionLog] = [],
        executionDiagnostics: [ToolDiagnostic] = [],
        error: CodeModeToolError? = nil
    ) {
        self.scenarioID = scenarioID
        self.title = title
        self.passed = passed
        self.failures = failures
        self.toolCalls = toolCalls
        self.searchResult = searchResult
        self.searchDiagnostics = searchDiagnostics
        self.executionOutput = executionOutput
        self.executionLogs = executionLogs
        self.executionDiagnostics = executionDiagnostics
        self.error = error
    }
}
