import ArgumentParser
import CallableFunction
import CodeMode
import CodeModeEvaluation
import Foundation
import Wavelike

struct LLM: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "llm",
        abstract: "Run Wavelike-backed model evaluation scenarios."
    )

    @Argument(help: "Scenario IDs to run. Omit to use --suite.")
    var scenarioIDs: [String] = []

    @Option(name: .long, help: "Scenario suite to run when no scenario IDs are provided: smoke, core, failures, or all.")
    var suite: LLMEvalSuite = .smoke

    @Option(name: .customLong("repeat"), help: "Number of times to run each selected scenario.")
    var repeatCount = 1

    @Option(name: .long, help: "Model ID. Defaults to WAVELIKE_MODEL_ID from the environment or .env.")
    var model: String?

    @Option(name: .long, help: "Path to a dotenv file containing Wavelike credentials.")
    var envFile = ".env"

    @Option(name: .long, help: "Maximum model/tool turns per scenario.")
    var maxTurns = 6

    @Option(name: .long, help: "Maximum retries for transient model transport errors.")
    var modelRetries = 3

    @Option(name: .long, help: "Base delay in milliseconds for transient model transport retries.")
    var retryDelayMs = 2_000

    @Option(name: .long, help: "Delay in milliseconds before each model request.")
    var requestDelayMs = 0

    @Option(name: .long, help: "Maximum output tokens for each model call.")
    var maxOutputTokens: Int?

    @Option(name: .long, help: "Optional reasoning effort: none, low, medium, high, or xhigh.")
    var reasoningEffort: String?

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Option(name: .long, help: "Write the JSON report to a file path.")
    var output: String?

    @Flag(name: .long, help: "Suppress per-scenario progress output on stderr.")
    var quiet = false

    @Flag(name: .long, help: "Print captured tool code in text output.")
    var showCode = false

    mutating func run() async throws {
        guard maxTurns > 0 else {
            throw ValidationError("--max-turns must be greater than 0.")
        }

        guard repeatCount > 0 else {
            throw ValidationError("--repeat must be greater than 0.")
        }

        guard modelRetries >= 0 else {
            throw ValidationError("--model-retries must be greater than or equal to 0.")
        }

        guard retryDelayMs >= 0 else {
            throw ValidationError("--retry-delay-ms must be greater than or equal to 0.")
        }

        guard requestDelayMs >= 0 else {
            throw ValidationError("--request-delay-ms must be greater than or equal to 0.")
        }

        let scenarios = try selectedLLMScenarios()
        let environment = try WavelikeEvalEnvironment.load(envFile: envFile, modelOverride: model)
        environment.configureWavelike()

        let modelClient = Wavelike.model(for: ModelIdentifier<ModelClient>(ModelClient.self, id: environment.modelID))
        let configuration = try modelConfiguration()
        let runner = WavelikeLLMEvalRunner(
            model: modelClient,
            modelID: environment.modelID,
            configuration: configuration,
            maxTurns: maxTurns,
            modelRetries: modelRetries,
            retryDelayMs: retryDelayMs,
            requestDelayMs: requestDelayMs
        )

        var results: [CodeModeLLMEvalResult] = []
        results.reserveCapacity(scenarios.count * repeatCount)
        let totalRuns = scenarios.count * repeatCount
        var completedRuns = 0
        for runIndex in 1...repeatCount {
            for scenario in scenarios {
                let position = completedRuns + 1
                let runLabel = progressLabel(position: position, total: totalRuns, runIndex: runIndex, scenario: scenario)
                printProgressStart(completed: completedRuns, total: totalRuns, label: runLabel)
                let startedAt = Date()
                let result: CodeModeLLMEvalResult

                do {
                    result = try await runner.run(scenario, runIndex: runIndex)
                } catch {
                    result = failedLLMResult(
                        modelID: environment.modelID,
                        runIndex: runIndex,
                        scenario: scenario,
                        error: error
                    )
                }

                completedRuns += 1
                results.append(result)
                printProgressResult(
                    resultProgressLine(result, label: runLabel, duration: Date().timeIntervalSince(startedAt)),
                    completed: completedRuns,
                    total: totalRuns
                )
            }
        }

        let report = CodeModeLLMEvalReport(
            modelID: environment.modelID,
            suite: scenarioIDs.isEmpty ? suite.rawValue : "custom",
            scenarioIDs: scenarios.map(\.id),
            repeatCount: repeatCount,
            maxTurns: maxTurns,
            summary: CodeModeLLMEvalSummary.make(results: results, scenarios: scenarios),
            results: results
        )

        if let output {
            try writeJSON(report, to: output)
        }

        if json {
            try printJSON(report)
        } else {
            printLLMReport(report)
            if let output {
                print("Saved JSON -> \(output)")
            }
        }

        if results.contains(where: { $0.passed == false }) {
            throw ExitCode.failure
        }
    }

    private func modelConfiguration() throws -> ModelConfiguration {
        let reasoning = try reasoningEffort.map { value in
            guard let effort = ResponseReasoningConfiguration.Effort(rawValue: value) else {
                throw ValidationError("Unsupported reasoning effort '\(value)'.")
            }
            return ResponseReasoningConfiguration(effort: effort)
        }

        return ModelConfiguration(
            maxOutputTokens: maxOutputTokens,
            toolChoice: .auto,
            toolExecutionMode: .manual,
            parallelToolCalls: false,
            reasoning: reasoning
        )
    }

    private func selectedLLMScenarios() throws -> [CodeModeEvalScenario] {
        if scenarioIDs.isEmpty == false {
            return try selectedScenarios(from: scenarioIDs)
        }

        return try selectedScenarios(from: suite.scenarioIDs)
    }

    private func printLLMReport(_ report: CodeModeLLMEvalReport) {
        let results = report.results
        for result in results {
            let status = TerminalUI.status(result.passed ? "PASS" : "FAIL", passed: result.passed)
            let runSuffix = report.repeatCount > 1 ? " run \(result.runIndex)" : ""
            let retrySuffix = result.retryCount == 1 ? "1 retry" : "\(result.retryCount) retries"
            print("\(status) \(result.scenarioID)\(runSuffix) - \(result.title) (\(result.turns) turn\(result.turns == 1 ? "" : "s"), \(retrySuffix))")

            if let assistantMessage = result.assistantMessage, assistantMessage.isEmpty == false {
                print("  assistant: \(assistantMessage)")
            }

            if let exactCapabilityMatched = result.exactCapabilityMatched {
                print("  capabilities: \(exactCapabilityMatched ? "exact/minimal" : "mismatch")")
            }

            if result.failureCategories.isEmpty == false {
                let categories = result.failureCategories.map(\.rawValue).joined(separator: ", ")
                print("  categories: \(categories)")
            }

            for call in result.evalResult.toolCalls {
                switch call.tool {
                case .searchJavaScriptAPI:
                    print("  tool: searchJavaScriptAPI")
                case .executeJavaScript:
                    let capabilities = call.allowedCapabilities.map(\.rawValue).sorted().joined(separator: ", ")
                    print("  tool: executeJavaScript [\(capabilities)]")
                }

                if showCode {
                    for line in call.code.split(separator: "\n", omittingEmptySubsequences: false) {
                        print("    \(line)")
                    }
                }
            }

            for failure in result.failures {
                print("  - \(failure)")
            }
        }

        printSummary(report.summary)
    }

    private func printSummary(_ summary: CodeModeLLMEvalSummary) {
        print(TerminalUI.table(title: "LLM Eval Summary", rows: summaryRows(summary)))

        print("By scenario:")
        for scenario in summary.byScenario {
            var line = "  \(scenario.scenarioID): \(scenario.passedRuns)/\(scenario.totalRuns) passed (\(percent(scenario.passRate))), avg turns \(decimal(scenario.averageTurns)), avg retries \(decimal(scenario.averageRetries))"
            if scenario.exactCapabilityRuns > 0 {
                line += ", capabilities \(scenario.exactCapabilityPassedRuns)/\(scenario.exactCapabilityRuns)"
            }
            print(line)
        }

        if summary.failureCategories.isEmpty == false {
            let categories = summary.failureCategories
                .map { "\($0.category.rawValue)=\($0.count)" }
                .joined(separator: ", ")
            print("Failure categories: \(categories)")
        }
    }

    private func summaryRows(_ summary: CodeModeLLMEvalSummary) -> [(String, String)] {
        var rows: [(String, String)] = [
            ("Total runs", "\(summary.totalRuns)"),
            ("Passed", "\(summary.passedRuns)/\(summary.totalRuns)"),
            ("Pass rate", percent(summary.passRate)),
            ("Avg turns", decimal(summary.averageTurns)),
            ("Avg retries", decimal(summary.averageRetries)),
        ]

        if summary.exactCapabilityRuns > 0 {
            rows.append(("Exact capabilities", "\(summary.exactCapabilityPassedRuns)/\(summary.exactCapabilityRuns)"))
            rows.append(("Capability rate", percent(summary.exactCapabilityPassRate)))
        }

        return rows
    }

    private func percent(_ value: Double) -> String {
        "\(decimal(value * 100))%"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    private func progressLabel(
        position: Int,
        total: Int,
        runIndex: Int,
        scenario: CodeModeEvalScenario
    ) -> String {
        let runText = repeatCount > 1 ? " run \(runIndex)" : ""
        return "[\(position)/\(total)] \(scenario.id)\(runText)"
    }

    private func resultProgressLine(
        _ result: CodeModeLLMEvalResult,
        label: String,
        duration: TimeInterval
    ) -> String {
        let status = TerminalUI.status(result.passed ? "PASS" : "FAIL", passed: result.passed, stream: .stderr)
        let capabilityText: String
        if let exactCapabilityMatched = result.exactCapabilityMatched {
            capabilityText = exactCapabilityMatched ? ", capabilities exact" : ", capabilities mismatch"
        } else {
            capabilityText = ""
        }
        let failureText = result.failures.isEmpty ? "" : ", failures \(result.failures.count)"
        return "\(status) \(label) - \(result.turns) turns, \(result.retryCount) retries\(capabilityText)\(failureText), \(String(format: "%.1f", duration))s"
    }

    private func printProgressStart(completed: Int, total: Int, label: String) {
        guard quiet == false else {
            return
        }

        if TerminalUI.supportsANSI(.stderr) {
            TerminalUI.write(
                "\r\u{001B}[2K\(TerminalUI.progressLine(current: completed, total: total, label: "Running \(label)"))"
            )
        } else {
            TerminalUI.writeLine("START \(label)")
        }
    }

    private func printProgressResult(_ message: String, completed: Int, total: Int) {
        guard quiet == false else {
            return
        }

        if TerminalUI.supportsANSI(.stderr) {
            TerminalUI.write(
                "\r\u{001B}[2K\(TerminalUI.progressLine(current: completed, total: total, label: message))"
            )
            if completed == total {
                TerminalUI.write("\n")
            }
        } else {
            TerminalUI.writeLine(message)
        }
    }

    private func failedLLMResult(
        modelID: String,
        runIndex: Int,
        scenario: CodeModeEvalScenario,
        error: any Error
    ) -> CodeModeLLMEvalResult {
        let failure = "LLM runner failed: \(error.localizedDescription)"
        let evalResult = CodeModeEvalResult(
            scenarioID: scenario.id,
            title: scenario.title,
            passed: false,
            failures: [failure],
            toolCalls: []
        )

        return CodeModeLLMEvalResult(
            modelID: modelID,
            runIndex: runIndex,
            scenarioID: scenario.id,
            title: scenario.title,
            passed: false,
            failures: [failure],
            failureCategories: [.failedRecovery],
            turns: 0,
            retryCount: 0,
            exactCapabilityMatched: nil,
            assistantMessage: nil,
            evalResult: evalResult
        )
    }
}

