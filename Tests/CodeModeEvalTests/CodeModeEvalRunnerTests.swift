import CodeMode
import CodeModeEvaluation
import Foundation
import Testing

@Test func builtInEvalScenariosPass() async throws {
    let results = await CodeModeEvalRunner().runAll()

    #expect(results.count == CodeModeEvalScenarios.all.count)
    if results.allSatisfy(\.passed) == false {
        Issue.record(Comment(rawValue: failureSummary(results)))
    }
    #expect(results.allSatisfy { $0.passed })
}

@Test func builtInEvalScenarioIDsAreUnique() {
    let ids = CodeModeEvalScenarios.all.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func executableScenariosDeclareExactCapabilities() {
    let executableScenarios = CodeModeEvalScenarios.all.filter { $0.executeCode != nil }

    #expect(executableScenarios.isEmpty == false)
    #expect(executableScenarios.allSatisfy { $0.expectation.exactAllowedCapabilities != nil })
}

@Test func transcriptValidatorCatchesOverbroadCapabilities() {
    let scenario = CodeModeEvalScenarios.filesystemReadOnlyMinimal
    let calls = [
        CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: scenario.searchCode ?? ""),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: scenario.executeCode ?? "",
            allowedCapabilities: [.fsRead, .fsWrite]
        ),
    ]

    let failures = CodeModeEvalRunner().validateTranscript(
        scenario: scenario,
        toolCalls: calls,
        searchResult: .string("fs.read fs.promises.readFile"),
        executionOutput: .object([
            "length": .number(9),
            "text": .string("seed data"),
        ]),
        error: nil
    )

    #expect(failures.contains(where: { $0.contains("Allowed capabilities") }))
    #expect(failures.contains(where: { $0.contains("Forbidden capabilities") }))
}

@Test func evalRunnerDoesNotDuplicateStreamedLogs() async {
    let runner = CodeModeEvalRunner()

    let consoleResult = await runner.run(CodeModeEvalScenarios.executionConsoleLogs)
    #expect(consoleResult.passed)
    #expect(consoleResult.executionLogs.map(\.message) == ["starting eval log", "finishing eval log"])

    let failureResult = await runner.run(CodeModeEvalScenarios.filesystemPathPolicyEscape)
    #expect(failureResult.passed)
    let pathPolicyLogCount = failureResult.executionLogs
        .filter { $0.message.contains("Path is outside allowed roots") }
        .count
    #expect(pathPolicyLogCount == 1)
}

private func failureSummary(_ results: [CodeModeEvalResult]) -> String {
    results
        .filter { $0.passed == false }
        .map { result in
            "\(result.scenarioID): \(result.failures.joined(separator: "; "))"
        }
        .joined(separator: "\n")
}
