import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataBudgetRepository")
struct SwiftDataBudgetRepositoryTests {

    private func makeMonth(year: Int, month: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: 1))!
    }

    @Test func fetchAllForMonthReturnsOnlyThatMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataBudgetRepository(context: ctx)
        let catRepo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Groceries", type: .expense)
        try catRepo.save(category)

        let jan = makeMonth(year: 2026, month: 1)
        let feb = makeMonth(year: 2026, month: 2)
        try repo.save(Budget(monthlyLimit: 500, month: jan, category: category))
        try repo.save(Budget(monthlyLimit: 300, month: feb, category: category))

        let results = try repo.fetchAll(for: jan)
        #expect(results.count == 1)
        #expect(results[0].monthlyLimit == 500)
    }

    @Test func fetchAllForMonthReturnsEmptyWhenNoneMatch() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataBudgetRepository(context: ctx)
        let catRepo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Transport", type: .expense)
        try catRepo.save(category)
        let jan = makeMonth(year: 2026, month: 1)
        try repo.save(Budget(monthlyLimit: 200, month: jan, category: category))

        let march = makeMonth(year: 2026, month: 3)
        #expect(try repo.fetchAll(for: march).isEmpty)
    }

    @Test func fetchForCategoryInMonthReturnsMatchingBudget() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataBudgetRepository(context: ctx)
        let catRepo = SwiftDataCategoryRepository(context: ctx)

        let groceries = Category(name: "Groceries", type: .expense)
        let transport = Category(name: "Transport", type: .expense)
        try catRepo.save(groceries)
        try catRepo.save(transport)

        let month = makeMonth(year: 2026, month: 1)
        try repo.save(Budget(monthlyLimit: 500, month: month, category: groceries))
        try repo.save(Budget(monthlyLimit: 200, month: month, category: transport))

        let found = try repo.fetch(for: groceries, in: month)
        #expect(found?.monthlyLimit == 500)
    }

    @Test func fetchForCategoryInMonthReturnsNilWhenNoMatch() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataBudgetRepository(context: ctx)
        let catRepo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Groceries", type: .expense)
        try catRepo.save(category)

        let jan = makeMonth(year: 2026, month: 1)
        let feb = makeMonth(year: 2026, month: 2)
        try repo.save(Budget(monthlyLimit: 500, month: jan, category: category))

        let result = try repo.fetch(for: category, in: feb)
        #expect(result == nil)
    }

    @Test func deleteRemovesBudget() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataBudgetRepository(context: ctx)
        let catRepo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Groceries", type: .expense)
        try catRepo.save(category)

        let month = makeMonth(year: 2026, month: 1)
        let budget = Budget(monthlyLimit: 500, month: month, category: category)
        try repo.save(budget)
        #expect(try repo.fetchAll(for: month).count == 1)

        try repo.delete(budget)
        #expect(try repo.fetchAll(for: month).isEmpty)
    }
}
