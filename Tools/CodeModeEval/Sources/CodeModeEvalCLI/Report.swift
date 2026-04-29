import ArgumentParser
import CodeModeEvaluation
import Foundation

struct Report: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Create a Markdown diagnostics report from a saved LLM eval JSON report."
    )

    @Argument(help: "Input JSON report path.")
    var inputPath: String

    @Option(name: .long, help: "Optional baseline JSON report path to include comparison metrics.")
    var baseline: String?

    @Option(name: .long, help: "Write the Markdown report to a file path. Omit to print Markdown to stdout.")
    var output: String?

    @Option(name: .long, help: "Highlight passing runs with retry counts greater than or equal to this value.")
    var highRetryThreshold = 1

    @Flag(name: .long, help: "Include captured tool JavaScript for highlighted runs.")
    var includeCode = false

    @Flag(name: .long, help: "Include final assistant messages for passing highlighted runs.")
    var includeAssistant = false

    @Flag(name: .long, help: "Include every raw run in the run detail section.")
    var allRuns = false

    mutating func run() throws {
        guard highRetryThreshold >= 0 else {
            throw ValidationError("--high-retry-threshold must be greater than or equal to 0.")
        }

        let report = try readReport(at: inputPath)
        let baselineReport = try baseline.map(readReport(at:))
        let comparison = baselineReport.map { baselineReport in
            CodeModeLLMEvalComparison.make(
                baselinePath: baseline ?? "",
                baseline: baselineReport,
                candidatePath: inputPath,
                candidate: report,
                thresholds: .init(
                    passRateTolerance: 0,
                    capabilityRateTolerance: 0,
                    retryTolerance: 0,
                    turnTolerance: 0
                )
            )
        }

        let markdown = MarkdownReportRenderer(
            inputPath: inputPath,
            report: report,
            comparison: comparison,
            highRetryThreshold: highRetryThreshold,
            includeCode: includeCode,
            includeAssistant: includeAssistant,
            allRuns: allRuns
        ).render()

        if let output {
            try writeText(markdown, to: output)
            print("Saved Markdown -> \(output)")
        } else {
            print(markdown)
        }
    }

    private func readReport(at path: String) throws -> CodeModeLLMEvalReport {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(CodeModeLLMEvalReport.self, from: data)
    }

    private func writeText(_ text: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        if directory.path != "." {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard let data = text.data(using: .utf8) else {
            throw ValidationError("Failed to encode Markdown as UTF-8.")
        }
        try data.write(to: url)
    }
}

private struct MarkdownReportRenderer {
    var inputPath: String
    var report: CodeModeLLMEvalReport
    var comparison: CodeModeLLMEvalComparison?
    var highRetryThreshold: Int
    var includeCode: Bool
    var includeAssistant: Bool
    var allRuns: Bool

    func render() -> String {
        var sections: [String] = []
        sections.append(titleSection())
        sections.append(overallSection())

        if let comparison {
            sections.append(comparisonSection(comparison))
        }

        sections.append(scenarioSection())
        sections.append(failureCategorySection())
        sections.append(runDetailsSection())
        return sections
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n") + "\n"
    }

    private func titleSection() -> String {
        """
        # CodeMode LLM Eval Report

        - Input: `\(inputPath)`
        - Model: `\(report.modelID)`
        - Suite: `\(report.suite)`
        - Scenarios: \(report.scenarioIDs.count)
        - Repeat: \(report.repeatCount)
        - Max turns: \(report.maxTurns)
        - Raw runs: \(report.results.isEmpty ? "not included" : "\(report.results.count)")
        """
    }

    private func overallSection() -> String {
        """
        ## Overall

        \(markdownTable(
            headers: ["Metric", "Value"],
            rows: [
                ["Total runs", "\(report.summary.totalRuns)"],
                ["Passed", "\(report.summary.passedRuns)/\(report.summary.totalRuns)"],
                ["Pass rate", percent(report.summary.passRate)],
                ["Exact capabilities", capabilitySummary(report.summary)],
                ["Avg turns", decimal(report.summary.averageTurns)],
                ["Avg retries", decimal(report.summary.averageRetries)],
            ]
        ))
        """
    }

