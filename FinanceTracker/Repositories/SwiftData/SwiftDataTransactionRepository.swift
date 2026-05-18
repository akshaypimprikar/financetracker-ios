import Foundation
import SwiftData

struct SwiftDataTransactionRepository: TransactionRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [Transaction] {
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(for account: Account) throws -> [Transaction] {
        let accountID = account.id
        // Fetch all and filter in memory to include transactions where this account
        // is either the source OR the transfer destination (toAccount).
        let descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let all = try context.fetch(descriptor)
        return all.filter { $0.account.id == accountID || $0.toAccount?.id == accountID }
    }

    func fetch(for category: Category, in month: Date) throws -> [Transaction] {
        let categoryID = category.id
        let calendar = Calendar.current
        guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else {
            return []
        }
        // Fetch all transactions in the date range first, then filter by category in memory
        // to avoid SwiftData #Predicate limitations with optional chaining ($0.category?.id)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let results = try context.fetch(descriptor)
        return results.filter { $0.category?.id == categoryID }
    }

    func fetchRecent(limit: Int) throws -> [Transaction] {
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    func existsWithHash(_ hash: String) throws -> Bool {
        // Filter in memory — SwiftData optional-String predicate on importHash
        // requires in-memory filtering to avoid #Predicate limitations with optionals.
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.fetchLimit = 1
        let all = try context.fetch(FetchDescriptor<Transaction>())
        return all.contains { $0.importHash == hash }
    }

    func save(_ transaction: Transaction) throws {
        context.insert(transaction)
        try context.save()
    }

    func delete(_ transaction: Transaction) throws {
        context.delete(transaction)
        try context.save()
    }
}
