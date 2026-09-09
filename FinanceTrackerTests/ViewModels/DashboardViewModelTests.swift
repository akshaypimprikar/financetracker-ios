import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("DashboardViewModel")
struct DashboardViewModelTests {

    @Test func loadComputesNetWorth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking, openingBalance: 1000)
        let card = Account(name: "Card", type: .creditCard, openingBalance: -300)
        ctx.insert(checking)
        ctx.insert(card)
        ctx.insert(Transaction(date: .now, amount: 200, payee: "Rent",
                               type: .debit, account: checking))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        // checking: 1000 - 200 = 800, card: -300, total = 500
        #expect(vm.netWorth == 500)
    }

    @Test func spendingThisMonthSumsDebitsOnly() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 50, payee: "Coffee",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 30, payee: "Salary",
                               type: .credit, account: account))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.spendingThisMonth == 50)
    }

    @Test func recentTransactionsLimitedToFive() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        for i in 1...7 {
            ctx.insert(Transaction(date: .now, amount: Decimal(i * 10),
                                   payee: "Tx \(i)", type: .debit, account: account))
        }
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.recentTransactions.count == 5)
    }

    @Test func categorySpendingGroupsDebitsByCategoryForCurrentMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let groceries = Category(name: "Groceries", type: .expense)
        let dining = Category(name: "Dining", type: .expense)
        ctx.insert(account)
        ctx.insert(groceries)
        ctx.insert(dining)
        ctx.insert(Transaction(date: .now, amount: 40, payee: "Store",
                               type: .debit, account: account, category: groceries))
        ctx.insert(Transaction(date: .now, amount: 10, payee: "Store2",
                               type: .debit, account: account, category: groceries))
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Cafe",
                               type: .debit, account: account, category: dining))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.categorySpending.count == 2)
        let groceriesSpend = vm.categorySpending.first { $0.category.id == groceries.id }
        #expect(groceriesSpend?.amount == 50)
        let diningSpend = vm.categorySpending.first { $0.category.id == dining.id }
        #expect(diningSpend?.amount == 25)
    }

    @Test func categorySpendingExcludesCreditAndUncategorizedTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let salary = Category(name: "Salary", type: .income)
        ctx.insert(account)
        ctx.insert(salary)
        ctx.insert(Transaction(date: .now, amount: 1000, payee: "Payroll",
                               type: .credit, account: account, category: salary))
        ctx.insert(Transaction(date: .now, amount: 20, payee: "Uncategorized Purchase",
                               type: .debit, account: account))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.categorySpending.isEmpty)
    }
}