enum LLMEvalSuite: String, CaseIterable, Codable, ExpressibleByArgument, Sendable {
    case smoke
    case core
    case failures
    case all

    var scenarioIDs: [String] {
        switch self {
        case .smoke:
            return [
                "fs.round-trip",
                "fs.read-only-minimal",
                "execution.console-logs",
                "catalog.reminder-create",
            ]
        case .core:
            return [
                "fs.round-trip",
                "fs.read-only-minimal",
                "fs.multi-file-summary",
                "fs.copy-move-stat",
                "execution.console-logs",
                "catalog.reminder-create",
                "catalog.console-diagnostics",
                "catalog.alias-platform-pruning",
                "weather.argument-validation",
                "fs.bad-helper-suggestion",
            ]
        case .failures:
            return [
                "fs.path-policy-escape",
                "fs.delete-directory-recursive",
                "fs.capability-denied",
                "execution.timeout",
                "catalog.rejects-non-function",
                "contacts.permission-denied",
            ]
        case .all:
            return []
        }
    }
}

struct CodeModeLLMEvalReport: Codable, Sendable {
    var modelID: String
    var suite: String
    var scenarioIDs: [String]
    var repeatCount: Int
    var maxTurns: Int
    var summary: CodeModeLLMEvalSummary
    var results: [CodeModeLLMEvalResult]
    var failureSummaries: [CodeModeLLMFailureSummary]? = nil
}

