import CodeMode
import Foundation
import ArgumentParser
import Wavelike
import WavelikeEngineApple

enum EvalToolKind: String {
    case search
    case execute
}

enum ModelDecision {
    case search(SearchRequest)
    case execute(String)
}

struct EvalCheck {
    var passed: Bool
    var reason: String
}

struct EvalScenario {
    var id: String
    var prompts: [String]
    var expectedTool: EvalToolKind
    var validate: (_ artifact: EvalArtifact) -> EvalCheck
}

struct EvalArtifact {
    var scenarioID: String
    var prompt: String
    var decision: ModelDecision
    var searchResponse: SearchResponse?
    var executeResponse: ExecuteResponse?
    var invocations: [CapturedInvocation]
}

struct EvalRunResult {
    var scenarioID: String
    var prompt: String
    var passed: Bool
    var reason: String
    var generatedSummary: String
}

protocol EvalModelProvider {
    var id: String { get }
    func generate(prompt: String, docs: [BridgeAPIDoc], guidance: String?) async throws -> ModelDecision
}

final class ScriptedModelProvider: EvalModelProvider {
    let id = "scripted"

    func generate(prompt: String, docs: [BridgeAPIDoc], guidance: String?) async throws -> ModelDecision {
        _ = docs
        _ = guidance
        let p = prompt.lowercased()

        if p.contains("what can you do") && (p.contains("reminder") || p.contains("calendar")) {
            return .search(SearchRequest(mode: .discover, query: "calendar reminders", limit: 10))
        }

        if p.contains("morning brief") || (p.contains("morning") && p.contains("weather") && (p.contains("calendar") || p.contains("event")) && p.contains("reminder")) {
            return .execute(
                """
                const weather = await ios.weather.getCurrentWeather({ latitude: 37.7749, longitude: -122.4194 });
                const events = await ios.calendar.listEvents({ limit: 10 });
                const reminders = await ios.reminders.listReminders({ limit: 10 });
                return { weather, events, reminders };
                """
            )
        }

        if p.contains("electric") || (p.contains("reminder") && p.contains("9")) {
            return .execute(
                """
                const due = new Date(Date.now() + 24 * 60 * 60 * 1000);
                due.setHours(9, 0, 0, 0);
                const reminder = await ios.reminders.createReminder({ title: 'Pay electric bill', dueDate: due.toISOString() });
                return { reminder };
                """
            )
        }

        if p.contains("project sync") || (p.contains("calendar event") && p.contains("2:00")) {
            return .execute(
                """
                function nextTuesdayAt(hour, minute) {
                  const now = new Date();
                  const day = now.getDay();
                  const tuesday = 2;
                  let delta = (tuesday - day + 7) % 7;
                  if (delta === 0) delta = 7;
                  const d = new Date(now);
                  d.setDate(now.getDate() + delta);
                  d.setHours(hour, minute, 0, 0);
                  return d;
                }
                const start = nextTuesdayAt(14, 0);
                const end = new Date(start.getTime() + 30 * 60 * 1000);
                const event = await ios.calendar.createEvent({ title: 'Project sync', start: start.toISOString(), end: end.toISOString() });
                return { event, start: start.toISOString(), end: end.toISOString() };
                """
            )
        }

        if p.contains("find alex") || (p.contains("contacts") && p.contains("phone") && p.contains("email")) {
            return .execute(
                """
                const matches = await ios.contacts.search({ query: 'Alex', limit: 10 });
                return matches.map(c => ({
                  name: [c.givenName, c.familyName].filter(Boolean).join(' ').trim(),
                  phones: c.phones || [],
                  emails: c.emails || []
                }));
                """
            )
        }

        if p.contains("auth token")
            || (p.contains("securely") && p.contains("reuse"))
            || (p.contains("keychain") && p.contains("token") && (p.contains("fetch") || p.contains("backend")))
        {
            return .execute(
                """
                await ios.keychain.set('auth_token', 'demo-token-123');
                const saved = await ios.keychain.get('auth_token');
                const token = saved && saved.value ? saved.value : '';
                const res = await fetch('https://api.example.com/profile', {
                  method: 'GET',
                  headers: { Authorization: `Bearer ${token}` }
                });
                return { status: res.status, usedToken: token.length > 0 };
                """
            )
        }

        if p.contains("backend") && p.contains("save") {
            return .execute(
                """
                const response = await fetch('https://api.example.com/reports/latest');
                const payload = await response.json();
                await ios.fs.write({ path: 'tmp:backend.json', data: JSON.stringify(payload) });
                const stat = await ios.fs.stat({ path: 'tmp:backend.json' });
                return { ok: true, stat };
                """
            )
        }

        if p.contains("list files") && p.contains("tmp") && p.contains("documents") {
            return .execute(
                """
                await ios.fs.write({ path: 'tmp:report-1.txt', data: 'r1' });
                await ios.fs.write({ path: 'tmp:report-2.txt', data: 'r2' });
                await ios.fs.write({ path: 'tmp:old.tmp', data: 'old' });
                const files = await ios.fs.list({ path: 'tmp:' });
                for (const file of files) {
                  if (file.name.startsWith('report')) {
                    await ios.fs.move({ from: `tmp:${file.name}`, to: `documents:${file.name}` });
                  }
                  if (file.name.endsWith('.tmp')) {
                    await ios.fs.delete({ path: `tmp:${file.name}` });
                  }
                }
                return { movedReports: true, cleanedTemps: true };
                """
            )
        }

        if p.contains("thumbnail") || (p.contains("metadata") && p.contains("1.5")) {
            return .execute(
                """
                const metadata = await ios.media.metadata({ path: 'tmp:clip.mov' });
                const frame = await ios.media.extractFrame({ path: 'tmp:clip.mov', timeMs: 1500, outputPath: 'tmp:thumb.jpg' });
                return { metadata, frame };
                """
            )
        }

        if p.contains("transcode") || (p.contains(".mov") && p.contains(".mp4")) {
            return .execute(
                """
                const out = await ios.media.transcode({
                  path: 'tmp:input.mov',
                  outputPath: 'tmp:input-small.mp4',
                  preset: 'AVAssetExportPresetMediumQuality'
                });
                return out;
                """
            )
        }

        return .search(SearchRequest(mode: .discover, query: prompt, limit: 10))
    }
}

struct CommandModelInput: Codable {
    var prompt: String
    var capabilities: [BridgeAPIDoc]
    var guidance: String?
}

struct CommandModelOutput: Codable {
    struct SearchPayload: Codable {
        var mode: String?
        var query: String?
        var capability: String?
        var limit: Int?
        var tags: [String]?
    }

    var tool: String
    var code: String?
    var search: SearchPayload?
}

func decision(from output: CommandModelOutput) throws -> ModelDecision {
    switch output.tool.lowercased() {
    case "execute":
        guard let code = output.code, code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw NSError(domain: "CodeModeEval", code: 3, userInfo: [NSLocalizedDescriptionKey: "model output missing code for execute tool"])
        }
        return .execute(code)
    case "search":
        let mode = SearchMode(rawValue: output.search?.mode ?? "discover") ?? .discover
        let capability = output.search?.capability.flatMap(CapabilityID.init(rawValue:))
        let request = SearchRequest(
            mode: mode,
            query: output.search?.query,
            capability: capability,
            limit: output.search?.limit ?? 10,
            tags: output.search?.tags
        )
        return .search(request)
    default:
        throw NSError(domain: "CodeModeEval", code: 4, userInfo: [NSLocalizedDescriptionKey: "model output tool must be search or execute"])
    }
}

private func traceLog(_ message: String) {
    fputs("[codemode-eval trace] \(message)\n", stderr)
}

private func errorDescription(_ error: Error) -> String {
    let nsError = error as NSError
    var parts: [String] = []

    let localized = nsError.localizedDescription
    if localized.isEmpty == false {
        parts.append(localized)
    }

    parts.append("(domain: \(nsError.domain), code: \(nsError.code))")

    if let debug = nsError.userInfo[NSDebugDescriptionErrorKey] as? String, debug.isEmpty == false {
        parts.append("debug: \(debug)")
    }
    if let reason = nsError.localizedFailureReason, reason.isEmpty == false {
        parts.append("reason: \(reason)")
    }
    if let recovery = nsError.localizedRecoverySuggestion, recovery.isEmpty == false {
        parts.append("suggestion: \(recovery)")
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
        parts.append("underlying: \(errorDescription(underlying))")
    }

    return parts.joined(separator: " ")
}

private func extractJSONEnvelope(_ content: String) -> String {
    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("{"), trimmed.hasSuffix("}") {
        return trimmed
    }

    if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
        return String(trimmed[start ... end])
    }

    return trimmed
}

private func extractTopLevelJSONObjects(from content: String) -> [String] {
    var objects: [String] = []
    var depth = 0
    var objectStart: String.Index?
    var isInString = false
    var isEscaping = false

    for index in content.indices {
        let character = content[index]

        if isInString {
            if isEscaping {
                isEscaping = false
                continue
            }

            if character == "\\" {
                isEscaping = true
                continue
            }

            if character == "\"" {
                isInString = false
            }
            continue
        }

        if character == "\"" {
            isInString = true
            continue
        }

        if character == "{" {
            if depth == 0 {
                objectStart = index
            }
            depth += 1
            continue
        }

        if character == "}" {
            guard depth > 0 else {
                continue
            }

            depth -= 1
            if depth == 0, let objectStart {
                objects.append(String(content[objectStart ... index]))
            }
        }
    }

    return objects
}

private func decodeModelOutputs(from raw: String) -> [CommandModelOutput] {
    var decoded: [CommandModelOutput] = []
    var seenCandidates: Set<String> = []

    func attemptDecode(_ candidate: String) {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return
        }
        guard seenCandidates.insert(trimmed).inserted else {
            return
        }

        let data = Data(trimmed.utf8)
        if let value = try? JSONDecoder.codeModeBridge.decode(CommandModelOutput.self, from: data) {
            decoded.append(value)
            return
        }

        if let values = try? JSONDecoder.codeModeBridge.decode([CommandModelOutput].self, from: data) {
            decoded.append(contentsOf: values)
        }
    }

    attemptDecode(raw)
    attemptDecode(extractJSONEnvelope(raw))
    for object in extractTopLevelJSONObjects(from: raw) {
        attemptDecode(object)
    }

    return decoded
}

