import Foundation
import SwiftData
@testable import FinanceTracker

func makeContainer() throws -> ModelContainer {
    let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

actor FakeTransactionImportWriting: TransactionImportWriting {
    private var _existingHashes: Set<String>
    private(set) var savedChunkCount = 0
    private var delayPerChunk: Duration?
    private var failNextSave: Error?
    private var failAfterSuccesses: Int?

    private var chunkStartCount = 0
    private var chunkStartWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    init(existingHashes: Set<String> = []) {
        self._existingHashes = existingHashes
    }

    func setDelayPerChunk(_ delay: Duration) {
        delayPerChunk = delay
    }

    /// Deterministic replacement for a guessed `Task.sleep` race window: suspends
    /// until at least `count` calls to `save(chunk:accountID:)` have been entered
    /// (before any artificial delay), so a test can act (e.g. cancel) at a known
    /// point instead of hoping a wall-clock sleep lands inside the delay window.
    func waitUntilChunksStarted(_ count: Int) async {
        if chunkStartCount >= count { return }
        await withCheckedContinuation { continuation in
            chunkStartWaiters.append((threshold: count, continuation: continuation))
        }
    }

    func setFailNextSave(with error: Error) {
        failNextSave = error
    }

    /// Deterministic partial-failure mode: the first `count` calls (across however
    /// many concurrent chunk tasks race into this actor — only one call body runs at
    /// a time since this is an actor) succeed; every call after that throws. Robust
    /// to TaskGroup scheduling order since the threshold is a running total, not
    /// "the Nth specific call."
    func setFailAfter(successfulSaves count: Int) {
        failAfterSuccesses = count
    }

    func existingHashes() async throws -> Set<String> {
        _existingHashes
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        chunkStartCount += 1
        let ready = chunkStartWaiters.filter { chunkStartCount >= $0.threshold }
        chunkStartWaiters.removeAll { chunkStartCount >= $0.threshold }
        for waiter in ready { waiter.continuation.resume() }

        if let delayPerChunk {
            try await Task.sleep(for: delayPerChunk)
        }
        try Task.checkCancellation()
        if let failAfterSuccesses, savedChunkCount >= failAfterSuccesses {
            throw TransactionImportError.accountNotFound
        }
        if let error = failNextSave {
            failNextSave = nil
            throw error
        }
        savedChunkCount += 1
    }
}

actor FakeCategorySuggesting: CategorySuggesting {
    nonisolated let isAvailable: Bool
    private(set) var suggestCallCount = 0
    /// The candidates the caller passed on the most recent call — lets a test assert
    /// on what ImportViewModel actually sent (e.g. that Income categories are excluded)
    /// even though this fake ignores `candidates` when deciding what to return.
    private(set) var lastReceivedCandidates: [CategoryCandidate] = []
    private var resultsByPayee: [String: CategorySuggestionResult]
    private var delay: Duration?

    init(isAvailable: Bool = true, resultsByPayee: [String: CategorySuggestionResult] = [:]) {
        self.isAvailable = isAvailable
        self.resultsByPayee = resultsByPayee
    }

    func setDelay(_ delay: Duration) {
        self.delay = delay
    }

    func suggestCategory(payee: String, candidates: [CategoryCandidate]) async -> CategorySuggestionResult? {
        suggestCallCount += 1
        lastReceivedCandidates = candidates
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

@discardableResult
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @escaping () -> Bool
) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
