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

    @Test func negativeAmountsAreAbsoluteValues() throws {
        let csv = "date,amount,payee\n2026-05-01,-45.00,ATM Withdrawal"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 1)
        #expect(results[0].amount == Decimal(string: "45.00"))
    }

    @Test func malformedRowsAreSkipped() throws {
        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee
        bad-row
        2026-05-02,10.00,Tea
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 2)
    }

    @Test func parsesSlashDateFormats() throws {
        let csv = "date,amount,payee\n05/01/2026,20.00,Store"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 1)
        #expect(results[0].payee == "Store")
    }

    @Test func importHashIsDateOnlyNotTimestamp() {
        // Two dates that share the same calendar day but differ in time
        // should produce the same hash (date-based dedup)
        let calendar = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 1
        comps.hour = 0; comps.minute = 0
        let midnight = calendar.date(from: comps)!
        comps.hour = 23; comps.minute = 59
        let lateEvening = calendar.date(from: comps)!

        let hash1 = CSVImportService.importHash(date: midnight, amount: 25, payee: "Coffee")
        let hash2 = CSVImportService.importHash(date: lateEvening, amount: 25, payee: "Coffee")
        #expect(hash1 == hash2)
    }

    @Test func parsedTransactionDefaultsCategoryIDToNil() throws {
        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)
        #expect(results[0].categoryID == nil)
    }

    // MARK: - Amount parsing (#189)

    private let dateAmountPayee = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)

    @Test func decimalCommaAmountIsNotTruncated() throws {
        let csv = "date;amount;payee\n2026-05-01;12,50;Bakery"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.count == 1)
        #expect(results.first?.amount == Decimal(string: "12.50"))
    }

    @Test func negativeDecimalCommaAmountIsAbsolute() throws {
        let csv = "date;amount;payee\n2026-05-01;-12,50;Bakery"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.first?.amount == Decimal(string: "12.50"))
    }

    @Test func dotGroupedDecimalCommaAmountParses() throws {
        let csv = "date;amount;payee\n2026-05-01;1.234,56;Rent"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.first?.amount == Decimal(string: "1234.56"))
    }

    @Test func commaGroupedAmountInQuotedFieldParses() throws {
        let csv = "date,amount,payee\n2026-05-01,\"1,234.56\",Rent"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.first?.amount == Decimal(string: "1234.56"))
    }

    @Test func ambiguousAmountFollowsTheFileConvention() throws {
        // "1.234" alone could be either convention; "12,50" settles it for the file.
        let semicolonFile = "date;amount;payee\n2026-05-01;1.234;Rent\n2026-05-02;12,50;Bakery"
        let commaFile = "date,amount,payee\n2026-05-01,\"1,234\",Rent\n2026-05-02,12.50,Bakery"

        let eu = try CSVImportService().parse(csv: semicolonFile, mapping: dateAmountPayee)
        let us = try CSVImportService().parse(csv: commaFile, mapping: dateAmountPayee)

        #expect(eu.map(\.amount) == [Decimal(1234), Decimal(string: "12.50")!])
        #expect(us.map(\.amount) == [Decimal(1234), Decimal(string: "12.50")!])
    }

    @Test func amountThatDoesNotFullyParseIsRejected() throws {
        let csv = "date,amount,payee\n2026-05-01,12.50 USD,Coffee\n2026-05-02,1.2.3,Tea\n2026-05-03,10.00,Juice"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["Juice"])
    }

    @Test func leadingOrTrailingSeparatorAmountsStillParse() throws {
        let csv = "date,amount,payee\n2026-05-01,.50,Gum\n2026-05-02,12.,Lunch\n2026-05-03,.,Bad"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(string: "0.5")!, Decimal(12)])
    }

    // MARK: - Delimiter and quoting (#190)

    @Test func semicolonInsidePayeeDoesNotSwitchTheDelimiter() throws {
        let csv = "Date,Payee,Amount\n2026-01-02,Smith; Co,12.50"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 2, payeeIndex: 1, hasHeader: true)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.count == 1)
        #expect(results.first?.payee == "Smith; Co")
        #expect(results.first?.amount == Decimal(string: "12.50"))
    }

    @Test func quotedFieldKeepsItsDelimiter() throws {
        let csv = "date,amount,payee\n2026-01-02,12.50,\"Smith, Co\""
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.first?.payee == "Smith, Co")
    }

    @Test func quotedFieldUnescapesDoubledQuotesAndKeepsNewlines() throws {
        let csv = "date,amount,payee\n2026-01-02,12.50,\"Joe \"\"The\nPlumber\"\"\"\n2026-01-03,3.00,Tea"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["Joe \"The\nPlumber\"", "Tea"])
    }

    @Test func crlfLineEndingsParse() throws {
        let csv = "date,amount,payee\r\n2026-05-01,25.50,Coffee\r\n2026-05-02,3.00,Tea\r\n"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["Coffee", "Tea"])
    }

    @Test func headerlessCommaFileWithSemicolonPayeeKeepsCommaDelimiter() throws {
        let csv = "2026-01-02,12.50,Smith; Co; Ltd; Inc\n2026-01-03,3.00,Tea"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: false)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.map(\.payee) == ["Smith; Co; Ltd; Inc", "Tea"])
    }

    @Test func quotedPayeeHashesLikeTheUnquotedPayee() throws {
        let quoted = try CSVImportService().parse(csv: "date,amount,payee\n2026-05-01,25.50,\"Coffee Shop\"", mapping: dateAmountPayee)
        let plain = try CSVImportService().parse(csv: "date,amount,payee\n2026-05-01,25.50,Coffee Shop", mapping: dateAmountPayee)

        #expect(quoted.first?.importHash == plain.first?.importHash)
    }

    @Test func rowsSplitsQuoteAwareAndDropsBlankLines() {
        let rows = CSVImportService.rows(from: "a,b,c\n\n1,\"x; y\",3\n")
        #expect(rows == [["a", "b", "c"], ["1", "x; y", "3"]])
    }
}