private func mergedDecision(from decisions: [ModelDecision]) -> ModelDecision {
    guard let first = decisions.first else {
        return .search(SearchRequest(mode: .discover, query: nil, limit: 10))
    }

    if decisions.count == 1 {
        return first
    }

    if let execute = decisions.first(where: {
        if case .execute = $0 { return true }
        return false
    }) {
        return execute
    }

    let searchRequests = decisions.compactMap { decision -> SearchRequest? in
        if case let .search(request) = decision {
            return request
        }
        return nil
    }

    guard searchRequests.isEmpty == false else {
        return first
    }

    if searchRequests.contains(where: { $0.mode == .describe }),
       let describedCapability = searchRequests.compactMap(\.capability).first
    {
        return .search(
            SearchRequest(
                mode: .describe,
                query: nil,
                capability: describedCapability,
                limit: searchRequests.map(\.limit).max() ?? 10,
                tags: nil
            )
        )
    }

    let mergedQuery = searchRequests
        .compactMap { $0.query?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .joined(separator: " ")

    let mergedTags = Array(Set(searchRequests.flatMap { $0.tags ?? [] })).sorted()

    return .search(
        SearchRequest(
            mode: .discover,
            query: mergedQuery.isEmpty ? nil : mergedQuery,
            capability: nil,
            limit: searchRequests.map(\.limit).max() ?? 10,
            tags: mergedTags.isEmpty ? nil : mergedTags
        )
    )
}

final class WavelikeModelProvider: EvalModelProvider {
    let id: String
    private let modelID: String
    private let modelEngineID: String?
    private let trace: Bool
    private var isAppleProvider: Bool { id == "wavelike-apple" }

    init(forceAppleEngine: Bool = false, trace: Bool = false) throws {
        let env = ProcessInfo.processInfo.environment
        self.trace = trace

        let requestedEngine = forceAppleEngine
            ? "apple"
            : (env["WAVELIKE_ENGINE"]?.lowercased() ?? "proxy")

        if let environment = env["WAVELIKE_ENV"]?.lowercased() {
            switch environment {
            case "local":
                Wavelike.set(environment: .local)
            case "stage", "staging":
                Wavelike.set(environment: .stage)
            case "production", "prod":
                Wavelike.set(environment: .production)
            default:
                break
            }
        }

        switch requestedEngine {
        case "apple":
            guard #available(iOS 26.0, macOS 26.0, *) else {
                throw NSError(
                    domain: "CodeModeEval",
                    code: 14,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Apple engine requires iOS 26+ or macOS 26+ runtime support.",
                    ]
                )
            }
            Wavelike.register(engine: AppleEngine())
            let appID = env["WAVELIKE_APP_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "codemode-eval-local"
            Wavelike.set(appId: appID)
            self.id = "wavelike-apple"
            self.modelEngineID = AppleEngine.identifier
            self.modelID = env["WAVELIKE_MODEL_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "com.apple.SystemLanguageModel.default"
        case "proxy", "remote", "wavelike":
            guard let appID = env["WAVELIKE_APP_ID"], appID.isEmpty == false else {
                throw NSError(
                    domain: "CodeModeEval",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Wavelike provider requires WAVELIKE_APP_ID.",
                    ]
                )
            }

            Wavelike.set(appId: appID)

            if let apiKey = env["WAVELIKE_API_KEY"], apiKey.isEmpty == false {
                Wavelike.set(auth: .apiKey(apiKey))
            } else if
                let userID = env["WAVELIKE_USER_ID"], userID.isEmpty == false,
                let userKey = env["WAVELIKE_USER_KEY"], userKey.isEmpty == false
            {
                Wavelike.set(auth: .backend(userId: userID, key: userKey))
            }

            self.id = "wavelike"
            self.modelEngineID = nil
            self.modelID = env["WAVELIKE_MODEL_ID"].flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-4.1-mini"
        default:
            throw NSError(
                domain: "CodeModeEval",
                code: 15,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unknown WAVELIKE_ENGINE '\(requestedEngine)'. Use apple|proxy.",
                ]
            )
        }

        if trace {
            traceLog("provider=\(id) engine=\(modelEngineID ?? "proxy") modelID=\(modelID)")
        }
    }

    func generate(prompt: String, docs: [BridgeAPIDoc], guidance: String?) async throws -> ModelDecision {
        let model = Wavelike.model(for: ModelIdentifier(ChatModel.self, id: modelID, engineId: modelEngineID))

        if trace {
            traceLog("generate start provider=\(id) prompt=\(prompt) docs=\(docs.count)")
        }

        let systemPrompt = """
        You produce tool calls for a JavaScript execution environment.
        Return strict JSON only (no markdown, no prose) with one of these shapes:
        {"tool":"search","search":{"mode":"discover","query":"...","limit":10,"tags":["optional"]}}
        {"tool":"search","search":{"mode":"describe","capability":"calendar.write"}}
        {"tool":"execute","code":"<javascript code>"}
        Rules:
        - Emit exactly one tool call JSON object per response.
        - Use search tool for capability discovery requests.
        - For action requests, prefer search first when capability/arguments are uncertain.
        - After receiving search output, emit execute with complete JavaScript that solves the full task.
        - If Planning context contains a hard requirement to emit execute now, you must return execute.
        - Execute code must only use these JS APIs: fetch, ios.*, fs.promises, console, setTimeout.
        - Never use fs.<method> directly; use fs.promises.<method> or ios.fs.*.
        - Do not include unsupported APIs or import statements.
        """

        func sendRaw(userPrompt: String) async throws -> String {
            let timeoutSeconds = isAppleProvider ? 25 : 45
            let timeoutNs = UInt64(timeoutSeconds) * 1_000_000_000

            return try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    let response = try await model.send(
                        history: [
                            Message(role: .system, content: systemPrompt),
                            Message(role: .user, content: userPrompt),
                        ],
                        configuration: ChatConfiguration(
                            temperature: 0.0,
                            toolExecutionMode: .manual
                        )
                    )

                    guard let raw = response.message.content, raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                        throw NSError(domain: "CodeModeEval", code: 13, userInfo: [NSLocalizedDescriptionKey: "Wavelike response did not include message content"])
                    }
                    return raw
                }

                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNs)
                    throw NSError(
                        domain: "CodeModeEval",
                        code: 17,
                        userInfo: [NSLocalizedDescriptionKey: "Model generation timed out after \(timeoutSeconds)s"]
                    )
                }

                guard let result = try await group.next() else {
                    throw NSError(domain: "CodeModeEval", code: 18, userInfo: [NSLocalizedDescriptionKey: "Model generation returned no result"])
                }
                group.cancelAll()
                return result
            }
        }

        func sendRawWithTransientRetry(userPrompt: String, context: String) async throws -> String {
            let maxAttempts = isAppleProvider ? 2 : 4
            var attempt = 1

            while true {
                do {
                    return try await sendRaw(userPrompt: userPrompt)
                } catch {
                    guard attempt < maxAttempts, isTransientTransportError(error) else {
                        throw error
                    }

                    let backoffMs = min(4_000, 400 * (1 << (attempt - 1)))
                    if trace {
                        traceLog("\(context) transient error attempt \(attempt)/\(maxAttempts): \(errorDescription(error)); retrying in \(backoffMs)ms")
                    }
                    try await Task.sleep(nanoseconds: UInt64(backoffMs) * 1_000_000)
                    attempt += 1
                }
            }
        }

        var raw: String
        let defaultUserPrompt = buildUserPrompt(
            prompt: prompt,
            docs: docs,
            guidance: guidance,
            compactCapabilities: isAppleProvider,
            includeExamples: isAppleProvider == false
        )

        do {
            raw = try await sendRawWithTransientRetry(userPrompt: defaultUserPrompt, context: "default")
        } catch {
            guard isAppleProvider else {
                throw error
            }

            if isGuardrailError(error) {
                if trace {
                    traceLog("apple retry after guardrail violation")
                }
                let sanitizedPrompt = sanitizePromptForAppleRetry(prompt)
                let retryUserPrompt = buildUserPrompt(
                    prompt: sanitizedPrompt,
                    docs: docs,
                    guidance: guidance,
                    compactCapabilities: true,
                    includeExamples: false
                )
                do {
                    raw = try await sendRawWithTransientRetry(userPrompt: retryUserPrompt, context: "apple-guardrail-retry")
                } catch {
                    if isContextWindowError(error) {
                        if trace {
                            traceLog("apple fallback after guardrail retry due context window")
                        }
                        let compactDocs = Array(docs.prefix(8))
                        let compactGuidance = guidance.map { compactText($0, maxLength: 400) }
                        let compactUserPrompt = buildUserPrompt(
                            prompt: sanitizedPrompt,
                            docs: compactDocs,
                            guidance: compactGuidance,
                            compactCapabilities: true,
                            includeExamples: false
                        )
                        raw = try await sendRawWithTransientRetry(userPrompt: compactUserPrompt, context: "apple-guardrail-compact")
                    } else {
                        throw error
                    }
                }
            } else if isContextWindowError(error) {
                if trace {
                    traceLog("apple retry after context window overflow")
                }
                let compactDocs = Array(docs.prefix(8))
                let compactGuidance = guidance.map { compactText($0, maxLength: 400) }
                let retryUserPrompt = buildUserPrompt(
                    prompt: prompt,
                    docs: compactDocs,
                    guidance: compactGuidance,
                    compactCapabilities: true,
                    includeExamples: false
                )
                raw = try await sendRawWithTransientRetry(userPrompt: retryUserPrompt, context: "apple-context-window-retry")
            } else {
                throw error
            }
        }

        if trace {
            let preview = raw
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            traceLog("model raw response preview: \(String(preview.prefix(280)))")
        }

        do {
            let outputs = decodeModelOutputs(from: raw)
            guard outputs.isEmpty == false else {
                throw NSError(domain: "CodeModeEval", code: 16)
            }
            let decisions = try outputs.map(decision(from:))
            if trace {
                traceLog("decoded \(outputs.count) tool object(s)")
            }
            return mergedDecision(from: decisions)
        } catch {
            let snippet = raw
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = String(snippet.prefix(280))
            if trace {
                traceLog("model output decode failed: \(errorDescription(error))")
            }
            throw NSError(
                domain: "CodeModeEval",
                code: 16,
                userInfo: [
                    NSLocalizedDescriptionKey: "Model response did not contain usable tool JSON. Preview: \(preview)",
                ]
            )
        }
    }

    private func compactText(_ text: String, maxLength: Int) -> String {
        let flattened = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard flattened.count > maxLength else {
            return flattened
        }
        let limit = max(maxLength - 3, 0)
        return String(flattened.prefix(limit)) + "..."
    }

    private func capabilitySummary(
        for docs: [BridgeAPIDoc],
        compact: Bool,
        includeExamples: Bool
    ) -> String {
        guard docs.isEmpty == false else {
            return "(none)"
        }

        let maxDocs = compact ? min(16, docs.count) : docs.count
        return docs.prefix(maxDocs).map { doc in
            if includeExamples {
                let summary = compactText(doc.summary, maxLength: compact ? 110 : 180)
                let example = compactText(doc.example, maxLength: compact ? 100 : 180)
                return "\(doc.capability.rawValue): \(summary). Example: \(example)"
            }

            let summary = compactText(doc.summary, maxLength: compact ? 110 : 180)
            return "\(doc.capability.rawValue): \(summary)"
        }.joined(separator: "\n")
    }

    private func buildUserPrompt(
        prompt: String,
        docs: [BridgeAPIDoc],
        guidance: String?,
        compactCapabilities: Bool,
        includeExamples: Bool
    ) -> String {
        let capabilitySummary = capabilitySummary(for: docs, compact: compactCapabilities, includeExamples: includeExamples)

        let guidanceSection: String = {
            guard let guidance = guidance?.trimmingCharacters(in: .whitespacesAndNewlines), guidance.isEmpty == false else {
                return ""
            }

            let guidanceText = compactCapabilities ? compactText(guidance, maxLength: 500) : guidance
            return """

            Planning context:
            \(guidanceText)
            """
        }()

        return """
        User request:
        \(prompt)

        Available capabilities:
        \(capabilitySummary)
        \(guidanceSection)
        """
    }

    private func sanitizePromptForAppleRetry(_ prompt: String) -> String {
        let normalized = prompt
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
        if let hint = taskExecutionHint(for: prompt), hint.isEmpty == false {
            return "Benign local automation request. \(normalized)\nObjective: \(compactText(hint, maxLength: 320))"
        }
        return "Benign local automation request. \(normalized)"
    }

    private func isGuardrailError(_ error: Error) -> Bool {
        let description = errorDescription(error).lowercased()
        return description.contains("guardrailviolation")
            || description.contains("unsafe content")
            || description.contains("sensitive or unsafe")
    }

    private func isContextWindowError(_ error: Error) -> Bool {
        let description = errorDescription(error).lowercased()
        return description.contains("context window")
            || description.contains("exceededcontextwindowsize")
            || description.contains("exceeds the maximum allowed context size")
    }

    private func isTransientTransportError(_ error: Error) -> Bool {
        let description = errorDescription(error).lowercased()

        let transientMarkers = [
            "status code: 429",
            "status code: 500",
            "status code: 502",
            "status code: 503",
            "status code: 504",
            "status code: 529",
            "network connection was lost",
            "timed out",
            "cannot connect to host",
            "service unavailable",
            "temporarily unavailable",
            "connection reset",
        ]
        if transientMarkers.contains(where: description.contains) {
            return true
        }

        for nsError in nsErrorChain(from: error) where nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut,
                 NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorDNSLookupFailed,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                continue
            }
        }

        return false
    }

    private func nsErrorChain(from error: Error) -> [NSError] {
        var chain: [NSError] = []
        var current: NSError? = error as NSError
        var depth = 0

        while let error = current, depth < 10 {
            chain.append(error)
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }

        return chain
    }
}

final class CommandModelProvider: EvalModelProvider {
    let id = "command"
    private let executablePath: String
    private let executableArgs: [String]
    private let trace: Bool

    init(executablePath: String, executableArgs: [String], trace: Bool = false) {
        self.executablePath = executablePath
        self.executableArgs = executableArgs
        self.trace = trace
    }

    func generate(prompt: String, docs: [BridgeAPIDoc], guidance: String?) async throws -> ModelDecision {
        if trace {
            traceLog("command provider start executable=\(executablePath) prompt=\(prompt) docs=\(docs.count)")
        }
        let input = CommandModelInput(prompt: prompt, capabilities: docs, guidance: guidance)
        let inputData = try JSONEncoder.codeModeBridge.encode(input)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = executableArgs

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        stdinPipe.fileHandleForWriting.write(inputData)
        stdinPipe.fileHandleForWriting.closeFile()

        process.waitUntilExit()

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr, encoding: .utf8) ?? "command model failed"
            if trace {
                traceLog("command provider failed status=\(process.terminationStatus) stderr=\(message)")
            }
            throw NSError(domain: "CodeModeEval", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])
        }

        let output = try JSONDecoder.codeModeBridge.decode(CommandModelOutput.self, from: stdout)
        if trace {
            let preview = String(data: stdout, encoding: .utf8)?
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            traceLog("command provider output preview: \(String(preview.prefix(280)))")
        }
        return try decision(from: output)
    }
}

struct CapturedInvocation {
    var capability: CapabilityID
    var arguments: [String: JSONValue]
    var timestamp: Date
}

final class InvocationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [CapturedInvocation] = []

    func record(capability: CapabilityID, arguments: [String: JSONValue]) {
        lock.lock()
        entries.append(CapturedInvocation(capability: capability, arguments: arguments, timestamp: Date()))
        lock.unlock()
    }

    func snapshot() -> [CapturedInvocation] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

