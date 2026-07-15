import Testing
import Foundation
import SwiftData
@testable import FinanceTracker

@Suite("ImportViewModel")
struct ImportViewModelTests {

    @Test func loadCSVAdvancesToColumnMapping() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting()
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)

        #expect(vm.step == .columnMapping)
        #expect(!vm.csvSampleRows.isEmpty)
    }

    @Test func applyMappingParsesTransactions() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting()
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,1200.00,Rent"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        #expect(vm.step == .preview)
        #expect(vm.pendingTransactions.count == 2)
        #expect(vm.skippedCount == 0)
    }

    @Test func applyMappingDeduplicatesAgainstExistingHashes() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let hash = CSVImportService.importHash(
            date: date, amount: Decimal(string: "25.50")!, payee: "Coffee Shop"
        )

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(existingHashes: [hash])
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,50.00,Grocery"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        #expect(vm.pendingTransactions.count == 1)
        #expect(vm.skippedCount == 1)
        #expect(vm.pendingTransactions[0].payee == "Grocery")
    }

    @Test func startImportChunksAndReportsCompletionProgress() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake,
            chunkSize: 2
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n" + (1...5).map { "2026-05-0\($0),10.00,Payee\($0)" }.joined(separator: "\n")
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }

        // progress is 0 here, not 1.0 — reset() (called on successful completion, see
        // below) zeroes it as part of returning the ViewModel to its ready state, and
        // that happens before the `defer { isImporting = false }` this waitUntil is
        // gated on. Chunk/record assertions below are the meaningful completion checks.
        let savedChunkCount = await fake.savedChunkCount
        #expect(savedChunkCount == 3)   // 5 items, chunkSize 2 → chunks of 2, 2, 1
        #expect(vm.step == .filePicker)
        #expect(vm.progress == 0)
        #expect(vm.importError == nil)

        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.count == 1)
        #expect(records[0].transactionCount == 5)
    }

    @Test func startImportIgnoresSecondCallWhileFirstIsInFlight() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        await fake.setDelayPerChunk(.milliseconds(200))
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake,
            chunkSize: 1
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n" + (1...3).map { "2026-05-0\($0),10.00,Payee\($0)" }.joined(separator: "\n")
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "first.csv")
        vm.startImport(filename: "second.csv")   // re-entrant call while isImporting — must be a no-op
        try await waitUntil { !vm.isImporting }

        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.count == 1)
        #expect(records[0].filename == "first.csv")
    }

    @Test func cancelImportClearsPendingTransactionsToPreventStaleRetry() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        await fake.setDelayPerChunk(.milliseconds(200))
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake,
            chunkSize: 1
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n" + (1...5).map { "2026-05-0\($0),10.00,Payee\($0)" }.joined(separator: "\n")
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await Task.sleep(for: .milliseconds(50))   // let chunks start, before any 200ms delay resolves
        vm.cancelImport()
        try await waitUntil { !vm.isImporting }

        let savedChunkCount = await fake.savedChunkCount
        #expect(savedChunkCount < 5)   // cancellation interrupted at least one in-flight chunk

        // Regression guard: a stale pendingTransactions list after cancellation would let
        // a re-tap of Import re-send rows already persisted by the completed chunks above —
        // duplicate transactions in a finance app. Must be cleared, forcing a fresh
        // applyMapping() dedup pass before another import attempt.
        #expect(vm.pendingTransactions.isEmpty)
        #expect(vm.importError != nil)
    }

    @Test func startImportDoesNotWriteImportRecordWhenAChunkFails() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        await fake.setFailNextSave(with: TransactionImportError.accountNotFound)
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }

        // No ImportRecord is written on failure, pendingTransactions is cleared (same
        // stale-retry protection as the cancellation case above), and the error is
        // captured on importError even though no UI surfaces it yet this PR — matches
        // the existing try?-swallowing pattern used elsewhere in this codebase (e.g.
        // ContentView's .task block), but the ViewModel itself must not lose the error.
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.isEmpty)
        #expect(vm.pendingTransactions.isEmpty)
        #expect(vm.importError != nil)
    }
}