    private func comparisonSection(_ comparison: CodeModeLLMEvalComparison) -> String {
        var lines: [String] = [
            "## Baseline Comparison",
            "",
            "- Baseline: `\(comparison.baselinePath)`",
            "- Candidate: `\(comparison.candidatePath)`",
            "- Status: \(comparison.passed ? "PASS" : "FAIL")",
            "",
            markdownTable(
                headers: ["Metric", "Baseline", "Candidate", "Delta"],
                rows: comparison.overallMetrics.compactMap { metric in
                    guard metric.applicable else {
                        return nil
                    }

                    return [
                        metric.metric.rawValue,
                        formatMetric(metric.baseline, metric: metric.metric),
                        formatMetric(metric.candidate, metric: metric.metric),
                        signed(metric.delta, metric: metric.metric),
                    ]
                }
            ),
        ]

        if comparison.warnings.isEmpty == false {
            lines.append("")
            lines.append("### Warnings")
            lines.append("")
            lines.append(contentsOf: comparison.warnings.map { "- \($0)" })
        }

        if comparison.regressions.isEmpty == false {
            lines.append("")
            lines.append("### Regressions")
            lines.append("")
            lines.append(
                markdownTable(
                    headers: ["Scope", "Metric", "Baseline", "Candidate", "Message"],
                    rows: comparison.regressions.map { regression in
                        [
                            regression.scope,
                            regression.metric.rawValue,
                            formatMetric(regression.baseline, metric: regression.metric),
                            formatMetric(regression.candidate, metric: regression.metric),
                            regression.message,
                        ]
                    }
                )
            )
        }

        return lines.joined(separator: "\n")
    }

    private func scenarioSection() -> String {
        """
        ## Scenario Summary

        \(markdownTable(
            headers: ["Scenario", "Passed", "Pass Rate", "Capabilities", "Avg Turns", "Avg Retries", "Failures"],
            rows: sortedScenarios().map { scenario in
                [
                    scenario.scenarioID,
                    "\(scenario.passedRuns)/\(scenario.totalRuns)",
                    percent(scenario.passRate),
                    capabilitySummary(scenario),
                    decimal(scenario.averageTurns),
                    decimal(scenario.averageRetries),
                    "\(scenario.failedRuns)",
                ]
            }
        ))
        """
    }

    private func failureCategorySection() -> String {
        guard report.summary.failureCategories.isEmpty == false else {
            return """
            ## Failure Categories

            No failure categories recorded.
            """
        }

        return """
        ## Failure Categories

        \(markdownTable(
            headers: ["Category", "Count"],
            rows: report.summary.failureCategories.map { category in
                [category.category.rawValue, "\(category.count)"]
            }
        ))
        """
    }

    private func runDetailsSection() -> String {
        if report.results.isEmpty {
            return summarizedFailureDetails()
        }

        let highlighted = report.results
            .filter(shouldIncludeRun)
            .sorted(by: runSort)

        guard highlighted.isEmpty == false else {
            return """
            ## Run Details

            No highlighted runs. Use `--all-runs` to include every raw run.
            """
        }

        var lines: [String] = ["## Run Details"]
        for result in highlighted {
            lines.append("")
            lines.append("### \(result.scenarioID) run \(result.runIndex)")
            lines.append("")
            lines.append("- Status: \(result.passed ? "PASS" : "FAIL")")
            lines.append("- Turns: \(result.turns)")
            lines.append("- Retries: \(result.retryCount)")
            if let exactCapabilityMatched = result.exactCapabilityMatched {
                lines.append("- Capabilities: \(exactCapabilityMatched ? "exact/minimal" : "mismatch")")
            }
            if result.failureCategories.isEmpty == false {
                lines.append("- Failure categories: \(result.failureCategories.map(\.rawValue).joined(separator: ", "))")
            }
            if shouldIncludeAssistant(result),
               let assistantMessage = result.assistantMessage,
               assistantMessage.isEmpty == false {
                lines.append("")
                lines.append("Assistant:")
                lines.append("")
                lines.append(blockquote(assistantMessage))
            }
            if result.failures.isEmpty == false {
                lines.append("")
                lines.append("Failures:")
                lines.append("")
                lines.append(contentsOf: result.failures.map { "- \($0)" })
            }

            lines.append("")
            lines.append("Tool calls:")
            lines.append("")
            lines.append(toolCallTable(result))

            if includeCode {
                lines.append("")
                lines.append(codeSnippets(result))
            }
        }

        return lines.joined(separator: "\n")
    }

    private func summarizedFailureDetails() -> String {
        guard let failureSummaries = report.failureSummaries, failureSummaries.isEmpty == false else {
            return """
            ## Run Details

            Raw run details are not included in this report.
            """
        }

        var lines: [String] = ["## Run Details"]
        for failure in failureSummaries {
            lines.append("")
            lines.append("### \(failure.scenarioID) run \(failure.runIndex)")
            lines.append("")
            lines.append("- Title: \(failure.title)")
            if failure.failureCategories.isEmpty == false {
                lines.append("- Failure categories: \(failure.failureCategories.map(\.rawValue).joined(separator: ", "))")
            }
            lines.append("")
            lines.append("Failures:")
            lines.append("")
            lines.append(contentsOf: failure.failures.map { "- \($0)" })
        }

        return lines.joined(separator: "\n")
    }

    private func toolCallTable(_ result: CodeModeLLMEvalResult) -> String {
        markdownTable(
            headers: ["#", "Tool", "allowedCapabilities"],
            rows: result.evalResult.toolCalls.enumerated().map { index, call in
                [
                    "\(index + 1)",
                    toolName(call.tool),
                    call.allowedCapabilities.isEmpty ? "-" : call.allowedCapabilities.map(\.rawValue).sorted().joined(separator: ", "),
                ]
            }
        )
    }