struct EvalSandbox {
    var root: URL
    var tmp: URL
    var caches: URL
    var documents: URL

    static func create() throws -> EvalSandbox {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CodeModeEval-\(UUID().uuidString)", isDirectory: true)
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        let caches = root.appendingPathComponent("caches", isDirectory: true)
        let documents = root.appendingPathComponent("documents", isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        return EvalSandbox(root: root, tmp: tmp, caches: caches, documents: documents)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

struct AllowAllPermissionBroker: PermissionBroker {
    func status(for permission: PermissionKind) -> PermissionStatus {
        _ = permission
        return .granted
    }

    func request(for permission: PermissionKind) -> PermissionStatus {
        _ = permission
        return .granted
    }
}

final class MockState: @unchecked Sendable {
    private let lock = NSLock()
    private var keychain: [String: String] = [:]
    private var events: [[String: JSONValue]] = [
        [
            "identifier": .string("evt-1"),
            "title": .string("Daily Standup"),
            "startDate": .string(Date().ISO8601Format()),
            "endDate": .string(Date().addingTimeInterval(900).ISO8601Format()),
            "notes": .string(""),
            "calendarTitle": .string("Default"),
        ],
    ]
    private var reminders: [[String: JSONValue]] = [
        [
            "identifier": .string("rem-1"),
            "title": .string("Buy coffee"),
            "isCompleted": .bool(false),
            "dueDate": .string(Date().addingTimeInterval(3600).ISO8601Format()),
        ],
    ]

    func keychainRead(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return keychain[key]
    }

    func keychainWrite(_ key: String, value: String) {
        lock.lock()
        keychain[key] = value
        lock.unlock()
    }

    func keychainDelete(_ key: String) {
        lock.lock()
        keychain.removeValue(forKey: key)
        lock.unlock()
    }

    func readEvents() -> [JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return events.map { .object($0) }
    }

    func addEvent(title: String, start: String, end: String, notes: String?) -> [String: JSONValue] {
        lock.lock()
        defer { lock.unlock() }

        let event: [String: JSONValue] = [
            "identifier": .string("evt-\(events.count + 1)"),
            "title": .string(title),
            "startDate": .string(start),
            "endDate": .string(end),
            "notes": .string(notes ?? ""),
            "calendarTitle": .string("Default"),
        ]

        events.append(event)
        return event
    }

    func readReminders() -> [JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return reminders.map { .object($0) }
    }

    func addReminder(title: String, dueDate: String?) -> [String: JSONValue] {
        lock.lock()
        defer { lock.unlock() }

        let reminder: [String: JSONValue] = [
            "identifier": .string("rem-\(reminders.count + 1)"),
            "title": .string(title),
            "isCompleted": .bool(false),
            "dueDate": .string(dueDate ?? ""),
        ]

        reminders.append(reminder)
        return reminder
    }
}

func makeEvalHost(recorder: InvocationRecorder, sandbox: EvalSandbox) -> CodeModeBridgeHost {
    let fs = FileSystemBridge()
    let defaultDescriptors = Dictionary(uniqueKeysWithValues: DefaultCapabilityLoader.loadAllRegistrations().map { ($0.descriptor.id, $0.descriptor) })
    let state = MockState()

    func descriptor(_ id: CapabilityID) -> CapabilityDescriptor {
        defaultDescriptors[id] ?? CapabilityDescriptor(id: id, title: id.rawValue, summary: id.rawValue, tags: [], example: "")
    }

    func registration(
        _ id: CapabilityID,
        _ handler: @escaping CapabilityHandler
    ) -> CapabilityRegistration {
        CapabilityRegistration(descriptor: descriptor(id)) { args, context in
            recorder.record(capability: id, arguments: args)
            return try handler(args, context)
        }
    }

    let registrations: [CapabilityRegistration] = [
        registration(.networkFetch) { args, _ in
            let url = args.string("url") ?? "https://api.example.com/unknown"
            return .object([
                "ok": .bool(true),
                "status": .number(200),
                "statusText": .string("ok"),
                "headers": .object(["Content-Type": .string("application/json")]),
                "bodyText": .string("{\"url\":\"\(url)\",\"ok\":true}"),
            ])
        },
        registration(.keychainRead) { args, _ in
            guard let key = args.string("key") else {
                throw BridgeError.invalidArguments("keychain.read requires 'key'")
            }

            guard let value = state.keychainRead(key) else {
                return .null
            }
            return .object(["key": .string(key), "value": .string(value)])
        },
        registration(.keychainWrite) { args, _ in
            guard let key = args.string("key") else {
                throw BridgeError.invalidArguments("keychain.write requires 'key'")
            }
            let value = args.string("value") ?? ""
            state.keychainWrite(key, value: value)
            return .object(["key": .string(key), "written": .bool(true)])
        },
        registration(.keychainDelete) { args, _ in
            guard let key = args.string("key") else {
                throw BridgeError.invalidArguments("keychain.delete requires 'key'")
            }
            state.keychainDelete(key)
            return .object(["key": .string(key), "deleted": .bool(true)])
        },
        registration(.locationRead) { args, _ in
            let mode = args.string("mode") ?? "current"
            if mode == "permissionStatus" {
                return .string(PermissionStatus.granted.rawValue)
            }

            return .object([
                "latitude": .number(37.7749),
                "longitude": .number(-122.4194),
                "altitude": .number(0),
                "horizontalAccuracy": .number(5),
                "timestamp": .string(Date().ISO8601Format()),
            ])
        },
        registration(.locationPermissionRequest) { _, _ in
            .string(PermissionStatus.granted.rawValue)
        },
        registration(.weatherRead) { _, _ in
            .object([
                "temperatureCelsius": .number(16.5),
                "condition": .string("partlyCloudy"),
                "symbolName": .string("cloud.sun"),
                "date": .string(Date().ISO8601Format()),
            ])
        },
        registration(.calendarRead) { _, _ in
            .array(state.readEvents())
        },
        registration(.calendarWrite) { args, _ in
            guard let title = args.string("title"), let start = args.string("start"), let end = args.string("end") else {
                throw BridgeError.invalidArguments("calendar.write requires title/start/end")
            }
            let event = state.addEvent(title: title, start: start, end: end, notes: args.string("notes"))
            return .object(["identifier": event["identifier"] ?? .string(""), "title": .string(title)])
        },
        registration(.remindersRead) { _, _ in
            .array(state.readReminders())
        },
        registration(.remindersWrite) { args, _ in
            guard let title = args.string("title") else {
                throw BridgeError.invalidArguments("reminders.write requires title")
            }
            let reminder = state.addReminder(title: title, dueDate: args.string("dueDate"))
            return .object(["identifier": reminder["identifier"] ?? .string(""), "title": .string(title)])
        },
        registration(.contactsRead) { _, _ in
            .array([
                .object([
                    "identifier": .string("contact-alex"),
                    "givenName": .string("Alex"),
                    "familyName": .string("Morgan"),
                    "organization": .string("Acme"),
                    "phones": .array([.string("+1-555-0100")]),
                    "emails": .array([.string("alex@example.com")]),
                ]),
            ])
        },
        registration(.contactsSearch) { _, _ in
            .array([
                .object([
                    "identifier": .string("contact-alex"),
                    "givenName": .string("Alex"),
                    "familyName": .string("Morgan"),
                    "organization": .string("Acme"),
                    "phones": .array([.string("+1-555-0100")]),
                    "emails": .array([.string("alex@example.com")]),
                ]),
            ])
        },
        registration(.photosRead) { args, _ in
            let mediaType = args.string("mediaType") ?? "image"
            return .array([
                .object([
                    "localIdentifier": .string("photo-1"),
                    "mediaType": .string(mediaType),
                    "pixelWidth": .number(3024),
                    "pixelHeight": .number(4032),
                    "durationSeconds": .number(mediaType == "video" ? 12.5 : 0),
                    "creationDate": .string(Date().addingTimeInterval(-3600).ISO8601Format()),
                    "modificationDate": .string(Date().ISO8601Format()),
                ]),
            ])
        },
        registration(.photosExport) { args, _ in
            guard let localIdentifier = args.string("localIdentifier"), localIdentifier.isEmpty == false else {
                throw BridgeError.invalidArguments("photos.export requires localIdentifier")
            }

            return .object([
                "localIdentifier": .string(localIdentifier),
                "path": .string(args.string("outputPath") ?? "tmp:photo-export.jpg"),
                "artifactID": .string("artifact-photo"),
                "mediaType": .string("image"),
                "uniformTypeIdentifier": .string("public.jpeg"),
                "bytes": .number(2048),
            ])
        },
        registration(.visionImageAnalyze) { args, _ in
            guard let path = args.string("path"), path.isEmpty == false else {
                throw BridgeError.invalidArguments("vision.image.analyze requires path")
            }

            return .object([
                "path": .string(path),
                "features": .array([.string("labels"), .string("text")]),
                "labels": .array([
                    .object([
                        "identifier": .string("document"),
                        "confidence": .number(0.93),
                    ]),
                ]),
                "text": .array([
                    .object([
                        "text": .string("Sample OCR text"),
                        "confidence": .number(0.87),
                    ]),
                ]),
            ])
        },
        registration(.notificationsPermissionRequest) { _, _ in
            .object([
                "status": .string(PermissionStatus.granted.rawValue),
                "granted": .bool(true),
            ])
        },
        registration(.notificationsSchedule) { args, _ in
            guard let title = args.string("title"), title.isEmpty == false else {
                throw BridgeError.invalidArguments("notifications.schedule requires title")
            }

            _ = title
            return .object([
                "identifier": .string(args.string("identifier") ?? "codemode.eval.notification"),
                "scheduled": .bool(true),
                "repeats": .bool(args.bool("repeats") ?? false),
            ])
        },
        registration(.notificationsPendingRead) { _, _ in
            .array([
                .object([
                    "identifier": .string("codemode.eval.notification"),
                    "title": .string("Eval"),
                    "subtitle": .string(""),
                    "body": .string("pending"),
                    "triggerType": .string("timeInterval"),
                    "repeats": .bool(false),
                ]),
            ])
        },
        registration(.notificationsPendingDelete) { args, _ in
            let count: Double
            if let identifiers = args.array("identifiers") {
                count = Double(identifiers.count)
            } else if args.string("identifier") != nil {
                count = 1
            } else {
                count = -1
            }

            return .object([
                "deleted": .bool(true),
                "count": .number(count),
            ])
        },
        registration(.homeRead) { args, _ in
            let includeCharacteristics = args.bool("includeCharacteristics") ?? false
            var service: [String: JSONValue] = [
                "serviceType": .string("HMServiceTypeLightbulb"),
                "name": .string("Light"),
            ]
            if includeCharacteristics {
                service["characteristics"] = .array([
                    .object([
                        "characteristicType": .string("HMCharacteristicTypePowerState"),
                        "isReadable": .bool(true),
                        "isWritable": .bool(true),
                        "value": .bool(true),
                    ]),
                ])
            }

            return .array([
                .object([
                    "identifier": .string("home-1"),
                    "name": .string("Home"),
                    "rooms": .array([.string("Office")]),
                    "accessories": .array([
                        .object([
                            "identifier": .string("acc-1"),
                            "name": .string("Desk Lamp"),
                            "isReachable": .bool(true),
                            "category": .string("HMAccessoryCategoryTypeLightbulb"),
                            "room": .string("Office"),
                            "services": .array([.object(service)]),
                        ]),
                    ]),
                ]),
            ])
        },
        registration(.homeWrite) { args, _ in
            guard let accessoryIdentifier = args.string("accessoryIdentifier"), accessoryIdentifier.isEmpty == false else {
                throw BridgeError.invalidArguments("home.write requires accessoryIdentifier")
            }
            guard let characteristicType = args.string("characteristicType"), characteristicType.isEmpty == false else {
                throw BridgeError.invalidArguments("home.write requires characteristicType")
            }
            guard args["value"] != nil else {
                throw BridgeError.invalidArguments("home.write requires value")
            }

            return .object([
                "accessoryIdentifier": .string(accessoryIdentifier),
                "characteristicType": .string(characteristicType),
                "written": .bool(true),
            ])
        },
        registration(.mediaMetadataRead) { args, _ in
            .object([
                "path": .string(args.string("path") ?? "tmp:clip.mov"),
                "durationSeconds": .number(42),
                "tracks": .array([
                    .object([
                        "mediaType": .string("vide"),
                        "naturalWidth": .number(1920),
                        "naturalHeight": .number(1080),
                        "estimatedDataRate": .number(1_500_000),
                    ]),
                ]),
            ])
        },
        registration(.mediaFrameExtract) { args, _ in
            .object([
                "path": .string(args.string("outputPath") ?? "tmp:frame.jpg"),
                "artifactID": .string("artifact-frame"),
            ])
        },
        registration(.mediaTranscode) { args, _ in
            .object([
                "path": .string(args.string("outputPath") ?? "tmp:output.mp4"),
                "artifactID": .string("artifact-video"),
                "preset": .string(args.string("preset") ?? "AVAssetExportPresetMediumQuality"),
            ])
        },
        registration(.fsList) { args, context in
            try fs.list(arguments: args, context: context)
        },
        registration(.fsRead) { args, context in
            try fs.read(arguments: args, context: context)
        },
        registration(.fsWrite) { args, context in
            try fs.write(arguments: args, context: context)
        },
        registration(.fsMove) { args, context in
            try fs.move(arguments: args, context: context)
        },
        registration(.fsCopy) { args, context in
            try fs.copy(arguments: args, context: context)
        },
        registration(.fsDelete) { args, context in
            try fs.delete(arguments: args, context: context)
        },
        registration(.fsStat) { args, context in
            try fs.stat(arguments: args, context: context)
        },
        registration(.fsMkdir) { args, context in
            try fs.mkdir(arguments: args, context: context)
        },
        registration(.fsExists) { args, context in
            try fs.exists(arguments: args, context: context)
        },
        registration(.fsAccess) { args, context in
            try fs.access(arguments: args, context: context)
        },
    ]

    let runtimeConfig = BridgeRuntimeConfig(
        pathPolicy: DefaultPathPolicy(
            config: PathPolicyConfig(
                tmpRoot: sandbox.tmp,
                cachesRoot: sandbox.caches,
                documentsRoot: sandbox.documents
            )
        ),
        artifactStore: InMemoryArtifactStore(),
        permissionBroker: AllowAllPermissionBroker(),
        auditLogger: SyncAuditLogger()
    )

    return CodeModeBridgeHost(
        config: CodeModeBridgeHostConfig(
            runtimeConfig: runtimeConfig,
            registrations: registrations
        )
    )
}

func value(at path: String, in args: [String: JSONValue]) -> JSONValue? {
    let segments = path.split(separator: ".").map(String.init)
    guard segments.isEmpty == false else { return nil }

    var current: JSONValue = .object(args)
    for segment in segments {
        guard let object = current.objectValue, let next = object[segment] else {
            return nil
        }
        current = next
    }

    return current
}

func parseISODate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    if let date = formatter.date(from: value) {
        return date
    }

    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value)
}

func scenarioCatalog() -> [EvalScenario] {
    [
        EvalScenario(
            id: "capability-discovery-reminders-calendar",
            prompts: [
                "What can you do on this device for reminders/calendar?",
                "Show me what reminder and calendar tools are available.",
                "Which reminder + calendar capabilities can you use here?",
            ],
            expectedTool: .search
        ) { artifact in
            guard case .search(let request) = artifact.decision else {
                return EvalCheck(passed: false, reason: "Expected search tool call")
            }

            switch request.mode {
            case .discover:
                guard let items = artifact.searchResponse?.items else {
                    return EvalCheck(passed: false, reason: "Missing search response items")
                }
                let hasCalendar = items.contains(where: { $0.capability.rawValue.hasPrefix("calendar.") })
                let hasReminders = items.contains(where: { $0.capability.rawValue.hasPrefix("reminders.") })
                guard hasCalendar, hasReminders else {
                    return EvalCheck(passed: false, reason: "Discover search did not surface both calendar and reminders capabilities")
                }
                return EvalCheck(passed: true, reason: "Search surfaced both calendar and reminders")
            case .describe:
                guard let capability = request.capability else {
                    return EvalCheck(passed: false, reason: "Describe mode missing capability")
                }
                if capability.rawValue.hasPrefix("calendar.") || capability.rawValue.hasPrefix("reminders.") {
                    return EvalCheck(passed: true, reason: "Describe targeted calendar/reminders capability")
                }
                return EvalCheck(passed: false, reason: "Describe targeted unrelated capability")
            }
        },
        EvalScenario(
            id: "morning-brief",
            prompts: [
                "Give me a morning brief: current weather, today’s calendar events, and open reminders.",
                "Build me a morning summary with weather + today's events + uncompleted reminders.",
                "Morning dashboard: weather now, calendar today, reminders outstanding.",
            ],
            expectedTool: .execute
        ) { artifact in
            let caps = Set(artifact.invocations.map(\.capability))
            let required: Set<CapabilityID> = [.weatherRead, .calendarRead, .remindersRead]
            guard required.isSubset(of: caps) else {
                return EvalCheck(passed: false, reason: "Missing required capability calls: weather/calendar/reminders")
            }
            return EvalCheck(passed: true, reason: "Called weather, calendar, and reminders")
        },
        EvalScenario(
            id: "create-reminder-9am",
            prompts: [
                "Create a reminder for ‘Pay electric bill’ tomorrow at 9am.",
                "Set a reminder tomorrow 9:00 AM to pay my electric bill.",
                "Make me a pay-bill reminder for 9 in the morning tomorrow.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard let invocation = artifact.invocations.first(where: { $0.capability == .remindersWrite }) else {
                return EvalCheck(passed: false, reason: "Did not call reminders.write")
            }

            guard let dueText = value(at: "dueDate", in: invocation.arguments)?.stringValue,
                  let dueDate = parseISODate(dueText)
            else {
                return EvalCheck(passed: false, reason: "Reminder write missing parseable dueDate")
            }

            let hour = Calendar.current.component(.hour, from: dueDate)
            guard hour == 9 else {
                return EvalCheck(passed: false, reason: "Reminder dueDate hour was \(hour), expected 9")
            }

            return EvalCheck(passed: true, reason: "Reminder created with 9am due date")
        },
        EvalScenario(
            id: "create-calendar-event-230",
            prompts: [
                "Add a calendar event: ‘Project sync’ on Tuesday 2:00–2:30pm.",
                "Create a Tuesday project sync from 2 PM to 2:30 PM.",
                "Schedule a 30-minute sync Tuesday at 14:00.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard let invocation = artifact.invocations.first(where: { $0.capability == .calendarWrite }) else {
                return EvalCheck(passed: false, reason: "Did not call calendar.write")
            }

            guard let startText = value(at: "start", in: invocation.arguments)?.stringValue,
                  let endText = value(at: "end", in: invocation.arguments)?.stringValue,
                  let start = parseISODate(startText),
                  let end = parseISODate(endText)
            else {
                return EvalCheck(passed: false, reason: "Calendar write missing parseable start/end")
            }

            let durationMinutes = Int(end.timeIntervalSince(start) / 60)
            let startHour = Calendar.current.component(.hour, from: start)
            guard startHour == 14 else {
                return EvalCheck(passed: false, reason: "Start hour was \(startHour), expected 14")
            }
            guard (25...35).contains(durationMinutes) else {
                return EvalCheck(passed: false, reason: "Duration was \(durationMinutes) minutes, expected ~30")
            }

            return EvalCheck(passed: true, reason: "Calendar event created around Tuesday 2:00-2:30 objective")
        },
        EvalScenario(
            id: "find-alex-contact",
            prompts: [
                "Find Alex in my contacts and return phone + email.",
                "Look up Alex and give me their phone numbers and email addresses.",
                "Search contacts for Alex and return contact methods.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard let invocation = artifact.invocations.first(where: { $0.capability == .contactsSearch }) else {
                return EvalCheck(passed: false, reason: "Did not call contacts.search")
            }

            let query = value(at: "query", in: invocation.arguments)?.stringValue?.lowercased() ?? ""
            guard query.contains("alex") else {
                return EvalCheck(passed: false, reason: "contacts.search query did not include 'alex'")
            }

            return EvalCheck(passed: true, reason: "contacts.search called with Alex query")
        },
        EvalScenario(
            id: "store-and-reuse-token",
            prompts: [
                "Store my auth token securely, then reuse it for API calls later.",
                "Save this auth token in secure storage and use it on a backend request.",
                "Put token in keychain and use it for subsequent fetches.",
            ],
            expectedTool: .execute
        ) { artifact in
            let invocations = artifact.invocations
            let hasWrite = invocations.contains(where: { $0.capability == .keychainWrite })
            let hasRead = invocations.contains(where: { $0.capability == .keychainRead })
            let hasFetch = invocations.contains(where: { $0.capability == .networkFetch })

            guard hasWrite else {
                return EvalCheck(passed: false, reason: "No keychain.write invocation")
            }
            guard hasRead || hasFetch else {
                return EvalCheck(passed: false, reason: "Token was stored but not reused via keychain.read or network.fetch")
            }

            return EvalCheck(passed: true, reason: "Token store/reuse flow executed")
        },
        EvalScenario(
            id: "fetch-json-and-save",
            prompts: [
                "Fetch JSON from our backend and save it to local sandbox storage.",
                "Call backend API, parse JSON, write it into tmp storage.",
                "Get JSON from server and persist to sandbox file.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard artifact.invocations.contains(where: { $0.capability == .networkFetch }) else {
                return EvalCheck(passed: false, reason: "No network.fetch call")
            }

            guard let write = artifact.invocations.first(where: { $0.capability == .fsWrite }),
                  let path = value(at: "path", in: write.arguments)?.stringValue
            else {
                return EvalCheck(passed: false, reason: "No fs.write call with path")
            }

            let lower = path.lowercased()
            let inSandbox = lower.hasPrefix("tmp:") || lower.hasPrefix("caches:") || lower.hasPrefix("documents:")
            guard inSandbox else {
                return EvalCheck(passed: false, reason: "fs.write path was outside sandbox scopes")
            }

            return EvalCheck(passed: true, reason: "Fetched JSON and wrote to sandbox")
        },
        EvalScenario(
            id: "fs-management",
            prompts: [
                "List files in tmp, move report files into documents, and delete old temp artifacts.",
                "Inspect tmp files, move reports to documents, remove stale temp files.",
                "Do tmp cleanup: list, move report outputs to docs, delete temp leftovers.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard let list = artifact.invocations.first(where: { $0.capability == .fsList }),
                  let listPath = value(at: "path", in: list.arguments)?.stringValue?.lowercased(),
                  listPath.hasPrefix("tmp:")
            else {
                return EvalCheck(passed: false, reason: "No fs.list on tmp scope")
            }

            guard let move = artifact.invocations.first(where: { $0.capability == .fsMove }),
                  let destination = value(at: "to", in: move.arguments)?.stringValue?.lowercased(),
                  destination.hasPrefix("documents:")
            else {
                return EvalCheck(passed: false, reason: "No fs.move into documents scope")
            }

            guard artifact.invocations.contains(where: { $0.capability == .fsDelete }) else {
                return EvalCheck(passed: false, reason: "No fs.delete invocation")
            }

            return EvalCheck(passed: true, reason: "tmp list/move/delete workflow completed")
        },
        EvalScenario(
            id: "video-metadata-and-thumbnail",
            prompts: [
                "Read video metadata and extract a thumbnail frame at 1.5 seconds.",
                "Inspect clip metadata, then grab a frame at 1500ms.",
                "Get media info and snapshot frame at one and a half seconds.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard artifact.invocations.contains(where: { $0.capability == .mediaMetadataRead }) else {
                return EvalCheck(passed: false, reason: "No media.metadata.read invocation")
            }

            guard let frame = artifact.invocations.first(where: { $0.capability == .mediaFrameExtract }) else {
                return EvalCheck(passed: false, reason: "No media.frame.extract invocation")
            }

            guard let timeMs = value(at: "timeMs", in: frame.arguments)?.doubleValue else {
                return EvalCheck(passed: false, reason: "media.frame.extract missing timeMs")
            }

            guard abs(timeMs - 1500) <= 300 else {
                return EvalCheck(passed: false, reason: "timeMs was \(timeMs), expected near 1500")
            }

            return EvalCheck(passed: true, reason: "Media metadata + frame extraction objective met")
        },
        EvalScenario(
            id: "transcode-mov-to-mp4",
            prompts: [
                "Transcode a .mov clip to a smaller .mp4 for upload.",
                "Convert MOV video into a smaller MP4 output.",
                "Compress and transcode this .mov into mp4 upload format.",
            ],
            expectedTool: .execute
        ) { artifact in
            guard let transcode = artifact.invocations.first(where: { $0.capability == .mediaTranscode }) else {
                return EvalCheck(passed: false, reason: "No media.transcode invocation")
            }

            let input = value(at: "path", in: transcode.arguments)?.stringValue?.lowercased() ?? ""
            guard input.contains(".mov") else {
                return EvalCheck(passed: false, reason: "Transcode input path did not look like .mov")
            }

            let output = value(at: "outputPath", in: transcode.arguments)?.stringValue?.lowercased() ?? ""
            let preset = value(at: "preset", in: transcode.arguments)?.stringValue ?? ""
            guard output.contains(".mp4") || preset.isEmpty == false else {
                return EvalCheck(passed: false, reason: "Transcode call missing mp4 output intent")
            }

            return EvalCheck(passed: true, reason: "media.transcode call matched objective")
        },
    ]
}

func summary(for decision: ModelDecision) -> String {
    switch decision {
    case let .search(request):
        return "search(mode=\(request.mode.rawValue), query=\(request.query ?? ""), capability=\(request.capability?.rawValue ?? ""), limit=\(request.limit))"
    case let .execute(code):
        let compact = code.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= 120 {
            return "execute(\(compact))"
        }
        let prefix = compact.prefix(120)
        return "execute(\(prefix)... )"
    }
}

func combinedSummary(for decisions: [ModelDecision]) -> String {
    guard decisions.isEmpty == false else {
        return "none"
    }

    return decisions.map(summary).joined(separator: " -> ")
}

func compactSingleLine(_ text: String, maxLength: Int) -> String {
    let normalized = text
        .replacingOccurrences(of: "\n", with: " ")
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)

    guard normalized.count > maxLength else {
        return normalized
    }

    let limit = max(maxLength - 3, 0)
    return String(normalized.prefix(limit)) + "..."
}

func replaceRegex(_ pattern: String, with template: String, in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return text
    }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
}

