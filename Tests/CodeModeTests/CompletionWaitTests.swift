import Foundation
import Testing
@testable import CodeMode

// The pattern this replaces — a `var` written from a framework's completion
// queue and read after a semaphore wait whose timeout result was discarded — is
// both a data race and an ambiguity: the caller could not tell "timed out" from
// "the API returned nothing".

@Test func completionWaitReturnsTheDeliveredValue() throws {
    let value = try CompletionWait.value(timeout: 5, operationName: "test") { complete in
        DispatchQueue.global().async { complete([1, 2, 3]) }
    }
    #expect(value == [1, 2, 3])
}

@Test func completionWaitThrowsRatherThanReturningAnEmptyResult() {
    do {
        // Never completes: the old shape returned `.array([])`, indistinguishable
        // from a genuinely empty fetch.
        let value: [Int] = try CompletionWait.value(timeout: 0.1, operationName: "reminders.read") { _ in }
        Issue.record("Expected a timeout, got \(value)")
    } catch {
        #expect(requireBridgeErrorCode(error) == "EXECUTION_TIMEOUT")
    }
}

@Test func completionWaitToleratesALateCallback() throws {
    // The late write must land in the box rather than racing a caller's read.
    let lateCallbackFinished = DispatchSemaphore(value: 0)
    do {
        let _: Int = try CompletionWait.value(timeout: 0.05, operationName: "test") { complete in
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
                complete(7)
                lateCallbackFinished.signal()
            }
        }
        Issue.record("Expected a timeout")
    } catch {
        #expect(requireBridgeErrorCode(error) == "EXECUTION_TIMEOUT")
    }

    // Generous on purpose: the suite runs in parallel and this runtime's timer
    // waits block GCD workers, so a 0.2s dispatch can be starved for seconds on a
    // loaded runner. The assertion is that the late callback lands at all.
    #expect(lateCallbackFinished.wait(timeout: .now() + 60) == .success)
}

@Test func completionWaitReportsWhetherTheCallbackArrived() {
    #expect(CompletionWait.completion(timeout: 5) { complete in complete() })
    #expect(CompletionWait.completion(timeout: 0.05) { _ in } == false)
}
