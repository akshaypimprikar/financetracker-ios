import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("SwiftDataImportRecordRepository")
struct SwiftDataImportRecordRepositoryTests {

    @Test func saveAndFetchAllReturnsRecord() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataImportRecordRepository(context: ctx)

        let record = ImportRecord(filename: "transactions.csv", transactionCount: 5)
        try repo.save(record)

        let results = try repo.fetchAll()
        #expect(results.count == 1)
        #expect(results[0].filename == "transactions.csv")
        #expect(results[0].transactionCount == 5)
    }

    @Test func fetchAllReturnsMostRecentFirst() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataImportRecordRepository(context: ctx)

        let older = ImportRecord(filename: "old.csv",
                                 importedAt: Date(timeIntervalSinceNow: -3600),
                                 transactionCount: 2)
        let newer = ImportRecord(filename: "new.csv",
                                 importedAt: Date(timeIntervalSinceNow: -60),
                                 transactionCount: 4)
        try repo.save(older)
        try repo.save(newer)

        let results = try repo.fetchAll()
        #expect(results.count == 2)
        #expect(results[0].filename == "new.csv")
    }

    @Test func deleteRemovesRecord() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let repo = SwiftDataImportRecordRepository(context: ctx)

        let record = ImportRecord(filename: "transactions.csv", transactionCount: 3)
        try repo.save(record)
        #expect(try repo.fetchAll().count == 1)

        try repo.delete(record)
        #expect(try repo.fetchAll().isEmpty)
    }
}
