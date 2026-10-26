import Testing
@testable import FinanceTracker

// The wait helpers on both fakes delegate to CallCounter, so a lost or doubled resume here
// would hang or crash the ImportViewModel tests that use them.
@Suite("CallCounter", .timeLimit(.minutes(1)))
struct CallCounterTests {
    @Test func waiterResumesOnlyOnceThresholdIsReached() async throws {
        let counter = CallCounter()
        let waiter = Task { try await counter.waitUntil(2) }
        while counter.waiterCount == 0 { await Task.yield() }

        counter.increment()
        #expect(counter.waiterCount == 1)   // 1 of 2: still suspended
        counter.increment()
        #expect(counter.waiterCount == 0)
        try await waiter.value
    }

    @Test func cancellingASuspendedWaiterThrows() async {
        let counter = CallCounter()
        let waiter = Task { try await counter.waitUntil(1) }
        while counter.waiterCount == 0 { await Task.yield() }

        waiter.cancel()
        await #expect(throws: CancellationError.self) { try await waiter.value }
        #expect(counter.waiterCount == 0)
        counter.increment()   // the cancelled waiter was removed, so nothing resumes twice
    }

    @Test func alreadyCancelledTaskThrowsWithoutRegistering() async {
        let counter = CallCounter()
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await counter.waitUntil(1)
        }
        await #expect(throws: CancellationError.self) { try await waiter.value }
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
}
