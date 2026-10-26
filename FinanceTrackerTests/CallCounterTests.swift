import Testing
@testable import FinanceTracker

// The wait helpers on both fakes delegate to CallCounter, so a lost or doubled resume here
// would hang or crash the ImportViewModel tests that use them.
@Suite("CallCounter", .timeLimit(.minutes(1)))
struct CallCounterTests {
    @Test func waiterResumesOnlyOnceThresholdIsReached() async throws {
        let counter = CallCounter()
        let waiter = Task { try await counter.waitUntil(2) }
        try await waitUntilSuspended(counter)

        counter.increment()
        #expect(counter.waiterCount == 1)   // 1 of 2: still suspended
        counter.increment()
        #expect(counter.waiterCount == 0)
        try await value(of: waiter)
    }

    @Test func cancellingASuspendedWaiterThrows() async throws {
        let counter = CallCounter()
        let waiter = Task { try await counter.waitUntil(1) }
        try await waitUntilSuspended(counter)

        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await value(of: waiter) }
        #expect(counter.waiterCount == 0)
        counter.increment()   // the cancelled waiter was removed, so nothing resumes twice
    }

    @Test func alreadyCancelledTaskThrowsWithoutRegistering() async {
        let counter = CallCounter()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await counter.waitUntil(1)
        }
        await #expect(throws: CancellationError.self) { try await value(of: waiter) }
        #expect(counter.waiterCount == 0)
    }

    @Test func returnsImmediatelyWhenThresholdAlreadyReached() async throws {
        let counter = CallCounter()
        counter.increment()
        counter.increment()

        try await counter.waitUntil(2)
        try await counter.waitUntil(1)
        #expect(counter.waiterCount == 0)
    }

    /// Yields until a waiter is registered, checking cancellation so the time limit can
    /// stop it if `waitUntil` never registers one.
    private func waitUntilSuspended(_ counter: CallCounter) async throws {
        while counter.waiterCount == 0 {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    /// Awaits `task`, cancelling it when this test is cancelled: an unstructured `Task`
    /// does not inherit cancellation, so without this the time limit can't stop a waiter
    /// whose resume was lost.
    private func value(of task: Task<Void, Error>) async throws {
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