struct CodeModeLLMEvalResult: Codable, Sendable {
    var modelID: String
    var runIndex: Int
    var scenarioID: String
    var title: String
    var passed: Bool
    var failures: [String]
    var failureCategories: [LLMEvalFailureCategory]
    var turns: Int
    var retryCount: Int
    var exactCapabilityMatched: Bool?
    var assistantMessage: String?
    var toolAttempts: [CodeModeLLMToolAttempt]? = nil
    var evalResult: CodeModeEvalResult
}

struct CodeModeLLMToolAttempt: Codable, Sendable {
    var index: Int
    var toolName: String
    var allowedCapabilities: [String]
    var succeeded: Bool
    var errorCode: String?
    var errorMessage: String?
    var functionName: String?
    var diagnostics: [String]
    var suggestions: [String]
    var repairedByNextAttempt: Bool?
}

struct CodeModeLLMEvalSummary: Codable, Sendable {
    var totalRuns: Int
    var passedRuns: Int
    var failedRuns: Int
    var passRate: Double
    var averageTurns: Double
    var averageRetries: Double
    var exactCapabilityRuns: Int
    var exactCapabilityPassedRuns: Int
    var exactCapabilityPassRate: Double
    var byScenario: [CodeModeLLMScenarioSummary]
    var failureCategories: [CodeModeLLMFailureCategoryCount]

    static func make(results: [CodeModeLLMEvalResult], scenarios: [CodeModeEvalScenario]) -> CodeModeLLMEvalSummary {
        let passedRuns = results.filter(\.passed).count
        let exactCapabilityResults = results.filter { $0.exactCapabilityMatched != nil }
        let exactCapabilityPassedRuns = exactCapabilityResults.filter { $0.exactCapabilityMatched == true }.count
        let groupedResults = Dictionary(grouping: results, by: \.scenarioID)

        return CodeModeLLMEvalSummary(
            totalRuns: results.count,
            passedRuns: passedRuns,
            failedRuns: results.count - passedRuns,
            passRate: ratio(passedRuns, results.count),
            averageTurns: average(results.map(\.turns)),
            averageRetries: average(results.map(\.retryCount)),
            exactCapabilityRuns: exactCapabilityResults.count,
            exactCapabilityPassedRuns: exactCapabilityPassedRuns,
            exactCapabilityPassRate: ratio(exactCapabilityPassedRuns, exactCapabilityResults.count),
            byScenario: scenarios.map { scenario in
                CodeModeLLMScenarioSummary.make(
                    scenario: scenario,
                    results: groupedResults[scenario.id] ?? []
                )
            },
            failureCategories: failureCategoryCounts(results)
        )
    }
}

struct CodeModeLLMScenarioSummary: Codable, Sendable {
    var scenarioID: String
    var title: String
    var totalRuns: Int
    var passedRuns: Int
    var failedRuns: Int
    var passRate: Double
    var averageTurns: Double
    var averageRetries: Double
    var exactCapabilityRuns: Int
    var exactCapabilityPassedRuns: Int
    var exactCapabilityPassRate: Double
    var failureCategories: [CodeModeLLMFailureCategoryCount]

    static func make(scenario: CodeModeEvalScenario, results: [CodeModeLLMEvalResult]) -> CodeModeLLMScenarioSummary {
        let passedRuns = results.filter(\.passed).count
        let exactCapabilityResults = results.filter { $0.exactCapabilityMatched != nil }
        let exactCapabilityPassedRuns = exactCapabilityResults.filter { $0.exactCapabilityMatched == true }.count

        return CodeModeLLMScenarioSummary(
            scenarioID: scenario.id,
            title: scenario.title,
            totalRuns: results.count,
            passedRuns: passedRuns,
            failedRuns: results.count - passedRuns,
            passRate: ratio(passedRuns, results.count),
            averageTurns: average(results.map(\.turns)),
            averageRetries: average(results.map(\.retryCount)),
            exactCapabilityRuns: exactCapabilityResults.count,
            exactCapabilityPassedRuns: exactCapabilityPassedRuns,
            exactCapabilityPassRate: ratio(exactCapabilityPassedRuns, exactCapabilityResults.count),
            failureCategories: failureCategoryCounts(results)
        )
    }
}

struct CodeModeLLMFailureCategoryCount: Codable, Sendable {
    var category: LLMEvalFailureCategory
    var count: Int
}

struct CodeModeLLMFailureSummary: Codable, Sendable {
    var scenarioID: String
    var title: String
    var runIndex: Int
    var failures: [String]
    var failureCategories: [LLMEvalFailureCategory]
}

