import Foundation
import Testing
@testable import CodeMode

/// Serialized: most of these hold a GCD worker for the length of a timer, and several
/// pin a slot deliberately. Run concurrently with each other on a small CI
/// runner they starve the global pool — and each other — for tens of seconds.
@Suite(.serialized) struct EventLoopTests {

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
        // The assertion is the lower bound: the delay was previously ignored
        // entirely, so a backoff loop spun. There is deliberately no tight upper
        // bound — a shared CI runner can stretch a 150ms wait by seconds, and the
        // script's own 5s timeoutMs already fails the test if the wait runs away.
        #expect(elapsed >= 0.14)
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

    @Test func timersFireInDueOrderNotRegistrationOrder() async throws {
        let (tools, sandbox) = try makeTools()
        defer { cleanup(sandbox) }

        // Registered late-first, so registration order and due order disagree. This
        // must hold however far the host's sleep overshoots — if enough time passes
        // for both to come due in one tick, they still fire shortest-delay first.
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

    @Test func timersComingDueInOneTickStillFireInDueOrder() async throws {
        let (tools, sandbox) = try makeTools()
        defer { cleanup(sandbox) }

        // Delays below the host's sleep granularity, so both timers reliably come due
        // inside a *single* advanceTimers call — the case that sorting by
        // registration id alone got wrong. Registered late-first so the two orderings
        // disagree; this fails deterministically against the old implementation
        // rather than only on a loaded runner.
        let observed = try await execute(
            tools,
            request: JavaScriptExecutionRequest(
                code: """
                const order = [];
                setTimeout(() => order.push('later'), 2);
                setTimeout(() => order.push('sooner'), 1);
                await new Promise(resolve => setTimeout(resolve, 40));
                return { order };
                """,
                allowedCapabilities: []
            )
        )

        #expect(observed.result?.output?.objectValue?.array("order") == [.string("sooner"), .string("later")])
    }

    @Test func timersDueAtTheSameInstantFireInRegistrationOrder() async throws {
        let (tools, sandbox) = try makeTools()
        defer { cleanup(sandbox) }

        // Equal delays, so only registration order can break the tie.
        let observed = try await execute(
            tools,
            request: JavaScriptExecutionRequest(
                code: """
                const order = [];
                setTimeout(() => order.push('first'), 5);
                setTimeout(() => order.push('second'), 5);
                setTimeout(() => order.push('third'), 5);
                await new Promise(resolve => setTimeout(resolve, 30));
                return { order };
                """,
                allowedCapabilities: []
            )
        )

        #expect(
            observed.result?.output?.objectValue?.array("order")
                == [.string("first"), .string("second"), .string("third")]
        )
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
        // No wall-clock bound: JS_RUNTIME_ERROR rather than EXECUTION_TIMEOUT
        // already proves the 30s budget was not run out.
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
        // No wall-clock bound: had the 30s timer been waited out the script would
        // have returned 1, not timed out. The error code is the proof.
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
        // Proves cancel interrupted the 20s timer rather than waiting it out.
        #expect(Date().timeIntervalSince(started) < 15)
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

    // MARK: - Lifetime and slot semantics

    @Test func iteratingEventsAfterDroppingTheCallDoesNotCancelTheExecution() async throws {
        let (tools, sandbox) = try makeTools()
        defer { cleanup(sandbox) }

        // Swift does not keep a local alive to the end of its scope, so a host that
        // reads `call.events` and never touches `call` again may have it released
        // mid-iteration in an optimized build. Cancelling in the call's deinit cut
        // that host off. Force the release explicitly here rather than hoping the
        // optimizer does it.
        var call: JavaScriptExecutionCall? = try await tools.executeJavaScript(
            JavaScriptExecutionRequest(
                code: """
                console.log('start');
                await new Promise(resolve => setTimeout(resolve, 200));
                console.log('end');
                return 'finished';
                """,
                allowedCapabilities: []
            )
        )
        let events = call!.events
        call = nil

        var sawFinished = false
        var sawEnd = false
        for await event in events {
            if case .finished = event { sawFinished = true }
            if case let .log(entry) = event, entry.message == "end" { sawEnd = true }
        }

        #expect(sawEnd)
        #expect(sawFinished)
    }

    @Test func droppingBothTheCallAndItsStreamCancelsTheExecution() async throws {
        // One slot: if the dropped execution were still running, the second call
        // could not start until its 20s timer elapsed.
        let (tools, sandbox) = try makeTools(
            executionLimits: ExecutionLimits(maxConcurrentExecutions: 1)
        )
        defer { cleanup(sandbox) }

        func startAndDrop() async throws {
            let dropped = try await tools.executeJavaScript(
                JavaScriptExecutionRequest(
                    code: "await new Promise(resolve => setTimeout(resolve, 20000)); return 1;",
                    allowedCapabilities: [],
                    timeoutMs: 60_000
                )
            )
            _ = dropped.events
            // Give it a moment to actually occupy the slot before we drop it.
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try await startAndDrop()

        let started = Date()
        let observed = try await execute(
            tools,
            request: JavaScriptExecutionRequest(code: "return 'got the slot';", allowedCapabilities: [], timeoutMs: 5_000)
        )

        #expect(observed.result?.output == .string("got the slot"))
        #expect(Date().timeIntervalSince(started) < 15, "the dropped execution must have released its slot")
    }

    @Test func cancellingWhileWaitingForASlotNeverRunsTheScript() async throws {
        let (tools, sandbox) = try makeTools(
            executionLimits: ExecutionLimits(maxConcurrentExecutions: 1)
        )
        defer { cleanup(sandbox) }

        // Occupy the only slot.
        let occupant = try await tools.executeJavaScript(
            JavaScriptExecutionRequest(
                code: "await new Promise(resolve => setTimeout(resolve, 3000)); return 'occupant';",
                allowedCapabilities: [],
                timeoutMs: 30_000
            )
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        // This one parks waiting for the slot. Cancel it there: it must report
        // CANCELLED and must never have executed — the file it would write is the
        // evidence.
        let parked = try await tools.executeJavaScript(
            JavaScriptExecutionRequest(
                code: "await apple.fs.write({ path: 'tmp:ran.txt', data: 'x' }); return 'ran';",
                allowedCapabilities: [.fsWrite],
                timeoutMs: 30_000
            )
        )
        try await Task.sleep(nanoseconds: 100_000_000)
        parked.cancel()

        let parkedOutcome = await observe(parked)
        #expect(parkedOutcome.error?.code == "CANCELLED")
        #expect(FileManager.default.fileExists(atPath: sandbox.tmp.appendingPathComponent("ran.txt").path) == false)

        // The occupant is unaffected and the slot still hands over cleanly afterwards.
        let occupantOutcome = await observe(occupant)
        #expect(occupantOutcome.result?.output == .string("occupant"))
    }

    @Test func cancellationInterruptsASleepImmediately() throws {
        let controller = ExecutionCancellationController()
        let entered = DispatchSemaphore(value: 0)
        let woke = DispatchSemaphore(value: 0)

        // A polling sleep would not notice the cancel until its next slice; an
        // interruptible one returns as soon as the cancel lands. Synchronous test on
        // purpose: the sleeper is a real blocked thread, as it is in the runtime.
        DispatchQueue.global().async {
            entered.signal()
            controller.sleep(until: Date(timeIntervalSinceNow: 30))
            woke.signal()
        }

        // Wait for the sleeper to actually be scheduled before cancelling. On a
        // starved runner the dispatch alone can take seconds, and cancelling before
        // the sleep has begun measures scheduling, not the wake-up this test is
        // about. The generous bound here is for scheduling; the tight one below is
        // for the wake.
        #expect(entered.wait(timeout: .now() + 60) == .success, "sleeper never got a thread")
        let cancelledAt = Date()
        controller.cancel()

        #expect(woke.wait(timeout: .now() + 10) == .success)
        #expect(Date().timeIntervalSince(cancelledAt) < 5)
    }

    @Test func sleepReturnsAtTheDeadlineWhenNotCancelled() {
        let controller = ExecutionCancellationController()
        let started = Date()
        controller.sleep(until: Date(timeIntervalSinceNow: 0.1))
        #expect(Date().timeIntervalSince(started) >= 0.09)
        #expect(controller.isCancelled == false)
    }
}
