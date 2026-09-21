// Golden hex values were cross-checked against `printf '%s' "<yyyy-MM-dd>-<amount>-<lowercased trimmed payee>" | shasum -a 256` (recipe read from CSVImportService.importHash), not just the production function.
import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@Suite("ImportHashGoldenTests")
struct ImportHashGoldenTests {

    private static let coffeeShopMay1 = "80b1ad9704d2e4a875c5938c4b6a2794d751b0e8c599cbccde1414b02d943998"
    private static let atmWithdrawalMay2Abs = "866e032ddda29e838a6a06fce665256971c2057b0cf80d20a4a4375d6fba365e"
    private static let rentMay4 = "1ac58c1b25b19ab84b55d04c0352549dac67fc56fa8ce3a58ce16363aa32062b"

    // Local-midnight date, built the same way CSV parsing builds it, so the yyyy-MM-dd
    // string the hash sees is identical under any device time zone.
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func amount(_ string: String) -> Decimal { Decimal(string: string)! }

    // MARK: Golden vectors

    @Test func normalPayeeMatchesGoldenHash() {
        let hash = CSVImportService.importHash(date: day(2026, 5, 1), amount: amount("25.50"), payee: "Coffee Shop")
        #expect(hash == Self.coffeeShopMay1)
    }

    @Test func payeeIsLowercasedAndTrimmedBeforeHashing() {
        let hash = CSVImportService.importHash(date: day(2026, 5, 1), amount: amount("25.50"), payee: "  COFFEE shop  ")
        #expect(hash == Self.coffeeShopMay1)
    }

    @Test func negativeAmountKeepsItsSignInTheHashInput() {
        let hash = CSVImportService.importHash(date: day(2026, 5, 2), amount: amount("-45.00"), payee: "ATM Withdrawal")
        #expect(hash == "369aa25bba22a264f5cd95a97f81d37584fcb70f4a4020ed3441bd3bda50ebdb")
    }

    @Test func parsedNegativeAmountHashesItsAbsoluteValue() throws {
        let csv = "date,amount,payee\n2026-05-02,-45.00,ATM Withdrawal"
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let parsed = try CSVImportService().parse(csv: csv, mapping: mapping)
        #expect(parsed.count == 1)
        #expect(parsed[0].importHash == Self.atmWithdrawalMay2Abs)
    }

    @Test func trailingZerosDoNotChangeTheHash() {
        // Decimal's description drops trailing zeros ("12.50" and "12.5" both render "12.5").
        let withZero = CSVImportService.importHash(date: day(2026, 5, 3), amount: amount("12.50"), payee: "Lunch")
        let withoutZero = CSVImportService.importHash(date: day(2026, 5, 3), amount: amount("12.5"), payee: "Lunch")
        #expect(withZero == "0b3da228b2ffa473bd264b64d0f166fd85d115a40a3994fb68ef13d275744c71")
        #expect(withoutZero == withZero)
    }

    @Test func wholeNumberAmountWithDecimalZerosMatchesGoldenHash() {
        let hash = CSVImportService.importHash(date: day(2026, 5, 4), amount: amount("1200.00"), payee: "Rent")
        #expect(hash == Self.rentMay4)
    }

    @Test func unicodePayeeMatchesGoldenHash() {
        // Escapes (precomposed é/ü) so source-file normalization can't alter the bytes hashed.
        let payee = "Caf\u{00E9} M\u{00FC}nchen \u{6771}\u{4EAC}"
        let hash = CSVImportService.importHash(date: day(2026, 6, 15), amount: amount("8.75"), payee: payee)
        #expect(hash == "c42700bfb65bd86f7982411aaf543b9664f73b0182fdf884e93add9271e2d4d8")
    }

    @Test func parsedCSVRowMatchesGoldenHash() throws {
        let csv = "date,amount,payee\n2026-05-01,25.50,  COFFEE shop  "
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        let parsed = try CSVImportService().parse(csv: csv, mapping: mapping)
        #expect(parsed.count == 1)
        #expect(parsed[0].importHash == Self.coffeeShopMay1)
    }

    // MARK: Time zone

    @Test func fixedInstantHashFollowsTheDeviceTimeZone() {
        // 2026-05-01T23:30:00Z is still 2026-05-01 at UTC+0 and west, and 2026-05-02 from
        // UTC+0:30 east, so the hash of a fixed *instant* changes with device time zone (no
        // injection point in production). Both outcomes are pinned so this passes under any TZ.
        let instant = Date(timeIntervalSince1970: 1_777_678_200)
        let hash = CSVImportService.importHash(date: instant, amount: amount("25.50"), payee: "Coffee Shop")
        let offset = Calendar.current.timeZone.secondsFromGMT(for: instant)
        let expected = offset >= 1800
            ? "34de012c6e0016e56c808f3ae4e42a782ec91af3cf27e597a934c56fffa42a2a"   // 2026-05-02
            : Self.coffeeShopMay1   // 2026-05-01
        #expect(hash == expected)
    }

    // MARK: Idempotency

    @Test func importingTheSameCSVTwiceAddsNothingAndKeepsHashes() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: TransactionImportActor(modelContainer: container),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = """
        date,amount,payee
        2026-05-01,25.50,Coffee Shop
        2026-05-02,-45.00,ATM Withdrawal
        2026-05-04,1200.00,Rent
        """
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)

        vm.loadCSV(csv)
        try await vm.applyMapping(mapping)
        #expect(vm.pendingTransactions.count == 3)
        vm.startImport(filename: "first.csv")
        #expect(try await waitUntil { !vm.isImporting })
        #expect(vm.importFailure == nil)

        // Sorted "payee|hash" pairs: a duplicate row fails an #expect instead of trapping a Dictionary.
        let firstPass = try ctx.fetch(FetchDescriptor<Transaction>())
        let firstSnapshot = firstPass.map { "\($0.payee)|\($0.importHash ?? "nil")" }.sorted()
        #expect(firstSnapshot == [
            "ATM Withdrawal|\(Self.atmWithdrawalMay2Abs)",
            "Coffee Shop|\(Self.coffeeShopMay1)",
            "Rent|\(Self.rentMay4)",
        ])

        // The second pass is stopped at dedup (pending empty), so startImport is a no-op by design;
        // the assertions below check the store and audit records are untouched end to end.
        vm.loadCSV(csv)
        try await vm.applyMapping(mapping)
        #expect(vm.pendingTransactions.isEmpty)
        #expect(vm.skippedCount == 3)
        vm.startImport(filename: "second.csv")
        #expect(try await waitUntil { !vm.isImporting })
        #expect(vm.importFailure == nil)

        let secondPass = try ctx.fetch(FetchDescriptor<Transaction>())
        let secondSnapshot = secondPass.map { "\($0.payee)|\($0.importHash ?? "nil")" }.sorted()
        #expect(secondSnapshot == firstSnapshot)
        #expect(try SwiftDataImportRecordRepository(context: ctx).fetchAll().count == 1)
    }
}
