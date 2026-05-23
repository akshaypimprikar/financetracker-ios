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

    @Test func deleteAccountRemovesAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Checking", type: .checking))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()
        #expect(vm.accounts.count == 1)

        try vm.delete(vm.accounts[0])

        #expect(vm.accounts.isEmpty)
    }

    @Test func archiveAccountSetsIsArchivedAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Account(name: "Old", type: .savings))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        try vm.load()
        let account = vm.accounts[0]
        #expect(account.isArchived == false)

        try vm.archive(account)

        #expect(vm.accounts[0].isArchived == true)
    }

    @Test func runningBalanceDataReturnsEmptyWhenNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        #expect(vm.runningBalanceData(for: account).isEmpty)
    }

    @Test func runningBalanceDataConvertsDecimalToDouble() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 250, payee: "Rent", type: .debit, account: account)
        ctx.insert(tx)
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        let points = vm.runningBalanceData(for: account)
        #expect(points.count == 2)
        #expect(points[0].balance == 1000.0)
        #expect(points[1].balance == 750.0)
    }

    @Test func transactionsReturnsOnlyAccountTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let accountA = Account(name: "Checking", type: .checking)
        let accountB = Account(name: "Savings", type: .savings)
        ctx.insert(accountA); ctx.insert(accountB)
        ctx.insert(Transaction(date: .now, amount: 50, payee: "Coffee", type: .debit, account: accountA))
        ctx.insert(Transaction(date: .now, amount: 100, payee: "Salary", type: .credit, account: accountB))
        try ctx.save()

        let vm = AccountViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx)
        )
        let txs = vm.transactions(for: accountA)

        #expect(txs.count == 1)
        #expect(txs[0].payee == "Coffee")
    }
}