    private func codeSnippets(_ result: CodeModeLLMEvalResult) -> String {
        var lines: [String] = []
        for (index, call) in result.evalResult.toolCalls.enumerated() {
            lines.append("#### \(index + 1). \(toolName(call.tool))")
            lines.append("")
            lines.append(fencedCode(call.code, language: "javascript"))
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldIncludeRun(_ result: CodeModeLLMEvalResult) -> Bool {
        if allRuns {
            return true
        }

        if result.passed == false {
            return true
        }

        if result.retryCount >= highRetryThreshold, highRetryThreshold > 0 {
            return true
        }

        if result.exactCapabilityMatched == false {
            return true
        }

        return false
    }

    private func shouldIncludeAssistant(_ result: CodeModeLLMEvalResult) -> Bool {
        includeAssistant || result.passed == false
    }

    private func runSort(_ lhs: CodeModeLLMEvalResult, _ rhs: CodeModeLLMEvalResult) -> Bool {
        if lhs.passed != rhs.passed {
            return rhs.passed
        }
        if lhs.retryCount != rhs.retryCount {
            return lhs.retryCount > rhs.retryCount
        }
        if lhs.turns != rhs.turns {
            return lhs.turns > rhs.turns
        }
        if lhs.scenarioID != rhs.scenarioID {
            return lhs.scenarioID < rhs.scenarioID
        }
        return lhs.runIndex < rhs.runIndex
    }

    private func sortedScenarios() -> [CodeModeLLMScenarioSummary] {
        report.summary.byScenario.sorted { lhs, rhs in
            if lhs.failedRuns != rhs.failedRuns {
                return lhs.failedRuns > rhs.failedRuns
            }
            if lhs.passRate != rhs.passRate {
                return lhs.passRate < rhs.passRate
            }
            if lhs.exactCapabilityRuns > 0 && rhs.exactCapabilityRuns > 0,
               lhs.exactCapabilityPassRate != rhs.exactCapabilityPassRate {
                return lhs.exactCapabilityPassRate < rhs.exactCapabilityPassRate
            }
            if lhs.averageRetries != rhs.averageRetries {
                return lhs.averageRetries > rhs.averageRetries
            }
            if lhs.averageTurns != rhs.averageTurns {
                return lhs.averageTurns > rhs.averageTurns
            }
            return lhs.scenarioID < rhs.scenarioID
        }
    }

    private func capabilitySummary(_ summary: CodeModeLLMEvalSummary) -> String {
        guard summary.exactCapabilityRuns > 0 else {
            return "n/a"
        }
        return "\(summary.exactCapabilityPassedRuns)/\(summary.exactCapabilityRuns) (\(percent(summary.exactCapabilityPassRate)))"
    }

    private func capabilitySummary(_ summary: CodeModeLLMScenarioSummary) -> String {
        guard summary.exactCapabilityRuns > 0 else {
            return "n/a"
        }
        return "\(summary.exactCapabilityPassedRuns)/\(summary.exactCapabilityRuns) (\(percent(summary.exactCapabilityPassRate)))"
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> String {
        let headerLine = "| " + headers.map(escapeTableCell).joined(separator: " | ") + " |"
        let separator = "| " + headers.map { _ in "---" }.joined(separator: " | ") + " |"
        let body = rows.map { row in
            "| " + row.map(escapeTableCell).joined(separator: " | ") + " |"
        }

        return ([headerLine, separator] + body).joined(separator: "\n")
    }

    private func escapeTableCell(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    private func toolName(_ tool: CodeModeEvalToolName) -> String {
        switch tool {
        case .searchJavaScriptAPI:
            return "searchJavaScriptAPI"
        case .executeJavaScript:
            return "executeJavaScript"
        }
    }

    private func fencedCode(_ code: String, language: String) -> String {
        var fence = "```"
        while code.contains(fence) {
            fence += "`"
        }
        return "\(fence)\(language)\n\(code)\n\(fence)"
    }

    private func blockquote(_ text: String) -> String {
        text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> \($0)" }
            .joined(separator: "\n")
    }

    private func percent(_ value: Double) -> String {
        "\(decimal(value * 100))%"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func formatMetric(_ value: Double, metric: CodeModeLLMEvalMetric) -> String {
        switch metric {
        case .passRate, .exactCapabilityPassRate:
            return percent(value)
        case .averageRetries, .averageTurns:
            return decimal(value)
        }
    }

    private func signed(_ value: Double, metric: CodeModeLLMEvalMetric) -> String {
        let prefix = value >= 0 ? "+" : ""
        switch metric {
        case .passRate, .exactCapabilityPassRate:
            return "\(prefix)\(decimal(value * 100))pp"
        case .averageRetries, .averageTurns:
            return "\(prefix)\(decimal(value))"
        }
    }
}
