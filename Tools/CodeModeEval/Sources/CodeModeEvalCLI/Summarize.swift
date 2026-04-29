import ArgumentParser
import Foundation

struct Summarize: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a summary-only JSON report from a saved LLM eval report."
    )

    @Argument(help: "Input JSON report path.")
    var inputPath: String

    @Option(name: .long, help: "Write the summary JSON report to a file path. Omit to print JSON to stdout.")
    var output: String?

    @Flag(name: .long, help: "Include failure strings for failed runs, without raw tool-call transcripts.")
    var includeFailures = false

    mutating func run() throws {
        let report = try readReport(at: inputPath)
        let summary = summarizedReport(report, includeFailures: includeFailures)

        if let output {
            try writeJSON(summary, to: output)
            print("Saved JSON -> \(output)")
        } else {
            try printJSON(summary)
        }
    }

    private func readReport(at path: String) throws -> CodeModeLLMEvalReport {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(CodeModeLLMEvalReport.self, from: data)
    }

    private func summarizedReport(
        _ report: CodeModeLLMEvalReport,
        includeFailures: Bool
    ) -> CodeModeLLMEvalReport {
        CodeModeLLMEvalReport(
            modelID: report.modelID,
            suite: report.suite,
            scenarioIDs: report.scenarioIDs,
            repeatCount: report.repeatCount,
            maxTurns: report.maxTurns,
            summary: report.summary,
            results: [],
            failureSummaries: includeFailures ? failureSummaries(from: report.results) : nil
        )
    }

    private func failureSummaries(from results: [CodeModeLLMEvalResult]) -> [CodeModeLLMFailureSummary] {
        results.compactMap { result in
            guard result.passed == false else {
                return nil
            }

            return CodeModeLLMFailureSummary(
                scenarioID: result.scenarioID,
                title: result.title,
                runIndex: result.runIndex,
                failures: result.failures,
                failureCategories: result.failureCategories
            )
        }
    }
}
