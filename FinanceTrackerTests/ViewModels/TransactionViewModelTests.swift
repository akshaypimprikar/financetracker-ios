import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("TransactionViewModel")
struct TransactionViewModelTests {

    @Test func loadFetchesAllTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 1200, payee: "Rent",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.transactions.count == 2)
    }

    @Test func addTransactionPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        try vm.add(date: .now, amount: 50, payee: "Grocery", notes: nil,
                   type: .debit, account: account, toAccount: nil, category: nil)

        #expect(vm.transactions.count == 1)
        #expect(vm.transactions[0].payee == "Grocery")
    }

    @Test func searchTextFiltersPayee() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee Shop",
                               type: .debit, account: account))
        ctx.insert(Transaction(date: .now, amount: 50, payee: "Grocery Store",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.searchText = "coffee"

        #expect(vm.filteredTransactions.count == 1)
        #expect(vm.filteredTransactions[0].payee == "Coffee Shop")
    }

    @Test func selectedAccountFiltersTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking)
        let savings = Account(name: "Savings", type: .savings)
        ctx.insert(checking)
        ctx.insert(savings)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: checking))
        ctx.insert(Transaction(date: .now, amount: 100, payee: "Interest",
                               type: .credit, account: savings))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = checking

        #expect(vm.filteredTransactions.count == 1)
        #expect(vm.filteredTransactions[0].payee == "Coffee")
    }

    @Test func filteredTransactionsIsMemoizedAcrossRepeatedAccess() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 1)
    }

    @Test func filteredTransactionsCacheInvalidatesOnSearchTextChange() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        vm.searchText = "coffee"
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }

    @Test func filteredTransactionsCacheInvalidatesOnSelectedAccountChange() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking)
        ctx.insert(checking)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: checking))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        vm.selectedAccount = checking
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }

    @Test func filteredTransactionsCacheInvalidatesOnReload() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        try vm.add(date: .now, amount: 50, payee: "Grocery", notes: nil,
                   type: .debit, account: account, toAccount: nil, category: nil)
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }
}
