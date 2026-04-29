import ArgumentParser
import CodeModeEvaluation
import Foundation

@main
struct CodeModeEvalCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codemode-eval",
        abstract: "Run CodeMode evaluation scenarios.",
        subcommands: [
            List.self,
            Run.self,
            LLM.self,
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
            }

            for failure in result.failures {
                print("  - \(failure)")
            }
        }

        let passed = results.filter(\.passed).count
        print("Summary: \(passed)/\(results.count) passed")
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
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
}
