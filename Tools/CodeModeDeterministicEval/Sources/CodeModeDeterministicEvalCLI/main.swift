import ArgumentParser
import CodeModeEvaluation
import Foundation

@main
struct CodeModeDeterministicEvalCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codemode-deterministic-eval",
        abstract: "Run deterministic CodeMode evaluation scenarios.",
        subcommands: [
            List.self,
            Run.self,
        ],
        defaultSubcommand: Run.self
    )
}

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List built-in evaluation scenarios.")

    mutating func run() throws {
        for scenario in CodeModeEvalScenarios.all {
            print("\(scenario.id)\t\(scenario.title)")
        }
    }
}

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Run deterministic built-in evaluation scenarios.")

    @Argument(help: "Scenario IDs to run. Omit to run all scenarios.")
    var scenarioIDs: [String] = []

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    @Flag(name: .long, help: "Print the search and execute code for each scenario.")
    var showCode = false

    mutating func run() async throws {
        let scenarios = try selectedScenarios(from: scenarioIDs)
        let results = await CodeModeEvalRunner().runAll(scenarios)

        if json {
            try printJSON(results)
        } else {
            printTextReport(results: results, scenarios: scenarios)
        }

        if results.contains(where: { $0.passed == false }) {
            throw ExitCode.failure
        }
    }

    private func printTextReport(results: [CodeModeEvalResult], scenarios: [CodeModeEvalScenario]) {
        let scenariosByID = Dictionary(uniqueKeysWithValues: scenarios.map { ($0.id, $0) })

        for result in results {
            let status = result.passed ? "PASS" : "FAIL"
            print("\(status) \(result.scenarioID) - \(result.title)")

            if showCode, let scenario = scenariosByID[result.scenarioID] {
                if let searchCode = scenario.searchCode {
                    printIndented(label: "search", code: searchCode)
                }
                if let executeCode = scenario.executeCode {
                    printIndented(label: "execute", code: executeCode)
                }
                for (index, step) in (scenario.executeSteps ?? []).enumerated() {
                    printIndented(label: "execute step \(index + 1)", code: step.code)
                }
            }

            for failure in result.failures {
                print("  - \(failure)")
            }
        }

        let passed = results.filter(\.passed).count
        print("")
        print("Deterministic Eval Summary")
        print("  Total runs: \(results.count)")
        print("  Passed: \(passed)/\(results.count)")
    }

    private func printIndented(label: String, code: String) {
        print("  \(label):")
        for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
            print("    \(line)")
        }
    }
}

func selectedScenarios(from scenarioIDs: [String]) throws -> [CodeModeEvalScenario] {
    if scenarioIDs.isEmpty {
        return CodeModeEvalScenarios.all
    }

    let scenariosByID = Dictionary(uniqueKeysWithValues: CodeModeEvalScenarios.all.map { ($0.id, $0) })
    let unknown = scenarioIDs.filter { scenariosByID[$0] == nil }
    if unknown.isEmpty == false {
        throw ValidationError("Unknown scenario ID(s): \(unknown.joined(separator: ", "))")
    }

    return scenarioIDs.compactMap { scenariosByID[$0] }
}

func printJSON<T: Encodable>(_ value: T) throws {
    let data = try encodedJSON(value)
    print(String(decoding: data, as: UTF8.self))
}

func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(value)
}
