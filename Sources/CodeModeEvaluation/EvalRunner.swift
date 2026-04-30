import CodeMode
import Foundation

public final class CodeModeEvalRunner: Sendable {
    public init() {}

    public func runAll(_ scenarios: [CodeModeEvalScenario] = CodeModeEvalScenarios.all) async -> [CodeModeEvalResult] {
        var results: [CodeModeEvalResult] = []
        results.reserveCapacity(scenarios.count)

        for scenario in scenarios {
            results.append(await run(scenario))
        }

        return results
    }

    public func run(_ scenario: CodeModeEvalScenario) async -> CodeModeEvalResult {
        var toolCalls: [CodeModeEvalToolCall] = []
        var searchResult: JSONValue?
        var searchDiagnostics: [ToolDiagnostic] = []
        var executionOutput: JSONValue?
        var executionLogs: [ExecutionLog] = []
        var executionDiagnostics: [ToolDiagnostic] = []
        var observedError: CodeModeToolError?
        var failures: [String] = []

        do {
            let sandbox = try CodeModeEvalSandbox.make()
            defer { sandbox.cleanup() }

            let pathPolicy = DefaultPathPolicy(
                config: PathPolicyConfig(
                    tmpRoot: sandbox.tmp,
                    cachesRoot: sandbox.caches,
                    documentsRoot: sandbox.documents
                )
            )

            try seedFiles(scenario.seedFiles, pathPolicy: pathPolicy)

            let tools = CodeModeAgentTools(
                config: CodeModeConfiguration(
                    pathPolicy: pathPolicy,
                    artifactStore: InMemoryArtifactStore(),
                    permissionBroker: CodeModeEvalPermissionBroker(configuration: scenario.permissions),
                    auditLogger: SyncAuditLogger()
                )
            )

            if let searchCode = scenario.searchCode {
                toolCalls.append(
                    CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: searchCode)
                )
                let response = try await tools.searchJavaScriptAPI(JavaScriptAPISearchRequest(code: searchCode))
                searchResult = response.result
                searchDiagnostics = response.diagnostics
            }

            for executeStep in executeSteps(for: scenario) {
                toolCalls.append(
                    CodeModeEvalToolCall(
                        tool: .executeJavaScript,
                        code: executeStep.code,
                        allowedCapabilities: executeStep.allowedCapabilities
                    )
                )
                let call = try await tools.executeJavaScript(
                    JavaScriptExecutionRequest(
                        code: executeStep.code,
                        allowedCapabilities: executeStep.allowedCapabilities,
                        timeoutMs: executeStep.timeoutMs ?? scenario.timeoutMs
                    )
                )
                let observed = await observe(call)
                executionOutput = observed.output
                executionLogs = observed.logs
                executionDiagnostics = observed.diagnostics
                observedError = observed.error
            }
        } catch let error as CodeModeToolError {
            observedError = error
            executionLogs = error.logs
            executionDiagnostics = error.diagnostics
        } catch {
            failures.append("Unexpected runner failure: \(error.localizedDescription)")
        }

        failures.append(
            contentsOf: validate(
                scenario: scenario,
                toolCalls: toolCalls,
                searchResult: searchResult,
                searchDiagnostics: searchDiagnostics,
                executionOutput: executionOutput,
                executionLogs: executionLogs,
                executionDiagnostics: executionDiagnostics,
                error: observedError
            )
        )

