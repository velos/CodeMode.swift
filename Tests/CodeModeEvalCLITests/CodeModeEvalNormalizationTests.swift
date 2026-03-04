import Testing
@testable import CodeMode
@testable import CodeModeEvalCLI

private struct StubModelProvider: EvalModelProvider {
    let id = "stub"
    let decision: ModelDecision

    func generate(prompt: String, docs: [BridgeAPIDoc], guidance: String?) async throws -> ModelDecision {
        _ = prompt
        _ = docs
        _ = guidance
        return decision
    }
}

@Test func staticValidationAllowsIOSFSCalls() {
    let code = """
    await ios.fs.list({ path: 'tmp:' });
    await ios.fs.read({ path: 'tmp:data.json' });
    await ios.fs.write({ path: 'tmp:data.json', data: '{}' });
    await ios.fs.move({ from: 'tmp:data.json', to: 'documents:data.json' });
    await ios.fs.delete({ path: 'tmp:data.json' });
    return { ok: true };
    """

    let diagnostic = staticExecuteValidationDiagnostic(for: code)
    #expect(diagnostic == nil)
}

@Test func normalizeCollapsesIOSIOSMediaNamespace() {
    let input = "return await ios.ios.media.transcode({ path: 'tmp:clip.mov' });"
    let normalized = normalizeExecuteCode(input, scenarioID: "transcode-mov-to-mp4")

    #expect(normalized.changed)
    #expect(normalized.code.contains("ios.media.transcode("))
    #expect(normalized.code.contains("ios.ios.media.") == false)
}

@Test func normalizeRewritesDirectFSObjectCallsToIOSFS() {
    let input = """
    await fs.list({ path: 'tmp:' });
    await fs.read({ path: 'tmp:report.json' });
    await fs.write({ path: 'tmp:report.json', data: '{}' });
    await fs.move({ from: 'tmp:report.json', to: 'documents:report.json' });
    await fs.delete({ path: 'tmp:report.json' });
    return { ok: true };
    """
    let normalized = normalizeExecuteCode(input, scenarioID: "fs-management")

    #expect(normalized.changed)
    #expect(normalized.code.contains("ios.fs.list({ path: 'tmp:' })"))
    #expect(normalized.code.contains("ios.fs.read({ path: 'tmp:report.json' })"))
    #expect(normalized.code.contains("ios.fs.write({ path: 'tmp:report.json', data: '{}' })"))
    #expect(normalized.code.contains("ios.fs.move({ from: 'tmp:report.json', to: 'documents:report.json' })"))
    #expect(normalized.code.contains("ios.fs.delete({ path: 'tmp:report.json' })"))
}

@Test func capabilityDiscoveryCoercesExecuteToSearch() async throws {
    let scenario = try #require(
        scenarioCatalog().first(where: { $0.id == "capability-discovery-reminders-calendar" })
    )
    let prompt = scenario.prompts[0]
    let sandbox = try EvalSandbox.create()
    defer { sandbox.cleanup() }
    let recorder = InvocationRecorder()
    let host = makeEvalHost(recorder: recorder, sandbox: sandbox)
    let docs = host.docs()

    let result = await evaluateSearchPrompt(
        scenario: scenario,
        prompt: prompt,
        host: host,
        docs: docs,
        recorder: recorder,
        provider: StubModelProvider(decision: .execute("console.log('calendar/reminders capability list');")),
        traceModel: false
    )

    #expect(result.generatedSummary.contains("[coerced]"))
    #expect(result.passed)
}
