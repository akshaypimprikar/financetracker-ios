import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("AccountViewModel")
struct AccountViewModelTests {

    @Test func loadFetchesAllAccounts() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Checking", type: .checking))
        ctx.insert(Account(name: "Savings", type: .savings))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.accounts.count == 2)
    }

    @Test func balanceIncludesTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 100, payee: "Rent",
                               type: .debit, account: account))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.balance(for: account) == 400)
    }

    @Test func netWorthExcludesArchivedAccounts() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Active", type: .checking, openingBalance: 1000))
        ctx.insert(Account(name: "Archived", type: .savings,
                           isArchived: true, openingBalance: 500))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.netWorth() == 1000)
    }

    @Test func addAccountPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()
        #expect(vm.accounts.isEmpty)

        try vm.addAccount(name: "Savings", type: .savings, currency: "USD",
                          colorHex: "#56aeff", icon: "banknote", openingBalance: 250)

        #expect(vm.accounts.count == 1)
        #expect(vm.accounts[0].name == "Savings")
        #expect(vm.accounts[0].openingBalance == 250)
    }
}
