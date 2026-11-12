import Foundation
import Testing
import SwiftData
@testable import FinanceTracker

/// Regression coverage for Apple FB23627448: SwiftData may lose precision when a
/// `Decimal` attribute is persisted (r/swift 2026-07-15 reported
/// `Decimal(string: "123456789012345.6")` coming back as `123456789012346`).
/// FinanceTracker stores all money as `Decimal` (Transaction.amount,
/// Account.openingBalance, Budget.monthlyLimit), so these tests round-trip values
/// through the app's real container configuration: the versioned `SchemaV1` with
/// `FinanceTrackerMigrationPlan` on an on-disk SQLite store, read back through a
/// brand-new container and context so nothing is served from an in-memory cache.
@Suite("DecimalPersistence")
struct DecimalPersistenceTests {

    /// Magnitudes the app can realistically store: cents, typical balances, and
    /// large-but-plausible figures, through the 15-significant-digit boundary.
    static let realisticValues: [String] = [
        "0.01", "0.1", "0.29", "12.50", "19.99", "1234.56", "99999.99",
        "1234567.89", "123456789.01", "9999999999.99", "999999999999.99",
        "-250.75",
        // 15 significant digits: the last width that survives persistence.
        "1234567890123.45", "123456789012345",
    ]

    /// Values with 16 significant digits, beyond what any real account holds.
    /// The first entry is the exact repro from the report. Measured with Xcode 27.1
    /// on iOS 26.4.1 and 27.0: the on-disk store keeps 15 significant digits and
    /// rounds the rest, so each of these is expected to fail until Apple fixes FB23627448.
    static let highMagnitudeValues: [String] = [
        "123456789012345.6",   // the FB23627448 repro
        "12345678901234.56",
        "1234567890123.456",
    ]

    private enum StoreKind: String, CaseIterable {
        case inMemory
        case onDiskWithMigrationPlan
    }

    private static func makeAppContainer(_ kind: StoreKind, storeURL: URL?) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        switch kind {
        case .inMemory:
            // UI-test / screenshot path in FinanceTrackerApp.sharedModelContainer.
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try ModelContainer(for: schema, configurations: [config])
        case .onDiskWithMigrationPlan:
            // Production path in FinanceTrackerApp.sharedModelContainer.
            let config = ModelConfiguration(schema: schema, url: try #require(storeURL))
            return try ModelContainer(
                for: schema,
                migrationPlan: FinanceTrackerMigrationPlan.self,
                configurations: [config]
            )
        }
    }

    /// Writes `value` to Transaction.amount, Account.openingBalance and
    /// Budget.monthlyLimit, then reads all three back and returns them.
    private static func roundTrip(
        _ value: Decimal,
        kind: StoreKind
    ) throws -> (amount: Decimal, openingBalance: Decimal, monthlyLimit: Decimal) {
        guard kind == .onDiskWithMigrationPlan else {
            return try writeThenRead(value, kind: kind, storeURL: nil)
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DecimalPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        // Both containers live only inside `writeThenRead`, so they are released
        // (and the SQLite files closed) before the directory is removed.
        return try writeThenRead(value, kind: kind, storeURL: dir.appendingPathComponent("store.sqlite"))
    }

    private static func writeThenRead(
        _ value: Decimal,
        kind: StoreKind,
        storeURL: URL?
    ) throws -> (amount: Decimal, openingBalance: Decimal, monthlyLimit: Decimal) {
        // Write, with the first container kept alive so the in-memory store
        // survives long enough to be read through a second context.
        let writer = try makeAppContainer(kind, storeURL: storeURL)
        do {
            let ctx = ModelContext(writer)
            let account = Account(name: "Checking", type: .checking, openingBalance: value)
            let category = Category(name: "Groceries", type: .expense)
            ctx.insert(account)
            ctx.insert(category)
            ctx.insert(Transaction(date: .now, amount: value, payee: "Payee", type: .debit, account: account))
            ctx.insert(Budget(monthlyLimit: value, month: .now, category: category))
            try ctx.save()
        }

        // Read back. On disk, open a fresh container so nothing is cached;
        // in memory the store only exists inside `writer`, so use a new context.
        let reader = kind == .onDiskWithMigrationPlan
            ? try makeAppContainer(kind, storeURL: storeURL)
            : writer
        let ctx = ModelContext(reader)
        let amount = try ctx.fetch(FetchDescriptor<Transaction>()).first?.amount
        let opening = try ctx.fetch(FetchDescriptor<Account>()).first?.openingBalance
        let limit = try ctx.fetch(FetchDescriptor<Budget>()).first?.monthlyLimit
        withExtendedLifetime(writer) {}
        return (try #require(amount), try #require(opening), try #require(limit))
    }

    @Test(arguments: realisticValues, StoreKind.allCases)
    private func realisticMagnitudesRoundTripExactly(_ text: String, kind: StoreKind) throws {
        let value = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
        let result = try Self.roundTrip(value, kind: kind)
        #expect(result.amount == value, "Transaction.amount \(text) came back as \(result.amount)")
        #expect(result.openingBalance == value, "Account.openingBalance \(text) came back as \(result.openingBalance)")
        #expect(result.monthlyLimit == value, "Budget.monthlyLimit \(text) came back as \(result.monthlyLimit)")
    }

    /// On-disk only: the in-memory store reads back through the writer's own
    /// container, so it may serve the saved value from cache and never hit the
    /// lossy conversion. Without `isIntermittent`, a future OS that fixes
    /// FB23627448 fails this test with "Known issue was not recorded", which is
    /// the signal to drop the wrapper and merge these values into `realisticValues`.
    @Test(arguments: highMagnitudeValues)
    private func highMagnitudesRoundTripExactly(_ text: String) throws {
        let value = try #require(Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")))
        let result = try Self.roundTrip(value, kind: .onDiskWithMigrationPlan)
        withKnownIssue("FB23627448: SwiftData rounds Decimal to 15 significant digits") {
            #expect(result.amount == value, "Transaction.amount \(text) came back as \(result.amount)")
            #expect(result.openingBalance == value, "Account.openingBalance \(text) came back as \(result.openingBalance)")
            #expect(result.monthlyLimit == value, "Budget.monthlyLimit \(text) came back as \(result.monthlyLimit)")
        }
    }
}
