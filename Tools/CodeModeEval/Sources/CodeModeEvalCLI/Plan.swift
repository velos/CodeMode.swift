import ArgumentParser
import CodeModeEvaluation
import Foundation

struct Plan: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Preview the LLM eval scenarios and request budget before running live model calls."
    )

    @Argument(help: "Scenario IDs to run. Omit to use --suite.")
    var scenarioIDs: [String] = []

    @Option(name: .long, help: "Scenario suite to plan when no scenario IDs are provided: smoke, core, failures, catalog, or all.")
    var suite: LLMEvalSuite = .smoke

    @Option(name: .customLong("repeat"), help: "Number of times each selected scenario would run.")
    var repeatCount = 1

    @Option(name: .long, help: "Maximum model/tool turns per scenario.")
    var maxTurns = 6

    @Option(name: .long, help: "Delay in milliseconds before each model request.")
    var requestDelayMs = 0

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    mutating func run() throws {
        guard repeatCount > 0 else {
            throw ValidationError("--repeat must be greater than 0.")
        }

        guard maxTurns > 0 else {
            throw ValidationError("--max-turns must be greater than 0.")
        }

        guard requestDelayMs >= 0 else {
            throw ValidationError("--request-delay-ms must be greater than or equal to 0.")
        }

        let scenarios = try loadScenarios()
        let plan = CodeModeLLMEvalPlan(
            suite: scenarioIDs.isEmpty ? suite.rawValue : "custom",
            scenarioIDs: scenarios.map(\.id),
            repeatCount: repeatCount,
            scenarioCount: scenarios.count,
            totalRuns: scenarios.count * repeatCount,
            maxTurns: maxTurns,
            maxModelRequests: scenarios.count * repeatCount * maxTurns,
            requestDelayMs: requestDelayMs,
            minimumRequestDelaySeconds: seconds(scenarios.count * repeatCount * requestDelayMs),
            maximumRequestDelaySeconds: seconds(scenarios.count * repeatCount * maxTurns * requestDelayMs)
        )

        if json {
            try printJSON(plan)
        } else {
            printPlan(plan, scenarios: scenarios)
        }
    }

    private func loadScenarios() throws -> [CodeModeEvalScenario] {
        if scenarioIDs.isEmpty == false {
            return try selectedScenarios(from: scenarioIDs)
        }

        return try selectedScenarios(from: suite.scenarioIDs)
    }

    private func printPlan(_ plan: CodeModeLLMEvalPlan, scenarios: [CodeModeEvalScenario]) {
        print(
            TerminalUI.table(
                title: "LLM Eval Plan",
                rows: [
                    ("Suite", plan.suite),
                    ("Scenarios", "\(plan.scenarioCount)"),
                    ("Repeat", "\(plan.repeatCount)"),
                    ("Total runs", "\(plan.totalRuns)"),
                    ("Max model requests", "\(plan.maxModelRequests)"),
                ]
            )
        )

        if plan.requestDelayMs > 0 {
            print(
                "\nConfigured request-delay budget: \(decimal(plan.minimumRequestDelaySeconds))s minimum, " +
                    "\(decimal(plan.maximumRequestDelaySeconds))s maximum"
            )
        }

        print("Scenario IDs:")
        for scenario in scenarios {
            print("  \(scenario.id) - \(scenario.title)")
        }
    }

    private func seconds(_ milliseconds: Int) -> Double {
        Double(milliseconds) / 1_000
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}

struct CodeModeLLMEvalPlan: Codable, Sendable {
    var suite: String
    var scenarioIDs: [String]
    var repeatCount: Int
    var scenarioCount: Int
    var totalRuns: Int
    var maxTurns: Int
    var maxModelRequests: Int
    var requestDelayMs: Int
    var minimumRequestDelaySeconds: Double
    var maximumRequestDelaySeconds: Double
}
