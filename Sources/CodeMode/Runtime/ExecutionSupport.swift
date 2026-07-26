import Foundation

final class ExecutionCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

final class ExecutionTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private let limits: ExecutionLimits
    private var logs: [ExecutionLog] = []
    private var diagnostics: [ToolDiagnostic] = []
    private var permissionEvents: [PermissionEvent] = []
    private var droppedLogs = 0
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

        var overflowNotice: ToolDiagnostic?
        lock.lock()
        if logs.count >= limits.maxLogEntries {
            // Keep the first N: the beginning of a runaway log is where the
            // cause is, and the tail is the same line a million times.
            droppedLogs += 1
            if noticedLogOverflow == false {
                noticedLogOverflow = true
                overflowNotice = ToolDiagnostic(
                    severity: .warning,
                    code: "LOG_LIMIT_REACHED",
                    message: "Kept the first \(limits.maxLogEntries) console.log entries; later entries are dropped.",
                    category: "execution",
                    suggestions: ["Log summaries rather than per-item lines, or return the data instead of logging it."]
                )
            }
            lock.unlock()
        } else {
            logs.append(entry)
            lock.unlock()
            // Streaming stays live even after the retained transcript is full;
            // it is the retained copy — re-copied into every CodeModeToolError —
            // that is the memory risk.
            emitEvent(.log(entry))
        }

        if let overflowNotice {
            record(diagnostic: overflowNotice)
        }
    }

    func record(diagnostic: ToolDiagnostic) {
        lock.lock()
        let accepted = diagnostics.count < limits.maxDiagnostics
        if accepted {
            diagnostics.append(diagnostic)
        }
        lock.unlock()

        if accepted, diagnostic.severity != .error {
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