enum LLMEvalFailureCategory: String, CaseIterable, Codable, Sendable {
    case wrongTool = "wrong_tool"
    case wrongJavaScript = "wrong_js"
    case overbroadCapability = "overbroad_capability"
    case failedRecovery = "failed_recovery"
    case noFinalAnswer = "no_final_answer"
    case other
}

private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
    guard denominator > 0 else {
        return 0
    }
    return Double(numerator) / Double(denominator)
}

private func average(_ values: [Int]) -> Double {
    guard values.isEmpty == false else {
        return 0
    }
    return Double(values.reduce(0, +)) / Double(values.count)
}

private func failureCategoryCounts(_ results: [CodeModeLLMEvalResult]) -> [CodeModeLLMFailureCategoryCount] {
    var counts: [LLMEvalFailureCategory: Int] = [:]
    for result in results {
        for category in Set(result.failureCategories) {
            counts[category, default: 0] += 1
        }
    }

    return LLMEvalFailureCategory.allCases.compactMap { category in
        guard let count = counts[category], count > 0 else {
            return nil
        }
        return CodeModeLLMFailureCategoryCount(category: category, count: count)
    }
}

private func retryCount(toolCalls: [CodeModeEvalToolCall], scenario: CodeModeEvalScenario) -> Int {
    max(0, toolCalls.count - scenario.expectation.toolOrder.count)
}

private func exactCapabilityMatched(toolCalls: [CodeModeEvalToolCall], scenario: CodeModeEvalScenario) -> Bool? {
    guard let expectedCapabilities = scenario.expectation.exactAllowedCapabilities else {
        return nil
    }

    let observedCapabilities = toolCalls.last(where: { $0.tool == .executeJavaScript })?.allowedCapabilities ?? []
    return Set(observedCapabilities) == Set(expectedCapabilities)
}

private func failureCategories(
    failures: [String],
    retryCount: Int,
    passed: Bool
) -> [LLMEvalFailureCategory] {
    guard failures.isEmpty == false else {
        return []
    }

    var categories = Set<LLMEvalFailureCategory>()
    for failure in failures {
        categories.insert(failureCategory(for: failure))
    }

    if passed == false, retryCount > 0 {
        categories.insert(.failedRecovery)
    }

    if categories.isEmpty {
        categories.insert(.other)
    }

    return LLMEvalFailureCategory.allCases.filter { categories.contains($0) }
}

private func failureCategory(for failure: String) -> LLMEvalFailureCategory {
    let lowercased = failure.lowercased()

    if lowercased.contains("did not produce a final assistant message") {
        return .noFinalAnswer
    }

    if lowercased.contains("tool order") ||
        lowercased.contains("unknown tool requested") ||
        lowercased.contains("function call without a name") {
        return .wrongTool
    }

    if lowercased.contains("allowed capabilities") ||
        lowercased.contains("forbidden capabilities") ||
        lowercased.contains("unknown allowedcapabilities") {
        return .overbroadCapability
    }

    if lowercased.contains("failed to decode arguments") ||
        lowercased.contains("failed unexpectedly") ||
        lowercased.contains("unexpected runner failure") {
        return .failedRecovery
    }

    if lowercased.contains("execute code") ||
        lowercased.contains("search result") ||
        lowercased.contains("search diagnostics") ||
        lowercased.contains("execution output") ||
        lowercased.contains("execution logs") ||
        lowercased.contains("execution diagnostics") ||
        lowercased.contains("error code") ||
        lowercased.contains("error functionname") ||
        lowercased.contains("error suggestions") {
        return .wrongJavaScript
    }

    return .other
}

private struct WavelikeEvalEnvironment {
    var modelID: String
    var appID: String
    var apiKey: String
    var environment: WavelikeEnvironment

    static func load(envFile: String, modelOverride: String?) throws -> WavelikeEvalEnvironment {
        let values = dotenvValues(at: envFile).merging(ProcessInfo.processInfo.environment) { _, process in
            process
        }

        let modelID = modelOverride ?? values["WAVELIKE_MODEL_ID"]
        guard let modelID, modelID.isEmpty == false else {
            throw ValidationError("Missing WAVELIKE_MODEL_ID. Set it in the environment, .env, or pass --model.")
        }

        guard let appID = values["WAVELIKE_APP_ID"], appID.isEmpty == false else {
            throw ValidationError("Missing WAVELIKE_APP_ID.")
        }

        guard let apiKey = values["WAVELIKE_API_KEY"], apiKey.isEmpty == false else {
            throw ValidationError("Missing WAVELIKE_API_KEY.")
        }

        let environmentName = values["WAVELIKE_ENV"].flatMap { value in
            value.isEmpty ? nil : value
        } ?? "production"

        return WavelikeEvalEnvironment(
            modelID: modelID,
            appID: appID,
            apiKey: apiKey,
            environment: try environment(named: environmentName)
        )
    }

    func configureWavelike() {
        Wavelike.set(environment: environment)
        Wavelike.set(appId: appID)
        Wavelike.set(auth: .apiKey(apiKey))
    }

    private static func environment(named rawValue: String) throws -> WavelikeEnvironment {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "local":
            return .local
        case "stage", "staging", "dev", "development":
            return .stage
        case "prod", "production":
            return .production
        default:
            throw ValidationError("Unsupported WAVELIKE_ENV '\(rawValue)'. Use local, stage, or production.")
        }
    }

    private static func dotenvValues(at path: String) -> [String: String] {
        guard FileManager.default.fileExists(atPath: path),
              let text = try? String(contentsOfFile: path, encoding: .utf8)
        else {
            return [:]
        }

        var values: [String: String] = [:]
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.isEmpty == false, line.hasPrefix("#") == false else {
                continue
            }
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                continue
            }
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value.trimmingMatchingQuotes()
        }
        return values
    }
}

private final class WavelikeLLMEvalRunner: Sendable {
    private let model: ModelClient
    private let modelID: String
    private let configuration: ModelConfiguration
    private let maxTurns: Int
    private let modelRetries: Int
    private let retryDelayMs: Int
    private let requestDelayMs: Int

