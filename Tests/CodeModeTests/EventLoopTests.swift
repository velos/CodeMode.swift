import Foundation
import Testing
@testable import CodeMode

// `setTimeout` used to invoke its callback synchronously and ignore the delay.
// Three things were wrong at once: clearTimeout could never cancel, an error
// thrown by a callback propagated to setTimeout's *caller*, and
// `await new Promise(r => setTimeout(r, 2000))` — the standard backoff — was a
// hot loop that hammered remote APIs through fetch.

@Test func setTimeoutDefersItsCallbackInsteadOfRunningItInline() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const order = [];
            setTimeout(() => { order.push('timer'); }, 0);
            order.push('sync');
            await new Promise(resolve => setTimeout(resolve, 1));
            return { order };
            """,
            allowedCapabilities: []
        )
    )

    #expect(observed.error == nil)
    let order = try #require(observed.result?.output?.objectValue?.array("order"))
    #expect(order == [.string("sync"), .string("timer")])
}

@Test func setTimeoutActuallyWaitsTheRequestedDelay() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let started = Date()
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "await new Promise(resolve => setTimeout(resolve, 150)); return 'done';",
            allowedCapabilities: [],
            timeoutMs: 5_000
        )
    )
    let elapsed = Date().timeIntervalSince(started)

    #expect(observed.result?.output == .string("done"))
    // The delay was previously ignored entirely, so a backoff loop spun.
    #expect(elapsed >= 0.14)
    #expect(elapsed < 3)
}

@Test func clearTimeoutCancelsAPendingCallback() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const fired = [];
            const id = setTimeout(() => { fired.push('should-not-run'); }, 5);
            clearTimeout(id);
            await new Promise(resolve => setTimeout(resolve, 20));
            return { fired };
            """,
            allowedCapabilities: []
        )
    )

    #expect(observed.result?.output?.objectValue?.array("fired") == [])
}

@Test func timersFireInRegistrationOrderWhenDueTogether() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            const order = [];
            setTimeout(() => order.push('b'), 10);
            setTimeout(() => order.push('a'), 5);
            await new Promise(resolve => setTimeout(resolve, 30));
            return { order };
            """,
            allowedCapabilities: []
        )
    )

    #expect(observed.result?.output?.objectValue?.array("order") == [.string("a"), .string("b")])
}

@Test func anErrorInATimerCallbackBecomesADiagnosticNotACallerThrow() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            setTimeout(() => { throw new Error('boom'); }, 1);
            await new Promise(resolve => setTimeout(resolve, 20));
            return 'survived';
            """,
            allowedCapabilities: []
        )
    )

    // Previously this propagated to whoever called setTimeout, which is not how
    // an event loop behaves.
    #expect(observed.result?.output == .string("survived"))
    let diagnostics = try #require(observed.result?.diagnostics)
    #expect(diagnostics.contains { $0.code == "TIMER_CALLBACK_ERROR" && $0.message.contains("boom") })
}

@Test func anUnsettleablePromiseIsReportedImmediately() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // No resolve path and no queued timer: nothing in this runtime can advance
    // it, so sleeping a thread to the deadline buys nothing.
    let started = Date()
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "await new Promise(() => {}); return 1;",
            allowedCapabilities: [],
            timeoutMs: 30_000
        )
    )

    #expect(observed.error?.code == "JS_RUNTIME_ERROR")
    #expect(observed.error?.message.contains("can never settle") == true)
    #expect(Date().timeIntervalSince(started) < 5)
}

@Test func aTimerStillPendingAtTheDeadlineTimesOut() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // A timer due long after the deadline must not be waited out.
    let started = Date()
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "await new Promise(resolve => setTimeout(resolve, 30000)); return 1;",
            allowedCapabilities: [],
            timeoutMs: 100
        )
    )

    #expect(observed.error?.code == "EXECUTION_TIMEOUT")
    #expect(Date().timeIntervalSince(started) < 5)
}

@Test func aLongBackoffStaysCancellable() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let call = try await tools.executeJavaScript(
        JavaScriptExecutionRequest(
            code: "await new Promise(resolve => setTimeout(resolve, 20000)); return 1;",
            allowedCapabilities: [],
            timeoutMs: 60_000
        )
    )

    Task {
        try? await Task.sleep(nanoseconds: 100_000_000)
        call.cancel()
    }

    let started = Date()
    let observed = await observe(call)
    #expect(observed.error?.code == "CANCELLED")
    #expect(Date().timeIntervalSince(started) < 10)
}

// MARK: - Swallowed bridge failures

@Test func aForgottenAwaitOnAFailedCallIsSurfacedAsADiagnostic() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // Nothing installs an unhandled-rejection hook, so this used to complete with
    // the agent told "done" while a CAPABILITY_DENIED was silently discarded.
    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: """
            apple.keychain.get({ key: 'never-allowed' }).catch(() => {});
            await new Promise(resolve => setTimeout(resolve, 10));
            return 'looks fine';
            """,
            allowedCapabilities: []
        )
    )

    #expect(observed.result?.output == .string("looks fine"))
    let diagnostics = try #require(observed.result?.diagnostics)
    let swallowed = try #require(diagnostics.first { $0.code == "BRIDGE_FAILURES_NOT_SURFACED" })
    #expect(swallowed.message.contains("keychain.read"))
    #expect(swallowed.message.contains("CAPABILITY_DENIED"))
    #expect(swallowed.suggestions.contains { $0.contains("missing await") })
}

@Test func aCleanRunGetsNoSwallowedFailureDiagnostic() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    let observed = try await execute(
        tools,
        request: JavaScriptExecutionRequest(
            code: "await apple.fs.write({ path: 'tmp:ok.txt', data: 'x' }); return 'ok';",
            allowedCapabilities: [.fsWrite]
        )
    )

    #expect(observed.result?.diagnostics.contains { $0.code == "BRIDGE_FAILURES_NOT_SURFACED" } == false)
}
