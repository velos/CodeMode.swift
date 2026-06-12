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
    let executableScenarios = CodeModeEvalScenarios.all.filter {
        $0.executeCode != nil || ($0.executeSteps?.isEmpty == false)
    }

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

@Test func orderedToolCallGradingDoesNotCollapseRepeatedExecuteCalls() {
    let scenario = CodeModeEvalScenarios.filesystemRepairAfterInvalidArguments
    let calls = [
        CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: scenario.searchCode ?? ""),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: """
            const result = await apple.fs.read({ path: "tmp:repair.txt", encoding: "utf8" });
            return result.text;
            """,
            allowedCapabilities: [.fsRead]
        ),
    ]

    let gradedCalls = CodeModeEvalToolCallGrader.orderedToolCalls(
        calls,
        expectedOrder: scenario.expectation.toolOrder
    )

    let failures = CodeModeEvalRunner().validateTranscript(
        scenario: scenario,
        toolCalls: gradedCalls,
        searchResult: .string("fs.read apple.fs.read path"),
        executionOutput: .string("repair target"),
        error: nil
    )

    #expect(gradedCalls.count == 2)
    #expect(failures.contains(where: { $0.contains("Tool order") }))
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

@Test func expandedNonFilesystemScenariosLockValidationSignals() {
    let runner = CodeModeEvalRunner()
    let scenarios = [
        CodeModeEvalScenarios.keychainRoundTrip,
        CodeModeEvalScenarios.notificationsPermissionRequest,
        CodeModeEvalScenarios.locationPermissionStatus,
        CodeModeEvalScenarios.networkInvalidURL,
        CodeModeEvalScenarios.calendarWritePermissionDenied,
        CodeModeEvalScenarios.homeWriteValidation,
        CodeModeEvalScenarios.mediaMetadataValidation,
    ]

    for scenario in scenarios {
        let calls = scenario.expectation.toolOrder.map { tool in
            CodeModeEvalToolCall(tool: tool, code: "", allowedCapabilities: [])
        }
        let failures = runner.validateTranscript(
            scenario: scenario,
            toolCalls: calls,
            searchResult: .null,
            executionOutput: nil,
            error: nil
        )

        #expect(failures.contains(where: { $0.contains("Search result") }))
        #expect(failures.contains(where: { $0.contains("Allowed capabilities") }))
        if scenario.expectation.expectedOutput != nil {
            #expect(failures.contains(where: { $0.contains("Execution output") }))
        }
        if scenario.expectation.expectedErrorCode != nil {
            #expect(failures.contains(where: { $0.contains("Error code") }))
        }
    }
}

private func failureSummary(_ results: [CodeModeEvalResult]) -> String {
    results
        .filter { $0.passed == false }
        .map { result in
            "\(result.scenarioID): \(result.failures.joined(separator: "; "))"
        }
        .joined(separator: "\n")
}
