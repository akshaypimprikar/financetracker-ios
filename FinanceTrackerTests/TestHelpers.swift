import Foundation
import SwiftData
import Synchronization
@testable import FinanceTracker

func makeContainer() throws -> ModelContainer {
    let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// The two fakes below are Mutex-backed final classes, not actors: under whole-module
// compilation on Swift 6.4 (Xcode 27), an actor declared in this test module that conforms
// to the `compiler(>=6.4)` `nonisolated` `TransactionImportWriting` fails with
// "'nonisolated' modifier cannot be applied to this declaration". The app target's own
// `TransactionImportActor` conforms to the same protocol and compiles, so the failure is
// specific to the cross-module (`@testable`) conformer, and the default batch mode compiles
// both, so only whole-module mode fails (checked on Xcode 27.1, 2026-10-23). AGENTS.md's
// test-fake rule points here. Every state read-modify-write happens inside one `withLock`;
// state that never changes after `init` is a `let` outside the lock.

/// A running count a test can wait on. `waitUntil(_:)` returns once `increment()` has
/// been called at least `threshold` times. If the waiting task is cancelled first (for
/// example by a `.timeLimit` trait), it throws `CancellationError`, so a test whose code
/// under test stops short fails instead of hanging. Continuations resume outside the lock.
final class CallCounter: Sendable {
    private struct State {
        var count = 0
        var nextWaiterID = 0
        var waiters: [Int: (threshold: Int, continuation: CheckedContinuation<Void, Never>)] = [:]
    }

    private let state = Mutex(State())

    var count: Int { state.withLock { $0.count } }

    /// Waiters registered and not yet resumed; lets `CallCounterTests` act once a wait is
    /// known to be suspended instead of guessing with a sleep.
    var waiterCount: Int { state.withLock { $0.waiters.count } }

    func increment() {
        let due = state.withLock { state in
            state.count += 1
            let count = state.count
            let dueIDs = state.waiters.filter { count >= $0.value.threshold }.keys
            return dueIDs.compactMap { state.waiters.removeValue(forKey: $0)?.continuation }
        }
        for continuation in due { continuation.resume() }
    }

    func waitUntil(_ threshold: Int) async throws {
        let id = state.withLock { state in
            defer { state.nextWaiterID += 1 }
            return state.nextWaiterID
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // Checking cancellation under the same lock as `onCancel` resumes the
                // continuation exactly once, whichever of the two runs first.
                let resumeNow = state.withLock { state in
                    if state.count >= threshold || Task.isCancelled { return true }
                    state.waiters[id] = (threshold: threshold, continuation: continuation)
                    return false
                }
                if resumeNow { continuation.resume() }
            }
        } onCancel: {
            state.withLock { $0.waiters.removeValue(forKey: id) }?.continuation.resume()
        }
        // A cancelled wait resumes without reaching the threshold; throwing here keeps
        // the caller from carrying on as if it had.
        try Task.checkCancellation()
    }
}

final class FakeTransactionImportWriting: TransactionImportWriting {
    private struct State {
        var savedChunkCount = 0
        var delayPerChunk: Duration?
        var failNextSave: Error?
        var failAfterSuccesses: Int?
        var failExistingHashes: Error?
    }

    private let storedHashes: Set<String>
    private let state = Mutex(State())
    private let chunkStarts = CallCounter()

    init(existingHashes: Set<String> = []) {
        self.storedHashes = existingHashes
    }

    var savedChunkCount: Int { state.withLock { $0.savedChunkCount } }

    func setDelayPerChunk(_ delay: Duration) {
        state.withLock { $0.delayPerChunk = delay }
    }

    /// Deterministic replacement for a guessed `Task.sleep` race window: suspends
    /// until at least `count` calls to `save(chunk:accountID:)` have been entered
    /// (before any artificial delay), so a test can act (e.g. cancel) at a known
    /// point instead of hoping a wall-clock sleep lands inside the delay window.
    func waitUntilChunksStarted(_ count: Int) async throws {
        try await chunkStarts.waitUntil(count)
    }

    func setFailNextSave(with error: Error) {
        state.withLock { $0.failNextSave = error }
    }

    /// Deterministic partial-failure mode: the first `count` calls (across however
    /// many concurrent chunk tasks race into this fake — the check and the increment
    /// happen inside one lock) succeed; every call after that throws. Robust to
    /// TaskGroup scheduling order since the threshold is a running total, not
    /// "the Nth specific call."
    func setFailAfter(successfulSaves count: Int) {
        state.withLock { $0.failAfterSuccesses = count }
    }

