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
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
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
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
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
            importWriter: FakeTransactionImportWriting(existingHashes: [hash]),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
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
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
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
        #expect(vm.importFailure == nil)

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
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
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
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
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
        // A user-initiated cancel is not an error to alert about — importFailure
        // stays nil, unlike a genuine chunk failure (see the tests below).
        #expect(vm.importFailure == nil)
    }

    @Test func staleTaskCompletionDoesNotClobberNewerSession() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        await fake.setDelayPerChunk(.milliseconds(300))
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake,
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            chunkSize: 1
        )
        try vm.load()
        vm.selectedAccount = account
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)

        // Session A: start a slow import, then cancel it exactly like the toolbar
        // Cancel button does (cancelImport() + reset()).
        vm.loadCSV("date,amount,payee\n2026-05-01,10.00,SessionA")
        try await vm.applyMapping(mapping)
        vm.startImport(filename: "sessionA.csv")
        vm.cancelImport()
        vm.reset()

        // Session B: start a fresh, unrelated session immediately, while session
        // A's cancelled task is still asleep (300ms delay) and hasn't reached its
        // catch block yet.
        vm.loadCSV("date,amount,payee\n2026-05-02,20.00,SessionB")
        try await vm.applyMapping(mapping)

        #expect(vm.step == .preview)
        #expect(vm.pendingTransactions.map(\.payee) == ["SessionB"])

        // Let session A's stale task actually unwind and attempt its now-stale
        // mutations.
        try await Task.sleep(for: .milliseconds(400))

        // Regression guard: without the generation guard, session A's delayed
        // catch block would wipe out session B's state set up above.
        #expect(vm.step == .preview)
        #expect(vm.pendingTransactions.map(\.payee) == ["SessionB"])
        #expect(vm.importFailure == nil)
    }

    @Test func startImportDoesNotWriteImportRecordWhenNoChunkSucceeds() async throws {
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
            importWriter: fake,
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }

        // No chunk succeeded (single chunk, single row, fails immediately) — no
        // best-effort ImportRecord is written since there's nothing to record.
        // pendingTransactions is cleared (stale-retry protection), and the failure
        // is captured on importFailure with an accurate zero persisted count.
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.isEmpty)
        #expect(vm.pendingTransactions.isEmpty)
        #expect(vm.importFailure == .partiallyFailed(persistedCount: 0))
    }

    @Test func startImportWritesPartialAuditRecordWhenSomeChunksSucceedBeforeFailure() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        // Exactly one chunk succeeds regardless of TaskGroup scheduling order — see
        // setFailAfter's doc comment. Deterministic without depending on which
        // specific chunk wins the race to run first.
        await fake.setFailAfter(successfulSaves: 1)
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: fake,
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            chunkSize: 1
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n" + (1...3).map { "2026-05-0\($0),10.00,Payee\($0)" }.joined(separator: "\n")
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }

        // Regression guard for the "silent partial persist, zero audit trail" bug:
        // one chunk's worth of transactions is durably in the store with no record
        // of it, unless a best-effort ImportRecord is written for what landed.
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.count == 1)
        #expect(records[0].transactionCount == 1)
        #expect(vm.pendingTransactions.isEmpty)
        #expect(vm.importFailure == .partiallyFailed(persistedCount: 1))
    }

    @Test func startImportReportsRecordSaveFailureSeparatelyFromChunkFailure() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        // Real actor (not the fake) so transactions genuinely land in the store —
        // this test's whole point is proving the data survives even though the
        // bookkeeping write fails.
        let importActor = TransactionImportActor(modelContainer: container)
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: FailingImportRecordRepo(),
            importWriter: importActor,
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = account

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,1200.00,Rent"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }

        // Regression guard for the "successful import misreported as total failure"
        // bug: both transactions are genuinely persisted (verified via a fresh fetch,
        // independent of the ViewModel's own state) even though the ImportRecord
        // save failed, and the failure is distinguishable from a chunk failure.
        let persisted = try SwiftDataTransactionRepository(context: ctx).fetchAll()
        #expect(persisted.count == 2)
        #expect(vm.importFailure == .recordSaveFailed(persistedCount: 2))
    }

    @Test func resetClearsImportFailure() async throws {
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
            importWriter: fake,
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.selectedAccount = account
        vm.loadCSV("date,amount,payee\n2026-05-01,25.50,Coffee Shop")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)
        vm.startImport(filename: "test.csv")
        try await waitUntil { !vm.isImporting }
        #expect(vm.importFailure != nil)

        vm.reset()

        #expect(vm.importFailure == nil)
    }

    @Test func loadSuggestionsPopulatesOneSuggestionPerUniquePayee() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let coffee = Category(name: "Coffee", type: .expense)
        let shopping = Category(name: "Shopping", type: .expense)
        ctx.insert(coffee)
        ctx.insert(shopping)
        try ctx.save()

        let fake = FakeCategorySuggesting(resultsByPayee: [
            "Starbucks": CategorySuggestionResult(
                suggestion: CategorySuggestion(categoryName: "Coffee", confidence: .high),
                matchedCategoryID: coffee.id
            ),
            "Amazon": CategorySuggestionResult(
                suggestion: CategorySuggestion(categoryName: "Shopping", confidence: .medium),
                matchedCategoryID: shopping.id
            ),
        ])
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: fake
        )
        try vm.load()

        let csv = "date,amount,payee\n2026-05-01,6.40,Starbucks\n2026-05-02,6.40,Starbucks\n2026-05-03,34.12,Amazon"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)
        await vm.loadSuggestions()

        #expect(vm.suggestions.count == 2)   // 2 unique payees, not 3 rows
        #expect(vm.suggestions["Starbucks"]?.suggestion.categoryName == "Coffee")
        #expect(vm.suggestions["Starbucks"]?.matchedCategoryID == coffee.id)
        #expect(vm.suggestions["Amazon"]?.suggestion.categoryName == "Shopping")
        let callCount = await fake.suggestCallCount
        #expect(callCount == 2)   // one call per unique payee, not per row
    }

    @Test func loadSuggestionsSkipsWhenSuggesterUnavailable() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Category(name: "Coffee", type: .expense))
        try ctx.save()

        let fake = FakeCategorySuggesting(isAvailable: false)
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: fake
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,6.40,Starbucks")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)
        await vm.loadSuggestions()

        #expect(vm.suggestions.isEmpty)
        let callCount = await fake.suggestCallCount
        #expect(callCount == 0)   // silent skip — no calls made at all
    }

    @Test func setCategoryAppliesToAllRowsSharingThatPayee() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Coffee", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,6.40,Starbucks\n2026-05-02,6.40,Starbucks\n2026-05-03,34.12,Amazon")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        vm.setCategory(categoryID: category.id, forPayee: "Starbucks")

        let starbucksRows = vm.pendingTransactions.filter { $0.payee == "Starbucks" }
        #expect(starbucksRows.allSatisfy { $0.categoryID == category.id })
        let amazonRow = vm.pendingTransactions.first { $0.payee == "Amazon" }
        #expect(amazonRow?.categoryID == nil)   // regression guard: other payees untouched
    }

    @Test func resetClearsStaleSuggestions() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let coffee = Category(name: "Coffee", type: .expense)
        ctx.insert(coffee)
        try ctx.save()

        let fake = FakeCategorySuggesting(resultsByPayee: [
            "Starbucks": CategorySuggestionResult(
                suggestion: CategorySuggestion(categoryName: "Coffee", confidence: .high),
                matchedCategoryID: coffee.id
            )
        ])
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: fake
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,6.40,Starbucks")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)
        await vm.loadSuggestions()
        #expect(vm.suggestions["Starbucks"] != nil)

        vm.reset()

        // Regression guard: a stale payee->suggestion mapping surviving reset() would
        // render a leftover chip for a same-named payee in a brand-new session, before
        // that session's own loadSuggestions() has even run — same stale-session class
        // of bug the importGeneration mechanism elsewhere in this file guards against.
        #expect(vm.suggestions.isEmpty)
    }

    @Test func createAndAssignCategoryCreatesNewWhenNoNearDuplicate() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        ctx.insert(Category(name: "Coffee", type: .expense))
        try ctx.save()

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,34.12,Amazon")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        try vm.createAndAssignCategory(named: "Shopping", forPayee: "Amazon")

        #expect(vm.categories.map(\.name).sorted() == ["Coffee", "Shopping"])
        let amazonRow = vm.pendingTransactions.first { $0.payee == "Amazon" }
        let created = vm.categories.first { $0.name == "Shopping" }
        #expect(amazonRow?.categoryID == created?.id)
    }

    @Test func createAndAssignCategoryReusesExistingNearDuplicate() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let travel = Category(name: "Travel", type: .expense)
        ctx.insert(travel)
        try ctx.save()

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,120.00,Delta Airlines")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        try vm.createAndAssignCategory(named: "  travel  ", forPayee: "Delta Airlines")

        // Reused the existing "Travel" category instead of inserting a duplicate.
        #expect(vm.categories.count == 1)
        let row = vm.pendingTransactions.first { $0.payee == "Delta Airlines" }
        #expect(row?.categoryID == travel.id)
    }

    @Test func createAndAssignCategoryRejectsBlankName() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        try ctx.save()

        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,34.12,Amazon")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)

        try vm.createAndAssignCategory(named: "   ", forPayee: "Amazon")

        #expect(vm.categories.isEmpty)
        let amazonRow = vm.pendingTransactions.first { $0.payee == "Amazon" }
        #expect(amazonRow?.categoryID == nil)
    }

    @Test func createAndAssignCategoryRematchesOtherPendingSuggestions() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        try ctx.save()

        let fake = FakeCategorySuggesting(resultsByPayee: [
            "Amazon": CategorySuggestionResult(
                suggestion: CategorySuggestion(categoryName: "Shopping", confidence: .high),
                matchedCategoryID: nil
            ),
            "Target": CategorySuggestionResult(
                suggestion: CategorySuggestion(categoryName: "Shopping", confidence: .medium),
                matchedCategoryID: nil
            ),
        ])
        let vm = ImportViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
            importWriter: FakeTransactionImportWriting(),
            categoryRepo: SwiftDataCategoryRepository(context: ctx),
            categorySuggester: fake
        )
        try vm.load()
        vm.loadCSV("date,amount,payee\n2026-05-01,34.12,Amazon\n2026-05-02,18.00,Target")
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try await vm.applyMapping(mapping)
        await vm.loadSuggestions()
        #expect(vm.suggestions["Target"]?.matchedCategoryID == nil)

        try vm.createAndAssignCategory(named: "Shopping", forPayee: "Amazon")

        // Target's cached suggestion now points at the category Amazon's create just
        // made — computed by re-checking cached names, not a second model call.
        let created = vm.categories.first { $0.name == "Shopping" }
        #expect(vm.suggestions["Target"]?.matchedCategoryID == created?.id)
        let callCount = await fake.suggestCallCount
        #expect(callCount == 2)   // still just the original per-payee calls
    }
}
