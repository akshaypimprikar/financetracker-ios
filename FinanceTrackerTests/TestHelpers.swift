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

    init(existingHashes: Set<String> = []) {
        self._existingHashes = existingHashes
    }

    func setDelayPerChunk(_ delay: Duration) {
        delayPerChunk = delay
    }

    func setFailNextSave(with error: Error) {
        failNextSave = error
    }

    func existingHashes() async throws -> Set<String> {
        _existingHashes
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        if let delayPerChunk {
            try await Task.sleep(for: delayPerChunk)
        }
        try Task.checkCancellation()
        if let error = failNextSave {
            failNextSave = nil
            throw error
        }
        savedChunkCount += 1
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
