import Foundation
import Testing
@testable import CodeMode

@Test func executeTerminatesCPUBoundInfiniteLoop() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let started = Date()
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "while (true) {}",
            allowedCapabilities: [],
            timeoutMs: 300
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "EXECUTION_TIMEOUT")
    #expect(Date().timeIntervalSince(started) < 5)
}

@Test func executeTerminatesCPUBoundLoopInsidePromiseChain() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            await Promise.resolve();
            while (true) {}
            """,
            allowedCapabilities: [],
            timeoutMs: 300
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "EXECUTION_TIMEOUT")
}

@Test func executeTimeoutTerminationIsNotCatchableByScript() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            try {
                while (true) {}
            } catch (error) {
                return { swallowed: true };
            }
            """,
            allowedCapabilities: [],
            timeoutMs: 300
        )
    )

    #expect(observed.result == nil)
    #expect(observed.error?.code == "EXECUTION_TIMEOUT")
}

@Test func executeRecoversWithFreshContextAfterTerminatedLoop() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let timedOut = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "while (true) {}",
            allowedCapabilities: [],
            timeoutMs: 200
        )
    )
    #expect(timedOut.error?.code == "EXECUTION_TIMEOUT")

    let recovered = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "return { ok: true };",
            allowedCapabilities: []
        )
    )

    let payload = try requireJSONObject(from: try #require(recovered.result))
    #expect(payload["ok"] as? Bool == true)
}

@Test func cancelInterruptsRunningInfiniteLoop() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "while (true) {}",
            allowedCapabilities: [],
            timeoutMs: 60_000
        )
    )

    try await Task.sleep(nanoseconds: 200_000_000)
    call.cancel()
    let observed = await observe(call)

    #expect(observed.result == nil)
    #expect(observed.error?.code == "CANCELLED")
}

@Test func searchTerminatesCPUBoundInfiniteLoop() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    do {
        _ = try await tools.searchJavaScriptAPI(
            JavaScriptAPISearchRequest(
                code: "async () => { while (true) {} }"
            )
        )
        Issue.record("Expected search to time out")
    } catch let error as CodeModeToolError {
        #expect(error.code == "SEARCH_TIMEOUT")
    }
}
