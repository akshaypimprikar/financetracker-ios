import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataAccountRepository")
struct SwiftDataAccountRepositoryTests {

    @Test func fetchAllReturnsSortedByName() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataAccountRepository(context: ctx)

        try repo.save(Account(name: "Savings", type: .savings))
        try repo.save(Account(name: "Checking", type: .checking))

        let results = try repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].name == "Checking")
        #expect(results[1].name == "Savings")
    }

    @Test func fetchByIdReturnsMatchingAccount() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataAccountRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        try repo.save(account)

        let found = try repo.fetch(id: account.id)
        #expect(found?.id == account.id)
        #expect(found?.name == "Checking")
    }

    @Test func fetchByIdReturnsNilForUnknownId() throws {
        let container = try makeContainer()
        let repo = SwiftDataAccountRepository(context: ModelContext(container))

        let result = try repo.fetch(id: UUID())
        #expect(result == nil)
    }

    @Test func fetchAllActiveExcludesArchivedAccounts() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataAccountRepository(context: ctx)

        try repo.save(Account(name: "Active Checking", type: .checking, isArchived: false))
        try repo.save(Account(name: "Archived Savings", type: .savings, isArchived: true))

        let active = try repo.fetchAllActive()
        #expect(active.count == 1)
        #expect(active[0].name == "Active Checking")
    }

    @Test func deleteRemovesAccount() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataAccountRepository(context: ctx)

        let account = Account(name: "Checking", type: .checking)
        try repo.save(account)
        #expect(try repo.fetchAll().count == 1)

        try repo.delete(account)
        #expect(try repo.fetchAll().isEmpty)
    }
}
