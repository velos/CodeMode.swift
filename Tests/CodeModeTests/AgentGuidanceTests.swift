import Foundation
import Testing
@testable import CodeMode

// The tool descriptions and the generated TypeScript teach an agent what the
// helpers are called. Nothing taught it what shape its work should take, so an
// agent could reasonably use executeJavaScript as a thin RPC — one call per
// operation — which is the pattern this package exists to replace.

@Test func everyTierStatesTheCoreIdea() {
    // A host dropping to a smaller tier must not lose a rule, only the examples.
    for length in CodeModeAgentGuidance.Length.allCases {
        let text = CodeModeAgentGuidance.systemPrompt(length)
        #expect(text.contains("One `executeJavaScript` call should do the entire job"))
        #expect(text.contains("Request only the capabilities your script actually calls"))
    }
}

@Test func tiersGrowStrictlyAndAreAdditive() {
    let brief = CodeModeAgentGuidance.systemPrompt(.brief)
    let standard = CodeModeAgentGuidance.systemPrompt(.standard)
    let full = CodeModeAgentGuidance.systemPrompt(.full)

    #expect(brief.count < standard.count)
    #expect(standard.count < full.count)
    // Additive, not rewritten: the larger tiers contain the smaller ones verbatim.
    #expect(standard.contains(brief))
    #expect(full.contains(standard))
}

@Test func largerTiersAddExamplesAndFailureModes() {
    let standard = CodeModeAgentGuidance.systemPrompt(.standard)
    let full = CodeModeAgentGuidance.systemPrompt(.full)

    #expect(standard.contains("```javascript"))
    #expect(standard.contains("searchJavaScriptAPI"))
    #expect(full.contains("Anti-patterns"))
    #expect(full.contains("BRIDGE_FAILURES_NOT_SURFACED"))
    // The concurrency reality must not be over-promised in the fan-out example.
    #expect(full.contains("`Promise.all` does not make these overlap"))
}

@Test func aBudgetSelectsTheLargestTierThatFits() {
    let brief = CodeModeAgentGuidance.Length.brief.approximateTokenCount
    let standard = CodeModeAgentGuidance.Length.standard.approximateTokenCount
    let full = CodeModeAgentGuidance.Length.full.approximateTokenCount

    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: full) == .full)
    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: full + 5_000) == .full)
    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: full - 1) == .standard)
    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: standard) == .standard)
    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: standard - 1) == .brief)
    #expect(CodeModeAgentGuidance.length(forApproximateTokenBudget: brief) == .brief)
}

@Test func aBudgetTooSmallForAnythingStillReturnsTheCoreIdea() {
    // Deliberately a floor rather than an empty string: some guidance is the
    // difference between an agent that batches and one that does not.
    #expect(CodeModeAgentGuidance.systemPrompt(approximateTokenBudget: 0) == CodeModeAgentGuidance.systemPrompt(.brief))
    #expect(CodeModeAgentGuidance.systemPrompt(approximateTokenBudget: -100) == CodeModeAgentGuidance.systemPrompt(.brief))
}

@Test func guidanceExamplesUseHelpersAndCapabilitiesThatActuallyExist() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let full = CodeModeAgentGuidance.systemPrompt(.full)
    let jsNames = Set(tools.capabilities().flatMap(\.jsNames))

    // Guidance naming a helper the runtime does not install would teach the exact
    // failure it is trying to prevent.
    for helper in ["apple.fs.list", "apple.fs.read", "apple.fs.move"] {
        #expect(full.contains(helper))
        #expect(jsNames.contains(helper), "guidance references missing helper \(helper)")
    }

    for capability in ["fs.list", "fs.read", "fs.move"] {
        #expect(CapabilityID(rawValue: capability) != nil, "guidance references missing capability \(capability)")
    }
}