    /// One-shot failure for the next `existingHashes()` call — mirrors `setFailNextSave`.
    func setFailNextExistingHashes(_ error: Error) {
        state.withLock { $0.failExistingHashes = error }
    }

    func existingHashes() async throws -> Set<String> {
        try state.withLock { state in
            if let error = state.failExistingHashes {
                state.failExistingHashes = nil
                throw error
            }
        }
        return storedHashes
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        chunkStarts.increment()
        if let delay = state.withLock({ $0.delayPerChunk }) {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        try state.withLock { state in
            if let failAfterSuccesses = state.failAfterSuccesses, state.savedChunkCount >= failAfterSuccesses {
                throw TransactionImportError.accountNotFound
            }
            if let error = state.failNextSave {
                state.failNextSave = nil
                throw error
            }
            state.savedChunkCount += 1
        }
    }
}

final class FakeCategorySuggesting: CategorySuggesting {
    private struct State {
        var lastReceivedCandidates: [CategoryCandidate] = []
        var delay: Duration?
    }

    let isAvailable: Bool
    private let resultsByPayee: [String: CategorySuggestionResult]
    private let state = Mutex(State())
    private let calls = CallCounter()

    init(isAvailable: Bool = true, resultsByPayee: [String: CategorySuggestionResult] = [:]) {
        self.isAvailable = isAvailable
        self.resultsByPayee = resultsByPayee
    }

    var suggestCallCount: Int { calls.count }

    /// The candidates the caller passed on the most recent call — lets a test assert
    /// on what ImportViewModel actually sent (e.g. that Income categories are excluded)
    /// even though this fake ignores `candidates` when deciding what to return.
    var lastReceivedCandidates: [CategoryCandidate] { state.withLock { $0.lastReceivedCandidates } }

    func setDelay(_ delay: Duration) {
        state.withLock { $0.delay = delay }
    }

    /// Suspends until `suggestCategory` has been entered at least `count` times (before
    /// any artificial delay), so a test can act at a known point instead of sleeping.
    func waitUntilCalled(_ count: Int) async throws {
        try await calls.waitUntil(count)
    }

    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult? {
        // Record the candidates before counting the call, so a test resumed by
        // `waitUntilCalled` always sees this call's candidates.
        let delay = state.withLock { state in
            state.lastReceivedCandidates = candidates
            return state.delay
        }
        calls.increment()
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return resultsByPayee[payee]
    }
}

struct FailingImportRecordRepo: ImportRecordRepositoryProtocol {
    enum RepoError: Error { case saveFailed }
    func fetchAll() throws -> [ImportRecord] { [] }
    func save(_ record: ImportRecord) throws { throw RepoError.saveFailed }
    func delete(_ record: ImportRecord) throws {}
}

struct FailingBudgetRepo: BudgetRepositoryProtocol {
    enum RepoError: Error { case fetchFailed }
    func fetchAll(for month: Date) throws -> [Budget] { throw RepoError.fetchFailed }
    func fetch(for category: FinanceTracker.Category, in month: Date) throws -> Budget? { nil }
    func save(_ budget: Budget) throws {}
    func delete(_ budget: Budget) throws {}
}

/// Wraps a real CategoryRepositoryProtocol but throws on save() after `failAfter`
/// successful saves — used to test rollback behavior when a batch of saves fails partway.
final class FailAfterNSavesCategoryRepo: CategoryRepositoryProtocol {
    enum RepoError: Error { case saveFailed }
    private let wrapped: any CategoryRepositoryProtocol
    private let failAfter: Int
    private(set) var saveCount = 0

    init(wrapping wrapped: any CategoryRepositoryProtocol, failAfter: Int) {
        self.wrapped = wrapped
        self.failAfter = failAfter
    }

    func fetchAll() throws -> [FinanceTracker.Category] { try wrapped.fetchAll() }
    func fetch(id: UUID) throws -> FinanceTracker.Category? { try wrapped.fetch(id: id) }
    func delete(_ category: FinanceTracker.Category) throws { try wrapped.delete(category) }

    func save(_ category: FinanceTracker.Category) throws {
        saveCount += 1
        guard saveCount <= failAfter else { throw RepoError.saveFailed }
        try wrapped.save(category)
    }
}
