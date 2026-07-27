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

// MARK: - Multi-step scenarios

// The runner overwrote executionOutput/Logs/Diagnostics/observedError on every
// step and did not stop on an intermediate error, so validation saw only the last
// step: a scenario could pass while step 1 failed in a way step 2 masked, and
// step 1's logs — the evidence — were gone.

@Test func multiStepScenariosAccumulateLogsAcrossSteps() async throws {
    let scenario = CodeModeEvalScenario(
        id: "multi-step-log-accumulation",
        title: "Logs from every step survive",
        task: "internal test",
        executeSteps: [
            CodeModeEvalExecuteStep(code: "console.log('step-one-ran'); return 1;", allowedCapabilities: []),
            CodeModeEvalExecuteStep(code: "console.log('step-two-ran'); return 2;", allowedCapabilities: []),
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript, .executeJavaScript],
            exactAllowedCapabilities: [],
            requiredExecutionLogFragments: ["step-one-ran", "step-two-ran"],
            expectedOutput: .number(2)
        )
    )

    let result = await CodeModeEvalRunner().run(scenario)
    #expect(result.passed, "\(result.failures)")
    #expect(result.executionLogs.contains { $0.message.contains("step-one-ran") })
    #expect(result.executionLogs.contains { $0.message.contains("step-two-ran") })
    #expect(result.executionOutput == .number(2))
}

@Test func anIntermediateStepFailureStopsTheRunAndIsReported() async throws {
    let scenario = CodeModeEvalScenario(
        id: "multi-step-intermediate-failure",
        title: "A failing first step is not masked by a passing second",
        task: "internal test",
        executeSteps: [
            // Denied: the step declares no capabilities.
            CodeModeEvalExecuteStep(code: "return await apple.fs.read({ path: 'tmp:nope.txt' });", allowedCapabilities: []),
            CodeModeEvalExecuteStep(code: "return 'second step succeeded';", allowedCapabilities: []),
        ],
        expectation: CodeModeEvalExpectation(
            toolOrder: [.executeJavaScript],
            exactAllowedCapabilities: [],
            expectedErrorCode: "CAPABILITY_DENIED"
        )
    )

    let result = await CodeModeEvalRunner().run(scenario)
    #expect(result.error?.code == "CAPABILITY_DENIED")
    // The second step must not have run and must not have supplied the output.
    #expect(result.toolCalls.filter { $0.tool == .executeJavaScript }.count == 1)
    #expect(result.executionOutput != .string("second step succeeded"))
}

// MARK: - Grading the one-script-per-job standard

// The docs now tell agents to do a whole job in one executeJavaScript call. That
// is only a real standard if a transcript that ignores it fails, so this grades
// the shape rather than just asserting the reference solution.

@Test func aTranscriptSplitAcrossExecutionsFailsTheOneScriptScenario() {
    let scenario = CodeModeEvalScenarios.filesystemWholeJobInOneScript

    // The anti-pattern: list in one call, read in another, sum in a third —
    // every intermediate result round-tripped through the model's context.
    let split = [
        CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: scenario.searchCode ?? ""),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: "return await apple.fs.list({ path: 'documents:receipts' });",
            allowedCapabilities: [.fsList]
        ),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: "return await apple.fs.read({ path: 'documents:receipts/a.json' });",
            allowedCapabilities: [.fsRead]
        ),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: "return await apple.fs.read({ path: 'documents:receipts/c.json' });",
            allowedCapabilities: [.fsRead]
        ),
    ]

    let failures = CodeModeEvalRunner().validateTranscript(
        scenario: scenario,
        toolCalls: split,
        searchResult: .string("fs.list fs.read"),
        executionOutput: .object(["total": .number(42), "count": .number(2)]),
        error: nil
    )

    #expect(failures.contains { $0.contains("Tool order") })
}

@Test func theSingleScriptTranscriptPassesTheOneScriptScenario() {
    let scenario = CodeModeEvalScenarios.filesystemWholeJobInOneScript

    let single = [
        CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: scenario.searchCode ?? ""),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: scenario.executeCode ?? "",
            allowedCapabilities: [.fsList, .fsRead]
        ),
    ]

    let failures = CodeModeEvalRunner().validateTranscript(
        scenario: scenario,
        toolCalls: single,
        searchResult: .string("fs.list fs.read"),
        executionOutput: .object(["total": .number(42), "count": .number(2)]),
        error: nil
    )

    #expect(failures.isEmpty, "\(failures)")
}

@Test func anOverBroadCapabilityRequestFailsEvenWithTheRightAnswer() {
    let scenario = CodeModeEvalScenarios.filesystemWholeJobInOneScript

    // Minimization is now stated plainly in the tool description, so grading it
    // is no longer an unstated rule.
    let overBroad = [
        CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: scenario.searchCode ?? ""),
        CodeModeEvalToolCall(
            tool: .executeJavaScript,
            code: scenario.executeCode ?? "",
            allowedCapabilities: [.fsList, .fsRead, .fsWrite]
        ),
    ]

    let failures = CodeModeEvalRunner().validateTranscript(
        scenario: scenario,
        toolCalls: overBroad,
        searchResult: .string("fs.list fs.read"),
        executionOutput: .object(["total": .number(42), "count": .number(2)]),
        error: nil
    )

    #expect(failures.contains { $0.contains("Allowed capabilities") || $0.contains("Forbidden capabilities") })
}