    init(
        model: ModelClient,
        modelID: String,
        configuration: ModelConfiguration,
        maxTurns: Int,
        modelRetries: Int,
        retryDelayMs: Int,
        requestDelayMs: Int
    ) {
        self.model = model
        self.modelID = modelID
        self.configuration = configuration
        self.maxTurns = maxTurns
        self.modelRetries = modelRetries
        self.retryDelayMs = retryDelayMs
        self.requestDelayMs = requestDelayMs
    }

    func run(_ scenario: CodeModeEvalScenario, runIndex: Int) async throws -> CodeModeLLMEvalResult {
        let toolState = try CodeModeLLMToolState(scenario: scenario)
        let searchFunction = SearchJavaScriptAPIFunction { parameters in
            await toolState.search(code: parameters.code)
        }
        let executeFunction = ExecuteJavaScriptFunction { parameters in
            await toolState.execute(
                code: parameters.code,
                allowedCapabilities: parameters.allowedCapabilities.values,
                timeoutMs: parameters.timeoutMs
            )
        }

        var input = prompt(for: scenario)
        var turns = 0
        var finalMessage: String?
        var loopFailures: [String] = []

        for turn in 1...maxTurns {
            turns = turn
            if requestDelayMs > 0 {
                try await sleep(milliseconds: requestDelayMs)
            }

            let response = try await retryingModelCall(
                maxRetries: modelRetries,
                baseDelayMs: retryDelayMs
            ) {
                try await model.send(
                    input: input,
                    configuration: configuration,
                    tools: searchFunction,
                    executeFunction
                )
            }

            let toolCalls = response.output.filter { $0.type == .functionCall }
            if toolCalls.isEmpty {
                finalMessage = response.message.content
                break
            }

            for item in toolCalls {
                guard let name = item.name else {
                    loopFailures.append("Model emitted a function call without a name.")
                    continue
                }

                let callID = item.callId ?? item.id
                let arguments = item.arguments ?? "{}"
                input.append(.functionCall(callId: callID, name: name, arguments: arguments, id: item.id))
                let output = await toolState.handleManualToolCall(name: name, argumentsJSON: arguments)
                input.append(
                    .functionCallOutput(
                        callId: callID,
                        output: [.init(type: .outputText, text: output)]
                    )
                )
            }
        }

        if finalMessage == nil {
            loopFailures.append("Model did not produce a final assistant message within \(maxTurns) turns.")
        }

        let snapshot = await toolState.snapshot()
        let gradedToolCalls = gradedToolCalls(snapshot.toolCalls, expectedOrder: scenario.expectation.toolOrder)
        let validationFailures = CodeModeEvalRunner().validateTranscript(
            scenario: scenario,
            toolCalls: gradedToolCalls,
            searchResult: snapshot.searchResult,
            searchDiagnostics: snapshot.searchDiagnostics,
            executionOutput: snapshot.executionOutput,
            executionLogs: snapshot.executionLogs,
            executionDiagnostics: snapshot.executionDiagnostics,
            error: snapshot.error
        )

        let failures = loopFailures + snapshot.failures + validationFailures
        let evalResult = CodeModeEvalResult(
            scenarioID: scenario.id,
            title: scenario.title,
            passed: failures.isEmpty,
            failures: failures,
            toolCalls: snapshot.toolCalls,
            searchResult: snapshot.searchResult,
            searchDiagnostics: snapshot.searchDiagnostics,
            executionOutput: snapshot.executionOutput,
            executionLogs: snapshot.executionLogs,
            executionDiagnostics: snapshot.executionDiagnostics,
            error: snapshot.error
        )
        let observedRetryCount = retryCount(toolCalls: snapshot.toolCalls, scenario: scenario)

        return CodeModeLLMEvalResult(
            modelID: modelID,
            runIndex: runIndex,
            scenarioID: scenario.id,
            title: scenario.title,
            passed: failures.isEmpty,
            failures: failures,
            failureCategories: failureCategories(
                failures: failures,
                retryCount: observedRetryCount,
                passed: failures.isEmpty
            ),
            turns: turns,
            retryCount: observedRetryCount,
            exactCapabilityMatched: exactCapabilityMatched(
                toolCalls: snapshot.toolCalls,
                scenario: scenario
            ),
            assistantMessage: finalMessage,
            toolAttempts: snapshot.toolAttempts,
            evalResult: evalResult
        )
    }

    private func prompt(for scenario: CodeModeEvalScenario) -> [ResponseInputItem] {
        [
            .message(
                role: .developer,
                content: [.init(type: .inputText, text: Self.instructions)]
            ),
            .message(
                role: .user,
                content: [.init(type: .inputText, text: scenario.task)]
            ),
        ]
    }

    private func retryingModelCall<Response>(
        maxRetries: Int,
        baseDelayMs: Int,
        operation: () async throws -> Response
    ) async throws -> Response {
        var attempt = 0
        while true {
            do {
                return try await operation()
            } catch {
                guard attempt < maxRetries, isTransientModelError(error) else {
                    throw error
                }

                let multiplier = 1 << min(attempt, 5)
                try await sleep(milliseconds: baseDelayMs * multiplier)
                attempt += 1
            }
        }
    }

    private func sleep(milliseconds: Int) async throws {
        guard milliseconds > 0 else {
            return
        }
        try await Task.sleep(nanoseconds: UInt64(milliseconds) * 1_000_000)
    }

    private func isTransientModelError(_ error: any Error) -> Bool {
        let text = "\(error.localizedDescription) \(String(describing: error))".lowercased()
        return text.contains("429") ||
            text.contains("too many requests") ||
            text.contains("rate limit") ||
            text.contains("502") ||
            text.contains("503") ||
            text.contains("504") ||
            text.contains("timed out") ||
            text.contains("temporarily")
    }

    private func gradedToolCalls(
        _ toolCalls: [CodeModeEvalToolCall],
        expectedOrder: [CodeModeEvalToolName]
    ) -> [CodeModeEvalToolCall] {
        expectedOrder.compactMap { expectedTool in
            toolCalls.last(where: { $0.tool == expectedTool })
        }
    }

