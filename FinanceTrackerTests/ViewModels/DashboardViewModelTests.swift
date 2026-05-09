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
}
