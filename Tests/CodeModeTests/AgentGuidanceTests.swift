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

@Test func toolDescriptionExamplesNameRealHelpersAndArguments() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let description = CodeModeAgentToolDescriptions.executeJavaScript.description
    let references = tools.capabilities()
    let byJSName = Dictionary(references.flatMap { ref in ref.jsNames.map { ($0, ref) } }, uniquingKeysWith: { first, _ in first })

    // An example that names a helper or argument the runtime does not have
    // teaches the exact failure the examples exist to prevent — and a wrong
    // argument name is the easiest kind to get wrong when writing prose.
    let used: [(helper: String, arguments: [String])] = [
        ("apple.calendar.listEvents", ["start", "end"]),
        ("apple.contacts.list", ["identifiers"]),
    ]

    for (helper, arguments) in used {
        #expect(description.contains(helper))
        let reference = try #require(byJSName[helper], "description references missing helper \(helper)")
        let known = Set(reference.requiredArguments + reference.optionalArguments)
        for argument in arguments {
            #expect(known.contains(argument), "\(helper) has no argument '\(argument)'")
        }
    }
}