    private static let instructions = """
    You are solving a CodeMode evaluation task.

    You have two tools:

    \(CodeModeAgentToolDescriptions.searchJavaScriptAPI.name):
    \(CodeModeAgentToolDescriptions.searchJavaScriptAPI.description)

    \(CodeModeAgentToolDescriptions.executeJavaScript.name):
    \(CodeModeAgentToolDescriptions.executeJavaScript.description)

    Use searchJavaScriptAPI before executeJavaScript whenever you need helper names, arguments, examples, or capability IDs. Search first for privileged Apple helpers such as filesystem, contacts, weather, reminders, calendar, photos, health, home, location, keychain, notifications, and alarms, even when the helper name looks obvious. Prefer api.byJSName["known.name"] for direct helper lookup; use api.byCapability["capability.id"] for capability IDs; use ?? null when a missing lookup must appear as null in JSON. For filesystem catalog searches, filter by ref.tags.includes("filesystem"). When calling executeJavaScript, pass only the minimal allowedCapabilities needed by the JavaScript you run. Platform permission failures still need the relevant capability in allowedCapabilities; capability allowlisting is separate from user privacy permission. Use sandbox paths exactly as the user gives them, including tmp:, caches:, and documents: prefixes.

    The execution runtime does not support require() or import. Never write const fs = require("fs"); fs is already a global variable. Use the provided globals directly. Node-style filesystem aliases are available as global fs.promises methods with positional arguments, while apple.fs.* helpers use object arguments with named fields.

    The JavaScript return value is what will be graded. executeJavaScript does not automatically return the final expression, so use an explicit top-level return statement for successful outputs. If the user asks for a string, number, boolean, or specific object shape, make the script return exactly that shape rather than returning a larger helper result and summarizing it later. Pay attention to each catalog reference's resultSummary and examples; for example, apple.fs.read returns an object with text/base64 fields, while fs.promises.readFile(path, "utf8") returns text.

    Do not catch CodeMode helper errors inside JavaScript just to return an error object. Let helper errors propagate to executeJavaScript so the structured tool response includes code, functionName, diagnostics, and suggestions. If a tool call fails and you can repair it from the structured error or suggestions, retry with corrected code. Give a final answer only after the last useful tool call.
    """
}

