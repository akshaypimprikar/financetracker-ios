import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataTransactionRepository")
struct SwiftDataTransactionRepositoryTests {

    @Test func fetchForAccountReturnsOnlyThatAccountsTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let accountA = Account(name: "Checking", type: .checking)
        let accountB = Account(name: "Savings", type: .savings)
        ctx.insert(accountA)
        ctx.insert(accountB)

        let txA = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, account: accountA)
        let txB = Transaction(date: .now, amount: 20, payee: "Salary", type: .credit, account: accountB)
        ctx.insert(txA)
        ctx.insert(txB)
        try ctx.save()

        let results = try repo.fetch(for: accountA)
        #expect(results.count == 1)
        #expect(results[0].payee == "Coffee")
    }

    @Test func existsWithHashReturnsTrueForDuplicate() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)

        let hash = "abc123"
        let tx = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, importHash: hash, account: account)
        try repo.save(tx)

        #expect(try repo.existsWithHash(hash) == true)
        #expect(try repo.existsWithHash("different") == false)
    }

    @Test func fetchAllReturnsAllTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try repo.save(Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, account: account))
        try repo.save(Transaction(date: .now, amount: 50, payee: "Salary", type: .credit, account: account))

        let results = try repo.fetchAll()
        #expect(results.count == 2)
    }

    @Test func fetchForCategoryInMonthReturnsMatchingTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        let category = Category(name: "Groceries", type: .expense)
        ctx.insert(account)
        ctx.insert(category)

        let jan15 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let feb15 = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 15))!
        let inJan = Transaction(date: jan15, amount: 30, payee: "Supermarket", type: .debit, account: account)
        inJan.category = category
        let inFeb = Transaction(date: feb15, amount: 20, payee: "Deli", type: .debit, account: account)
        inFeb.category = category
        try repo.save(inJan)
        try repo.save(inFeb)

        let janMonth = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let results = try repo.fetch(for: category, in: janMonth)
        #expect(results.count == 1)
        #expect(results[0].payee == "Supermarket")
    }

    @Test func deleteRemovesTransaction() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataTransactionRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, account: account)
        try repo.save(tx)
        #expect(try repo.fetchAll().count == 1)

        try repo.delete(tx)
        #expect(try repo.fetchAll().isEmpty)
    }
}
