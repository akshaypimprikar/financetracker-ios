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
        let csv = "date,amount,payee\n2026-05-01,12.50abc,Coffee\n2026-05-02,1.2.3,Tea\n2026-05-03,10.00,Juice"
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

    @Test func inchMarkDoesNotCloseAStrayQuoteAcrossRows() throws {
        // `27"` ends a line, so it looks like a closing quote; the field it would close holds a dated row.
        let csv = "date,amount,payee\n2026-05-01,12.50,\"Weird Al\n2026-05-02,30.00,Monitor 27\""
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["\"Weird Al", "Monitor 27\""])
        #expect(results.map(\.amount) == [Decimal(string: "12.50")!, Decimal(30)])
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

    @Test func badDigitGroupingIsRejectedAndPlusSignIsAccepted() throws {
        let csv = "date,amount,payee\n2026-05-01,\"12,34.56\",A\n2026-05-02,\"1234,567.89\",B\n2026-05-03,+5.00,C"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["C"])
        #expect(results.first?.amount == Decimal(5))
    }

    @Test func tiedSeparatorVotesFallBackToTheDelimiterConvention() throws {
        // "12,50" votes comma, "3.75" votes dot; a tie in a ';' file means decimal comma, so "3.75" is rejected.
        let csv = "date;amount;payee\n2026-05-01;12,50;Bakery\n2026-05-02;3.75;Tea"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(string: "12.50")!])
    }

    @Test func raggedSemicolonFileKeepsSemicolon() throws {
        let csv = "date;amount;payee\n2026-05-01;12,50;Bakery\n2026-05-02;3,00"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["Bakery"])
    }

    @Test func midFieldQuoteIsLiteralAndUnclosedQuoteDoesNotSwallowLaterRows() {
        let rows = CSVImportService.rows(from: "a,b,c\n5\" pipe,\"open,x\nd,e,f")
        #expect(rows == [["a", "b", "c"], ["5\" pipe", "\"open", "x"], ["d", "e", "f"]])
    }

    @Test func laterQuoteDoesNotCloseAStrayOpeningQuote() throws {
        let csv = "date,amount,payee\n2026-05-01,1.00,\"Joe\n2026-05-02,2.00,\"Tea\""
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["\"Joe", "Tea"])
    }

    @Test func footerRowWithoutADateDoesNotVoteOnTheSeparator() throws {
        let csv = "date;amount;payee\n2026-05-01;1.234;A\nSumme;12.50;x"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(1234)])
    }

    @Test func unicodeLineSeparatorDoesNotEndARecord() throws {
        let csv = "date,amount,payee\n2026-05-01,1.00,A\u{2028}B"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["A\u{2028}B"])
    }

    @Test func onlyCurrencyMarkersAreStrippedFromAmounts() throws {
        // Any uppercase 3-letter code counts as a currency code ("REF" too); longer words, other short
        // words and punctuation do not.
        let csv = "date,amount,payee\n2026-05-01,REFX 12.50,A\n2026-05-02,No 3.00,B\n2026-05-03,Ref. 4.00,C\n2026-05-04,REF 5.00,D\n2026-05-05,EUR 6.00,E"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["D", "E"])
    }

    @Test func letterCurrencyMarkersParseInAnyCase() throws {
        let csv = "date,amount,payee\n2026-05-01,12.50 usd,A\n2026-05-02,kr 100.00,B\n2026-05-03,ZŁ 1.50,C\n2026-05-04,R$ 5.00,D\n2026-05-05,Fr. 7.25,E\n2026-05-06,9.00 Kč,F\n2026-05-07,GHS 2.00,G"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == ["12.50", "100", "1.50", "5", "7.25", "9", "2"].map { Decimal(string: $0)! })
    }

    @Test func signOnBothSidesIsRejected() throws {
        let csv = "date,amount,payee\n2026-05-01,-12.50-,A\n2026-05-02,-3.00,B"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["B"])
    }

    @Test func indianLakhGroupingParses() throws {
        let csv = "date,amount,payee\n2026-05-01,\"1,23,456.78\",A\n2026-05-02,\"12,34,567\",B\n2026-05-03,\"1,00,00,000.00\",C\n2026-05-04,\"1,2,345.00\",D\n2026-05-05,\"12,345,67.00\",E"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["A", "B", "C"])
        #expect(results.map(\.amount) == ["123456.78", "1234567", "10000000"].map { Decimal(string: $0)! })
    }

    @Test func titleLineBeforeSemicolonHeaderKeepsSemicolon() throws {
        let csv = "Kontoauszug\nDatum;Betrag;Empfänger\n2026-05-01;12,50;Bakery"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(string: "12.50")!])
    }

    @Test func headerlessSemicolonFileWithCommasInFieldsKeepsSemicolon() throws {
        let csv = "2026-05-01;12,50;Doe, John\n2026-05-02;3,00;Roe, Jane"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: false)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.map(\.payee) == ["Doe, John", "Roe, Jane"])
        #expect(results.map(\.amount) == [Decimal(string: "12.50")!, Decimal(3)])
    }

    @Test func headerlessSemicolonFileWithSeveralCommasPerPayeeKeepsSemicolon() throws {
        let csv = "2026-05-01;12,50;Doe, John, Jr\n2026-05-02;3,00;Roe, Jane, Sr"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: false)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.map(\.payee) == ["Doe, John, Jr", "Roe, Jane, Sr"])
    }

    @Test func headerlessCommaFileWithASemicolonInEveryRowKeepsComma() throws {
        let csv = "2026-05-01,12.50,A;B\n2026-05-02,3.00,C;D"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: false)
        let results = try CSVImportService().parse(csv: csv, mapping: mapping)

        #expect(results.map(\.payee) == ["A;B", "C;D"])
    }

    @Test func tiedVotesFromAFourDigitAmountKeepTheDecimalComma() throws {
        // '.' and ',' get one vote each, so a ';' file keeps its decimal comma.
        let csv = "date;amount;payee\n2026-05-01;1234.567;A\n2026-05-02;12,50;B"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.payee) == ["B"])
        #expect(results.map(\.amount) == [Decimal(string: "12.50")!])
    }

    @Test func fourDigitIntegerPartIsNotAThousandsGroup() throws {
        // "1234.567" can't be grouped, so it votes '.' even in a ';' file.
        let csv = "date;amount;payee\n2026-05-01;1234.567;A"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(string: "1234.567")!])
    }

    @Test func currencyAffixesTrailingSignAndSpaceGroupingParse() throws {
        let us = "date,amount,payee\n2026-05-01,12.50-,A\n2026-05-02,USD 3.00,B\n2026-05-03,$4.25,C"
        let eu = "date;amount;payee\n2026-05-01;12,50 €;A\n2026-05-02;1 234,56;B"

        let usResults = try CSVImportService().parse(csv: us, mapping: dateAmountPayee)
        let euResults = try CSVImportService().parse(csv: eu, mapping: dateAmountPayee)

        #expect(usResults.map(\.amount) == [Decimal(string: "12.50")!, Decimal(3), Decimal(string: "4.25")!])
        #expect(euResults.map(\.amount) == [Decimal(string: "12.50")!, Decimal(string: "1234.56")!])
    }

    @Test func leadingZeroIsNotAThousandsGroup() throws {
        let commaFile = "date,amount,payee\n2026-05-01,\"0,123\",A\n2026-05-02,12.50,B"
        let semicolonFile = "date;amount;payee\n2026-05-01;0.500;A\n2026-05-02;12,50;B"

        let us = try CSVImportService().parse(csv: commaFile, mapping: dateAmountPayee)
        let eu = try CSVImportService().parse(csv: semicolonFile, mapping: dateAmountPayee)

        #expect(us.map(\.payee) == ["B"])
        #expect(eu.map(\.payee) == ["B"])
    }

    @Test func malformedAmountsDoNotVoteOnTheSeparator() throws {
        let csv = "date,amount,payee\n2026-05-01,1.2.3,A\n2026-05-02,4.5.6,B\n2026-05-03,12.50,C"
        let results = try CSVImportService().parse(csv: csv, mapping: dateAmountPayee)

        #expect(results.map(\.amount) == [Decimal(string: "12.50")!])
    }

    @Test func rowsSplitsQuoteAwareAndDropsBlankLines() {
        let rows = CSVImportService.rows(from: "a,b,c\n\n1,\"x; y\",3\n")
        #expect(rows == [["a", "b", "c"], ["1", "x; y", "3"]])
    }
}
