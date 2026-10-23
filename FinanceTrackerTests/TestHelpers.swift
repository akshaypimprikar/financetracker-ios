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
// compilation on Swift 6.4 (Xcode 27), an actor conforming to the `compiler(>=6.4)`
// nonisolated protocols fails with "'nonisolated' modifier cannot be applied to this
// declaration". Every state read-modify-write happens inside one `withLock`, so the
// guarantees the actor gave (no torn updates, waiters registered atomically against
// the count) still hold.
final class FakeTransactionImportWriting: TransactionImportWriting {
    private struct State {
        var existingHashes: Set<String>
        var savedChunkCount = 0
        var delayPerChunk: Duration?
        var failNextSave: Error?
        var failAfterSuccesses: Int?
        var failExistingHashes: Error?
        var chunkStartCount = 0
        var chunkStartWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state: Mutex<State>

    init(existingHashes: Set<String> = []) {
        self.state = Mutex(State(existingHashes: existingHashes))
    }

    var savedChunkCount: Int { state.withLock { $0.savedChunkCount } }

    func setDelayPerChunk(_ delay: Duration) {
        state.withLock { $0.delayPerChunk = delay }
    }

    /// Deterministic replacement for a guessed `Task.sleep` race window: suspends
    /// until at least `count` calls to `save(chunk:accountID:)` have been entered
    /// (before any artificial delay), so a test can act (e.g. cancel) at a known
    /// point instead of hoping a wall-clock sleep lands inside the delay window.
    func waitUntilChunksStarted(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyReached = state.withLock { state in
                if state.chunkStartCount >= count { return true }
                state.chunkStartWaiters.append((threshold: count, continuation: continuation))
                return false
            }
            if alreadyReached { continuation.resume() }
        }
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
        let result: Result<Set<String>, Error> = state.withLock { state in
            if let error = state.failExistingHashes {
                state.failExistingHashes = nil
                return .failure(error)
            }
            return .success(state.existingHashes)
        }
        return try result.get()
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        let (ready, delay) = state.withLock { state in
            state.chunkStartCount += 1
            let count = state.chunkStartCount
            let ready = state.chunkStartWaiters.filter { count >= $0.threshold }
            state.chunkStartWaiters.removeAll { count >= $0.threshold }
            return (ready.map(\.continuation), state.delayPerChunk)
        }
        for continuation in ready { continuation.resume() }

        if let delay {
            try await Task.sleep(for: delay)
        }
        try Task.checkCancellation()
        let failure: Error? = state.withLock { state in
            if let failAfterSuccesses = state.failAfterSuccesses, state.savedChunkCount >= failAfterSuccesses {
                return TransactionImportError.accountNotFound
            }
            if let error = state.failNextSave {
                state.failNextSave = nil
                return error
            }
            state.savedChunkCount += 1
            return nil
        }
        if let failure { throw failure }
    }
}

final class FakeCategorySuggesting: CategorySuggesting {
    private struct State {
        var suggestCallCount = 0
        var lastReceivedCandidates: [CategoryCandidate] = []
        var resultsByPayee: [String: CategorySuggestionResult]
        var delay: Duration?
        var callWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    let isAvailable: Bool
    private let state: Mutex<State>

    init(isAvailable: Bool = true, resultsByPayee: [String: CategorySuggestionResult] = [:]) {
        self.isAvailable = isAvailable
        self.state = Mutex(State(resultsByPayee: resultsByPayee))
    }

    var suggestCallCount: Int { state.withLock { $0.suggestCallCount } }

    /// The candidates the caller passed on the most recent call — lets a test assert
    /// on what ImportViewModel actually sent (e.g. that Income categories are excluded)
    /// even though this fake ignores `candidates` when deciding what to return.
    var lastReceivedCandidates: [CategoryCandidate] { state.withLock { $0.lastReceivedCandidates } }

    func setDelay(_ delay: Duration) {
        state.withLock { $0.delay = delay }
    }

    /// Suspends until `suggestCategory` has been entered at least `count` times (before
    /// any artificial delay), so a test can act at a known point instead of sleeping.
    func waitUntilCalled(_ count: Int) async {
        await withCheckedContinuation { continuation in
            let alreadyReached = state.withLock { state in
                if state.suggestCallCount >= count { return true }
                state.callWaiters.append((threshold: count, continuation: continuation))
                return false
            }
            if alreadyReached { continuation.resume() }
        }
    }

    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult? {
        let (ready, delay) = state.withLock { state in
            state.suggestCallCount += 1
            state.lastReceivedCandidates = candidates
            let count = state.suggestCallCount
            let ready = state.callWaiters.filter { count >= $0.threshold }
            state.callWaiters.removeAll { count >= $0.threshold }
            return (ready.map(\.continuation), state.delay)
        }
        for continuation in ready { continuation.resume() }
        if let delay {
            try? await Task.sleep(for: delay)
        }
        return state.withLock { $0.resultsByPayee[payee] }
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
