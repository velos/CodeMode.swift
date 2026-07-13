import Foundation
import Testing
@testable import CodeMode

/// One registration's complete advertised surface, in a deterministic
/// encoding. This is everything an LLM or host sees about a capability.
private struct CapabilitySnapshot: Codable, Equatable {
    var id: String
    var jsNames: [String]
    var title: String
    var summary: String
    var tags: [String]
    var example: String
    var requiredPermissions: [String]
    var requiredArguments: [String]
    var optionalArguments: [String]
    var argumentTypes: [String: String]
    var argumentHints: [String: String]
    var allowedStringValues: [String: [String]]
    var resultSummary: String

    init(_ registration: CapabilityRegistration) {
        let descriptor = registration.descriptor
        id = descriptor.id.rawValue
        jsNames = registration.jsNames
        title = descriptor.title
        summary = descriptor.summary
        tags = descriptor.tags
        example = descriptor.example
        requiredPermissions = descriptor.requiredPermissions.map(\.rawValue)
        requiredArguments = descriptor.requiredArguments
        optionalArguments = descriptor.optionalArguments
        argumentTypes = descriptor.argumentTypes.mapValues(\.rawValue)
        argumentHints = descriptor.argumentHints
        allowedStringValues = descriptor.argumentConstraints.allowedStringValues
        resultSummary = descriptor.resultSummary
    }
}

private let goldenFileURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("capability-metadata-golden.json")

private func encodeSnapshots() throws -> Data {
    let snapshots = DefaultCapabilityLoader.loadAllRegistrations()
        .map(CapabilitySnapshot.init)
        .sorted { ($0.id, $0.jsNames.first ?? "") < ($1.id, $1.jsNames.first ?? "") }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(snapshots)
}

/// Golden test over the full advertised capability surface.
///
/// Purpose: registration-idiom migrations (PLAN-registration-macros.md Phase 3)
/// must not change what capabilities advertise unless the change is intended
/// and reviewed. Any drift — a reworded hint, a lost constraint, a type that
/// silently tightened from `any` — fails here.
///
/// To regenerate after an INTENDED change:
///     CODEMODE_REGENERATE_GOLDEN=1 swift test --filter capabilityMetadata
/// then review the diff of capability-metadata-golden.json in the commit —
/// the diff is the review artifact.
@Test func capabilityMetadataMatchesGoldenBaseline() throws {
    let current = try encodeSnapshots()

    if ProcessInfo.processInfo.environment["CODEMODE_REGENERATE_GOLDEN"] == "1" {
        try current.write(to: goldenFileURL)
        return
    }

    let golden = try Data(contentsOf: goldenFileURL)
    if current != golden {
        let decoder = JSONDecoder()
        let currentSnapshots = try decoder.decode([CapabilitySnapshot].self, from: current)
        let goldenSnapshots = try decoder.decode([CapabilitySnapshot].self, from: golden)

        let goldenByID = Dictionary(grouping: goldenSnapshots, by: \.id)
        let currentByID = Dictionary(grouping: currentSnapshots, by: \.id)
        for id in Set(goldenByID.keys).union(currentByID.keys).sorted() {
            if goldenByID[id] == nil {
                Issue.record("Capability \(id) is new (not in golden baseline)")
            } else if currentByID[id] == nil {
                Issue.record("Capability \(id) disappeared from the loaded registrations")
            } else if goldenByID[id] != currentByID[id] {
                Issue.record("Capability \(id) metadata changed vs golden baseline")
            }
        }
        let advice = "Advertised capability metadata drifted from capability-metadata-golden.json. If intended, regenerate with CODEMODE_REGENERATE_GOLDEN=1 and review the JSON diff."
        Issue.record("\(advice)")
    }
}
