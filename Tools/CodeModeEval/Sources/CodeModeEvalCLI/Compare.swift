import ArgumentParser
import Foundation

struct Compare: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compare two saved Wavelike LLM eval JSON reports."
    )

    @Argument(help: "Baseline JSON report path.")
    var baselinePath: String

    @Argument(help: "Candidate JSON report path.")
    var candidatePath: String

    @Option(name: .long, help: "Allowed overall and per-scenario pass-rate decrease before failing, as a 0...1 fraction.")
    var passRateTolerance = 0.0

    @Option(name: .long, help: "Allowed exact-capability pass-rate decrease before failing, as a 0...1 fraction.")
    var capabilityRateTolerance = 0.0

    @Option(name: .long, help: "Allowed average retry increase before failing.")
    var retryTolerance = 0.0

    @Option(name: .long, help: "Allowed average turn-count increase before failing.")
    var turnTolerance = 0.0

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    mutating func run() throws {
        let baseline = try readReport(at: baselinePath)
        let candidate = try readReport(at: candidatePath)
        let comparison = CodeModeLLMEvalComparison.make(
            baselinePath: baselinePath,
            baseline: baseline,
            candidatePath: candidatePath,
            candidate: candidate,
            thresholds: .init(
                passRateTolerance: passRateTolerance,
                capabilityRateTolerance: capabilityRateTolerance,
                retryTolerance: retryTolerance,
                turnTolerance: turnTolerance
            )
        )

        if json {
            try printJSON(comparison)
        } else {
            printComparison(comparison)
        }

        if comparison.passed == false {
            throw ExitCode.failure
        }
    }

    private func readReport(at path: String) throws -> CodeModeLLMEvalReport {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodeModeLLMEvalReport.self, from: data)
    }

    private func printComparison(_ comparison: CodeModeLLMEvalComparison) {
        print("\(comparison.passed ? "PASS" : "FAIL") compare \(comparison.baselinePath) -> \(comparison.candidatePath)")
        print("Baseline: \(comparison.baselineModelID) \(comparison.baselineSuite) repeat \(comparison.baselineRepeatCount)")
        print("Candidate: \(comparison.candidateModelID) \(comparison.candidateSuite) repeat \(comparison.candidateRepeatCount)")

        print("Overall:")
        for metric in comparison.overallMetrics {
            guard metric.applicable else {
                continue
            }
            print("  \(metric.metric.rawValue): \(formatMetric(metric.baseline, metric: metric.metric)) -> \(formatMetric(metric.candidate, metric: metric.metric)) (\(signed(metric.delta, metric: metric.metric)))")
        }

        if comparison.scenarioMetrics.isEmpty == false {
            print("By scenario:")
            for scenario in comparison.scenarioMetrics {
                print("  \(scenario.scenarioID):")
                for metric in scenario.metrics {
                    guard metric.applicable else {
                        continue
                    }
                    print("    \(metric.metric.rawValue): \(formatMetric(metric.baseline, metric: metric.metric)) -> \(formatMetric(metric.candidate, metric: metric.metric)) (\(signed(metric.delta, metric: metric.metric)))")
                }
            }
        }

        if comparison.warnings.isEmpty == false {
            print("Warnings:")
            for warning in comparison.warnings {
                print("  - \(warning)")
            }
        }

        if comparison.regressions.isEmpty == false {
            print("Regressions:")
            for regression in comparison.regressions {
                print("  - \(regression.scope) \(regression.metric.rawValue): \(regression.message)")
            }
        }
    }

    private func formatMetric(_ value: Double, metric: CodeModeLLMEvalMetric) -> String {
        switch metric {
        case .passRate, .exactCapabilityPassRate:
            return "\(decimal(value * 100))%"
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

    private func decimal(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

struct CodeModeLLMEvalComparison: Codable, Sendable {
    var passed: Bool
    var baselinePath: String
    var candidatePath: String
    var baselineModelID: String
    var candidateModelID: String
    var baselineSuite: String
    var candidateSuite: String
    var baselineRepeatCount: Int
    var candidateRepeatCount: Int
    var overallMetrics: [CodeModeLLMEvalMetricComparison]
    var scenarioMetrics: [CodeModeLLMScenarioMetricComparison]
    var warnings: [String]
    var regressions: [CodeModeLLMEvalRegression]

    static func make(
        baselinePath: String,
        baseline: CodeModeLLMEvalReport,
        candidatePath: String,
        candidate: CodeModeLLMEvalReport,
        thresholds: CodeModeLLMEvalComparisonThresholds
    ) -> CodeModeLLMEvalComparison {
        var warnings: [String] = []
        var regressions: [CodeModeLLMEvalRegression] = []

        if baseline.suite != candidate.suite {
            warnings.append("Suite changed from \(baseline.suite) to \(candidate.suite).")
        }
        if baseline.modelID != candidate.modelID {
            warnings.append("Model changed from \(baseline.modelID) to \(candidate.modelID).")
        }
        if baseline.repeatCount != candidate.repeatCount {
            warnings.append("Repeat count changed from \(baseline.repeatCount) to \(candidate.repeatCount).")
        }

        let overallMetrics = metricComparisons(
            baseline: baseline.summary,
            candidate: candidate.summary
        )
        regressions.append(
            contentsOf: metricRegressions(
                scope: "overall",
                metrics: overallMetrics,
                thresholds: thresholds,
                compareCapabilities: baseline.summary.exactCapabilityRuns > 0 && candidate.summary.exactCapabilityRuns > 0
            )
        )

        let baselineScenarios = Dictionary(uniqueKeysWithValues: baseline.summary.byScenario.map { ($0.scenarioID, $0) })
        let candidateScenarios = Dictionary(uniqueKeysWithValues: candidate.summary.byScenario.map { ($0.scenarioID, $0) })
        let scenarioIDs = Array(Set(baselineScenarios.keys).union(candidateScenarios.keys)).sorted()
        var scenarioMetrics: [CodeModeLLMScenarioMetricComparison] = []

        for scenarioID in scenarioIDs {
            guard let baselineScenario = baselineScenarios[scenarioID] else {
                warnings.append("Candidate added scenario \(scenarioID).")
                continue
            }
            guard let candidateScenario = candidateScenarios[scenarioID] else {
                regressions.append(
                    CodeModeLLMEvalRegression(
                        scope: "scenario:\(scenarioID)",
                        metric: .passRate,
                        baseline: baselineScenario.passRate,
                        candidate: 0,
                        threshold: thresholds.passRateTolerance,
                        message: "Scenario is missing from candidate report."
                    )
                )
                continue
            }

            let metrics = metricComparisons(
                baseline: baselineScenario,
                candidate: candidateScenario
            )
            scenarioMetrics.append(
                CodeModeLLMScenarioMetricComparison(
                    scenarioID: scenarioID,
                    metrics: metrics
                )
            )
            regressions.append(
                contentsOf: metricRegressions(
                    scope: "scenario:\(scenarioID)",
                    metrics: metrics,
                    thresholds: thresholds,
                    compareCapabilities: baselineScenario.exactCapabilityRuns > 0 && candidateScenario.exactCapabilityRuns > 0
                )
            )
        }

        return CodeModeLLMEvalComparison(
            passed: regressions.isEmpty,
            baselinePath: baselinePath,
            candidatePath: candidatePath,
            baselineModelID: baseline.modelID,
            candidateModelID: candidate.modelID,
            baselineSuite: baseline.suite,
            candidateSuite: candidate.suite,
            baselineRepeatCount: baseline.repeatCount,
            candidateRepeatCount: candidate.repeatCount,
            overallMetrics: overallMetrics,
            scenarioMetrics: scenarioMetrics,
            warnings: warnings,
            regressions: regressions
        )
    }
}

struct CodeModeLLMEvalComparisonThresholds: Codable, Sendable {
    var passRateTolerance: Double
    var capabilityRateTolerance: Double
    var retryTolerance: Double
    var turnTolerance: Double
}

struct CodeModeLLMEvalMetricComparison: Codable, Sendable {
    var metric: CodeModeLLMEvalMetric
    var baseline: Double
    var candidate: Double
    var delta: Double
    var applicable: Bool
}

struct CodeModeLLMScenarioMetricComparison: Codable, Sendable {
    var scenarioID: String
    var metrics: [CodeModeLLMEvalMetricComparison]
}

struct CodeModeLLMEvalRegression: Codable, Sendable {
    var scope: String
    var metric: CodeModeLLMEvalMetric
    var baseline: Double
    var candidate: Double
    var threshold: Double
    var message: String
}

enum CodeModeLLMEvalMetric: String, Codable, Sendable {
    case passRate = "pass_rate"
    case exactCapabilityPassRate = "exact_capability_pass_rate"
    case averageRetries = "average_retries"
    case averageTurns = "average_turns"
}

private func metricComparisons(
    baseline: CodeModeLLMEvalSummary,
    candidate: CodeModeLLMEvalSummary
) -> [CodeModeLLMEvalMetricComparison] {
    [
        metric(.passRate, baseline: baseline.passRate, candidate: candidate.passRate),
        metric(
            .exactCapabilityPassRate,
            baseline: baseline.exactCapabilityPassRate,
            candidate: candidate.exactCapabilityPassRate,
            applicable: baseline.exactCapabilityRuns > 0 || candidate.exactCapabilityRuns > 0
        ),
        metric(.averageRetries, baseline: baseline.averageRetries, candidate: candidate.averageRetries),
        metric(.averageTurns, baseline: baseline.averageTurns, candidate: candidate.averageTurns),
    ]
}

private func metricComparisons(
    baseline: CodeModeLLMScenarioSummary,
    candidate: CodeModeLLMScenarioSummary
) -> [CodeModeLLMEvalMetricComparison] {
    [
        metric(.passRate, baseline: baseline.passRate, candidate: candidate.passRate),
        metric(
            .exactCapabilityPassRate,
            baseline: baseline.exactCapabilityPassRate,
            candidate: candidate.exactCapabilityPassRate,
            applicable: baseline.exactCapabilityRuns > 0 || candidate.exactCapabilityRuns > 0
        ),
        metric(.averageRetries, baseline: baseline.averageRetries, candidate: candidate.averageRetries),
        metric(.averageTurns, baseline: baseline.averageTurns, candidate: candidate.averageTurns),
    ]
}

private func metric(
    _ metric: CodeModeLLMEvalMetric,
    baseline: Double,
    candidate: Double,
    applicable: Bool = true
) -> CodeModeLLMEvalMetricComparison {
    CodeModeLLMEvalMetricComparison(
        metric: metric,
        baseline: baseline,
        candidate: candidate,
        delta: candidate - baseline,
        applicable: applicable
    )
}

private func metricRegressions(
    scope: String,
    metrics: [CodeModeLLMEvalMetricComparison],
    thresholds: CodeModeLLMEvalComparisonThresholds,
    compareCapabilities: Bool
) -> [CodeModeLLMEvalRegression] {
    metrics.compactMap { metric in
        switch metric.metric {
        case .passRate:
            return lowerIsRegression(metric, scope: scope, tolerance: thresholds.passRateTolerance)
        case .exactCapabilityPassRate:
            guard compareCapabilities, metric.applicable else {
                return nil
            }
            return lowerIsRegression(metric, scope: scope, tolerance: thresholds.capabilityRateTolerance)
        case .averageRetries:
            return higherIsRegression(metric, scope: scope, tolerance: thresholds.retryTolerance)
        case .averageTurns:
            return higherIsRegression(metric, scope: scope, tolerance: thresholds.turnTolerance)
        }
    }
}

private func lowerIsRegression(
    _ metric: CodeModeLLMEvalMetricComparison,
    scope: String,
    tolerance: Double
) -> CodeModeLLMEvalRegression? {
    guard metric.candidate < metric.baseline - tolerance else {
        return nil
    }

    return CodeModeLLMEvalRegression(
        scope: scope,
        metric: metric.metric,
        baseline: metric.baseline,
        candidate: metric.candidate,
        threshold: tolerance,
        message: "Candidate decreased by \(formatDelta(metric.delta)) beyond tolerance \(formatDelta(-tolerance))."
    )
}

private func higherIsRegression(
    _ metric: CodeModeLLMEvalMetricComparison,
    scope: String,
    tolerance: Double
) -> CodeModeLLMEvalRegression? {
    guard metric.candidate > metric.baseline + tolerance else {
        return nil
    }

    return CodeModeLLMEvalRegression(
        scope: scope,
        metric: metric.metric,
        baseline: metric.baseline,
        candidate: metric.candidate,
        threshold: tolerance,
        message: "Candidate increased by \(formatDelta(metric.delta)) beyond tolerance +\(formatDelta(tolerance))."
    )
}

private func formatDelta(_ value: Double) -> String {
    String(format: "%.4f", value)
}
