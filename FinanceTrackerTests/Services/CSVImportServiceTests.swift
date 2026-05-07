import Testing
import CryptoKit
import Foundation
@testable import FinanceTracker

@Suite("CSVImportService")
struct CSVImportServiceTests {

    @Test func parsesCommaDelimitedCSV() throws {
        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee Shop
        2026-05-02,1200.00,Rent
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 2)
        #expect(results[0].payee == "Coffee Shop")
        #expect(results[0].amount == Decimal(string: "25.50"))
        #expect(results[1].payee == "Rent")
    }

    @Test func parsesSemicolonDelimitedCSV() throws {
        let csv = "date;amount;payee\n2026-05-01;50.00;Supermarket"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 1)
        #expect(results[0].payee == "Supermarket")
    }

    @Test func deduplicatesRowsWithMatchingHashes() throws {
        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee Shop
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let parsed = try CSVImportService().parse(csv: csv, mapping: mapping)
        let hash = parsed[0].importHash

        let results = CSVImportService().deduplicated(parsed: parsed, existingHashes: Set([hash]))
        #expect(results.isEmpty)
    }

    @Test func importHashIsDeterministic() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let hash1 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        let hash2 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        #expect(hash1 == hash2)
    }

    @Test func importHashDiffersForDifferentInputs() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        let hash1 = CSVImportService.importHash(date: date, amount: 25, payee: "Coffee")
        let hash2 = CSVImportService.importHash(date: date, amount: 26, payee: "Coffee")
        #expect(hash1 != hash2)
    }
}
