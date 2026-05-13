import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataCategoryRepository")
struct SwiftDataCategoryRepositoryTests {

    @Test func fetchAllReturnsSortedByName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataCategoryRepository(context: ctx)

        try repo.save(Category(name: "Transport", type: .expense))
        try repo.save(Category(name: "Groceries", type: .expense))

        let results = try repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].name == "Groceries")
        #expect(results[1].name == "Transport")
    }

    @Test func fetchByIdReturnsMatchingCategory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Groceries", type: .expense)
        try repo.save(category)

        let found = try repo.fetch(id: category.id)
        #expect(found?.id == category.id)
        #expect(found?.name == "Groceries")
    }

    @Test func fetchByIdReturnsNilForUnknownId() throws {
        let container = try makeContainer()
        let repo = SwiftDataCategoryRepository(context: ModelContext(container))

        let result = try repo.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test func deleteRemovesCategory() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataCategoryRepository(context: ctx)

        let category = Category(name: "Groceries", type: .expense)
        try repo.save(category)
        #expect(try repo.fetchAll().count == 1)

        try repo.delete(category)
        #expect(try repo.fetchAll().isEmpty)
    }
}
