import Foundation

/// The runtime's source of time, so the parts of execution that wait — the
/// timer loop and the watchdog deadline — can be driven by a virtual clock under
/// test instead of by real elapsed time.
///
/// Production always uses `RealClock`. The seam exists because timer tests that
/// really slept were the least reliable tests in the suite: their assertions were
/// wall-clock bounds, and a loaded CI runner turned a 150ms wait into seconds.
/// Under a `VirtualClock` a sleep is a jump, so those tests are instant and
/// exact, and they can assert on how long the runtime *asked* to wait rather
/// than on how long the machine took.
///
/// Watchdog termination of a CPU-bound script stays real-time regardless: it is
/// driven by JavaScriptCore's own execution-time callback, which virtual time
/// cannot advance. Tests of that path use `RealClock`.
protocol RuntimeClock: Sendable {
    var now: ContinuousClock.Instant { get }

    /// Blocks until `deadline` or until `cancellation` fires, whichever is
    /// first. A virtual clock jumps instead of blocking.
    func sleep(until deadline: ContinuousClock.Instant, cancellation: ExecutionCancellationController)
}

struct RealClock: RuntimeClock {
    var now: ContinuousClock.Instant { ContinuousClock.now }

    func sleep(until deadline: ContinuousClock.Instant, cancellation: ExecutionCancellationController) {
        // The wall-clock `Date` is only the wake-up hint; callers re-check
        // against `now`, so an NTP adjustment cannot move a deadline.
        let seconds = max(0, (deadline - ContinuousClock.now).milliseconds / 1_000)
        cancellation.sleep(until: Date(timeIntervalSinceNow: seconds))
    }
}

/// A clock that only moves when the runtime sleeps.
///
/// `sleep(until:)` advances `now` to the deadline — plus `overshoot`, which
/// models a slow machine waking late. That is the one condition a real clock
/// cannot reproduce on demand, and it is exactly the condition that exposed the
/// timer-ordering bug: two timers with different delays both coming due in one
/// tick.
final class VirtualClock: RuntimeClock, @unchecked Sendable {
    private let base = ContinuousClock.now
    private let lock = NSLock()
    private var offset: Duration = .zero
    let overshoot: Duration

    init(overshoot: Duration = .zero) {
        self.overshoot = overshoot
    }

    var now: ContinuousClock.Instant {
        base.advanced(by: elapsed)
    }

    /// Total virtual time the runtime has slept through.
    var elapsed: Duration {
        lock.lock()
        defer { lock.unlock() }
        return offset
    }

    func sleep(until deadline: ContinuousClock.Instant, cancellation: ExecutionCancellationController) {
        // A cancelled sleep returns without advancing, as a real one would wake
        // early; the caller's interrupt check then throws.
        guard cancellation.isCancelled == false else {
            return
        }
        lock.lock()
        offset = max(offset, (deadline - base) + overshoot)
        lock.unlock()
    }
}

extension Duration {
    /// Whole and fractional milliseconds. `components` splits into seconds plus
    /// attoseconds, which is otherwise an awkward two-term conversion.
    var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }
}
