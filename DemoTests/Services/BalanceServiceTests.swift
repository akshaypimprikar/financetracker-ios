import Foundation
import Testing
import SwiftData
@testable import Demo

@Suite("BalanceService")
struct BalanceServiceTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test func openingBalanceWithNoTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 500)
        ctx.insert(account)

        let result = BalanceService().balance(for: account, transactions: [])
        #expect(result == 500)
    }

    @Test func debitReducesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 1000)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 200, payee: "Rent", type: .debit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 800)
    }

    @Test func creditIncreasesBalance() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking, openingBalance: 0)
        ctx.insert(account)
        let tx = Transaction(date: .now, amount: 3000, payee: "Salary", type: .credit, account: account)
        ctx.insert(tx)

        let result = BalanceService().balance(for: account, transactions: [tx])
        #expect(result == 3000)
    }

    @Test func transferReducesSourceAndIncreasesDestination() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking, openingBalance: 1000)
        let savings = Account(name: "Savings", type: .savings, openingBalance: 0)
        ctx.insert(checking)
        ctx.insert(savings)
        let tx = Transaction(date: .now, amount: 500, payee: "Transfer", type: .transfer, account: checking, toAccount: savings)
        ctx.insert(tx)

        let service = BalanceService()
        #expect(service.balance(for: checking, transactions: [tx]) == 500)
        #expect(service.balance(for: savings, transactions: [tx]) == 500)
    }
}