private actor CodeModeLLMToolState {
    private var toolCalls: [CodeModeEvalToolCall] = []
    private var searchResults: [JSONValue] = []
    private var searchResult: JSONValue?
    private var searchDiagnostics: [ToolDiagnostic] = []
    private var executionOutput: JSONValue?
    private var executionLogs: [ExecutionLog] = []
    private var executionDiagnostics: [ToolDiagnostic] = []
    private var error: CodeModeToolError?
    private var failures: [String] = []
    private var toolAttempts: [CodeModeLLMToolAttempt] = []

    private let scenario: CodeModeEvalScenario
    private let runtime: CodeModeLLMRuntime

    init(scenario: CodeModeEvalScenario) throws {
        self.scenario = scenario
        self.runtime = try CodeModeLLMRuntime(scenario: scenario)
    }

    func handleManualToolCall(name: String, argumentsJSON: String) async -> String {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            switch name {
            case CodeModeAgentToolDescriptions.searchJavaScriptAPI.name:
                let parameters = try decoder.decode(SearchJavaScriptAPIFunction.Parameters.self, from: Data(argumentsJSON.utf8))
                return await search(code: parameters.code)

            case CodeModeAgentToolDescriptions.executeJavaScript.name:
                let parameters = try decoder.decode(ExecuteJavaScriptFunction.Parameters.self, from: Data(argumentsJSON.utf8))
                return await execute(
                    code: parameters.code,
                    allowedCapabilities: parameters.allowedCapabilities.values,
                    timeoutMs: parameters.timeoutMs
                )

            default:
                let message = "Unknown tool requested by model: \(name)"
                failures.append(message)
                recordAttempt(
                    toolName: name,
                    succeeded: false,
                    errorCode: "UNKNOWN_TOOL",
                    errorMessage: message
                )
                return encoded(ToolOutput(ok: false, error: message))
            }
        } catch {
            let message = "Failed to decode arguments for \(name): \(error.localizedDescription)"
            failures.append(message)
            recordAttempt(
                toolName: name,
                succeeded: false,
                errorCode: "ARGUMENT_DECODE_FAILED",
                errorMessage: message
            )
            return encoded(ToolOutput(ok: false, error: message))
        }
    }

    func search(code: String) async -> String {
        toolCalls.append(CodeModeEvalToolCall(tool: .searchJavaScriptAPI, code: code))

        do {
            let response = try await runtime.tools.searchJavaScriptAPI(JavaScriptAPISearchRequest(code: code))
            searchResults.append(response.result ?? .null)
            searchResult = combinedSearchResult()
            searchDiagnostics = mergedUnique(searchDiagnostics, response.diagnostics)
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.searchJavaScriptAPI.name,
                succeeded: true,
                diagnostics: response.diagnostics
            )
            return encoded(SearchToolOutput(ok: true, result: response.result, diagnostics: response.diagnostics))
        } catch let toolError as CodeModeToolError {
            error = toolError
            searchDiagnostics = mergedUnique(searchDiagnostics, toolError.diagnostics)
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.searchJavaScriptAPI.name,
                succeeded: false,
                error: toolError
            )
            return encoded(ToolErrorOutput(ok: false, error: toolError))
        } catch {
            let message = error.localizedDescription
            failures.append("searchJavaScriptAPI failed unexpectedly: \(message)")
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.searchJavaScriptAPI.name,
                succeeded: false,
                errorCode: "UNEXPECTED_ERROR",
                errorMessage: message
            )
            return encoded(ToolOutput(ok: false, error: message))
        }
    }

    func execute(code: String, allowedCapabilities rawCapabilities: [String], timeoutMs: Int?) async -> String {
        let unknownCapabilities = rawCapabilities.filter { CapabilityID(rawValue: $0) == nil }
        guard unknownCapabilities.isEmpty else {
            let message = "Unknown allowedCapabilities: \(unknownCapabilities.joined(separator: ", "))"
            failures.append(message)
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.executeJavaScript.name,
                allowedCapabilities: rawCapabilities,
                succeeded: false,
                errorCode: "UNKNOWN_CAPABILITY",
                errorMessage: message
            )
            return encoded(ToolOutput(ok: false, error: message))
        }

        let capabilities = rawCapabilities.compactMap(CapabilityID.init(rawValue:))
        toolCalls.append(
            CodeModeEvalToolCall(
                tool: .executeJavaScript,
                code: code,
                allowedCapabilities: capabilities
            )
        )

        do {
            let call = try await runtime.tools.executeJavaScript(
                JavaScriptExecutionRequest(
                    code: code,
                    allowedCapabilities: capabilities,
                    timeoutMs: timeoutMs ?? scenario.timeoutMs
                )
            )
            let observed = await observe(call)
            executionOutput = observed.output
            executionLogs = observed.logs
            executionDiagnostics = observed.diagnostics
            error = observed.error

            if let toolError = observed.error {
                recordAttempt(
                    toolName: CodeModeAgentToolDescriptions.executeJavaScript.name,
                    allowedCapabilities: rawCapabilities,
                    succeeded: false,
                    error: toolError,
                    diagnostics: observed.diagnostics
                )
                return encoded(ToolErrorOutput(ok: false, error: toolError))
            }

            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.executeJavaScript.name,
                allowedCapabilities: rawCapabilities,
                succeeded: true,
                diagnostics: observed.diagnostics
            )
            return encoded(
                ExecuteToolOutput(
                    ok: true,
                    output: observed.output,
                    logs: observed.logs,
                    diagnostics: observed.diagnostics
                )
            )
        } catch let toolError as CodeModeToolError {
            error = toolError
            executionLogs = toolError.logs
            executionDiagnostics = toolError.diagnostics
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.executeJavaScript.name,
                allowedCapabilities: rawCapabilities,
                succeeded: false,
                error: toolError
            )
            return encoded(ToolErrorOutput(ok: false, error: toolError))
        } catch {
            let message = error.localizedDescription
            failures.append("executeJavaScript failed unexpectedly: \(message)")
            recordAttempt(
                toolName: CodeModeAgentToolDescriptions.executeJavaScript.name,
                allowedCapabilities: rawCapabilities,
                succeeded: false,
                errorCode: "UNEXPECTED_ERROR",
                errorMessage: message
            )
            return encoded(ToolOutput(ok: false, error: message))
        }
    }

    func snapshot() -> CodeModeLLMToolSnapshot {
        CodeModeLLMToolSnapshot(
            toolCalls: toolCalls,
            searchResult: searchResult,
            searchDiagnostics: searchDiagnostics,
            executionOutput: executionOutput,
            executionLogs: executionLogs,
            executionDiagnostics: executionDiagnostics,
            error: error,
            failures: failures,
            toolAttempts: attemptsWithRepairSignals()
        )
    }

    private func recordAttempt(
        toolName: String,
        allowedCapabilities: [String] = [],
        succeeded: Bool,
        error: CodeModeToolError? = nil,
        errorCode: String? = nil,
        errorMessage: String? = nil,
        diagnostics: [ToolDiagnostic] = []
    ) {
        let allDiagnostics = error.map { mergedUnique(diagnostics, $0.diagnostics) } ?? diagnostics
        let allSuggestions = error.map { suggestions(from: $0, diagnostics: allDiagnostics) } ?? suggestions(from: nil, diagnostics: allDiagnostics)
        toolAttempts.append(
            CodeModeLLMToolAttempt(
                index: toolAttempts.count + 1,
                toolName: toolName,
                allowedCapabilities: allowedCapabilities,
                succeeded: succeeded,
                errorCode: error?.code ?? errorCode,
                errorMessage: error?.message ?? errorMessage,
                functionName: error?.functionName,
                diagnostics: diagnosticSummaries(allDiagnostics),
                suggestions: allSuggestions,
                repairedByNextAttempt: nil
            )
        )
    }

    private func attemptsWithRepairSignals() -> [CodeModeLLMToolAttempt] {
        var attempts = toolAttempts
        for index in attempts.indices where attempts[index].succeeded == false {
            let toolName = attempts[index].toolName
            if let nextIndex = attempts.indices.dropFirst(index + 1).first(where: { attempts[$0].toolName == toolName }) {
                attempts[index].repairedByNextAttempt = attempts[nextIndex].succeeded
            } else {
                attempts[index].repairedByNextAttempt = false
            }
        }
        return attempts
    }

    private func diagnosticSummaries(_ diagnostics: [ToolDiagnostic], limit: Int = 3) -> [String] {
        Array(diagnostics.prefix(limit)).map { diagnostic in
            var summary = "[\(diagnostic.severity.rawValue)] \(diagnostic.code): \(diagnostic.message)"
            if let functionName = diagnostic.functionName {
                summary += " (\(functionName))"
            }
            return summary
        }
    }

    private func suggestions(
        from error: CodeModeToolError?,
        diagnostics: [ToolDiagnostic],
        limit: Int = 3
    ) -> [String] {
        var values = error?.suggestions ?? []
        for diagnostic in diagnostics {
            values.append(contentsOf: diagnostic.suggestions)
        }
        var unique: [String] = []
        for value in values where unique.contains(value) == false {
            unique.append(value)
        }
        return Array(unique.prefix(limit))
    }

    private func combinedSearchResult() -> JSONValue? {
        guard searchResults.isEmpty == false else {
            return nil
        }

        if searchResults.count == 1 {
            return searchResults[0]
        }

        return .array(searchResults)
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
        } catch let toolError as CodeModeToolError {
            let events = await eventTask.value
            return (
                nil,
                mergedUnique(toolError.logs, events.logs),
                mergedUnique(toolError.diagnostics, events.diagnostics),
                toolError
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
}

private struct CodeModeLLMToolSnapshot: Sendable {
    var toolCalls: [CodeModeEvalToolCall]
    var searchResult: JSONValue?
    var searchDiagnostics: [ToolDiagnostic]
    var executionOutput: JSONValue?
    var executionLogs: [ExecutionLog]
    var executionDiagnostics: [ToolDiagnostic]
    var error: CodeModeToolError?
    var failures: [String]
    var toolAttempts: [CodeModeLLMToolAttempt]
}

private final class CodeModeLLMRuntime: Sendable {
    let tools: CodeModeAgentTools
    private let sandbox: CodeModeLLMSandbox

    init(scenario: CodeModeEvalScenario) throws {
        let sandbox = try CodeModeLLMSandbox.make()
        self.sandbox = sandbox

        let pathPolicy = DefaultPathPolicy(
            config: PathPolicyConfig(
                tmpRoot: sandbox.tmp,
                cachesRoot: sandbox.caches,
                documentsRoot: sandbox.documents
            )
        )

        for file in scenario.seedFiles {
            let url = try pathPolicy.resolve(path: file.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.text.data(using: .utf8)?.write(to: url)
        }

        self.tools = CodeModeAgentTools(
            config: CodeModeConfiguration(
                pathPolicy: pathPolicy,
                artifactStore: InMemoryArtifactStore(),
                permissionBroker: CodeModeLLMPermissionBroker(configuration: scenario.permissions),
                auditLogger: SyncAuditLogger()
            )
        )
    }

    deinit {
        sandbox.cleanup()
    }
}

private struct CodeModeLLMSandbox {
    var root: URL
    var tmp: URL
    var caches: URL
    var documents: URL

    static func make() throws -> CodeModeLLMSandbox {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("CodeModeLLMEval-\(UUID().uuidString)", isDirectory: true)
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let documents = root.appendingPathComponent("documents", isDirectory: true)

        try fileManager.createDirectory(at: tmp, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)

        return CodeModeLLMSandbox(root: root, tmp: tmp, caches: caches, documents: documents)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct CodeModeLLMPermissionBroker: PermissionBroker {
    var configuration: CodeModeEvalPermissions

    func status(for permission: PermissionKind) -> PermissionStatus {
        configuration.statuses[permission] ?? .unavailable
    }

    func request(for permission: PermissionKind) -> PermissionStatus {
        configuration.requestStatuses[permission] ?? configuration.statuses[permission] ?? .unavailable
    }
}

private struct SearchJavaScriptAPIFunction: CallableFunction {
    struct Parameters: Codable {
        var code: String
    }

    typealias Output = String

    let execute: (Parameters) async throws -> String
    let functionDescription: FunctionDescription

    init(_ execute: @escaping (Parameters) async throws -> String) {
        self.execute = execute
        self.functionDescription = FunctionDescription(
            name: CodeModeAgentToolDescriptions.searchJavaScriptAPI.name,
            description: CodeModeAgentToolDescriptions.searchJavaScriptAPI.description,
            parameters: .object(
                properties: [
                    "code": .string(
                        description: "JavaScript source that evaluates to an async function and returns JSON-serializable catalog output.",
                        enum: nil
                    ),
                ],
                required: ["code"]
            )
        )
    }
}

private struct ExecuteJavaScriptFunction: CallableFunction {
    struct Parameters: Codable {
        var code: String
        var allowedCapabilities: CapabilityList
        var timeoutMs: Int?
    }

    typealias Output = String

    let execute: (Parameters) async throws -> String
    let functionDescription: FunctionDescription

    init(_ execute: @escaping (Parameters) async throws -> String) {
        self.execute = execute
        self.functionDescription = FunctionDescription(
            name: CodeModeAgentToolDescriptions.executeJavaScript.name,
            description: CodeModeAgentToolDescriptions.executeJavaScript.description,
            parameters: .object(
                properties: [
                    "code": .string(
                        description: "JavaScript body to execute. Return the final value to grade.",
                        enum: nil
                    ),
                    "allowedCapabilities": .string(
                        description: "Comma-separated capability IDs required by the JavaScript, for example fs.write,fs.read. Use an empty string when no capabilities are needed.",
                        enum: nil
                    ),
                    "timeoutMs": .integer(
                        description: "Optional execution timeout in milliseconds.",
                        minimum: 1,
                        maximum: 60_000
                    ),
                ],
                required: ["code", "allowedCapabilities"]
            )
        )
    }
}

private struct CapabilityList: Codable {
    var values: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let values = try? container.decode([String].self) {
            self.values = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
            return
        }

        let rawValue = try container.decode(String.self)
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.values = decoded.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
            return
        }

        self.values = trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

private struct ToolOutput: Encodable {
    var ok: Bool
    var error: String
}

private struct SearchToolOutput: Encodable {
    var ok: Bool
    var result: JSONValue?
    var diagnostics: [ToolDiagnostic]
}

private struct ExecuteToolOutput: Encodable {
    var ok: Bool
    var output: JSONValue?
    var logs: [ExecutionLog]
    var diagnostics: [ToolDiagnostic]
}

private struct ToolErrorOutput: Encodable {
    var ok: Bool
    var error: CodeModeToolError
}

private func encoded<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder.codeModeBridge
    guard let data = try? encoder.encode(value),
          let text = String(data: data, encoding: .utf8)
    else {
        return #"{"ok":false,"error":"Failed to encode tool output."}"#
    }
    return text
}

private func mergedUnique<Value: Equatable>(_ primary: [Value], _ secondary: [Value]) -> [Value] {
    var merged = primary
    for value in secondary where merged.contains(value) == false {
        merged.append(value)
    }
    return merged
}

private extension String {
    func trimmingMatchingQuotes() -> String {
        guard count >= 2 else {
            return self
        }

        if (hasPrefix("\"") && hasSuffix("\"")) || (hasPrefix("'") && hasSuffix("'")) {
            return String(dropFirst().dropLast())
        }

        return self
    }
}