@Test func theWorkedExampleActuallyRuns() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // The example is the shape we ask agents to copy, so it has to be a script
    // this runtime accepts — arguments, calling conventions, and all. The setup
    // lines are the only addition.
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await apple.fs.mkdir({ path: 'documents:receipts/lisbon' });
            await apple.fs.write({
                path: 'documents:receipts/a.json',
                data: JSON.stringify({ trip: 'lisbon', amount: 12 })
            });
            await apple.fs.write({
                path: 'documents:receipts/b.json',
                data: JSON.stringify({ trip: 'porto', amount: 99 })
            });

            const entries = await apple.fs.list({ path: 'documents:receipts' });
            let total = 0;
            const filed = [];

            for (const entry of entries) {
              if (entry.isDirectory || !entry.name.endsWith('.json')) continue;
              const { text } = await apple.fs.read({ path: entry.path });
              const receipt = JSON.parse(text);
              if (receipt.trip !== 'lisbon') continue;
              total += receipt.amount;
              await apple.fs.move({
                from: entry.path,
                to: `documents:receipts/lisbon/${entry.name}`,
                overwrite: true
              });
              filed.push(entry.name);
            }

            return { total, filedCount: filed.length };
            """,
            allowedCapabilities: [.fsMkdir, .fsWrite, .fsList, .fsRead, .fsMove]
        )
    )

    #expect(observed.error == nil)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.int("total") == 12)
    #expect(output.int("filedCount") == 1)
}

@Test func everyHelperCallInTheDocsNamesARealHelperAndRealArguments() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }

    let references = tools.capabilities()
    let byJSName = Dictionary(references.flatMap { ref in ref.jsNames.map { ($0, ref) } }, uniquingKeysWith: { first, _ in first })

    // An example naming a helper or argument the runtime does not have teaches
    // the exact failure the docs exist to prevent — and the wrong argument name
    // is the easy mistake (`identifier` vs `identifiers` got through once).
    // Parsed rather than listed, so new examples are checked automatically.
    let texts = [CodeModeAgentToolDescriptions.executeJavaScript.description]
        + CodeModeAgentGuidance.Length.allCases.map { CodeModeAgentGuidance.systemPrompt($0) }
    let call = try Regex(#"((?:apple|ios)\.[A-Za-z.]+)\(\{([^}]*)\}"#)
    let key = try Regex(#"(?:^|[,{\s])([A-Za-z_][A-Za-z0-9_]*)\s*(?=[:,}]|$)"#)

    var checked = 0
    for text in texts {
        for match in text.matches(of: call) {
            let helper = String(match.output[1].substring!)
            let reference = try #require(byJSName[helper], "docs reference missing helper \(helper)")
            let known = Set(reference.requiredArguments + reference.optionalArguments)
            let body = String(match.output[2].substring!)
            for argument in body.matches(of: key).map({ String($0.output[1].substring!) }) {
                #expect(known.contains(argument), "\(helper) has no argument '\(argument)'")
            }
            checked += 1
        }
    }
    #expect(checked >= 5, "the parser found too few helper calls to be checking anything")
}

@Test func theToolDescriptionStaysWithinItsBudget() {
    // Sent on every turn and not trimmable by the host — unlike the guidance
    // tiers, which exist precisely so worked examples can be budgeted. Examples
    // belong there; this guard stops the description regrowing them.
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.count < 4_800)
    #expect(CodeModeAgentToolDescriptions.executeJavaScript.description.contains("const results = []") == false)
}

@Test func everyCatalogExampleNamesRealHelpersAndArguments() async throws {
    let (tools, sandbox) = try makeTools(hostPlatform: .iOS)
    defer { cleanup(sandbox) }
    let references = tools.capabilities()
    let byName = Dictionary(references.flatMap { ref in ref.jsNames.map { ($0, ref) } }, uniquingKeysWith: { first, _ in first })
    // Scan object keys at each declared level, skipping quoted strings and
    // nested literals. Open objects (fields, parameters, etc.) own their keys;
    // only objects with catalogued children constrain the nested names.
    func keys(in source: Substring) throws -> [(String, Substring?)] {
        let chars = Array(source)
        var entries: [(String, Substring?)] = []
        var depth = 0
        var quote: Character?
        var escaped = false
        var start = 0
        var pieces: [String] = []
        for (index, char) in chars.enumerated() {
            if let current = quote {
                if escaped { escaped = false }
                else if char == "\\" { escaped = true }
                else if char == current { quote = nil }
                continue
            }
            if char == "\"" || char == "'" || char == "`" { quote = char }
            else if char == "{" || char == "[" || char == "(" { depth += 1 }
            else if char == "}" || char == "]" || char == ")" { depth -= 1 }
            else if char == ",", depth == 0 {
                pieces.append(String(chars[start..<index]))
                start = index + 1
            }
        }
        pieces.append(String(chars[start...]))
        for piece in pieces where !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let pair = piece.split(separator: ":", maxSplits: 1)
            let key = String(pair[0]).trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = pair.count == 2 ? pair[1].trimmingCharacters(in: .whitespacesAndNewlines) : ""
            entries.append((key, value.hasPrefix("{") && value.hasSuffix("}") ? value.dropFirst().dropLast() : nil))
        }
        return entries
    }
    func check(_ body: Substring, prefix: String = "", reference: JavaScriptAPIReference, helper: String) throws {
        let known = Set(reference.requiredArguments + reference.optionalArguments + Array(reference.argumentTypes.keys))
        for (key, nested) in try keys(in: body) {
            let path = prefix + key
            #expect(known.contains(path), "\(helper) example has unknown argument '\(path)'")
            if let nested, known.contains(where: { $0.hasPrefix(path + ".") }) {
                try check(nested, prefix: path + ".", reference: reference, helper: helper)
            }
        }
    }
    let call = try Regex(#"^await ((?:apple|ios)\.[A-Za-z.]+|fetch)\((.*?)\)(?:\.then\(.*\))?$"#)
    for reference in references {
        let match = try #require(reference.example.wholeMatch(of: call), "Unparsed example: \(reference.example)")
        let helper = String(match.output[1].substring!)
        let target = try #require(byName[helper], "example references missing helper \(helper)")
        let args = match.output[2].substring!.trimmingCharacters(in: .whitespacesAndNewlines)
        if helper == "fetch" {
            // fetch is positional; its second argument is the catalog's options
            // object. The URL itself has no argument keys to check.
            let positional = try Regex(#"^(['"])(.*?)\1(?:,\s*\{(.*)\})?$"#)
            let invocation = try #require(args.wholeMatch(of: positional), "Unparsed fetch arguments: \(args)")
            if let options = invocation.output[3].substring {
                try check(options, prefix: "options.", reference: target, helper: helper)
            }
        } else if !args.isEmpty {
            #expect(args.hasPrefix("{") && args.hasSuffix("}"), "Expected object arguments in \(reference.example)")
            try check(args.dropFirst().dropLast(), reference: target, helper: helper)
        }
    }
}
