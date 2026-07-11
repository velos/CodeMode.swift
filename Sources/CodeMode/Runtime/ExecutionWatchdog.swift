import Foundation
import JavaScriptCore
import CCodeModeJSC

/// Preemptively terminates JavaScript that runs past its deadline or is cancelled.
///
/// Bridge calls are synchronous, so the entire user script — including its full
/// promise graph — settles inside a single `evaluateScript` call. A wall-clock
/// check after evaluation can therefore never interrupt CPU-bound code such as
/// `while (true) {}`. This installs a JavaScriptCore execution time limit whose
/// callback re-checks the deadline and the cancellation flag on a short interval
/// and terminates the script when either trips.
///
/// The underlying `JSContextGroupSetExecutionTimeLimit` API is reached through
/// the `CCodeModeJSC` shim because it is exported by JavaScriptCore but declared
/// only in a private WebKit header. It is the only mechanism JavaScriptCore
/// offers for interrupting runaway scripts; hosts shipping to the App Store
/// should be aware they are relying on this exported-but-private symbol.
///
/// Because the time limit is measured against script CPU time, a synchronous
/// bridge call that blocks on native I/O (network, a UI picker) does not itself
/// count against the deadline while it is blocked, but the time already elapsed
/// does: `timeoutMs` bounds total wall-clock across an execution, so hosts that
/// present long-running UI or issue slow requests should size `timeoutMs`
/// accordingly.
final class ExecutionWatchdog: @unchecked Sendable {
    enum Termination: Sendable {
        case timedOut
        case cancelled
    }

    /// How often JavaScriptCore re-invokes the termination callback while a
    /// script is executing. Bounds both timeout overshoot and cancellation latency.
    private static let checkInterval: TimeInterval = 0.05

    private let lock = NSLock()
    private var deadlineValue: Date
    private var terminationValue: Termination?
    private let cancellationController: ExecutionCancellationController

    init(timeoutMs: Int, cancellationController: ExecutionCancellationController) {
        self.deadlineValue = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        self.cancellationController = cancellationController
    }

    var deadline: Date {
        lock.lock()
        defer { lock.unlock() }
        return deadlineValue
    }

    var termination: Termination? {
        lock.lock()
        defer { lock.unlock() }
        return terminationValue
    }

    /// Starts a fresh time budget for a follow-on phase such as serializing the
    /// result. A script that settled close to the original deadline still gets a
    /// bounded-but-usable window to run `JSON.stringify` (which may invoke
    /// user-defined getters/`toJSON`), while a runaway getter is still terminated.
    func rearm(timeoutMs: Int) {
        lock.lock()
        deadlineValue = Date().addingTimeInterval(Double(timeoutMs) / 1_000)
        lock.unlock()
    }

    func install(on context: JSContext) {
        guard let contextRef = context.jsGlobalContextRef else {
            return
        }
        let group = JSContextGetGroup(contextRef)
        let info = Unmanaged.passUnretained(self).toOpaque()
        ccodemode_set_execution_time_limit(
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
        ccodemode_clear_execution_time_limit(JSContextGetGroup(contextRef))
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
        if Date() >= deadlineValue {
            terminationValue = .timedOut
            return true
        }
        return false
    }
}
