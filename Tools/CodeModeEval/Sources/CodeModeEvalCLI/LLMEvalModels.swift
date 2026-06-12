import ArgumentParser
import CodeModeEvaluation
import Foundation

enum LLMEvalSuite: String, CaseIterable, Codable, ExpressibleByArgument, Sendable {
    case smoke
    case core
    case failures
    case catalog
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
                "fs.nested-report-summary",
                "fs.read-api-shapes",
                "fs.repair-invalid-read-arguments",
                "execution.console-logs",
                "catalog.reminder-create",
                "catalog.console-diagnostics",
                "catalog.alias-platform-pruning",
                "weather.argument-validation",
                "keychain.round-trip",
                "notifications.permission-request",
                "location.permission-status",
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
                "network.invalid-url",
                "calendar.write-permission-denied",
                "home.write-validation",
                "media.metadata-validation",
            ]
        case .catalog:
            return [
                "catalog.reminder-create",
                "catalog.fs-read-shape",
                "catalog.console-diagnostics",
                "catalog.rejects-non-function",
                "catalog.alias-platform-pruning",
                "catalog.system-ui-platform-pruning",
                "catalog.system-ui-documents-discovery",
                "catalog.system-ui-interaction-discovery",
                "catalog.system-ui-photo-camera-discovery",
                "catalog.system-ui-ios-only-discovery",
                "calendar.lifecycle-catalog",
                "network.base64-timeout-catalog",
                "notifications.delivered-content-catalog",
                "system-ui.parameter-catalog",
                "cloudkit.big-ticket-catalog",
                "notifications.remote-catalog",
                "speech.big-ticket-catalog",
                "maps.big-ticket-catalog",
                "foundation-appintents-activity.catalog",
                "wallet-music-storekit.safety-catalog",
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
    var allowedCapabilityKeys: [String]
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
