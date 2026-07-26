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

    /// How often the termination callback runs while a script is executing.
    /// Bounds both timeout overshoot and cancellation latency.
    ///
    /// JavaScriptCore is documented to re-invoke the callback on this interval
    /// when it returns false, but on current OS releases (observed on macOS 26)
    /// returning false permanently disarms the watchdog instead. The callback
    /// therefore re-installs the time limit itself before returning false; see
    /// `codeModeWatchdogShouldTerminate`.
    fileprivate static let checkInterval: TimeInterval = 0.05

    private let lock = NSLock()
    /// `ContinuousClock`, not `Date`: a wall-clock deadline moves when NTP
    /// adjusts the clock, which can push a timeout arbitrarily far out (or fire it
    /// immediately) while a script is running.
    private var deadlineValue: ContinuousClock.Instant
    private var terminationValue: Termination?
    private let cancellationController: ExecutionCancellationController

    init(timeoutMs: Int, cancellationController: ExecutionCancellationController) {
        self.deadlineValue = ContinuousClock.now.advanced(by: .milliseconds(timeoutMs))
        self.cancellationController = cancellationController
    }

    var deadline: ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return deadlineValue
    }

    var hasPassedDeadline: Bool {
        ContinuousClock.now >= deadline
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
        deadlineValue = ContinuousClock.now.advanced(by: .milliseconds(timeoutMs))
        lock.unlock()
    }

    func install(on context: JSContext) {
        guard let contextRef = context.jsGlobalContextRef else {
            return
        }
        let group = JSContextGetGroup(contextRef)
        let info = Unmanaged.passUnretained(self).toOpaque()
        ccodemode_set_execution_time_limit(group, Self.checkInterval, codeModeWatchdogShouldTerminate, info)
    }

    /// Callers must keep the watchdog installed only while `self` is alive; the
    /// callback holds an unretained reference.
    func uninstall(from context: JSContext) {
        guard let contextRef = context.jsGlobalContextRef else {
            return
        }
        ccodemode_clear_execution_time_limit(JSContextGetGroup(contextRef))
    }

    fileprivate func shouldTerminate() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if terminationValue != nil {
            return true
        }
        if cancellationController.isCancelled {
            terminationValue = .cancelled
            return true
        }
        if ContinuousClock.now >= deadlineValue {
            terminationValue = .timedOut
            return true
        }
        return false
    }
}

/// C-convention termination callback passed to `JSContextGroupSetExecutionTimeLimit`.
///
/// A free function rather than a closure so it can reference itself: on current
/// OS releases (observed on macOS 26) JavaScriptCore does not re-arm the time
/// limit when the callback returns false — the callback fires exactly once and
/// the watchdog is dead for the rest of the execution. Re-installing the limit
/// here before returning false restores the documented periodic-check behavior.
/// Verified against a minimal JSC reproduction; without the re-arm a
/// `while (true) {}` script runs forever after the first 50ms check.
private func codeModeWatchdogShouldTerminate(
    _ ctx: JSContextRef?,
    _ info: UnsafeMutableRawPointer?
) -> Bool {
    guard let info else {
        return false
    }
    let watchdog = Unmanaged<ExecutionWatchdog>.fromOpaque(info).takeUnretainedValue()
    if watchdog.shouldTerminate() {
        return true
    }
    if let ctx {
        ccodemode_set_execution_time_limit(
            JSContextGetGroup(ctx),
            ExecutionWatchdog.checkInterval,
            codeModeWatchdogShouldTerminate,
            info
        )
    }
    return false
}
