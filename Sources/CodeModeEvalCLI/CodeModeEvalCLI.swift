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
        let capabilitySummary = docs
            .map { "\($0.capability.rawValue): \($0.summary). Example: \($0.example)" }
            .joined(separator: "\n")

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

        let guidanceSection: String = {
            guard let guidance = guidance?.trimmingCharacters(in: .whitespacesAndNewlines), guidance.isEmpty == false else {
                return ""
            }

            return """

            Planning context:
            \(guidance)
            """
        }()

        let userPrompt = """
        User request:
        \(prompt)

        Available capabilities:
        \(capabilitySummary)
        \(guidanceSection)
        """

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

    if let method = firstCaptureGroup(#"\bfs\.(?!promises\b)([A-Za-z_][A-Za-z0-9_]*)\s*\("#, in: code, group: 1) {
        issues.append("Unsupported fs.\(method)(...) usage. Use fs.promises.\(method)(...) or ios.fs.*.")
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
        return "Use fetch for backend JSON then fs.write to sandbox path (tmp:/caches:/documents:)."
    }

    if lower.contains("tmp") && lower.contains("documents") {
        return "Use fs.list on tmp:, fs.move into documents:, and fs.delete for temp cleanup."
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

func normalizeExecuteCode(_ code: String, scenarioID: String) -> (code: String, changed: Bool, reason: String?) {
    guard scenarioID == "store-and-reuse-token" else {
        return (code, false, nil)
    }

    let hasSet = code.contains("ios.keychain.set(")
    let hasGet = code.contains("ios.keychain.get(")
    let hasFetch = code.contains("fetch(")
    let usesWrongKeychainMethods = code.contains("ios.keychain.write(") || code.contains("ios.keychain.read(")
    let usesBareKeychain = firstRegexMatch(#"\b(?<!ios\.)keychain\.[A-Za-z_][A-Za-z0-9_]*\s*\("#, in: code) != nil
    let usesNetworkNamespace = code.contains("network.fetch(")
    let usesSafeTokenExtraction = code.contains("saved && saved.value ? saved.value : ''")

    let looksSafe = hasSet && hasGet && hasFetch && usesWrongKeychainMethods == false && usesBareKeychain == false && usesNetworkNamespace == false && usesSafeTokenExtraction
    if looksSafe {
        return (code, false, nil)
    }

    return (canonicalTokenWorkflowScript(), true, "Applied token workflow normalization (required keychain.set/get + fetch pattern).")
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
            lines.append("required args: \(detail.requiredArguments.joined(separator: ", "))")
        }
        if detail.optionalArguments.isEmpty == false {
            lines.append("optional args: \(detail.optionalArguments.joined(separator: ", "))")
        }
        lines.append("example: \(detail.example)")
    }

    if response.items.isEmpty == false {
        lines.append("Discover results:")
        for item in response.items.prefix(5) {
            lines.append("- \(item.capability.rawValue): \(item.summary)")
        }
    }

    if response.diagnostics.isEmpty == false {
        lines.append("Search diagnostics:")
        for diagnostic in response.diagnostics.prefix(3) {
            lines.append("- \(diagnostic.code): \(diagnostic.message)")
        }
    }

    return lines.joined(separator: "\n")
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
        lines.append("Task hint: \(taskHint)")
    }

    if mustExecuteNow {
        lines.append("Hard requirement: emit tool=execute now. Additional search calls are invalid.")
    }

    if observations.isEmpty {
        lines.append("No prior tool outputs yet.")
    } else {
        lines.append("Prior tool outputs/errors (most recent first):")
        for observation in observations.suffix(3).reversed() {
            lines.append(observation)
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

    guard case let .search(request) = decision else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Expected search tool, model emitted execute",
            generatedSummary: summary(for: decision)
        )
    }

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
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: check.passed,
            reason: check.reason,
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
    let taskHint = taskExecutionHint(for: prompt)

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

        observations.append("Objective check failed: \(check.reason)")
        if scenario.id == "store-and-reuse-token" {
            observations.append(
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
            observations.append("Emit corrected execute script that satisfies the missing objective.")
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
            decision = try await provider.generate(prompt: prompt, docs: docs, guidance: guidance)
        } catch {
            let reason = "Model generation error: \(errorDescription(error))"
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
                observations.append("Repeated search request detected: \(fingerprint)")
            }

            do {
                let response = try await host.search(request)
                latestSearchResponse = response
                observations.append(searchObservationText(response))
                let nowMustExecute = searchCount >= maxSearchesBeforeForceExecute
                if nowMustExecute {
                    observations.append("Search budget exhausted. Emit execute next; do not emit search again.")
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
                        forcedDecision = try await provider.generate(prompt: prompt, docs: docs, guidance: forcedGuidance)
                    } catch {
                        let reason = "Model generation error: \(errorDescription(error))"
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
                        observations.append("Model emitted search again after hard execute requirement.")
                        continue planningLoop
                    case let .execute(forcedCode):
                        let normalized = normalizeExecuteCode(forcedCode, scenarioID: scenario.id)
                        let codeToRun = normalized.code
                        if let reason = normalized.reason {
                            observations.append(reason)
                        }

                        let forcedFingerprint = summary(for: .execute(codeToRun))
                        if executeFingerprints.insert(forcedFingerprint).inserted == false {
                            observations.append("Repeated execute code detected; modify the script to satisfy missing objective requirements.")
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
                observations.append(reason)
            }

            let fingerprint = summary(for: .execute(codeToRun))
            if executeFingerprints.insert(fingerprint).inserted == false {
                observations.append("Repeated execute code detected; modify the script to satisfy missing objective requirements.")
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

    guard decisions.isEmpty == false else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model did not return any decision",
            generatedSummary: "none"
        )
    }

    guard let executeDecision = latestExecuteDecision else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model never emitted execute within \(maxSteps) planning steps",
            generatedSummary: combinedSummary(for: decisions)
        )
    }

    guard let executeResponse = latestExecuteResponse else {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Model emitted execute but no executable script completed",
            generatedSummary: combinedSummary(for: decisions)
        )
    }

    let artifact = EvalArtifact(
        scenarioID: scenario.id,
        prompt: prompt,
        decision: executeDecision,
        searchResponse: latestSearchResponse,
        executeResponse: executeResponse,
        invocations: recorder.snapshot()
    )

    if let runtimeError = executeResponse.diagnostics.first(where: { $0.severity == .error }) {
        return EvalRunResult(
            scenarioID: scenario.id,
            prompt: prompt,
            passed: false,
            reason: "Runtime error: \(runtimeError.code) \(runtimeError.message)",
            generatedSummary: combinedSummary(for: decisions)
        )
    }

    let check = scenario.validate(artifact)
    return EvalRunResult(
        scenarioID: scenario.id,
        prompt: prompt,
        passed: check.passed,
        reason: check.reason,
        generatedSummary: combinedSummary(for: decisions)
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

        var results: [EvalRunResult] = []

        for scenario in selectedScenarios {
            for prompt in scenario.prompts {
                let sandbox = try EvalSandbox.create()
                defer { sandbox.cleanup() }

                let recorder = InvocationRecorder()
                let host = makeEvalHost(recorder: recorder, sandbox: sandbox)
                let docs = host.docs()

                if traceModel {
                    traceLog("scenario=\(scenario.id) prompt=\(prompt)")
                }

                let result: EvalRunResult
                switch scenario.expectedTool {
                case .search:
                    result = await evaluateSearchPrompt(
                        scenario: scenario,
                        prompt: prompt,
                        host: host,
                        docs: docs,
                        recorder: recorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                case .execute:
                    result = await evaluateExecutePrompt(
                        scenario: scenario,
                        prompt: prompt,
                        host: host,
                        docs: docs,
                        recorder: recorder,
                        provider: provider,
                        traceModel: traceModel
                    )
                }

                results.append(result)
            }
        }

        let passed = results.filter(\.passed).count
        let total = results.count

        print("CodeMode eval provider=\(provider.id) scenarios=\(selectedScenarios.count) prompts=\(total)")
        print("Pass rate: \(passed)/\(total) (\(String(format: "%.1f", total > 0 ? Double(passed) * 100 / Double(total) : 0))%)")
        print("")

        for result in results {
            let marker = result.passed ? "PASS" : "FAIL"
            print("[\(marker)] \(result.scenarioID)")
            print("  prompt: \(result.prompt)")
            print("  reason: \(result.reason)")
            if showGenerated {
                print("  generated: \(result.generatedSummary)")
            }
        }

        if passed != total {
            throw ExitCode(1)
        }
    }
}
