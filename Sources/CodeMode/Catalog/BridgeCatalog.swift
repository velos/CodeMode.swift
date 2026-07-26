import Foundation

/// The model-facing view of the registry.
///
/// Tracks the registry rather than snapshotting it once at init. The snapshot
/// used to be frozen in `CodeModeAgentTools.init`, which made
/// `CapabilityRegistry`'s public post-init `register(...)` methods either
/// unreachable in the supported flow or — if reached — a way to desync what
/// search advertises from what execution can actually invoke.
final class BridgeCatalog: @unchecked Sendable {
    private struct SearchCatalogPayload: Sendable, Codable {
        var references: [JavaScriptAPIReference]
        var byCapability: [String: JavaScriptAPIReference]
        var byJSName: [String: JavaScriptAPIReference]
    }

    private struct Snapshot {
        var generation: Int
        var references: [JavaScriptAPIReference]
        var referencesByCapability: [CodeModeCapabilityKey: JavaScriptAPIReference]
        var searchCatalog: JSONValue
        var allJavaScriptNames: [String]
    }

    private let registry: CapabilityRegistry
    private let lock = NSLock()
    private var snapshot: Snapshot

    init(registry: CapabilityRegistry) {
        self.registry = registry
        self.snapshot = Self.makeSnapshot(registry: registry)
    }

    /// Rebuilds if the registry has changed since the last read. Rebuilding is
    /// the whole catalog, but it only happens when a provider is actually
    /// registered — not on every search.
    private func current() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        let generation = registry.generation
        if snapshot.generation != generation {
            snapshot = Self.makeSnapshot(registry: registry)
        }
        return snapshot
    }

    private static func makeSnapshot(registry: CapabilityRegistry) -> Snapshot {
        let generation = registry.generation
        let functions = registry.allRegisteredFunctions().sorted { $0.catalogCapability < $1.catalogCapability }
        let references = functions.map(Self.reference(from:))

        var byJSName: [String: JavaScriptAPIReference] = [:]
        for reference in references {
            for jsName in reference.jsNames {
                byJSName[jsName] = reference
            }
        }

        return Snapshot(
            generation: generation,
            references: references,
            referencesByCapability: Dictionary(references.map { ($0.capabilityKey, $0) }, uniquingKeysWith: { first, _ in first }),
            searchCatalog: Self.jsonValue(
                from: SearchCatalogPayload(
                    references: references,
                    byCapability: Dictionary(references.map { ($0.capability, $0) }, uniquingKeysWith: { first, _ in first }),
                    byJSName: byJSName
                )
            ),
            allJavaScriptNames: Array(Set(references.flatMap(\.jsNames))).sorted()
        )
    }

    func reference(for capability: CapabilityID) -> JavaScriptAPIReference? {
        current().referencesByCapability[capability.codeModeKey]
    }

    func reference(for capabilityKey: CodeModeCapabilityKey) -> JavaScriptAPIReference? {
        current().referencesByCapability[capabilityKey]
    }

    func allReferences() -> [JavaScriptAPIReference] {
        current().references
    }

    func searchCatalogValue() -> JSONValue {
        current().searchCatalog
    }

    /// TypeScript declarations for the whole platform-filtered surface, for a
    /// host to drop into its system prompt.
    func typeDeclarations() -> String {
        TypeScriptDeclarations.surface(for: current().references)
    }

    func closestFunctionNames(to candidate: String, limit: Int = 3) -> [String] {
        let normalizedCandidate = candidate
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCandidate.isEmpty == false else {
            return []
        }

        let distanceThreshold = max(2, min(8, normalizedCandidate.count / 3 + 1))

        let ranked = current().allJavaScriptNames.map { name in
            let normalizedName = name.lowercased()
            let distance = Self.levenshtein(normalizedCandidate, normalizedName)
            let prefixBonus = normalizedName.hasPrefix(normalizedCandidate) || normalizedCandidate.hasPrefix(normalizedName) ? -2 : 0
            let score = distance + prefixBonus
            let hasSubstringMatch = normalizedName.contains(normalizedCandidate) || normalizedCandidate.contains(normalizedName)
            return (name, distance, score, hasSubstringMatch)
        }

        return ranked
            .filter { _, distance, _, hasSubstringMatch in
                hasSubstringMatch || distance <= distanceThreshold
            }
            .sorted {
                if $0.2 == $1.2 {
                    return $0.0 < $1.0
                }
                return $0.2 < $1.2
            }
            .prefix(limit)
            .map(\.0)
    }

    private static func jsonValue<T: Encodable>(from value: T) -> JSONValue {
        do {
            let data = try JSONEncoder.codeModeBridge.encode(value)
            return try JSONDecoder.codeModeBridge.decode(JSONValue.self, from: data)
        } catch {
            return .object([
                "references": .array([]),
                "byCapability": .object([:]),
                "byJSName": .object([:]),
            ])
        }
    }

    private static func reference(from function: RegisteredCodeModeFunction) -> JavaScriptAPIReference {
        let reference = JavaScriptAPIReference(
            capability: function.catalogCapability,
            capabilityKey: function.capabilityKey,
            builtInCapability: function.builtInCapability,
            jsNames: function.jsNames,
            summary: function.summary,
            tags: function.tags,
            example: function.example,
            requiredArguments: function.requiredArguments,
            optionalArguments: function.optionalArguments,
            argumentTypes: function.argumentTypes,
            argumentHints: function.argumentHints,
            argumentConstraints: function.argumentConstraints,
            resultSummary: function.resultSummary
        )
        var withTypes = reference
        withTypes.dts = TypeScriptDeclarations.declaration(for: reference)
        return withTypes
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let lhsChars = Array(lhs)
        let rhsChars = Array(rhs)

        if lhsChars.isEmpty { return rhsChars.count }
        if rhsChars.isEmpty { return lhsChars.count }

        var distances = Array(0...rhsChars.count)

        for (lhsIndex, lhsChar) in lhsChars.enumerated() {
            var previous = distances[0]
            distances[0] = lhsIndex + 1

            for (rhsIndex, rhsChar) in rhsChars.enumerated() {
                let current = distances[rhsIndex + 1]
                if lhsChar == rhsChar {
                    distances[rhsIndex + 1] = previous
                } else {
                    distances[rhsIndex + 1] = min(
                        distances[rhsIndex] + 1,
                        distances[rhsIndex + 1] + 1,
                        previous + 1
                    )
                }
                previous = current
            }
        }

        return distances[rhsChars.count]
    }
}
