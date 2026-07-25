import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@Suite("TransactionImportActor")
struct TransactionImportActorTests {

    @Test func existingHashesReturnsAllStoredHashes() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        let tx1 = Transaction(date: .now, amount: 10, payee: "Coffee", type: .debit, importHash: "hash1", account: account)
        let tx2 = Transaction(date: .now, amount: 20, payee: "Rent", type: .debit, importHash: "hash2", account: account)
        ctx.insert(tx1)
        ctx.insert(tx2)
        try ctx.save()

        let actor = TransactionImportActor(modelContainer: container)
        let hashes = try await actor.existingHashes()

        #expect(hashes == ["hash1", "hash2"])
    }

    @Test func existingHashesReturnsEmptySetForFreshStore() async throws {
        let container = try makeContainer()
        let actor = TransactionImportActor(modelContainer: container)

        let hashes = try await actor.existingHashes()

        #expect(hashes.isEmpty)
    }

    @Test func saveInsertsAndPersistsWholeChunk() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let actor = TransactionImportActor(modelContainer: container)
        let chunk = [
            ParsedTransaction(date: .now, amount: 25.50, payee: "Coffee Shop", importHash: "h1"),
            ParsedTransaction(date: .now, amount: 1200, payee: "Rent", importHash: "h2"),
        ]
        try await actor.save(chunk: chunk, accountID: account.id)

        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved.count == 2)
        #expect(Set(saved.map { $0.importHash ?? "" }) == ["h1", "h2"])
        #expect(saved.allSatisfy { $0.account.id == account.id })
    }

    @Test func saveThrowsAccountNotFoundForUnknownID() async throws {
        let container = try makeContainer()
        let actor = TransactionImportActor(modelContainer: container)
        let chunk = [ParsedTransaction(date: .now, amount: 10, payee: "Coffee", importHash: "h1")]

        await #expect(throws: TransactionImportError.accountNotFound) {
            try await actor.save(chunk: chunk, accountID: UUID())
        }
    }

    @Test func saveAttachesCategoryWhenCategoryIDResolves() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let category = Category(name: "Coffee", type: .expense)
        ctx.insert(account)
        ctx.insert(category)
        try ctx.save()

        let actor = TransactionImportActor(modelContainer: container)
        let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1", categoryID: category.id)]
        try await actor.save(chunk: chunk, accountID: account.id)

        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved.count == 1)
        #expect(saved[0].category?.id == category.id)
    }

    @Test func saveLeavesCategoryNilWhenCategoryIDIsNil() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let actor = TransactionImportActor(modelContainer: container)
        let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1")]
        try await actor.save(chunk: chunk, accountID: account.id)

        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved[0].category == nil)
    }

    @Test func saveLeavesCategoryNilWhenCategoryIDDoesNotResolve() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let actor = TransactionImportActor(modelContainer: container)
        let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1", categoryID: UUID())]
        try await actor.save(chunk: chunk, accountID: account.id)   // must not throw

        let saved = try ctx.fetch(FetchDescriptor<Transaction>())
        #expect(saved.count == 1)
        #expect(saved[0].category == nil)   // fails safe, not a hard failure
    }
}
