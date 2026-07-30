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

    init(existingHashes: Set<String> = []) {
        self._existingHashes = existingHashes
    }

    func setDelayPerChunk(_ delay: Duration) {
        delayPerChunk = delay
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
