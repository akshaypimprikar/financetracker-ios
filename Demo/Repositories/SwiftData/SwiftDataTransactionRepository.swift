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
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.account.id == accountID },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func fetch(for category: Category, in month: Date) throws -> [Transaction] {
        let categoryID = category.id
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        // Fetch all transactions in the date range first, then filter by category in memory
        // to avoid SwiftData #Predicate limitations with optional chaining ($0.category?.id)
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let results = try context.fetch(descriptor)
        return results.filter { $0.category?.id == categoryID }
    }

    func existsWithHash(_ hash: String) throws -> Bool {
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate { $0.importHash == hash }
        )
        return try !context.fetch(descriptor).isEmpty
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
