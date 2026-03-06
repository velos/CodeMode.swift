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
    private var logs: [ExecutionLog] = []
    private var diagnostics: [ToolDiagnostic] = []
    private var permissionEvents: [PermissionEvent] = []
    private let emitEvent: @Sendable (JavaScriptExecutionEvent) -> Void

    init(emitEvent: @escaping @Sendable (JavaScriptExecutionEvent) -> Void = { _ in }) {
        self.emitEvent = emitEvent
    }

    func record(log: ExecutionLog) {
        lock.lock()
        logs.append(log)
        lock.unlock()
        emitEvent(.log(log))
    }

    func record(diagnostic: ToolDiagnostic) {
        lock.lock()
        diagnostics.append(diagnostic)
        lock.unlock()

        if diagnostic.severity != .error {
            emitEvent(.diagnostic(diagnostic))
        }
    }

    func record(permissionEvent: PermissionEvent) {
        lock.lock()
        permissionEvents.append(permissionEvent)
        lock.unlock()
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