        return CodeModeEvalResult(
            scenarioID: scenario.id,
            title: scenario.title,
            passed: failures.isEmpty,
            failures: failures,
            toolCalls: toolCalls,
            searchResult: searchResult,
            searchDiagnostics: searchDiagnostics,
            executionOutput: executionOutput,
            executionLogs: executionLogs,
            executionDiagnostics: executionDiagnostics,
            error: observedError
        )
    }

    private func executeSteps(for scenario: CodeModeEvalScenario) -> [CodeModeEvalExecuteStep] {
        var steps: [CodeModeEvalExecuteStep] = []
        if let executeCode = scenario.executeCode {
            steps.append(
                CodeModeEvalExecuteStep(
                    code: executeCode,
                    allowedCapabilities: scenario.allowedCapabilities,
                    timeoutMs: scenario.timeoutMs
                )
            )
        }
        steps.append(contentsOf: scenario.executeSteps ?? [])
        return steps
    }

    public func validateTranscript(
        scenario: CodeModeEvalScenario,
        toolCalls: [CodeModeEvalToolCall],
        searchResult: JSONValue?,
        searchDiagnostics: [ToolDiagnostic] = [],
        executionOutput: JSONValue?,
        executionLogs: [ExecutionLog] = [],
        executionDiagnostics: [ToolDiagnostic] = [],
        error: CodeModeToolError?
    ) -> [String] {
        validate(
            scenario: scenario,
            toolCalls: toolCalls,
            searchResult: searchResult,
            searchDiagnostics: searchDiagnostics,
            executionOutput: executionOutput,
            executionLogs: executionLogs,
            executionDiagnostics: executionDiagnostics,
            error: error
        )
    }

    private func seedFiles(_ files: [CodeModeEvalSeedFile], pathPolicy: any PathPolicy) throws {
        for file in files {
            let url = try pathPolicy.resolve(path: file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.text.data(using: .utf8)?.write(to: url)
        }
    }

    private func observe(_ call: JavaScriptExecutionCall) async -> (
        output: JSONValue?,
        logs: [ExecutionLog],
        diagnostics: [ToolDiagnostic],
        error: CodeModeToolError?
    ) {
        let eventTask = Task { () -> (logs: [ExecutionLog], diagnostics: [ToolDiagnostic]) in
            var logs: [ExecutionLog] = []
            var diagnostics: [ToolDiagnostic] = []
            for await event in call.events {
                switch event {
                case .log(let entry):
                    logs.append(entry)
                case .diagnostic(let diagnostic):
                    diagnostics.append(diagnostic)
                case .syntaxError(let error),
                     .functionNotFound(let error),
                     .thrownError(let error),
                     .toolError(let error):
                    logs.append(contentsOf: error.logs)
                    diagnostics.append(contentsOf: error.diagnostics)
                case .finished:
                    break
                }
            }
            return (logs, diagnostics)
        }

        do {
            let result = try await call.result
            let events = await eventTask.value
            return (
                result.output,
                mergedUnique(result.logs, events.logs),
                mergedUnique(result.diagnostics, events.diagnostics),
                nil
            )
        } catch let error as CodeModeToolError {
            let events = await eventTask.value
            return (
                nil,
                mergedUnique(error.logs, events.logs),
                mergedUnique(error.diagnostics, events.diagnostics),
                error
            )
        } catch {
            let events = await eventTask.value
            return (
                nil,
                events.logs,
                events.diagnostics,
                CodeModeToolError(code: "INTERNAL_FAILURE", message: error.localizedDescription)
            )
        }
    }

    private func mergedUnique<Value: Equatable>(_ primary: [Value], _ secondary: [Value]) -> [Value] {
        var merged = primary
        for value in secondary where merged.contains(value) == false {
            merged.append(value)
        }
        return merged
    }

    private func validate(
        scenario: CodeModeEvalScenario,
        toolCalls: [CodeModeEvalToolCall],
        searchResult: JSONValue?,
        searchDiagnostics: [ToolDiagnostic],
        executionOutput: JSONValue?,
        executionLogs: [ExecutionLog],
        executionDiagnostics: [ToolDiagnostic],
        error: CodeModeToolError?
    ) -> [String] {
        var failures: [String] = []
        let expectation = scenario.expectation
        let observedOrder = toolCalls.map(\.tool)

        if observedOrder != expectation.toolOrder {
            failures.append(
                "Tool order was \(observedOrder.map(\.rawValue)); expected \(expectation.toolOrder.map(\.rawValue))"
            )
        }

        if let exactAllowedCapabilities = expectation.exactAllowedCapabilities {
            let executeCapabilities = toolCalls.last(where: { $0.tool == .executeJavaScript })?.allowedCapabilities ?? []
            if Set(executeCapabilities) != Set(exactAllowedCapabilities) {
                failures.append(
                    "Allowed capabilities were \(executeCapabilities.map(\.rawValue).sorted()); expected exactly \(exactAllowedCapabilities.map(\.rawValue).sorted())"
                )
            }
        }

        if expectation.forbiddenCapabilities.isEmpty == false {
            let executeCapabilities = Set(toolCalls.last(where: { $0.tool == .executeJavaScript })?.allowedCapabilities ?? [])
            let forbidden = expectation.forbiddenCapabilities.filter { executeCapabilities.contains($0) }
            if forbidden.isEmpty == false {
                failures.append("Forbidden capabilities were requested: \(forbidden.map(\.rawValue).sorted())")
            }
        }

        let executeCode = toolCalls.last(where: { $0.tool == .executeJavaScript })?.code ?? ""
        for fragment in expectation.requiredExecuteCodeFragments where executeCode.contains(fragment) == false {
            failures.append("Execute code did not contain required fragment: \(fragment)")
        }

        for alternatives in expectation.requiredExecuteCodeAlternativeFragments
            where alternatives.contains(where: { executeCode.contains($0) }) == false
        {
            failures.append("Execute code did not contain any required alternative fragment: \(alternatives.joined(separator: " | "))")
        }

        let searchText = encoded(searchResult)
        for fragment in expectation.requiredSearchResultFragments where searchText.contains(fragment) == false {
            failures.append("Search result did not contain required fragment: \(fragment)")
        }

        let searchDiagnosticText = searchDiagnostics.map(\.message).joined(separator: "\n")
        for fragment in expectation.requiredSearchDiagnosticFragments where searchDiagnosticText.contains(fragment) == false {
            failures.append("Search diagnostics did not contain required fragment: \(fragment)")
        }

        if let expectedOutput = expectation.expectedOutput, executionOutput != expectedOutput {
            failures.append("Execution output was \(encoded(executionOutput)); expected \(encoded(expectedOutput))")
        }

        let outputText = encoded(executionOutput)
        for fragment in expectation.requiredOutputFragments where outputText.contains(fragment) == false {
            failures.append("Execution output did not contain required fragment: \(fragment)")
        }

        let logText = executionLogs.map(\.message).joined(separator: "\n")
        for fragment in expectation.requiredExecutionLogFragments where logText.contains(fragment) == false {
            failures.append("Execution logs did not contain required fragment: \(fragment)")
        }

        let executionDiagnosticText = executionDiagnostics.map(\.message).joined(separator: "\n")
        for fragment in expectation.requiredExecutionDiagnosticFragments where executionDiagnosticText.contains(fragment) == false {
            failures.append("Execution diagnostics did not contain required fragment: \(fragment)")
        }

        if let expectedErrorCode = expectation.expectedErrorCode, error?.code != expectedErrorCode {
            failures.append("Error code was \(error?.code ?? "nil"); expected \(expectedErrorCode)")
        }

        if expectation.expectedErrorCode == nil, let error {
            failures.append("Unexpected error: \(error.code) \(error.message)")
        }

        if let expectedFunctionName = expectation.expectedFunctionName, error?.functionName != expectedFunctionName {
            failures.append("Error functionName was \(error?.functionName ?? "nil"); expected \(expectedFunctionName)")
        }

        let suggestionText = error?.suggestions.joined(separator: "\n") ?? ""
        for fragment in expectation.requiredErrorSuggestionFragments where suggestionText.contains(fragment) == false {
            failures.append("Error suggestions did not contain required fragment: \(fragment)")
        }

        return failures
    }

    private func encoded(_ value: JSONValue?) -> String {
        guard let value else {
            return "nil"
        }
        return encoded(value)
    }

    private func encoded(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder.codeModeBridge.encode(value),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: value)
        }
        return text
    }
}

private struct CodeModeEvalSandbox {
    var root: URL
    var tmp: URL
    var caches: URL
    var documents: URL

    static func make() throws -> CodeModeEvalSandbox {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("CodeModeEval-\(UUID().uuidString)", isDirectory: true)
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let documents = root.appendingPathComponent("documents", isDirectory: true)

        try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)

        return CodeModeEvalSandbox(root: root, tmp: tmp, caches: caches, documents: documents)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct CodeModeEvalPermissionBroker: PermissionBroker {
    var configuration: CodeModeEvalPermissions

    func status(for permission: PermissionKind) -> PermissionStatus {
        configuration.statuses[permission] ?? .unavailable
    }

    func request(for permission: PermissionKind) -> PermissionStatus {
        configuration.requestStatuses[permission] ?? configuration.statuses[permission] ?? .unavailable
    }
}