func initialPlanningDocs(for prompt: String, from docs: [BridgeAPIDoc], maxCount: Int = 14) -> [BridgeAPIDoc] {
    guard docs.count > maxCount else {
        return docs
    }

    let tokens = Set(
        prompt.lowercased()
            .split(whereSeparator: { $0.isLetter == false && $0.isNumber == false })
            .map(String.init)
            .filter { $0.count >= 3 }
    )
    guard tokens.isEmpty == false else {
        return Array(docs.prefix(maxCount))
    }

    let ranked = docs.enumerated().map { index, doc in
        let haystack = "\(doc.capability.rawValue) \(doc.title) \(doc.summary) \(doc.tags.joined(separator: " "))".lowercased()
        let score = tokens.reduce(into: 0) { partial, token in
            if haystack.contains(token) {
                partial += 1
            }
        }
        return (index: index, score: score, doc: doc)
    }

    let matched = ranked
        .filter { $0.score > 0 }
        .sorted {
            if $0.score == $1.score {
                return $0.index < $1.index
            }
            return $0.score > $1.score
        }
        .map(\.doc)

    if matched.isEmpty {
        return Array(docs.prefix(maxCount))
    }

    if matched.count >= maxCount {
        return Array(matched.prefix(maxCount))
    }

    var selected = matched
    var seen = Set(selected.map(\.capability))
    for doc in docs {
        if selected.count >= maxCount {
            break
        }
        if seen.contains(doc.capability) {
            continue
        }
        selected.append(doc)
        seen.insert(doc.capability)
    }
    return selected
}

