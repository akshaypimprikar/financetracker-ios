import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@Suite("BudgetViewModel")
struct BudgetViewModelTests {

    func startOfMay2026() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    }

    @Test func loadFetchesBudgetsForSelectedMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 500, month: startOfMay2026(), category: category)
        ctx.insert(category); ctx.insert(budget)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.budgets.count == 1)
        #expect(vm.budgets[0].0.category.name == "Food")
    }

    @Test func addBudgetPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Transport", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()
        #expect(vm.budgets.isEmpty)

        try vm.add(category: category, monthlyLimit: 200)

        #expect(vm.budgets.count == 1)
        #expect(vm.budgets[0].0.monthlyLimit == 200)
    }

    @Test func progressReflectsSpending() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 200, month: startOfMay2026(), category: category)
        ctx.insert(account); ctx.insert(category); ctx.insert(budget)
        let txDate = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        ctx.insert(Transaction(date: txDate, amount: 80, payee: "Grocery",
                               type: .debit, account: account, category: category))
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.budgets[0].1.spent == 80)
        #expect(vm.budgets[0].1.remaining == 120)
        #expect(vm.budgets[0].1.isOverBudget == false)
    }

    @Test func unbudgetedCategoriesExcludesBudgetedOnes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let food = Category(name: "Food", type: .expense)
        let transport = Category(name: "Transport", type: .expense)
        let budget = Budget(monthlyLimit: 200, month: startOfMay2026(), category: food)
        ctx.insert(food); ctx.insert(transport); ctx.insert(budget)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.unbudgetedCategories.count == 1)
        #expect(vm.unbudgetedCategories[0].name == "Transport")
    }

    @Test func addThrowsOnDuplicateBudgetForSameCategoryAndMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.add(category: category, monthlyLimit: 200)

        #expect(throws: BudgetViewModel.BudgetError.duplicateBudget) {
            try vm.add(category: category, monthlyLimit: 300)
        }
        // Only one budget should exist
        #expect(vm.budgets.count == 1)
        #expect(vm.budgets[0].0.monthlyLimit == 200)
    }

    @Test func monthlySpendingHistoryReturnsCorrectNumberOfMonths() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()

        let points = vm.monthlySpendingHistory(for: category)
        #expect(points.count == BudgetViewModel.defaultSpendingHistoryMonths)
    }

    @Test func monthlySpendingHistoryRespectsCustomWindowSize() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        vm.spendingHistoryMonths = 3

        let points = vm.monthlySpendingHistory(for: category)
        #expect(points.count == 3)
    }

    @Test func monthlySpendingHistoryReturnsZeroForMonthsWithNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        vm.spendingHistoryMonths = 3

        let points = vm.monthlySpendingHistory(for: category)
        #expect(points.allSatisfy { $0.spent == 0.0 })
    }

    @Test func suggestionsAvailableReflectsCategorySuggesterAvailability() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let available = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: FakeCategorySuggesting(isAvailable: true)
        )
        #expect(available.suggestionsAvailable)

        let unavailable = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: FakeCategorySuggesting(isAvailable: false)
        )
        #expect(!unavailable.suggestionsAvailable)
    }

    @Test func canOpenAddBudgetIsFalseOnlyWhenNoUnbudgetedCategoriesAndSuggestionsAvailable() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 500, month: startOfMay2026(), category: category)
        ctx.insert(category); ctx.insert(budget)
        try ctx.save()

        // No unbudgeted categories + suggestions available (AI path is the only route,
        // and it's not reachable from this sheet) -> nothing to do here.
        let blocked = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: FakeCategorySuggesting(isAvailable: true)
        )
        blocked.selectedMonth = startOfMay2026()
        try blocked.load()
        #expect(!blocked.canOpenAddBudget)

        // No unbudgeted categories, but suggestions unavailable -> manual "Add Category"
        // fallback is still reachable, so the sheet should open.
        let fallbackAvailable = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: FakeCategorySuggesting(isAvailable: false)
        )
        fallbackAvailable.selectedMonth = startOfMay2026()
        try fallbackAvailable.load()
        #expect(fallbackAvailable.canOpenAddBudget)
    }
}
