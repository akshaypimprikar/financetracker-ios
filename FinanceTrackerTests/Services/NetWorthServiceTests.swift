import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("NetWorthService")
struct NetWorthServiceTests {

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([Account.self, Transaction.self, Category.self, Budget.self, ImportRecord.self])
        return try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    }

    @Test func netWorthIsAssetsMinusLiabilities() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let balanceService = BalanceService()

        let checking = Account(name: "Checking", type: .checking, openingBalance: 2000)
        let savings = Account(name: "Savings", type: .savings, openingBalance: 5000)
        let creditCard = Account(name: "Visa", type: .creditCard, openingBalance: 0)
        ctx.insert(checking); ctx.insert(savings); ctx.insert(creditCard)

        let tx = Transaction(date: .now, amount: 300, payee: "Amazon", type: .debit, account: creditCard)
        ctx.insert(tx)

        let accounts: [(Account, [Transaction])] = [
            (checking, []),
            (savings, []),
            (creditCard, [tx])
        ]
        let result = NetWorthService().netWorth(accounts: accounts, balanceService: balanceService)
        // checking: 2000, savings: 5000, creditCard: 0 - 300 = -300
        // net worth = 2000 + 5000 + (-300) = 6700
        #expect(result == 6700)
    }

    @Test func netWorthWithNoAccountsIsZero() {
        let result = NetWorthService().netWorth(accounts: [], balanceService: BalanceService())
        #expect(result == 0)
    }

    @Test func archivedAccountsAreExcluded() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let active = Account(name: "Active", type: .checking, openingBalance: 1000)
        let archived = Account(name: "Old", type: .savings, isArchived: true, openingBalance: 500)
        ctx.insert(active); ctx.insert(archived)

        let accounts: [(Account, [Transaction])] = [(active, []), (archived, [])]
        let result = NetWorthService().netWorth(accounts: accounts, balanceService: BalanceService())
        #expect(result == 1000)
    }
}
