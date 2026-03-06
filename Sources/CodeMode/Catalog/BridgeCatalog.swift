import Foundation

struct BridgeCatalog: Sendable {
    private struct SearchEntry: Sendable {
        var reference: JavaScriptAPIReference
        var title: String
    }

    private let entries: [SearchEntry]
    private let referencesByCapability: [CapabilityID: JavaScriptAPIReference]
    private let allJavaScriptNames: [String]

    init(registry: CapabilityRegistry) {
        let descriptors = registry.allDescriptors().sorted { $0.id.rawValue < $1.id.rawValue }
        self.entries = descriptors.map { descriptor in
            SearchEntry(reference: Self.reference(from: descriptor), title: descriptor.title)
        }
        self.referencesByCapability = Dictionary(uniqueKeysWithValues: entries.map { ($0.reference.capability, $0.reference) })
        self.allJavaScriptNames = Array(
            Set(entries.flatMap(\.reference.jsNames))
        ).sorted()
    }

    func reference(for capability: CapabilityID) -> JavaScriptAPIReference? {
        referencesByCapability[capability]
    }

    func allReferences() -> [JavaScriptAPIReference] {
        entries.map(\.reference)
    }

    func search(query: String, limit: Int, tags: [String]) -> [JavaScriptAPIReference] {
        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let queryTerms = normalizedQuery.split(whereSeparator: \.isWhitespace).map(String.init)
        let requiredTags = Set(tags.map { $0.lowercased() })

        let scored: [(JavaScriptAPIReference, Int)] = entries.compactMap { entry in
            let reference = entry.reference
            let entryTags = Set(reference.tags.map { $0.lowercased() })

            if requiredTags.isEmpty == false, requiredTags.isSubset(of: entryTags) == false {
                return nil
            }

            var score = 0
            let jsNames = reference.jsNames.map { $0.lowercased() }
            let capability = reference.capability.rawValue.lowercased()
            let title = entry.title.lowercased()
            let summary = reference.summary.lowercased()
            let example = reference.example.lowercased()

            if jsNames.contains(normalizedQuery) { score += 1_000 }
            if capability == normalizedQuery { score += 950 }
            if jsNames.contains(where: { $0.hasPrefix(normalizedQuery) }) { score += 700 }
            if jsNames.contains(where: { $0.contains(normalizedQuery) }) { score += 550 }
            if capability.contains(normalizedQuery) { score += 450 }
            if title.contains(normalizedQuery) { score += 325 }
            if entryTags.contains(normalizedQuery) { score += 275 }
            if summary.contains(normalizedQuery) { score += 220 }
            if example.contains(normalizedQuery) { score += 180 }

            for term in queryTerms {
                if jsNames.contains(where: { $0 == term }) { score += 80 }
                if jsNames.contains(where: { $0.hasPrefix(term) }) { score += 65 }
                if jsNames.contains(where: { $0.contains(term) }) { score += 50 }
                if capability.contains(term) { score += 30 }
                if title.contains(term) { score += 22 }
                if entryTags.contains(where: { $0.contains(term) }) { score += 18 }
                if summary.contains(term) { score += 16 }
                if example.contains(term) { score += 12 }
            }

            return score > 0 ? (reference, score) : nil
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

    func closestFunctionNames(to candidate: String, limit: Int = 3) -> [String] {
        let normalizedCandidate = candidate
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedCandidate.isEmpty == false else {
            return []
        }

        let distanceThreshold = max(2, min(8, normalizedCandidate.count / 3 + 1))

        let ranked = allJavaScriptNames.map { name in
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

    private static func reference(from descriptor: CapabilityDescriptor) -> JavaScriptAPIReference {
        JavaScriptAPIReference(
            capability: descriptor.id,
            jsNames: JavaScriptBindings.names(for: descriptor.id),
            summary: descriptor.summary,
            tags: descriptor.tags,
            example: descriptor.example,
            requiredArguments: descriptor.requiredArguments,
            optionalArguments: descriptor.optionalArguments,
            argumentTypes: descriptor.argumentTypes,
            argumentHints: descriptor.argumentHints,
            resultSummary: descriptor.resultSummary
        )
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

private enum JavaScriptBindings {
    static func names(for capability: CapabilityID) -> [String] {
        bindings[capability] ?? []
    }

    private static let bindings: [CapabilityID: [String]] = [
        .networkFetch: ["fetch"],
        .keychainRead: ["ios.keychain.get"],
        .keychainWrite: ["ios.keychain.set"],
        .keychainDelete: ["ios.keychain.delete"],
        .locationRead: ["ios.location.getPermissionStatus", "ios.location.getCurrentPosition"],
        .locationPermissionRequest: ["ios.location.requestPermission"],
        .weatherRead: ["ios.weather.getCurrentWeather"],
        .calendarRead: ["ios.calendar.listEvents"],
        .calendarWrite: ["ios.calendar.createEvent"],
        .remindersRead: ["ios.reminders.listReminders"],
        .remindersWrite: ["ios.reminders.createReminder"],
        .contactsRead: ["ios.contacts.list"],
        .contactsSearch: ["ios.contacts.search"],
        .photosRead: ["ios.photos.list"],
        .photosExport: ["ios.photos.export"],
        .visionImageAnalyze: ["ios.vision.analyzeImage"],
        .notificationsPermissionRequest: ["ios.notifications.requestPermission"],
        .notificationsSchedule: ["ios.notifications.schedule"],
        .notificationsPendingRead: ["ios.notifications.listPending"],
        .notificationsPendingDelete: ["ios.notifications.cancelPending"],
        .alarmPermissionRequest: ["ios.alarm.requestPermission"],
        .alarmRead: ["ios.alarm.list"],
        .alarmSchedule: ["ios.alarm.schedule"],
        .alarmCancel: ["ios.alarm.cancel"],
        .healthPermissionRequest: ["ios.health.requestPermission"],
        .healthRead: ["ios.health.read"],
        .healthWrite: ["ios.health.write"],
        .homeRead: ["ios.home.list"],
        .homeWrite: ["ios.home.writeCharacteristic"],
        .mediaMetadataRead: ["ios.media.metadata"],
        .mediaFrameExtract: ["ios.media.extractFrame"],
        .mediaTranscode: ["ios.media.transcode"],
        .fsList: ["ios.fs.list", "fs.promises.readdir"],
        .fsRead: ["ios.fs.read", "fs.promises.readFile"],
        .fsWrite: ["ios.fs.write", "fs.promises.writeFile"],
        .fsMove: ["ios.fs.move", "fs.promises.rename"],
        .fsCopy: ["ios.fs.copy", "fs.promises.copyFile"],
        .fsDelete: ["ios.fs.delete", "fs.promises.rm"],
        .fsStat: ["ios.fs.stat", "fs.promises.stat"],
        .fsMkdir: ["ios.fs.mkdir", "fs.promises.mkdir"],
        .fsExists: ["ios.fs.exists"],
        .fsAccess: ["ios.fs.access", "fs.promises.access"],
    ]
}
