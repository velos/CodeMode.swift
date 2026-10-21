import Foundation
import Testing
@testable import CodeMode

// Nothing bounded a script's output before: the whole result was stringified and
// copied into Swift, every console.log was retained and re-copied into each
// CodeModeToolError, and the events stream buffered without limit. One script
// could jetsam an iOS host. Every limit degrades with a diagnostic instead of
// failing, because for an LLM consumer a truncated result beats an OOM.

@Test func oversizedResultsAreReplacedWithAParseableDescriptor() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxResultCharacters: 2_000, truncatedResultPreviewCharacters: 200)
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return Array.from({ length: 5000 }, (_, i) => 'entry-' + i);",
            allowedCapabilities: []
        )
    )

    #expect(observed.error == nil)
    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.bool("__codeModeTruncated") == true)
    #expect((output.int("characterCount") ?? 0) > 2_000)
    #expect(output.int("limit") == 2_000)
    #expect((output.string("preview")?.count ?? 0) <= 200)

    let diagnostics = try #require(observed.result?.diagnostics)
    #expect(diagnostics.contains { $0.code == "RESULT_TRUNCATED" })
}

@Test func resultsWithinTheLimitAreUntouched() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxResultCharacters: 100_000)
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(code: "return { ok: true, items: [1, 2, 3] };", allowedCapabilities: [])
    )

    let output = try #require(observed.result?.output?.objectValue)
    #expect(output.bool("ok") == true)
    #expect(output.array("items")?.count == 3)
    #expect(observed.result?.diagnostics.contains { $0.code == "RESULT_TRUNCATED" } == false)
}

@Test func retainedLogsAreCappedWithANotice() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxLogEntries: 25)
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "for (let i = 0; i < 500; i++) { console.log('line ' + i); } return 'done';",
            allowedCapabilities: []
        )
    )

    let logs = try #require(observed.result?.logs)
    #expect(logs.count == 25)
    // The first N are kept: the beginning of a runaway log is where the cause is.
    #expect(logs.first?.message == "line 0")
    #expect(observed.result?.diagnostics.contains { $0.code == "LOG_LIMIT_REACHED" } == true)
}

@Test func longLogMessagesAreElidedInTheMiddle() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxLogMessageCharacters: 200)
    )
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "console.log('HEAD' + 'x'.repeat(100000) + 'TAIL'); return 'done';",
            allowedCapabilities: []
        )
    )

    let message = try #require(observed.result?.logs.first?.message)
    #expect(message.count < 400)
    #expect(message.hasPrefix("HEAD"))
    #expect(message.hasSuffix("TAIL"))
    #expect(message.contains("characters elided"))
}

@Test func diagnosticsAndPermissionEventsAreCapped() {
    let transcript = ExecutionTranscript(
        limits: ExecutionLimits(maxDiagnostics: 3, maxPermissionEvents: 2)
    )

    for index in 0..<50 {
        transcript.record(diagnostic: ToolDiagnostic(severity: .info, code: "D\(index)", message: "m"))
        transcript.record(permissionEvent: PermissionEvent(permission: .contacts, status: .granted))
    }

    let snapshot = transcript.snapshot()
    #expect(snapshot.diagnostics.count == 3)
    #expect(snapshot.permissionEvents.count == 2)
}

@Test func theEventStreamBufferIsBounded() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxLogEntries: 100_000, maxBufferedEvents: 16)
    )
    defer { cleanup(sandbox) }

    // Never drained until the script has finished: with the default unbounded
    // policy this buffers every event; bounded, it keeps only the newest.
    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "for (let i = 0; i < 5000; i++) { console.log('line ' + i); } return 'done';",
            allowedCapabilities: []
        )
    )
    _ = try await call.result

    var received = 0
    for await _ in call.events {
        received += 1
    }
    #expect(received <= 16)
}
