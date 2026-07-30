import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("CategoryViewModel")
struct CategoryViewModelTests {

    @Test func loadFetchesAllCategories() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Category(name: "Food", type: .expense))
        ctx.insert(Category(name: "Salary", type: .income))
        try ctx.save()

        let vm = CategoryViewModel(categoryRepo: SwiftDataCategoryRepository(context: ctx))
        try vm.load()

        #expect(vm.categories.count == 2)
    }

    @Test func addCategoryPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = CategoryViewModel(categoryRepo: SwiftDataCategoryRepository(context: ctx))
        try vm.load()
        #expect(vm.categories.isEmpty)

        try vm.add(name: "Groceries", icon: "cart", colorHex: "#FF0000", type: .expense)

        #expect(vm.categories.count == 1)
        #expect(vm.categories[0].name == "Groceries")
        #expect(vm.categories[0].type == .expense)
    }

    @Test func deleteCategoryRemovesAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Transport", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = CategoryViewModel(categoryRepo: SwiftDataCategoryRepository(context: ctx))
        try vm.load()
        #expect(vm.categories.count == 1)

        try vm.delete(vm.categories[0])

        #expect(vm.categories.isEmpty)
    }

    @Test func findNearDuplicateMatchesCaseAndConnectorInsensitively() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Category(name: "Travel", type: .expense))
        try ctx.save()

        let vm = CategoryViewModel(categoryRepo: SwiftDataCategoryRepository(context: ctx))
        try vm.load()

        #expect(vm.findNearDuplicate(named: "travel") != nil)
        #expect(vm.findNearDuplicate(named: "Travel Insurance") == nil)   // regression guard: not a substring match
    }

    @Test func findNearDuplicateReturnsNilWhenNoMatch() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Category(name: "Travel", type: .expense))
        try ctx.save()

        let vm = CategoryViewModel(categoryRepo: SwiftDataCategoryRepository(context: ctx))
        try vm.load()

        #expect(vm.findNearDuplicate(named: "Shopping") == nil)
    }
}
