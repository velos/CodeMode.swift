import Foundation
import JavaScriptCore

/// Preemptively terminates JavaScript that runs past its deadline or is cancelled.
///
/// Bridge calls are synchronous, so the entire user script — including its full
/// promise graph — settles inside a single `evaluateScript` call. A wall-clock
/// check after evaluation can therefore never interrupt CPU-bound code such as
/// `while (true) {}`. This installs a JavaScriptCore execution time limit whose
/// callback re-checks the deadline and the cancellation flag on a short interval
/// and terminates the script when either trips.
final class ExecutionWatchdog: @unchecked Sendable {
    enum Termination: Sendable {
        case timedOut
        case cancelled
    }

    /// How often JavaScriptCore re-invokes the termination callback while a
    /// script is executing. Bounds both timeout overshoot and cancellation latency.
    private static let checkInterval: TimeInterval = 0.05

    let deadline: Date

    private let lock = NSLock()
    private var terminationValue: Termination?
    private let cancellationController: ExecutionCancellationController

    init(timeoutMs: Int, cancellationController: ExecutionCancellationController) {
        self.deadline = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        self.cancellationController = cancellationController
    }

    var termination: Termination? {
        lock.lock()
        defer { lock.unlock() }
        return terminationValue
    }

    func install(on context: JSContext) {
        guard let contextRef = context.jsGlobalContextRef else {
            return
        }
        let group = JSContextGetGroup(contextRef)
        let info = Unmanaged.passUnretained(self).toOpaque()
        JSContextGroupSetExecutionTimeLimit(
            group,
            Self.checkInterval,
            { _, info in
                guard let info else {
                    return false
                }
                return Unmanaged<ExecutionWatchdog>
                    .fromOpaque(info)
                    .takeUnretainedValue()
                    .shouldTerminate()
            },
            info
        )
    }

    /// Callers must keep the watchdog installed only while `self` is alive; the
    /// callback holds an unretained reference.
    func uninstall(from context: JSContext) {
        guard let contextRef = context.jsGlobalContextRef else {
            return
        }
        JSContextGroupClearExecutionTimeLimit(JSContextGetGroup(contextRef))
    }

    private func shouldTerminate() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if terminationValue != nil {
            return true
        }
        if cancellationController.isCancelled {
            terminationValue = .cancelled
            return true
        }
        if Date() >= deadline {
            terminationValue = .timedOut
            return true
        }
        return false
    }
}