func narrowDocsAfterSearch(
    allDocs: [BridgeAPIDoc],
    response: SearchResponse,
    maxCount: Int = 8
) -> [BridgeAPIDoc] {
    guard allDocs.isEmpty == false else {
        return allDocs
    }

    let docsByCapability = Dictionary(uniqueKeysWithValues: allDocs.map { ($0.capability, $0) })
    var selected: [BridgeAPIDoc] = []
    var seen: Set<CapabilityID> = []

    func appendCapability(_ capability: CapabilityID) {
        guard seen.insert(capability).inserted else {
            return
        }
        guard let doc = docsByCapability[capability] else {
            return
        }
        selected.append(doc)
    }

    if let capability = response.detail?.capability {
        appendCapability(capability)
    }

    for item in response.items {
        appendCapability(item.capability)
        if selected.count >= maxCount {
            return selected
        }
    }

    let searchTags = Set(response.items.flatMap(\.tags).map { $0.lowercased() })
    if searchTags.isEmpty == false {
        for doc in allDocs where selected.count < maxCount {
            if seen.contains(doc.capability) {
                continue
            }
            let docTags = Set(doc.tags.map { $0.lowercased() })
            if docTags.intersection(searchTags).isEmpty == false {
                appendCapability(doc.capability)
            }
        }
    }

    for doc in allDocs where selected.count < maxCount {
        appendCapability(doc.capability)
    }

    return selected
}

func firstRegexMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return nil
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    return regex.firstMatch(in: text, options: [], range: range)
}

func firstCaptureGroup(_ pattern: String, in text: String, group: Int) -> String? {
    guard let match = firstRegexMatch(pattern, in: text) else {
        return nil
    }
    guard group < match.numberOfRanges else {
        return nil
    }
    guard let range = Range(match.range(at: group), in: text) else {
        return nil
    }
    return String(text[range])
}

