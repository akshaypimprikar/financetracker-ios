import Foundation
import SwiftData

struct SwiftDataBudgetRepository: BudgetRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll(for month: Date) throws -> [Budget] {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.month >= start && $0.month < end }
        )
        return try context.fetch(descriptor)
    }

    func fetch(for category: Category, in month: Date) throws -> Budget? {
        let categoryID = category.id
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month))!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        // Fetch all budgets in the date range first, then filter by category in memory
        // to avoid SwiftData #Predicate limitations with non-optional relationship key paths
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate { $0.month >= start && $0.month < end }
        )
        let results = try context.fetch(descriptor)
        return results.first { $0.category.id == categoryID }
    }

    func save(_ budget: Budget) throws {
        context.insert(budget)
        try context.save()
    }

    func delete(_ budget: Budget) throws {
        context.delete(budget)
        try context.save()
    }
}
