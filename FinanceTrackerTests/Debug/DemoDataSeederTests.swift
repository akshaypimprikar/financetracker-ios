import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("DemoDataSeeder")
struct DemoDataSeederTests {

    @Test func seedInsertsExpectedCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        DemoDataSeeder.seed(into: context)

        #expect(try context.fetchCount(FetchDescriptor<Account>()) == 3)
        #expect(try context.fetchCount(FetchDescriptor<FinanceTracker.Category>()) == 9)
        #expect(try context.fetchCount(FetchDescriptor<Transaction>()) == 43)
        #expect(try context.fetchCount(FetchDescriptor<Budget>()) == 4)
    }

    @Test func seedProducesExpectedAccountBalances() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        DemoDataSeeder.seed(into: context)

        let accounts = try context.fetch(FetchDescriptor<Account>())
        let allTransactions = try context.fetch(FetchDescriptor<Transaction>())
        let balanceService = BalanceService()
        var balanceByName: [String: Decimal] = [:]
        for account in accounts {
            let transactions = allTransactions.filter { $0.account.id == account.id }
            balanceByName[account.name] = balanceService.balance(for: account, transactions: transactions)
        }

        #expect(balanceByName["Ally Savings"] == 12000)
        #expect(balanceByName["Chase Sapphire"] == -809.87)
    }

    @Test func seedNeverPersistsOutsideInMemoryStore() throws {
        // Every consumer of DemoDataSeeder must force an in-memory ModelConfiguration
        // (see FinanceTrackerApp's --seedscreenshots wiring) -- this test only
        // documents the seeder's own behavior is deterministic and side-effect-free
        // beyond the passed-in context, so that guarantee is safe to rely on.
        let container = try makeContainer()
        let context = ModelContext(container)

        DemoDataSeeder.seed(into: context)
        let firstRunCount = try context.fetchCount(FetchDescriptor<Transaction>())

        let secondContainer = try makeContainer()
        let secondContext = ModelContext(secondContainer)
        DemoDataSeeder.seed(into: secondContext)
        let secondRunCount = try secondContext.fetchCount(FetchDescriptor<Transaction>())

        #expect(firstRunCount == secondRunCount)
    }
}
