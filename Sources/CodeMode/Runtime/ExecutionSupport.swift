import Foundation

final class ExecutionCancellationController: @unchecked Sendable {
    private let condition = NSCondition()
    private var cancelled = false

    func cancel() {
        condition.lock()
        cancelled = true
        // Wakes anything parked in `sleep(until:)`, so a cancel lands
        // immediately instead of at the next poll.
        condition.broadcast()
        condition.unlock()
    }

    var isCancelled: Bool {
        condition.lock()
        defer { condition.unlock() }
        return cancelled
    }

    /// Blocks until `date` or until cancelled, whichever is first. The timer
    /// loop used to poll `Thread.sleep` in 5ms slices — 200 wakeups a second per
    /// sleeping execution, and up to 5ms of cancellation latency — where one
    /// interruptible wait does both jobs.
    func sleep(until date: Date) {
        condition.lock()
        defer { condition.unlock() }
        while cancelled == false, Date() < date {
            condition.wait(until: date)
        }
    }
}

/// Bounds how many executions run at once, parking the excess as suspended
/// tasks rather than blocked threads.
///
/// A `DispatchSemaphore` acquired on the GCD worker got this exactly backwards:
/// every execution beyond the limit held a thread while waiting for a slot, which
/// is the resource the limit exists to protect. Waiters here cost nothing until
/// a slot frees, and a cancelled waiter leaves the queue without ever running.
actor ExecutionSlots {
    private var available: Int
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var cancelledBeforeParking: Set<UUID> = []

    init(count: Int) {
        available = max(1, count)
    }

    func acquire() async throws {
        try Task.checkCancellation()
        if available > 0 {
            available -= 1
            return
        }

        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                // The cancellation handler can run before this closure does; if it
                // already did, do not park at all.
                if cancelledBeforeParking.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.withdraw(id) }
        }
    }

    func release() {
        // Hand the slot straight to the next waiter; `available` only grows when
        // nobody is waiting for it.
        if waiters.isEmpty == false {
            waiters.removeFirst().continuation.resume()
        } else {
            available += 1
        }
    }

    private func withdraw(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            waiters.remove(at: index).continuation.resume(throwing: CancellationError())
        } else {
            cancelledBeforeParking.insert(id)
        }
    }
}

/// Cancels an execution once nothing can observe its outcome.
///
/// Held by both the `JavaScriptExecutionCall` and its events stream, so the
/// execution keeps running while *either* is reachable — a host iterating
/// `call.events` after its last use of `call` is still observing. Cancelling in
/// the call's own `deinit` cut that host off mid-stream: Swift does not keep a
/// local alive to the end of its scope, and an optimized build released `call` as
/// soon as `.events` had been read.
final class ExecutionObservationToken: @unchecked Sendable {
    private let onDrop: @Sendable () -> Void

    init(onDrop: @escaping @Sendable () -> Void) {
        self.onDrop = onDrop
    }

    deinit {
        onDrop()
    }
}

final class ExecutionTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private let limits: ExecutionLimits
    private var logs: [ExecutionLog] = []
    private var diagnostics: [ToolDiagnostic] = []
    private var permissionEvents: [PermissionEvent] = []
    private var noticedLogOverflow = false
    private let emitEvent: @Sendable (JavaScriptExecutionEvent) -> Void

    init(
        limits: ExecutionLimits = .standard,
        emitEvent: @escaping @Sendable (JavaScriptExecutionEvent) -> Void = { _ in }
    ) {
        self.limits = limits
        self.emitEvent = emitEvent
    }

    func record(log: ExecutionLog) {
        var entry = log
        entry.message = Self.elide(entry.message, to: limits.maxLogMessageCharacters)

        // Keep the first N: the beginning of a runaway log is where the cause is,
        // and the tail is the same line a million times.
        lock.lock()
        let accepted = logs.count < limits.maxLogEntries
        let isFirstOverflow = accepted == false && noticedLogOverflow == false
        if accepted {
            logs.append(entry)
        } else {
            noticedLogOverflow = true
        }
        lock.unlock()

        if accepted {
            // Streaming stays live even after the retained transcript is full;
            // it is the retained copy — re-copied into every CodeModeToolError —
            // that is the memory risk.
            emitEvent(.log(entry))
        } else if isFirstOverflow {
            record(
                diagnostic: ToolDiagnostic(
                    severity: .warning,
                    code: "LOG_LIMIT_REACHED",
                    message: "Kept the first \(limits.maxLogEntries) console.log entries; later entries are dropped.",
                    category: "execution",
                    suggestions: ["Log summaries rather than per-item lines, or return the data instead of logging it."]
                )
            )
        }
    }

    func record(diagnostic: ToolDiagnostic) {
        lock.lock()
        let accepted = diagnostics.count < limits.maxDiagnostics
        if accepted {
            diagnostics.append(diagnostic)
        }
        lock.unlock()

        // Error-severity diagnostics used to be recorded but never emitted, so a
        // host watching the stream saw every diagnostic *except* the ones that
        // mattered most. They are on the result either way; the stream is the
        // live view and should not be the incomplete one.
        if accepted {
            emitEvent(.diagnostic(diagnostic))
        }
    }

    func record(permissionEvent: PermissionEvent) {
        lock.lock()
        if permissionEvents.count < limits.maxPermissionEvents {
            permissionEvents.append(permissionEvent)
        }
        lock.unlock()
    }

    /// Elides the middle of an over-long message, keeping both ends: a stack
    /// trace's origin and its outcome are usually at opposite ends.
    private static func elide(_ message: String, to limit: Int) -> String {
        guard limit > 0, message.count > limit else {
            return message
        }
        let keep = max(1, (limit - 1) / 2)
        let head = message.prefix(keep)
        let tail = message.suffix(keep)
        return "\(head)… [\(message.count - 2 * keep) characters elided] …\(tail)"
    }

    func snapshot(output: JSONValue? = nil) -> JavaScriptExecutionResult {
        lock.lock()
        defer { lock.unlock() }
        return JavaScriptExecutionResult(
            output: output,
            logs: logs,
            diagnostics: diagnostics,
            permissionEvents: permissionEvents
        )
    }
}
