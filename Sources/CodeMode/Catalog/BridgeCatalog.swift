import Foundation

struct BridgeCatalog: Sendable {
    private struct SearchEntry: Sendable {
        var reference: JavaScriptAPIReference
        var index: SearchIndex
    }

    private struct SearchIndex: Sendable {
        var jsNames: [String]
        var capability: String
        var title: String
        var tags: [String]
        var summary: String
        var resultSummary: String
        var example: String
        var requiredArguments: [String]
        var optionalArguments: [String]
        var argumentHints: [String]
        var generatedPhrases: [String]
        var jsTokens: Set<String>
        var capabilityTokens: Set<String>
        var titleTokens: Set<String>
        var tagTokens: Set<String>
        var summaryTokens: Set<String>
        var resultSummaryTokens: Set<String>
        var exampleTokens: Set<String>
        var argumentTokens: Set<String>
        var argumentHintTokens: Set<String>
        var generatedTokens: Set<String>
    }

    private let entries: [SearchEntry]
    private let referencesByCapability: [CapabilityID: JavaScriptAPIReference]
    private let allJavaScriptNames: [String]

    init(registry: CapabilityRegistry) {
        let descriptors = registry.allDescriptors().sorted { $0.id.rawValue < $1.id.rawValue }
        self.entries = descriptors.map { descriptor in
            let reference = Self.reference(from: descriptor)
            return SearchEntry(
                reference: reference,
                index: Self.makeSearchIndex(reference: reference, title: descriptor.title)
            )
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
        let normalizedQuery = Self.normalizePhrase(query)
        let queryTerms = Array(Set(Self.tokenize(normalizedQuery))).sorted()
        let requiredTags = Set(tags.map(Self.normalizePhrase))

        let scored: [(JavaScriptAPIReference, Int)] = entries.compactMap { entry in
            let index = entry.index
            if requiredTags.isEmpty == false, requiredTags.isSubset(of: Set(index.tags)) == false {
                return nil
            }

            let score = Self.score(index: index, normalizedQuery: normalizedQuery, queryTerms: queryTerms)
            return score > 0 ? (entry.reference, score) : nil
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

    private static func makeSearchIndex(reference: JavaScriptAPIReference, title: String) -> SearchIndex {
        let jsNames = reference.jsNames.map(normalizePhrase)
        let capability = normalizePhrase(reference.capability.rawValue)
        let normalizedTitle = normalizePhrase(title)
        let tags = reference.tags.map(normalizePhrase)
        let summary = normalizePhrase(reference.summary)
        let resultSummary = normalizePhrase(reference.resultSummary)
        let example = normalizePhrase(reference.example)
        let requiredArguments = reference.requiredArguments.map(normalizePhrase)
        let optionalArguments = reference.optionalArguments.map(normalizePhrase)

        let argumentTypeNames = reference.argumentTypes.keys.sorted().map(normalizePhrase)
        let argumentHints = reference.argumentHints.keys.sorted().compactMap { key -> String? in
            guard let hint = reference.argumentHints[key] else {
                return nil
            }
            let normalizedKey = normalizePhrase(key)
            let normalizedHint = normalizePhrase(hint)
            return [normalizedKey, normalizedHint]
                .filter { $0.isEmpty == false }
                .joined(separator: " ")
        }

        let generatedPhrases = generatedPhrases(
            for: reference,
            title: normalizedTitle,
            jsNames: jsNames,
            capability: capability,
            tags: tags,
            requiredArguments: requiredArguments,
            optionalArguments: optionalArguments
        )

        let argumentFields = requiredArguments + optionalArguments + argumentTypeNames

        return SearchIndex(
            jsNames: jsNames,
            capability: capability,
            title: normalizedTitle,
            tags: tags,
            summary: summary,
            resultSummary: resultSummary,
            example: example,
            requiredArguments: requiredArguments,
            optionalArguments: optionalArguments,
            argumentHints: argumentHints,
            generatedPhrases: generatedPhrases,
            jsTokens: tokenSet(jsNames),
            capabilityTokens: tokenSet([capability]),
            titleTokens: tokenSet([normalizedTitle]),
            tagTokens: tokenSet(tags),
            summaryTokens: tokenSet([summary]),
            resultSummaryTokens: tokenSet([resultSummary]),
            exampleTokens: tokenSet([example]),
            argumentTokens: tokenSet(argumentFields),
            argumentHintTokens: tokenSet(argumentHints),
            generatedTokens: tokenSet(generatedPhrases)
        )
    }

    private static func generatedPhrases(
        for reference: JavaScriptAPIReference,
        title: String,
        jsNames: [String],
        capability: String,
        tags: [String],
        requiredArguments: [String],
        optionalArguments: [String]
    ) -> [String] {
        var phrases = Set<String>()
        let tokenSequences = [
            tokenize(title),
            tokenize(capability),
        ] + jsNames.map(tokenize) + tags.map(tokenize)

        for tokens in tokenSequences {
            guard tokens.isEmpty == false else {
                continue
            }

            phrases.insert(tokens.joined(separator: " "))
            phrases.formUnion(ngrams(from: tokens, sizes: 2...3))

            for token in Set(tokens) {
                phrases.formUnion(SearchVocabulary.tokenSynonyms(token).map(normalizePhrase))
            }
        }

        for argument in requiredArguments + optionalArguments {
            let tokens = tokenize(argument)
            phrases.formUnion(ngrams(from: tokens, sizes: 1...2))
        }

        phrases.formUnion(SearchVocabulary.capabilityPhrases(reference.capability).map(normalizePhrase))

        return phrases
            .map(normalizePhrase)
            .filter { $0.isEmpty == false }
            .sorted()
    }

    private static func score(index: SearchIndex, normalizedQuery: String, queryTerms: [String]) -> Int {
        guard normalizedQuery.isEmpty == false else {
            return 0
        }

        var score = 0
        var matchedTerms = Set<String>()
        var highSignalTerms = Set<String>()

        score += phraseScore(query: normalizedQuery, candidates: index.jsNames, exact: 4_000, prefix: 3_200, contains: 2_800)
        score += phraseScore(query: normalizedQuery, candidates: [index.capability], exact: 2_500, prefix: 2_150, contains: 1_850)
        score += phraseScore(query: normalizedQuery, candidates: [index.title], exact: 2_000, prefix: 1_700, contains: 1_450)
        score += phraseScore(query: normalizedQuery, candidates: index.generatedPhrases, exact: 1_650, prefix: 1_350, contains: 1_100)
        score += phraseScore(query: normalizedQuery, candidates: index.tags, exact: 1_250, prefix: 950, contains: 760)
        score += phraseScore(query: normalizedQuery, candidates: index.requiredArguments + index.optionalArguments, exact: 950, prefix: 760, contains: 620)
        score += phraseScore(query: normalizedQuery, candidates: [index.summary], exact: 900, prefix: 760, contains: 620)
        score += phraseScore(query: normalizedQuery, candidates: [index.resultSummary], exact: 760, prefix: 620, contains: 500)
        score += phraseScore(query: normalizedQuery, candidates: index.argumentHints, exact: 700, prefix: 560, contains: 450)
        score += phraseScore(query: normalizedQuery, candidates: [index.example], exact: 620, prefix: 500, contains: 380)

        addTokenMatches(queryTerms, in: index.jsTokens, weight: 260, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.capabilityTokens, weight: 200, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.titleTokens, weight: 165, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.generatedTokens, weight: 150, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.tagTokens, weight: 130, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.argumentTokens, weight: 105, countsAsHighSignal: true, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.argumentHintTokens, weight: 72, countsAsHighSignal: false, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.summaryTokens, weight: 58, countsAsHighSignal: false, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.resultSummaryTokens, weight: 52, countsAsHighSignal: false, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)
        addTokenMatches(queryTerms, in: index.exampleTokens, weight: 38, countsAsHighSignal: false, score: &score, matchedTerms: &matchedTerms, highSignalTerms: &highSignalTerms)

        guard queryTerms.isEmpty == false else {
            return score
        }

        guard matchedTerms.isEmpty == false else {
            return 0
        }

        if matchedTerms.count == queryTerms.count {
            score += 260 + queryTerms.count * 24
        }

        if highSignalTerms.count == queryTerms.count {
            score += 420 + queryTerms.count * 32
        }

        if queryTerms.count > 1, matchedTerms.count == 1, score < 1_200 {
            return 0
        }

        return score
    }

    private static func phraseScore(query: String, candidates: [String], exact: Int, prefix: Int, contains: Int) -> Int {
        var best = 0
        for candidate in candidates where candidate.isEmpty == false {
            if candidate == query {
                best = max(best, exact)
            } else if candidate.hasPrefix(query) {
                best = max(best, prefix)
            } else if candidate.contains(query) {
                best = max(best, contains)
            }
        }
        return best
    }

    private static func addTokenMatches(
        _ queryTerms: [String],
        in tokens: Set<String>,
        weight: Int,
        countsAsHighSignal: Bool,
        score: inout Int,
        matchedTerms: inout Set<String>,
        highSignalTerms: inout Set<String>
    ) {
        for term in queryTerms where tokens.contains(term) {
            score += weight
            matchedTerms.insert(term)
            if countsAsHighSignal {
                highSignalTerms.insert(term)
            }
        }
    }

    private static func tokenSet(_ values: [String]) -> Set<String> {
        Set(values.flatMap(tokenize))
    }

    private static func ngrams(from tokens: [String], sizes: ClosedRange<Int>) -> Set<String> {
        guard tokens.isEmpty == false else {
            return []
        }

        var phrases = Set<String>()
        for size in sizes where size > 0 && tokens.count >= size {
            for start in 0...(tokens.count - size) {
                phrases.insert(tokens[start..<(start + size)].joined(separator: " "))
            }
        }
        return phrases
    }

    private static func normalizePhrase(_ value: String) -> String {
        tokenize(value).joined(separator: " ")
    }

    private static func tokenize(_ value: String) -> [String] {
        guard value.isEmpty == false else {
            return []
        }

        var tokens: [String] = []
        var current = ""

        func flushCurrent() {
            guard current.isEmpty == false else {
                return
            }
            tokens.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for character in value {
            let isAlphaNumeric = character.isLetter || character.isNumber
            if isAlphaNumeric == false {
                flushCurrent()
                continue
            }

            let startsNewToken = current.isEmpty == false && (
                (character.isUppercase && current.last?.isLowercase == true) ||
                (character.isNumber && current.last?.isLetter == true) ||
                (character.isLetter && current.last?.isNumber == true)
            )

            if startsNewToken {
                flushCurrent()
            }

            current.append(contentsOf: String(character).lowercased())
        }

        flushCurrent()
        return tokens
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

private enum SearchVocabulary {
    private static let tokenExpansions: [String: [String]] = [
        "fetch": ["http request", "api request", "download url"],
        "keychain": ["secret", "credential", "password", "auth token", "api key"],
        "location": ["gps", "geolocation", "coordinates", "position", "current location"],
        "weather": ["forecast", "temperature", "conditions"],
        "calendar": ["meeting", "schedule", "agenda"],
        "reminders": ["todo", "to do", "task", "tasks"],
        "contacts": ["address book", "people", "person"],
        "photos": ["photo library", "camera roll", "image", "images"],
        "vision": ["ocr", "text recognition", "barcode scan", "image analysis"],
        "notifications": ["notification", "notify", "alert", "alerts"],
        "alarm": ["alarm clock", "wake up"],
        "health": ["healthkit", "steps", "heart rate", "sleep", "workout"],
        "home": ["smart home", "iot", "light", "lights", "thermostat", "accessory"],
        "media": ["video", "audio", "clip", "movie"],
        "filesystem": ["file system", "files", "directory", "folder"],
        "fs": ["filesystem", "file system", "file", "directory", "folder"],
        "read": ["load", "inspect", "view"],
        "write": ["save", "store", "update", "set"],
        "delete": ["remove", "erase", "clear"],
        "search": ["find", "lookup"],
        "permission": ["authorization", "authorize", "access"],
        "schedule": ["plan", "set up"],
        "pending": ["queued", "scheduled"],
        "cancel": ["stop", "unschedule"],
        "export": ["save as", "copy out"],
        "frame": ["thumbnail", "still frame"],
        "transcode": ["convert", "encode", "mp4"],
        "mkdir": ["create directory", "make directory", "create folder", "make folder"],
        "exists": ["check exists", "is there"],
        "access": ["permissions", "readable", "writable"],
        "stat": ["metadata", "file info", "path info"],
    ]

    private static let capabilityExpansions: [CapabilityID: [String]] = [
        .networkFetch: ["http request", "call api", "download url"],
        .keychainRead: ["read secret", "get auth token", "load password"],
        .keychainWrite: ["store secret", "save auth token", "set api key"],
        .keychainDelete: ["delete secret", "remove auth token"],
        .locationRead: ["gps coordinates", "current location", "location status"],
        .locationPermissionRequest: ["request location permission", "ask for location access"],
        .weatherRead: ["current weather", "weather forecast", "temperature for coordinates"],
        .calendarRead: ["list calendar events", "upcoming meetings", "calendar agenda"],
        .calendarWrite: ["create calendar event", "schedule meeting", "add event to calendar"],
        .remindersRead: ["list reminders", "show tasks", "todo list"],
        .remindersWrite: ["create reminder", "add todo", "add task"],
        .contactsRead: ["list contacts", "address book"],
        .contactsSearch: ["find contact", "search people", "lookup person"],
        .photosRead: ["browse photo library", "list camera roll assets"],
        .photosExport: ["export photo asset", "save photo to file"],
        .visionImageAnalyze: ["ocr image", "scan barcode", "analyze receipt image"],
        .notificationsPermissionRequest: ["request notification permission", "ask for alert access"],
        .notificationsSchedule: ["schedule notification", "set local alert"],
        .notificationsPendingRead: ["list pending notifications", "show scheduled alerts"],
        .notificationsPendingDelete: ["cancel pending notification", "remove scheduled alert"],
        .alarmPermissionRequest: ["request alarm permission", "ask for alarm access"],
        .alarmRead: ["list alarms", "show scheduled alarms"],
        .alarmSchedule: ["set wake up alarm", "schedule alarm"],
        .alarmCancel: ["cancel alarm", "remove scheduled alarm"],
        .healthPermissionRequest: ["request health access", "ask for health permission"],
        .healthRead: ["read heart rate data", "read step count", "read health samples"],
        .healthWrite: ["write step count sample", "save health sample"],
        .homeRead: ["list smart home devices", "show home accessories"],
        .homeWrite: ["turn off light", "turn on light", "control smart home device", "set thermostat"],
        .mediaMetadataRead: ["read video metadata", "media duration info"],
        .mediaFrameExtract: ["make video thumbnail", "extract frame from video"],
        .mediaTranscode: ["convert mov to mp4", "transcode video"],
        .fsList: ["list files in tmp", "browse directory"],
        .fsRead: ["read file contents", "load text file"],
        .fsWrite: ["write json file", "save file contents"],
        .fsMove: ["rename file", "move file"],
        .fsCopy: ["copy file"],
        .fsDelete: ["remove folder recursively", "delete file"],
        .fsStat: ["file info metadata", "inspect file metadata"],
        .fsMkdir: ["create folder", "make directory"],
        .fsExists: ["does file exist", "check path exists"],
        .fsAccess: ["check if file is writable", "check file permissions"],
    ]

    static func tokenSynonyms(_ token: String) -> [String] {
        tokenExpansions[token] ?? []
    }

    static func capabilityPhrases(_ capability: CapabilityID) -> [String] {
        capabilityExpansions[capability] ?? []
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
