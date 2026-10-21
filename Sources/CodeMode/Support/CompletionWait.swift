import Foundation

/// Bridges a callback-style system API into the bridges' synchronous world.
///
/// The pattern this replaces — a `var` written from the framework's completion
/// queue, read after `_ = semaphore.wait(...)` with the timeout result
/// discarded — is a data race on timeout: the late callback writes while the
/// caller reads, and the caller cannot tell "timed out" from "no results". Every
/// wait here either produces the value the callback delivered or throws
/// `BridgeError.timeout`; the box stays alive for a late callback to write into
/// harmlessly.
enum CompletionWait {
    /// Runs `operation`, which must call its `complete` argument exactly once,
    /// and returns the delivered value.
    ///
    /// - Throws: `BridgeError.timeout` if `complete` is not called in time.
    static func value<Value>(
        timeout: TimeInterval,
        operationName: String,
        _ operation: (@escaping @Sendable (Value) -> Void) -> Void
    ) throws -> Value {
        let box = LockedBox<Value?>(nil)
        let semaphore = DispatchSemaphore(value: 0)

        operation { value in
            box.set(value)
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            throw BridgeError.timeout(milliseconds: Int(timeout * 1_000))
        }

        guard let value = box.get() else {
            throw BridgeError.nativeFailure("\(operationName) completed without a result")
        }

        return value
    }

    /// Waits for a completion that carries no value, for APIs whose result is
    /// read back from the store afterwards.
    ///
    /// - Returns: true when the callback arrived, false on timeout. Callers that
    ///   must distinguish the two should use `value(timeout:operationName:_:)`.
    @discardableResult
    static func completion(
        timeout: TimeInterval,
        _ operation: (@escaping @Sendable () -> Void) -> Void
    ) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        operation { semaphore.signal() }
        return semaphore.wait(timeout: .now() + timeout) == .success
    }
}
