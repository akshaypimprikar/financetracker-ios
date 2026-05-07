import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataTransactionRepository")
struct SwiftDataTransactionRepositoryTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

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
}
