import Foundation

public struct BridgeCatalog: Sendable {
    public var entries: [BridgeAPIDoc]
    private var detailsByCapability: [CapabilityID: CapabilityDetail]

    public init(entries: [BridgeAPIDoc], detailsByCapability: [CapabilityID: CapabilityDetail] = [:]) {
        self.entries = entries
        self.detailsByCapability = detailsByCapability
    }

    public init(registry: CapabilityRegistry) {
        let descriptors = registry.allDescriptors().sorted { $0.id.rawValue < $1.id.rawValue }
        self.entries = descriptors.map {
            BridgeAPIDoc(
                capability: $0.id,
                title: $0.title,
                summary: $0.summary,
                tags: $0.tags,
                example: $0.example
            )
        }
        self.detailsByCapability = Dictionary(uniqueKeysWithValues: descriptors.map {
            (
                $0.id,
                CapabilityDetail(
                    capability: $0.id,
                    title: $0.title,
                    summary: $0.summary,
                    tags: $0.tags,
                    example: $0.example,
                    requiredPermissions: $0.requiredPermissions,
                    requiredArguments: $0.requiredArguments,
                    optionalArguments: $0.optionalArguments,
                    argumentTypes: $0.argumentTypes,
                    argumentHints: $0.argumentHints,
                    resultSummary: $0.resultSummary
                )
            )
        })
    }

    public func search(query: String, limit: Int, tags: [String]? = nil) -> [BridgeAPIDoc] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let requiredTags = Set((tags ?? []).map { $0.lowercased() })

        let scored: [(BridgeAPIDoc, Int)] = entries.compactMap { entry in
            let entryTags = Set(entry.tags.map { $0.lowercased() })
            if requiredTags.isEmpty == false, requiredTags.isSubset(of: entryTags) == false {
                return nil
            }

            if normalizedQuery.isEmpty {
                return (entry, 1)
            }

            var score = 0
            if entry.capability.rawValue.lowercased().contains(normalizedQuery) { score += 6 }
            if entry.title.lowercased().contains(normalizedQuery) { score += 4 }
            if entry.summary.lowercased().contains(normalizedQuery) { score += 3 }
            if entry.example.lowercased().contains(normalizedQuery) { score += 2 }
            if entryTags.contains(where: { $0.contains(normalizedQuery) }) { score += 2 }

            for term in normalizedQuery.split(separator: " ").map(String.init) {
                if entry.summary.lowercased().contains(term) { score += 1 }
                if entry.title.lowercased().contains(term) { score += 1 }
                if entryTags.contains(where: { $0.contains(term) }) { score += 1 }
            }

            return score > 0 ? (entry, score) : nil
        }

        return scored
            .sorted {
                if $0.1 == $1.1 {
                    return $0.0.capability.rawValue < $1.0.capability.rawValue
                }
                return $0.1 > $1.1
            }
            .prefix(max(1, limit))
            .map(\.0)
    }

    public func detail(for capability: CapabilityID) -> CapabilityDetail? {
        detailsByCapability[capability]
    }

    public func entry(for capability: CapabilityID) -> BridgeAPIDoc? {
        entries.first { $0.capability == capability }
    }
}