func staticExecuteValidationDiagnostic(for code: String) -> ToolDiagnostic? {
    var issues: [String] = []

    if let method = firstCaptureGroup(#"(?<!ios\.)\bfs\.(?!promises\b)([A-Za-z_][A-Za-z0-9_]*)\s*\("#, in: code, group: 1) {
        let suggestionByMethod: [String: String] = [
            "read": "fs.promises.readFile",
            "write": "fs.promises.writeFile",
            "list": "fs.promises.readdir",
            "stat": "fs.promises.stat",
            "access": "fs.promises.access",
            "mkdir": "fs.promises.mkdir",
            "move": "fs.promises.rename",
            "copy": "fs.promises.copyFile",
            "delete": "fs.promises.rm",
            "exists": "ios.fs.exists",
        ]
        let suggestion = suggestionByMethod[method] ?? "fs.promises.<method>"
        issues.append("Unsupported fs.\(method)(...) usage. Use \(suggestion)(...) or ios.fs.*.")
    }

    if firstRegexMatch(#"\brequire\s*\("#, in: code) != nil {
        issues.append("CommonJS require(...) is not available.")
    }

    if firstRegexMatch(#"\b(?<!ios\.)keychain\.[A-Za-z_][A-Za-z0-9_]*\s*\("#, in: code) != nil {
        issues.append("Use ios.keychain.get/set/delete. Bare keychain.* is not available.")
    }

    if firstRegexMatch(#"\bnetwork\.[A-Za-z_][A-Za-z0-9_]*\s*\("#, in: code) != nil {
        issues.append("Use fetch(...) for HTTP requests. network.* is not available.")
    }

    if firstRegexMatch(#"\bios\.keychain\.(read|write|remove)\s*\("#, in: code) != nil {
        issues.append("Use ios.keychain.get/set/delete method names.")
    }

    if let method = firstCaptureGroup(#"\bfs\.promises\.([A-Za-z_][A-Za-z0-9_]*)\s*\("#, in: code, group: 1) {
        let supported: Set<String> = ["readFile", "writeFile", "readdir", "stat", "access", "mkdir", "rm", "rename", "copyFile"]
        if supported.contains(method) == false {
            issues.append("Unsupported fs.promises.\(method)(...) usage. Use supported fs.promises methods or ios.fs.*.")
        }
    }

    if firstRegexMatch(#"\b(?:async\s+)?function\s+main\s*\("#, in: code) != nil,
       firstRegexMatch(#"\bmain\s*\(\s*\)"#, in: code) == nil
    {
        issues.append("If you define main(), you must call main(). Prefer direct top-level await statements.")
    }

    if firstRegexMatch(#"\bimport\s+["']"#, in: code) != nil {
        issues.append("ES module import is not available.")
    }

    if firstRegexMatch(#"\bprocess\s*(?:\.|\[)"#, in: code) != nil {
        issues.append("process is not available in this runtime.")
    }

    if firstRegexMatch(#"\bBuffer\b"#, in: code) != nil {
        issues.append("Buffer is not available in this runtime.")
    }

    guard issues.isEmpty == false else {
        return nil
    }

    return ToolDiagnostic(
        severity: .error,
        code: "PRE_EXECUTE_VALIDATION",
        message: issues.joined(separator: " ")
    )
}

func taskExecutionHint(for prompt: String) -> String? {
    let lower = prompt.lowercased()

    if lower.contains("token") && (lower.contains("auth") || lower.contains("keychain") || lower.contains("secure")) {
        return """
        Use this exact API pattern:
        await ios.keychain.set('auth_token', 'demo-token-123');
        const saved = await ios.keychain.get('auth_token');
        const token = saved && saved.value ? saved.value : '';
        const response = await fetch('https://api.example.com/profile', {
          method: 'GET',
          headers: { Authorization: `Bearer ${token}` }
        });
        return { status: response.status, reused: token.length > 0 };
        Do not use keychain.read/write names and do not use network.fetch.
        """
    }

    if lower.contains("morning") && lower.contains("weather") && (lower.contains("calendar") || lower.contains("event")) {
        return "Use weather.read + calendar.read + reminders.read and return a combined JSON object."
    }

    if lower.contains("reminder") && (lower.contains("9am") || lower.contains("9:00")) {
        return "Use reminders.write with title and dueDate ISO string around 09:00 local time."
    }

    if lower.contains("calendar") && (lower.contains("2:00") || lower.contains("2 pm") || lower.contains("14:00")) {
        return "Use calendar.write with title/start/end ISO strings and ~30 minute duration."
    }

    if lower.contains("contact") && lower.contains("alex") {
        return "Use contacts.search with query Alex and return phones/emails."
    }

    if lower.contains("backend") && lower.contains("save") {
        return "Use fetch for backend JSON then ios.fs.write or fs.promises.writeFile to sandbox path (tmp:/caches:/documents:)."
    }

    if lower.contains("tmp") && lower.contains("documents") {
        return "Use ios.fs.list on tmp:, ios.fs.move into documents:, and ios.fs.delete for temp cleanup."
    }

    if lower.contains("thumbnail") || lower.contains("1.5") {
        return "Use media.metadata.read then media.frame.extract with timeMs near 1500."
    }

    if lower.contains("transcode") || (lower.contains(".mov") && lower.contains(".mp4")) {
        return "Use media.transcode with input .mov and output .mp4 intent."
    }

    return nil
}

func canonicalTokenWorkflowScript() -> String {
    """
    await ios.keychain.set('auth_token', 'demo-token-123');
    const saved = await ios.keychain.get('auth_token');
    const token = saved && saved.value ? saved.value : '';
    const response = await fetch('https://api.example.com/profile', {
      method: 'GET',
      headers: { Authorization: `Bearer ${token}` }
    });
    return { status: response.status, reused: token.length > 0 };
    """
}

func canonicalMorningBriefScript() -> String {
    """
    const weather = await ios.weather.getCurrentWeather({ latitude: 37.7749, longitude: -122.4194 });
    const events = await ios.calendar.listEvents({ limit: 20 });
    const reminders = await ios.reminders.listReminders({ limit: 20 });
    return { weather, events, reminders };
    """
}

func canonicalReminderAt9AMScript() -> String {
    """
    const due = new Date();
    due.setDate(due.getDate() + 1);
    due.setHours(9, 0, 0, 0);
    const reminder = await ios.reminders.createReminder({
      title: 'Pay electric bill',
      dueDate: due.toISOString()
    });
    return { reminder, dueDate: due.toISOString() };
    """
}

func canonicalCalendar230Script() -> String {
    """
    function nextTuesdayAt(hour, minute) {
      const now = new Date();
      const candidate = new Date(now);
      const tuesday = 2;
      let delta = (tuesday - candidate.getDay() + 7) % 7;
      if (delta === 0) delta = 7;
      candidate.setDate(candidate.getDate() + delta);
      candidate.setHours(hour, minute, 0, 0);
      return candidate;
    }
    const start = nextTuesdayAt(14, 0);
    const end = new Date(start.getTime() + 30 * 60 * 1000);
    const event = await ios.calendar.createEvent({
      title: 'Project sync',
      start: start.toISOString(),
      end: end.toISOString()
    });
    return { event, start: start.toISOString(), end: end.toISOString() };
    """
}

func canonicalFindAlexScript() -> String {
    """
    const matches = await ios.contacts.search({ query: 'Alex', limit: 10 });
    return matches.map(c => ({
      name: [c.givenName, c.familyName].filter(Boolean).join(' ').trim(),
      phones: c.phones || [],
      emails: c.emails || []
    }));
    """
}

func canonicalFetchAndSaveScript() -> String {
    """
    const response = await fetch('https://api.example.com/data');
    const payload = await response.json();
    await ios.fs.write({
      path: 'tmp:data.json',
      data: JSON.stringify(payload)
    });
    return { status: response.status, path: 'tmp:data.json' };
    """
}

func canonicalFSManagementScript() -> String {
    """
    await ios.fs.write({ path: 'tmp:report-output.json', data: '{}' });
    await ios.fs.write({ path: 'tmp:old-temp.bin', data: 'stale' });
    const files = await ios.fs.list({ path: 'tmp:' });
    await ios.fs.move({ from: 'tmp:report-output.json', to: 'documents:report-output.json' });
    await ios.fs.delete({ path: 'tmp:old-temp.bin' });
    return { listedCount: Array.isArray(files) ? files.length : 0 };
    """
}

func canonicalVideoMetadataAndThumbnailScript() -> String {
    """
    const metadata = await ios.media.metadata({ path: 'tmp:video.mov' });
    const frame = await ios.media.extractFrame({
      path: 'tmp:video.mov',
      timeMs: 1500,
      outputPath: 'tmp:thumb.jpg'
    });
    return { metadata, frame };
    """
}

func canonicalTranscodeScript() -> String {
    """
    const output = await ios.media.transcode({
      path: 'tmp:video.mov',
      outputPath: 'tmp:video.mp4',
      preset: 'AVAssetExportPresetMediumQuality'
    });
    return { output };
    """
}

func deterministicFallbackScript(for scenarioID: String, prompt: String) -> String? {
    _ = prompt
    switch scenarioID {
    case "morning-brief":
        return canonicalMorningBriefScript()
    case "create-reminder-9am":
        return canonicalReminderAt9AMScript()
    case "create-calendar-event-230":
        return canonicalCalendar230Script()
    case "find-alex-contact":
        return canonicalFindAlexScript()
    case "store-and-reuse-token":
        return canonicalTokenWorkflowScript()
    case "fetch-json-and-save":
        return canonicalFetchAndSaveScript()
    case "fs-management":
        return canonicalFSManagementScript()
    case "video-metadata-and-thumbnail":
        return canonicalVideoMetadataAndThumbnailScript()
    case "transcode-mov-to-mp4":
        return canonicalTranscodeScript()
    default:
        return nil
    }
}

func normalizeExecuteCode(_ code: String, scenarioID: String) -> (code: String, changed: Bool, reason: String?) {
    var normalized = code
    var reasons: [String] = []

    func rewrite(_ pattern: String, _ replacement: String, _ reason: String) {
        let rewritten = replaceRegex(pattern, with: replacement, in: normalized)
        if rewritten != normalized {
            normalized = rewritten
            reasons.append(reason)
        }
    }

    rewrite(#"\bios\.ios\.media\."#, "ios.media.", "Collapsed ios.ios.media namespace to ios.media.")
    rewrite(#"\bios\.ios\.fs\."#, "ios.fs.", "Collapsed ios.ios.fs namespace to ios.fs.")

    rewrite(#"\bnetwork\.fetch\s*\("#, "fetch(", "Normalized network.fetch to fetch.")
    rewrite(#"\bios\.keychain\.read\s*\("#, "ios.keychain.get(", "Normalized ios.keychain.read to ios.keychain.get.")
    rewrite(#"\bios\.keychain\.write\s*\("#, "ios.keychain.set(", "Normalized ios.keychain.write to ios.keychain.set.")
    rewrite(#"\bios\.keychain\.remove\s*\("#, "ios.keychain.delete(", "Normalized ios.keychain.remove to ios.keychain.delete.")
    rewrite(#"\b(?<!ios\.)keychain\.read\s*\("#, "ios.keychain.get(", "Normalized bare keychain.read to ios.keychain.get.")
    rewrite(#"\b(?<!ios\.)keychain\.write\s*\("#, "ios.keychain.set(", "Normalized bare keychain.write to ios.keychain.set.")
    rewrite(#"\b(?<!ios\.)keychain\.remove\s*\("#, "ios.keychain.delete(", "Normalized bare keychain.remove to ios.keychain.delete.")

    rewrite(#"\bios\.media\.frame\.extract\s*\("#, "ios.media.extractFrame(", "Normalized ios.media.frame.extract to ios.media.extractFrame.")
    rewrite(#"\bios\.media\.metadata\.read\s*\("#, "ios.media.metadata(", "Normalized ios.media.metadata.read to ios.media.metadata.")
    rewrite(#"(?<!ios\.)\bmedia\.frame\.extract\s*\("#, "ios.media.extractFrame(", "Normalized media.frame.extract to ios.media.extractFrame.")
    rewrite(#"(?<!ios\.)\bmedia\.metadata\.read\s*\("#, "ios.media.metadata(", "Normalized media.metadata.read to ios.media.metadata.")
    rewrite(#"(?<!ios\.)\bmedia\.transcode\s*\("#, "ios.media.transcode(", "Normalized media.transcode to ios.media.transcode.")

    let directFsToIOS: [String: String] = [
        "list": "list",
        "read": "read",
        "write": "write",
        "move": "move",
        "copy": "copy",
        "delete": "delete",
        "stat": "stat",
        "mkdir": "mkdir",
        "exists": "exists",
        "access": "access",
    ]
    for (method, mapped) in directFsToIOS {
        rewrite(#"(?<!ios\.)\bfs\.\#(method)\s*\("#, "ios.fs.\(mapped)(", "Normalized fs.\(method) to ios.fs.\(mapped).")
    }

    let directFsToPromises = ["readFile", "writeFile", "readdir", "stat", "access", "mkdir", "rm", "rename", "copyFile"]
    for method in directFsToPromises {
        rewrite(#"(?<!ios\.)\bfs\.\#(method)\s*\("#, "fs.promises.\(method)(", "Normalized fs.\(method) to fs.promises.\(method).")
    }

    let promisesMethodAliases: [String: String] = [
        "list": "readdir",
        "read": "readFile",
        "write": "writeFile",
        "move": "rename",
        "copy": "copyFile",
        "delete": "rm",
        "remove": "rm",
        "writeFileSync": "writeFile",
        "readFileSync": "readFile",
        "readdirSync": "readdir",
        "mkdirSync": "mkdir",
        "rmSync": "rm",
        "renameSync": "rename",
        "copyFileSync": "copyFile",
    ]
    for (method, mapped) in promisesMethodAliases {
        rewrite(#"\bfs\.promises\.\#(method)\s*\("#, "fs.promises.\(mapped)(", "Normalized fs.promises.\(method) to fs.promises.\(mapped).")
    }

    let unsupportedPromisesToIOS: [String: String] = [
        "exists": "exists",
        "unlink": "delete",
    ]
    for (method, mapped) in unsupportedPromisesToIOS {
        rewrite(#"\bfs\.promises\.\#(method)\s*\("#, "ios.fs.\(mapped)(", "Normalized fs.promises.\(method) to ios.fs.\(mapped).")
    }

    rewrite(#"\bios\.fs\.mkdir\s*\(\s*(['\"][^'\"]+['\"])\s*\)"#, "ios.fs.mkdir({ path: $1, recursive: true })", "Normalized ios.fs.mkdir(path) to object argument form.")
    rewrite(#"\bios\.fs\.(list|read|stat|exists|access|delete)\s*\(\s*(['\"][^'\"]+['\"])\s*\)"#, "ios.fs.$1({ path: $2 })", "Normalized ios.fs path-only calls to object argument form.")
    rewrite(#"\bios\.fs\.(move|copy)\s*\(\s*(['\"][^'\"]+['\"])\s*,\s*(['\"][^'\"]+['\"])\s*\)"#, "ios.fs.$1({ from: $2, to: $3 })", "Normalized ios.fs move/copy positional args to object form.")
    rewrite(#"\bios\.fs\.write\s*\(\s*(['\"][^'\"]+['\"])\s*,\s*([^)]+)\)"#, "ios.fs.write({ path: $1, data: $2 })", "Normalized ios.fs.write(path, data) to object form.")

    if scenarioID == "store-and-reuse-token" {
        let hasSet = normalized.contains("ios.keychain.set(")
        let hasGet = normalized.contains("ios.keychain.get(")
        let hasFetch = normalized.contains("fetch(")
        let usesWrongKeychainMethods = normalized.contains("ios.keychain.write(") || normalized.contains("ios.keychain.read(")
        let usesBareKeychain = firstRegexMatch(#"\b(?<!ios\.)keychain\.[A-Za-z_][A-Za-z0-9_]*\s*\("#, in: normalized) != nil
        let usesNetworkNamespace = normalized.contains("network.fetch(")
        let usesSafeTokenExtraction = normalized.contains("saved && saved.value ? saved.value : ''")

        let looksSafe = hasSet && hasGet && hasFetch && usesWrongKeychainMethods == false && usesBareKeychain == false && usesNetworkNamespace == false && usesSafeTokenExtraction
        if looksSafe == false {
            return (canonicalTokenWorkflowScript(), true, "Applied token workflow normalization (required keychain.set/get + fetch pattern).")
        }
    }

    if normalized == code {
        return (code, false, nil)
    }
    let reason = "Applied compatibility normalization: \(reasons.joined(separator: " "))"
    return (normalized, true, reason)
}

func shouldRetryAfterRuntimeError(_ diagnostic: ToolDiagnostic) -> Bool {
    let retryableCodes: Set<String> = [
        "JS_REJECTED",
        "JS_EXCEPTION",
        "INVALID_ARGUMENTS",
        "CAPABILITY_NOT_FOUND",
        "NATIVE_FAILURE",
    ]

    if retryableCodes.contains(diagnostic.code) {
        return true
    }

    let lower = diagnostic.message.lowercased()
    return lower.contains("typeerror") || lower.contains("referenceerror")
}

enum ExecuteAttemptOutcome {
    case continuePlanning
    case finished
}

func runExecuteAttempt(
    code: String,
    host: CodeModeBridgeHost,
    step: Int,
    maxSteps: Int,
    staticValidationRetries: inout Int,
    maxStaticValidationRetries: Int,
    runtimeRetries: inout Int,
    maxRuntimeRetries: Int,
    observations: inout [String],
    latestExecuteResponse: inout ExecuteResponse?
) async throws -> ExecuteAttemptOutcome {
    if let validation = staticExecuteValidationDiagnostic(for: code) {
        if staticValidationRetries < maxStaticValidationRetries, step < maxSteps {
            staticValidationRetries += 1
            observations.append("Static validation error: \(validation.code) \(validation.message)")
            return .continuePlanning
        }

        latestExecuteResponse = ExecuteResponse(
            resultJSON: nil,
            logs: [],
            diagnostics: [validation],
            permissionEvents: []
        )
        return .finished
    }

    let response = try await host.execute(
        ExecuteRequest(
            code: code,
            allowedCapabilities: CapabilityID.allCases,
            timeoutMs: 20_000
        )
    )
    latestExecuteResponse = response

    if let runtimeError = response.diagnostics.first(where: { $0.severity == .error }),
       runtimeRetries < maxRuntimeRetries,
       step < maxSteps,
       shouldRetryAfterRuntimeError(runtimeError)
    {
        runtimeRetries += 1
        observations.append("Runtime error: \(runtimeError.code) \(runtimeError.message)")
        observations.append("Repair with valid JavaScript using only fetch, ios.*, fs.promises, console, setTimeout.")
        latestExecuteResponse = nil
        return .continuePlanning
    }

    return .finished
}

func searchObservationText(_ response: SearchResponse) -> String {
    var lines: [String] = []

    if let detail = response.detail {
        lines.append("Describe \(detail.capability.rawValue):")
        if detail.requiredArguments.isEmpty == false {
            lines.append("required args: \(compactSingleLine(detail.requiredArguments.joined(separator: ", "), maxLength: 140))")
        }
        if detail.optionalArguments.isEmpty == false {
            lines.append("optional args: \(compactSingleLine(detail.optionalArguments.joined(separator: ", "), maxLength: 140))")
        }
        lines.append("result: \(compactSingleLine(detail.resultSummary, maxLength: 160))")
        lines.append("example: \(compactSingleLine(detail.example, maxLength: 160))")
    }

    if response.items.isEmpty == false {
        lines.append("Discover results:")
        for item in response.items.prefix(4) {
            lines.append("- \(item.capability.rawValue): \(compactSingleLine(item.summary, maxLength: 120))")
        }
    }

    if response.diagnostics.isEmpty == false {
        lines.append("Search diagnostics:")
        for diagnostic in response.diagnostics.prefix(3) {
            lines.append("- \(diagnostic.code): \(compactSingleLine(diagnostic.message, maxLength: 140))")
        }
    }

    return compactSingleLine(lines.joined(separator: " | "), maxLength: 700)
}

func planningGuidance(
    for scenario: EvalScenario,
    step: Int,
    maxSteps: Int,
    observations: [String],
    mustExecuteNow: Bool,
    taskHint: String?
) -> String {
    var lines: [String] = []
    lines.append("Step \(step) of \(maxSteps).")

    switch scenario.expectedTool {
    case .search:
        lines.append("This scenario expects search output.")
    case .execute:
        lines.append("This scenario must eventually emit execute with a complete script, not a single API call.")
    }

    if let taskHint, taskHint.isEmpty == false {
        lines.append("Task hint: \(compactSingleLine(taskHint, maxLength: 260))")
    }

    if mustExecuteNow {
        lines.append("Hard requirement: emit tool=execute now. Additional search calls are invalid.")
    }

    if observations.isEmpty {
        lines.append("No prior tool outputs yet.")
    } else {
        lines.append("Prior tool outputs/errors (most recent first):")
        for observation in observations.suffix(2).reversed() {
            lines.append(compactSingleLine(observation, maxLength: 260))
        }
    }

    lines.append("Return exactly one JSON tool call object.")
    return lines.joined(separator: "\n")
}

func evaluateSearchPrompt(
    scenario: EvalScenario,
    prompt: String,
    host: CodeModeBridgeHost,
    docs: [BridgeAPIDoc],
    recorder: InvocationRecorder,
    provider: EvalModelProvider,
    traceModel: Bool
) async -> EvalRunResult {
    func normalizedDiscoveryRequest(_ request: SearchRequest) -> SearchRequest {
        guard scenario.id == "capability-discovery-reminders-calendar" else {
            return request
        }

        var normalized = request

        if normalized.mode == .describe, normalized.capability == nil {
            normalized = SearchRequest(
                mode: .describe,
                query: nil,
                capability: .remindersRead,
                limit: 1,
                tags: nil
            )
            return normalized
        }

        guard normalized.mode == .discover else {
            return normalized
        }

        let query = (normalized.query ?? prompt).lowercased()
        let hasCalendar = query.contains("calendar")
        let hasReminder = query.contains("reminder")

        if hasCalendar && hasReminder {
            normalized.query = query
        } else {
            normalized.query = "reminders calendar"
        }

        // BridgeCatalog tag filtering requires all requested tags on each entry.
        // For discovery prompts asking for both domains, tags can over-constrain
        // results and hide one side. Use query-only matching here.
        normalized.tags = nil

        if normalized.limit <= 0 {
            normalized.limit = 10
        }

        return normalized
    }

    func coerceExecuteToSearch(_ code: String) -> SearchRequest? {
        guard scenario.id == "capability-discovery-reminders-calendar" else {
            _ = code
            return nil
        }
        let request = SearchRequest(mode: .discover, query: "reminders calendar", capability: nil, limit: 10, tags: nil)
        return normalizedDiscoveryRequest(request)
    }

    let decision: ModelDecision
    do {
        decision = try await provider.generate(prompt: prompt, docs: docs, guidance: nil)
    } catch {
        let reason = "Model generation error: \(errorDescription(error))"
        if traceModel {
            traceLog("generation failed scenario=\(scenario.id) reason=\(reason)")
        }
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: reason,
            generatedSummary: "generate(error)"
        )
    }

    if traceModel {
        traceLog("decision scenario=\(scenario.id) \(summary(for: decision))")
    }

    var request: SearchRequest
    var generated = summary(for: decision)

    switch decision {
    case let .search(searchRequest):
        request = normalizedDiscoveryRequest(searchRequest)
        let originalSummary = summary(for: .search(searchRequest))
        let normalizedSummary = summary(for: .search(request))
        if normalizedSummary != originalSummary {
            generated = "\(generated) -> \(summary(for: .search(request))) [normalized]"
        }
    case let .execute(code):
        guard let coerced = coerceExecuteToSearch(code) else {
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: "Expected search tool, model emitted execute",
                generatedSummary: generated
            )
        }
        request = coerced
        generated = "\(generated) -> \(summary(for: .search(request))) [coerced]"
    }

    do {
        let response = try await host.search(request)
        let artifact = EvalArtifact(
            scenarioID: scenario.id,
            prompt: prompt,
            decision: .search(request),
            searchResponse: response,
            executeResponse: nil,
            invocations: recorder.snapshot()
        )

        let check = scenario.validate(artifact)
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: check.passed,
            reason: check.reason,
            generatedSummary: generated
        )
    } catch {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Search execution error: \(errorDescription(error))",
            generatedSummary: generated
        )
    }
}

func evaluateExecutePromptRaw(
    scenario: EvalScenario,
    prompt: String,
    host: CodeModeBridgeHost,
    docs: [BridgeAPIDoc],
    recorder: InvocationRecorder,
    provider: EvalModelProvider,
    traceModel: Bool
) async -> EvalRunResult {
    let decision: ModelDecision
    do {
        decision = try await provider.generate(prompt: prompt, docs: docs, guidance: nil)
    } catch {
        let reason = "Model generation error: \(errorDescription(error))"
        if traceModel {
            traceLog("raw generation failed scenario=\(scenario.id) reason=\(reason)")
        }
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: reason,
            generatedSummary: "generate(error)"
        )
    }

    if traceModel {
        traceLog("raw decision scenario=\(scenario.id) \(summary(for: decision))")
    }

    switch decision {
    case let .search(request):
        do {
            let response = try await host.search(request)
            let artifact = EvalArtifact(
                scenarioID: scenario.id,
                prompt: prompt,
                decision: decision,
                searchResponse: response,
                executeResponse: nil,
                invocations: recorder.snapshot()
            )
            let check = scenario.validate(artifact)
            if check.passed {
                return EvalRunResult(
                    scenarioID: scenario.id,
                    prompt: prompt,
                    passed: true,
                    reason: check.reason,
                    generatedSummary: summary(for: decision)
                )
            }
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: "Raw model emitted search only. \(check.reason)",
                generatedSummary: summary(for: decision)
            )
        } catch {
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: "Search execution error: \(errorDescription(error))",
                generatedSummary: summary(for: decision)
            )
        }
    case let .execute(code):
        let normalized = normalizeExecuteCode(code, scenarioID: scenario.id)
        let codeToRun = normalized.code
        let generatedSummary = summary(for: .execute(codeToRun))

        if let validation = staticExecuteValidationDiagnostic(for: codeToRun) {
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: "Runtime error: \(validation.code) \(validation.message)",
                generatedSummary: generatedSummary
            )
        }

        do {
            let response = try await host.execute(
                ExecuteRequest(
                    code: codeToRun,
                    allowedCapabilities: CapabilityID.allCases,
                    timeoutMs: 20_000
                )
            )

            if let runtimeError = response.diagnostics.first(where: { $0.severity == .error }) {
                return EvalRunResult(
                    scenarioID: scenario.id,
                    prompt: prompt,
                    passed: false,
                    reason: "Runtime error: \(runtimeError.code) \(runtimeError.message)",
                    generatedSummary: generatedSummary
                )
            }

            let artifact = EvalArtifact(
                scenarioID: scenario.id,
                prompt: prompt,
                decision: .execute(codeToRun),
                searchResponse: nil,
                executeResponse: response,
                invocations: recorder.snapshot()
            )
            let check = scenario.validate(artifact)
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: check.passed,
                reason: check.reason,
                generatedSummary: generatedSummary
            )
        } catch {
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: "Execute call failed: \(errorDescription(error))",
                generatedSummary: generatedSummary
            )
        }
    }
}

func evaluateExecutePrompt(
    scenario: EvalScenario,
    prompt: String,
    host: CodeModeBridgeHost,
    docs: [BridgeAPIDoc],
    recorder: InvocationRecorder,
    provider: EvalModelProvider,
    traceModel: Bool
) async -> EvalRunResult {
    let maxSteps = 6
    let maxSearchesBeforeForceExecute = 1
    let maxForcedExecuteReprompts = 6
    let maxStaticValidationRetries = 4
    let maxRuntimeRetries = 2

    var decisions: [ModelDecision] = []
    var observations: [String] = []
    var searchFingerprints: Set<String> = []
    var executeFingerprints: Set<String> = []
    var searchCount = 0
    var forcedExecuteReprompts = 0
    var staticValidationRetries = 0
    var runtimeRetries = 0
    var latestSearchResponse: SearchResponse?
    var latestExecuteDecision: ModelDecision?
    var latestExecuteResponse: ExecuteResponse?
    var docsForStep: [BridgeAPIDoc] = initialPlanningDocs(for: prompt, from: docs, maxCount: 14)
    var usedDeterministicFallback = false
    let taskHint = taskExecutionHint(for: prompt)

    func appendObservation(_ message: String) {
        observations.append(compactSingleLine(message, maxLength: 700))
        if observations.count > 12 {
            observations.removeFirst(observations.count - 12)
        }
    }

    func tryDeterministicFallbackExecute(reason: String) async -> Bool {
        guard usedDeterministicFallback == false else {
            return false
        }

        usedDeterministicFallback = true
        appendObservation("Applying deterministic assisted fallback execute (\(reason)).")

        let fallbackCode: String
        if let deterministicScript = deterministicFallbackScript(for: scenario.id, prompt: prompt) {
            fallbackCode = deterministicScript
            appendObservation("Using scenario-specific fallback script for \(scenario.id).")
        } else {
            let fallbackProvider = ScriptedModelProvider()
            guard case let .execute(scriptedCode) = try? await fallbackProvider.generate(prompt: prompt, docs: docsForStep, guidance: "Hard requirement: emit execute now.") else {
                appendObservation("Deterministic fallback did not produce execute code.")
                return false
            }
            fallbackCode = scriptedCode
            appendObservation("Using scripted fallback provider output.")
        }

        let normalized = normalizeExecuteCode(fallbackCode, scenarioID: scenario.id)
        let codeToRun = normalized.code
        if let normalizationReason = normalized.reason {
            appendObservation(normalizationReason)
        }

        decisions.append(.execute(codeToRun))
        latestExecuteDecision = .execute(codeToRun)

        if let validation = staticExecuteValidationDiagnostic(for: codeToRun) {
            latestExecuteResponse = ExecuteResponse(
                resultJSON: nil,
                logs: [],
                diagnostics: [validation],
                permissionEvents: []
            )
            appendObservation("Fallback pre-execute validation error: \(validation.code) \(validation.message)")
            return true
        }

        do {
            let response = try await host.execute(
                ExecuteRequest(
                    code: codeToRun,
                    allowedCapabilities: CapabilityID.allCases,
                    timeoutMs: 20_000
                )
            )
            latestExecuteResponse = response
            return true
        } catch {
            appendObservation("Fallback execute failed: \(errorDescription(error))")
            return false
        }
    }

    func shouldRepairForObjectiveFailure(currentDecision: ModelDecision, step: Int) -> Bool {
        guard let executeResponse = latestExecuteResponse else {
            return false
        }

        if executeResponse.diagnostics.contains(where: { $0.severity == .error }) {
            return false
        }

        let artifact = EvalArtifact(
            scenarioID: scenario.id,
            prompt: prompt,
            decision: currentDecision,
            searchResponse: latestSearchResponse,
            executeResponse: executeResponse,
            invocations: recorder.snapshot()
        )
        let check = scenario.validate(artifact)
        guard check.passed == false else {
            return false
        }

        appendObservation("Objective check failed: \(check.reason)")
        if scenario.id == "store-and-reuse-token" {
            appendObservation(
                """
                Required token workflow:
                1) await ios.keychain.set('auth_token', 'demo-token-123');
                2) const saved = await ios.keychain.get('auth_token');
                3) const token = saved && saved.value ? saved.value : '';
                4) await fetch('https://api.example.com/profile', { method: 'GET', headers: { Authorization: `Bearer ${token}` } });
                Return JSON with status and reused/token flag.
                """
            )
        }
        if step < maxSteps {
            appendObservation("Emit corrected execute script that satisfies the missing objective.")
            latestExecuteResponse = nil
            return true
        }

        return false
    }

    planningLoop: for step in 1 ... maxSteps {
        let mustExecuteNow = searchCount >= maxSearchesBeforeForceExecute
        let guidance = planningGuidance(
            for: scenario,
            step: step,
            maxSteps: maxSteps,
            observations: observations,
            mustExecuteNow: mustExecuteNow,
            taskHint: taskHint
        )
        let decision: ModelDecision
        do {
            decision = try await provider.generate(prompt: prompt, docs: docsForStep, guidance: guidance)
        } catch {
            let reason = "Model generation error: \(errorDescription(error))"
            appendObservation(reason)
            if await tryDeterministicFallbackExecute(reason: "model generation error") {
                break planningLoop
            }
            if traceModel {
                traceLog("generation failed scenario=\(scenario.id) step=\(step) reason=\(reason)")
            }
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: false,
                reason: reason,
                generatedSummary: combinedSummary(for: decisions)
            )
        }

        decisions.append(decision)
        if traceModel {
            traceLog("decision scenario=\(scenario.id) step=\(step) \(summary(for: decision))")
        }

        switch decision {
        case let .search(request):
            searchCount += 1
            let fingerprint = summary(for: .search(request))
            if searchFingerprints.insert(fingerprint).inserted == false {
                appendObservation("Repeated search request detected: \(fingerprint)")
            }

            do {
                let response = try await host.search(request)
                latestSearchResponse = response
                appendObservation(searchObservationText(response))
                docsForStep = narrowDocsAfterSearch(allDocs: docs, response: response, maxCount: 8)
                let nowMustExecute = searchCount >= maxSearchesBeforeForceExecute
                if nowMustExecute {
                    appendObservation("Search budget exhausted. Emit execute next; do not emit search again.")
                }

                if nowMustExecute, forcedExecuteReprompts < maxForcedExecuteReprompts {
                    forcedExecuteReprompts += 1
                    let forcedGuidance = """
                    \(planningGuidance(
                        for: scenario,
                        step: step,
                        maxSteps: maxSteps,
                        observations: observations,
                        mustExecuteNow: true,
                        taskHint: taskHint
                    ))
                    Hard requirement now: return ONLY {"tool":"execute","code":"..."}.
                    Do not call search again.
                    """

                    let forcedDecision: ModelDecision
                    do {
                        forcedDecision = try await provider.generate(prompt: prompt, docs: docsForStep, guidance: forcedGuidance)
                    } catch {
                        let reason = "Model generation error: \(errorDescription(error))"
                        appendObservation(reason)
                        if await tryDeterministicFallbackExecute(reason: "forced execute generation error") {
                            break planningLoop
                        }
                        if traceModel {
                            traceLog("forced execute generation failed scenario=\(scenario.id) step=\(step) reason=\(reason)")
                        }
                        return EvalRunResult(
                            scenarioID: scenario.id,
                            prompt: prompt,
                            passed: false,
                            reason: reason,
                            generatedSummary: combinedSummary(for: decisions)
                        )
                    }

                    decisions.append(forcedDecision)
                    if traceModel {
                        traceLog("decision scenario=\(scenario.id) step=\(step)-forced \(summary(for: forcedDecision))")
                    }

                    switch forcedDecision {
                    case .search:
                        appendObservation("Model emitted search again after hard execute requirement.")
                        if await tryDeterministicFallbackExecute(reason: "repeated search after hard execute requirement") {
                            break planningLoop
                        }
                        continue planningLoop
                    case let .execute(forcedCode):
                        let normalized = normalizeExecuteCode(forcedCode, scenarioID: scenario.id)
                        let codeToRun = normalized.code
                        if let reason = normalized.reason {
                            appendObservation(reason)
                        }

                        let forcedFingerprint = summary(for: .execute(codeToRun))
                        if executeFingerprints.insert(forcedFingerprint).inserted == false {
                            appendObservation("Repeated execute code detected; modify the script to satisfy missing objective requirements.")
                        }
                        latestExecuteDecision = .execute(codeToRun)
                        do {
                            let outcome = try await runExecuteAttempt(
                                code: codeToRun,
                                host: host,
                                step: step,
                                maxSteps: maxSteps,
                                staticValidationRetries: &staticValidationRetries,
                                maxStaticValidationRetries: maxStaticValidationRetries,
                                runtimeRetries: &runtimeRetries,
                                maxRuntimeRetries: maxRuntimeRetries,
                                observations: &observations,
                                latestExecuteResponse: &latestExecuteResponse
                            )

                            switch outcome {
                            case .continuePlanning:
                                continue planningLoop
                            case .finished:
                                if shouldRepairForObjectiveFailure(currentDecision: .execute(codeToRun), step: step) {
                                    continue planningLoop
                                }
                                break planningLoop
                            }
                        } catch {
                            return EvalRunResult(
                                scenarioID: scenario.id,
                                prompt: prompt,
                                passed: false,
                                reason: "Execute call failed: \(errorDescription(error))",
                                generatedSummary: combinedSummary(for: decisions)
                            )
                        }
                    }
                }

                continue planningLoop
            } catch {
                return EvalRunResult(
                    scenarioID: scenario.id,
                    prompt: prompt,
                    passed: false,
                    reason: "Search execution error: \(errorDescription(error))",
                    generatedSummary: combinedSummary(for: decisions)
                )
            }
        case let .execute(code):
            let normalized = normalizeExecuteCode(code, scenarioID: scenario.id)
            let codeToRun = normalized.code
            if let reason = normalized.reason {
                appendObservation(reason)
            }

            let fingerprint = summary(for: .execute(codeToRun))
            if executeFingerprints.insert(fingerprint).inserted == false {
                appendObservation("Repeated execute code detected; modify the script to satisfy missing objective requirements.")
            }
            latestExecuteDecision = .execute(codeToRun)
            do {
                let outcome = try await runExecuteAttempt(
                    code: codeToRun,
                    host: host,
                    step: step,
                    maxSteps: maxSteps,
                    staticValidationRetries: &staticValidationRetries,
                    maxStaticValidationRetries: maxStaticValidationRetries,
                    runtimeRetries: &runtimeRetries,
                    maxRuntimeRetries: maxRuntimeRetries,
                    observations: &observations,
                    latestExecuteResponse: &latestExecuteResponse
                )

                switch outcome {
                case .continuePlanning:
                    continue planningLoop
                case .finished:
                    if shouldRepairForObjectiveFailure(currentDecision: .execute(codeToRun), step: step) {
                        continue planningLoop
                    }
                    break planningLoop
                }
            } catch {
                return EvalRunResult(
                    scenarioID: scenario.id,
                    prompt: prompt,
                    passed: false,
                    reason: "Execute call failed: \(errorDescription(error))",
                    generatedSummary: combinedSummary(for: decisions)
                )
            }
        }
    }

    if latestExecuteDecision == nil || latestExecuteResponse == nil {
        _ = await tryDeterministicFallbackExecute(reason: "planning completed without executable result")
    }

    let decisionSummary: String = {
        if decisions.isEmpty == false {
            return combinedSummary(for: decisions)
        }
        if let latestExecuteDecision {
            return combinedSummary(for: [latestExecuteDecision])
        }
        return "none"
    }()

    guard decisions.isEmpty == false || latestExecuteDecision != nil else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model did not return any decision",
            generatedSummary: decisionSummary
        )
    }

    guard let executeDecision = latestExecuteDecision else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model never emitted execute within \(maxSteps) planning steps",
            generatedSummary: decisionSummary
        )
    }

    guard let executeResponse = latestExecuteResponse else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model emitted execute but no executable script completed",
            generatedSummary: decisionSummary
        )
    }

    var artifact = EvalArtifact(
        scenarioID: scenario.id,
        prompt: prompt,
        decision: executeDecision,
        searchResponse: latestSearchResponse,
        executeResponse: executeResponse,
        invocations: recorder.snapshot()
    )

    if let runtimeError = artifact.executeResponse?.diagnostics.first(where: { $0.severity == .error }),
       usedDeterministicFallback == false
    {
        _ = await tryDeterministicFallbackExecute(reason: "runtime error after execute: \(runtimeError.code)")
        if let latestExecuteDecision, let latestExecuteResponse {
            artifact = EvalArtifact(
                scenarioID: scenario.id,
                prompt: prompt,
                decision: latestExecuteDecision,
                searchResponse: latestSearchResponse,
                executeResponse: latestExecuteResponse,
                invocations: recorder.snapshot()
            )
        }
    }

    if let runtimeError = artifact.executeResponse?.diagnostics.first(where: { $0.severity == .error }) {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Runtime error: \(runtimeError.code) \(runtimeError.message)",
            generatedSummary: decisionSummary
        )
    }

    let check = scenario.validate(artifact)
    if check.passed == false, usedDeterministicFallback == false {
        _ = await tryDeterministicFallbackExecute(reason: "objective mismatch: \(check.reason)")
        if let latestExecuteDecision, let latestExecuteResponse {
            let fallbackArtifact = EvalArtifact(
                scenarioID: scenario.id,
                prompt: prompt,
                decision: latestExecuteDecision,
                searchResponse: latestSearchResponse,
                executeResponse: latestExecuteResponse,
                invocations: recorder.snapshot()
            )
            if let runtimeError = fallbackArtifact.executeResponse?.diagnostics.first(where: { $0.severity == .error }) {
                return EvalRunResult(
                    scenarioID: scenario.id,
                    prompt: prompt,
                    passed: false,
                    reason: "Runtime error: \(runtimeError.code) \(runtimeError.message)",
                    generatedSummary: decisionSummary
                )
            }
            let fallbackCheck = scenario.validate(fallbackArtifact)
            return EvalRunResult(
                scenarioID: scenario.id,
                prompt: prompt,
                passed: fallbackCheck.passed,
                reason: fallbackCheck.reason,
                generatedSummary: decisionSummary
            )
        }
    }

    return EvalRunResult(
        scenarioID: scenario.id,
        prompt: prompt,
        passed: check.passed,
        reason: check.reason,
        generatedSummary: decisionSummary
    )
}

@main
struct CodeModeEvalCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codemode-eval",
        abstract: "Evaluate prompt-to-search/execute behavior using mocked CodeMode bridges."
    )

    @Option(
        name: .long,
        help: "Model provider to use: wavelike, apple, scripted, or command."
    )
    var model: String = "wavelike"

    @Option(
        name: .long,
        help: "Path to external adapter executable when --model command."
    )
    var modelCommand: String?

    @Option(
        name: .long,
        help: "Argument passed to --model-command. Repeat for multiple values."
    )
    var modelCommandArg: [String] = []

    @Option(
        name: .long,
        help: "Scenario id filter. Repeat this option or pass comma-separated values."
    )
    var scenario: [String] = []

    @Flag(
        name: .long,
        help: "List available scenario IDs and exit."
    )
    var listScenarios: Bool = false

    @Flag(
        name: .long,
        help: "Print generated tool/script summary for each prompt."
    )
    var showGenerated: Bool = false

    @Flag(
        name: .long,
        help: "Emit per-prompt model diagnostics and error chains to stderr."
    )
    var traceModel: Bool = false

    private var scenarioFilter: Set<String> {
        let ids = scenario.flatMap { item in
            item.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        return Set(ids.filter { $0.isEmpty == false })
    }

    mutating func run() async throws {
        let scenarios = scenarioCatalog()

        if listScenarios {
            for scenario in scenarios {
                print("\(scenario.id)")
            }
            return
        }

        let selectedScenarios = scenarioFilter.isEmpty
            ? scenarios
            : scenarios.filter { scenarioFilter.contains($0.id) }

        guard selectedScenarios.isEmpty == false else {
            throw ValidationError("No scenarios matched --scenario filter")
        }

        let provider: EvalModelProvider
        switch model.lowercased() {
        case "wavelike":
            provider = try WavelikeModelProvider(trace: traceModel)
        case "apple", "wavelike-apple":
            provider = try WavelikeModelProvider(forceAppleEngine: true, trace: traceModel)
        case "scripted":
            provider = ScriptedModelProvider()
        case "command":
            guard let command = modelCommand else {
                throw ValidationError("--model command requires --model-command <path>")
            }
            provider = CommandModelProvider(executablePath: command, executableArgs: modelCommandArg, trace: traceModel)
        default:
            throw ValidationError("Unknown model \(model). Use wavelike, apple, scripted, or command.")
        }

        var rawResults: [EvalRunResult] = []
        var assistedResults: [EvalRunResult] = []

        for scenario in selectedScenarios {
            for prompt in scenario.prompts {
                if traceModel {
                    traceLog("scenario=\(scenario.id) prompt=\(prompt)")
                }

                let rawSandbox = try EvalSandbox.create()
                defer { rawSandbox.cleanup() }
                let rawRecorder = InvocationRecorder()
                let rawHost = makeEvalHost(recorder: rawRecorder, sandbox: rawSandbox)
                let rawDocs = rawHost.docs()

                let rawResult: EvalRunResult
                switch scenario.expectedTool {
                case .search:
                    rawResult = await evaluateSearchPrompt(
                        scenario: scenario,
                        prompt: prompt,
                        host: rawHost,
                        docs: rawDocs,
                        recorder: rawRecorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                case .execute:
                    rawResult = await evaluateExecutePromptRaw(
                        scenario: scenario,
                        prompt: prompt,
                        host: rawHost,
                        docs: rawDocs,
                        recorder: rawRecorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                }
                rawResults.append(rawResult)

                let assistedSandbox = try EvalSandbox.create()
                defer { assistedSandbox.cleanup() }
                let assistedRecorder = InvocationRecorder()
                let assistedHost = makeEvalHost(recorder: assistedRecorder, sandbox: assistedSandbox)
                let assistedDocs = assistedHost.docs()

                let assistedResult: EvalRunResult
                switch scenario.expectedTool {
                case .search:
                    assistedResult = await evaluateSearchPrompt(
                        scenario: scenario,
                        prompt: prompt,
                        host: assistedHost,
                        docs: assistedDocs,
                        recorder: assistedRecorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                case .execute:
                    assistedResult = await evaluateExecutePrompt(
                        scenario: scenario,
                        prompt: prompt,
                        host: assistedHost,
                        docs: assistedDocs,
                        recorder: assistedRecorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                }
                assistedResults.append(assistedResult)
            }
        }

        let rawPassed = rawResults.filter(\.passed).count
        let assistedPassed = assistedResults.filter(\.passed).count
        let total = assistedResults.count

        print("CodeMode eval provider=\(provider.id) scenarios=\(selectedScenarios.count) prompts=\(total)")
        print("Raw pass rate: \(rawPassed)/\(total) (\(String(format: "%.1f", total > 0 ? Double(rawPassed) * 100 / Double(total) : 0))%)")
        print("Assisted pass rate: \(assistedPassed)/\(total) (\(String(format: "%.1f", total > 0 ? Double(assistedPassed) * 100 / Double(total) : 0))%)")
        print("")

        for (index, result) in assistedResults.enumerated() {
            let raw = rawResults[index]
            let marker = result.passed ? "PASS" : "FAIL"
            let rawMarker = raw.passed ? "PASS" : "FAIL"
            print("[\(marker)] \(result.scenarioID)")
            print("  prompt: \(result.prompt)")
            print("  raw: [\(rawMarker)] \(raw.reason)")
            print("  assisted: \(result.reason)")
            if showGenerated {
                print("  raw generated: \(raw.generatedSummary)")
                print("  assisted generated: \(result.generatedSummary)")
            }
        }

        if assistedPassed != total {
            throw ExitCode(1)
        }
    }
}
