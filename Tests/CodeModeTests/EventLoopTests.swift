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

// MARK: - Bounded concurrency

@Test func concurrentExecutionsAllCompleteAndStayIsolated() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxConcurrentExecutions: 3)
    )
    defer { cleanup(sandbox) }

    // The concurrent execution queue is a core design point but had no test, and
    // no width limit: each execution blocks its thread for the whole run, so N
    // parallel calls meant N blocked GCD threads and N live JavaScriptCore VMs.
    // More executions than slots must still all complete, each with its own
    // context and its own result.
    let results = try await withThrowingTaskGroup(of: (Int, JSONValue?).self) { group in
        for index in 0..<12 {
            group.addTask {
                let observed = try await execute(
                    tools,
                    request: JavaScriptExecutionRequest(
                        code: """
                        await apple.fs.write({ path: 'tmp:worker-\(index).txt', data: 'value-\(index)' });
                        const read = await apple.fs.read({ path: 'tmp:worker-\(index).txt' });
                        return { index: \(index), text: read.text, leaked: typeof globalThis.__leaked };
                        """,
                        allowedCapabilities: [.fsRead, .fsWrite],
                        timeoutMs: 20_000
                    )
                )
                return (index, observed.result?.output)
            }
        }

        var collected: [Int: JSONValue?] = [:]
        for try await (index, output) in group {
            collected[index] = output
        }
        return collected
    }

    #expect(results.count == 12)
    for index in 0..<12 {
        let output = try #require(results[index]??.objectValue)
        #expect(output.int("index") == index)
        #expect(output.string("text") == "value-\(index)")
        // A fresh JSContext per execution: no state carries between them.
        #expect(output.string("leaked") == "undefined")
    }
}

@Test func executionsBeyondTheSlotLimitQueueRatherThanFail() async throws {
    let (tools, sandbox) = try makeTools(
        executionLimits: ExecutionLimits(maxConcurrentExecutions: 1)
    )
    defer { cleanup(sandbox) }

    // With one slot these serialize; the point is that the extras wait for a slot
    // instead of erroring, and that waiting for a slot does not count against the
    // per-execution timeout.
    let outputs = try await withThrowingTaskGroup(of: JSONValue?.self) { group in
        for index in 0..<4 {
            group.addTask {
                try await execute(
                    tools,
                    request: JavaScriptExecutionRequest(
                        code: "await new Promise(r => setTimeout(r, 60)); return \(index);",
                        allowedCapabilities: [],
                        timeoutMs: 500
                    )
                ).result?.output
            }
        }
        var collected: [JSONValue?] = []
        for try await output in group {
            collected.append(output)
        }
        return collected
    }

    #expect(outputs.compactMap { $0?.intValue }.sorted() == [0, 1, 2, 3])
}

@Test func aResultThatSettlesRightAtTheDeadlineIsNotDiscarded() async throws {
    let (tools, sandbox) = try makeTools()
    defer { cleanup(sandbox) }

    // The settled state must be read before the deadline is enforced. Checking
    // the deadline first turns a script that fulfilled a hair late into a
    // spurious timeout, discarding a result that already exists.
    for _ in 0..<12 {
        let observed = try await execute(
            tools,
            request: JavaScriptExecutionRequest(
                code: "await new Promise(resolve => setTimeout(resolve, 40)); return 'settled';",
                allowedCapabilities: [],
                timeoutMs: 40
            )
        )
        // Either outcome is legitimate under the race, but a fulfilled script
        // must never come back empty *and* successful.
        if observed.error == nil {
            #expect(observed.result?.output == .string("settled"))
        } else {
            #expect(observed.error?.code == "EXECUTION_TIMEOUT")
        }
    }
}
