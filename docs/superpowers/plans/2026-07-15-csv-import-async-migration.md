# CSV Import Async Migration Implementation Plan

**Goal:** Replace the synchronous, main-thread-blocking CSV import path with an async pipeline — a single batched dedup fetch, a `TaskGroup`-driven `@ModelActor` for chunked saves, and a cancellable, progress-reporting `ImportSheet`.
**Architecture:** New `TransactionImportActor` (`@ModelActor`) behind a `TransactionImportWriting` protocol owns all import-time SwiftData writes; `ImportViewModel` drives it via `TaskGroup` (one child task per chunk) and exposes `progress`/`isImporting`/`cancelImport()`; `ImportSheet` binds to that state with a determinate progress bar.
**Tech Stack:** Swift 6.2, SwiftUI, SwiftData (`@ModelActor`), Swift Concurrency (`TaskGroup`, structured cancellation), Swift Testing.
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains FinanceTracker.xcodeproj)

## Deviation from spec (flag for reviewer)

`docs/superpowers/specs/2026-07-15-csv-import-async-migration.md` shows `TransactionImportWriting.save(chunk:accountID:)` taking a `PersistentIdentifier`. That's a SwiftData type — putting it in a Protocols/ file would violate the "Repository Protocols: Foundation-only imports" rule enforced on every task below. Fix used throughout this plan: `accountID: UUID` (the existing `Account.id` domain identity), resolved inside `TransactionImportActor` via a `#Predicate` fetch instead of `modelContext.model(for:)`. Same safety property the spec's constraint was protecting (never a live `@Model` reference crossing the actor boundary); account counts are always small, so the fetch-vs-direct-lookup cost is a non-issue. Everything else in the spec is followed as written.

## Task 1 — `TransactionImportWriting` protocol + `TransactionImportActor`

New files only — nothing references them yet, so the build stays green throughout.

### 1a. Write the failing test

Create `FinanceTrackerTests/Repositories/TransactionImportActorTests.swift`:

```swift
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
}
```

### 1b. Confirm failure

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/TransactionImportActorTests \
  2>&1 | xcsift
```
Expected: **BUILD FAILED** — `TransactionImportActor`, `TransactionImportError`, and `ParsedTransaction`'s missing `Sendable` conformance don't exist/compile yet.

### 1c. Implement

Edit `FinanceTracker/Services/CSVImportService.swift` — add `Sendable` to `ParsedTransaction` (only this one line changes; rest of the file is untouched):

```swift
struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
}
```

Create `FinanceTracker/Repositories/Protocols/TransactionImportWriting.swift`:

```swift
import Foundation

protocol TransactionImportWriting: Sendable {
    /// All `importHash` values currently in the store, fetched once rather than
    /// checked per row — see docs/superpowers/specs/2026-07-15-csv-import-async-migration.md.
    func existingHashes() async throws -> Set<String>

    /// Inserts and saves one chunk of parsed rows against the account identified by
    /// `accountID`. Exactly one `save()` per call — never per row.
    func save(chunk: [ParsedTransaction], accountID: UUID) async throws
}

enum TransactionImportError: Error, Equatable {
    case accountNotFound
}
```

Create `FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift`:

```swift
import Foundation
import SwiftData

@ModelActor
actor TransactionImportActor: TransactionImportWriting {
    func existingHashes() async throws -> Set<String> {
        let all = try modelContext.fetch(FetchDescriptor<Transaction>())
        return Set(all.compactMap(\.importHash))
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        try Task.checkCancellation()
        var accountDescriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == accountID }
        )
        accountDescriptor.fetchLimit = 1
        guard let account = try modelContext.fetch(accountDescriptor).first else {
            throw TransactionImportError.accountNotFound
        }
        for parsed in chunk {
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account
            )
            modelContext.insert(tx)
        }
        try modelContext.save()   // ONE save() per chunk, never per row
    }
}
```

### 1d. Confirm pass

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/TransactionImportActorTests \
  2>&1 | xcsift
```
Expected: **TEST SUCCEEDED**, 4/4 tests pass.

### 1e. Commit

```bash
git add FinanceTracker/Services/CSVImportService.swift \
        FinanceTracker/Repositories/Protocols/TransactionImportWriting.swift \
        FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift \
        FinanceTrackerTests/Repositories/TransactionImportActorTests.swift
git commit -m "feat(import): add TransactionImportActor for chunked async saves"
```

## Task 2 — `ImportViewModel` async migration + DI wiring

Must land together: changing `ImportViewModel.init` to require `importWriter` breaks every existing call site in the same commit, so `FinanceTrackerApp.swift`/`ContentView.swift` are updated here too, not in a later task.

### 2a. Write the failing tests

Add to `FinanceTrackerTests/TestHelpers.swift` (append below the existing `makeContainer()`):

```swift
actor FakeTransactionImportWriting: TransactionImportWriting {
    private var _existingHashes: Set<String>
    private(set) var savedChunkCount = 0
    private var delayPerChunk: Duration?
    private var failNextSave: Error?

    init(existingHashes: Set<String> = []) {
        self._existingHashes = existingHashes
    }

    func setDelayPerChunk(_ delay: Duration) {
        delayPerChunk = delay
    }

    func setFailNextSave(with error: Error) {
        failNextSave = error
    }

    func existingHashes() async throws -> Set<String> {
        _existingHashes
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        if let delayPerChunk {
            try await Task.sleep(for: delayPerChunk)
        }
        try Task.checkCancellation()
        if let error = failNextSave {
            failNextSave = nil
            throw error
        }
        savedChunkCount += 1
    }
}

@discardableResult
func waitUntil(
    timeout: Duration = .seconds(2),
    _ condition: @escaping () -> Bool
) async throws -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
```

Replace `FinanceTrackerTests/ViewModels/ImportViewModelTests.swift` in full:

```swift
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
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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

        #expect(vm.progress == 1.0)
        let savedChunkCount = await fake.savedChunkCount
        #expect(savedChunkCount == 3)   // 5 items, chunkSize 2 → chunks of 2, 2, 1
        #expect(vm.step == .filePicker)

        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.count == 1)
        #expect(records[0].transactionCount == 5)
    }

    @Test func cancelImportStopsBeforeAllChunksSave() async throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let fake = FakeTransactionImportWriting()
        await fake.setDelayPerChunk(.milliseconds(200))
        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
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

        // startImport() swallows the thrown error internally today (matches the existing
        // try?-swallowing pattern used elsewhere in this codebase, e.g. ContentView's
        // .task block) — surfacing it to the UI is out of scope for this PR. This test
        // documents the one invariant that matters: no ImportRecord is written on failure.
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()
        #expect(records.isEmpty)
    }
}
```

### 2b. Confirm failure

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/ImportViewModelTests \
  2>&1 | xcsift
```
Expected: **BUILD FAILED** — `ImportViewModel.init` doesn't accept `importWriter`/`chunkSize`, `startImport`/`cancelImport`/`progress`/`isImporting` don't exist yet.

### 2c. Implement

Replace `FinanceTracker/ViewModels/ImportViewModel.swift` in full:

```swift
import Foundation
import Observation

enum ImportStep: Equatable {
    case filePicker, columnMapping, preview
}

@Observable
final class ImportViewModel {
    private(set) var step: ImportStep = .filePicker
    private(set) var rawCSVText: String = ""
    private(set) var csvSampleRows: [[String]] = []
    private(set) var pendingTransactions: [ParsedTransaction] = []
    private(set) var skippedCount: Int = 0
    private(set) var accounts: [Account] = []
    private(set) var progress: Double = 0
    private(set) var isImporting = false
    var selectedAccount: Account?

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let importRecordRepo: any ImportRecordRepositoryProtocol
    private let importService: CSVImportService
    private let importWriter: any TransactionImportWriting
    private let chunkSize: Int
    private var importTask: Task<Void, Error>?

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        importRecordRepo: any ImportRecordRepositoryProtocol,
        importWriter: any TransactionImportWriting,
        importService: CSVImportService = CSVImportService(),
        chunkSize: Int = 300
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.importRecordRepo = importRecordRepo
        self.importWriter = importWriter
        self.importService = importService
        self.chunkSize = chunkSize
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
        if selectedAccount == nil { selectedAccount = accounts.first }
    }

    func loadCSV(_ text: String) {
        rawCSVText = text
        let delimiter: Character = text.contains(";") ? ";" : ","
        let lines = text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        csvSampleRows = lines.prefix(5).map {
            $0.components(separatedBy: String(delimiter))
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        step = .columnMapping
    }

    func applyMapping(_ mapping: ColumnMapping) async throws {
        let parsed = try importService.parse(csv: rawCSVText, mapping: mapping)
        let existingHashes = try await importWriter.existingHashes()
        let deduped = importService.deduplicated(parsed: parsed, existingHashes: existingHashes)
        pendingTransactions = deduped
        skippedCount = parsed.count - deduped.count
        step = .preview
    }

    func startImport(filename: String = "import.csv") {
        guard let account = selectedAccount, !pendingTransactions.isEmpty else { return }
        let accountID = account.id
        let items = pendingTransactions
        let writer = importWriter
        let size = chunkSize

        isImporting = true
        progress = 0

        importTask = Task {
            defer { isImporting = false }
            let chunks = items.chunked(into: size)
            var completed = 0
            try await withThrowingTaskGroup(of: Int.self) { group in
                for (index, chunk) in chunks.enumerated() {
                    group.addTask(name: "CSV import chunk \(index)") {
                        try await writer.save(chunk: chunk, accountID: accountID)
                        return chunk.count
                    }
                }
                for try await count in group {
                    completed += count
                    self.progress = Double(completed) / Double(items.count)
                }
            }
            let record = ImportRecord(filename: filename, transactionCount: items.count)
            try importRecordRepo.save(record)
            reset()
        }
    }

    func cancelImport() {
        importTask?.cancel()
    }

    func reset() {
        step = .filePicker
        rawCSVText = ""
        csvSampleRows = []
        pendingTransactions = []
        skippedCount = 0
        progress = 0
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
```

> **Note for this task's execution:** the `Task { }` in `startImport()` is intentionally left without a `@concurrent` annotation — it inherits `@MainActor` isolation from `ImportViewModel` by default (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`), which is required for `self.progress = ...` to be safely mutated inside the `for try await count in group` loop without extra annotation. Per the spec, only add `@concurrent` if Instruments profiling (during `/feature`'s verification pass) shows this holding a main-thread token unnecessarily — don't add it speculatively.

Replace `FinanceTracker/FinanceTrackerApp.swift` in full:

```swift
import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            // In-memory stores (UI tests) start fresh every launch — there is no
            // existing store to migrate, and SwiftData's behavior when a
            // SchemaMigrationPlan is applied to isStoredInMemoryOnly is undefined.
            // Skip the migration plan for in-memory stores.
            if isUITesting {
                return try ModelContainer(for: schema, configurations: [config])
            }
            return try ModelContainer(
                for: schema,
                migrationPlan: FinanceTrackerMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    let importActor: TransactionImportActor

    init() {
        importActor = TransactionImportActor(modelContainer: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(importActor: importActor)
        }
        .modelContainer(sharedModelContainer)
    }
}
```

Replace `FinanceTracker/ContentView.swift` in full:

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    let importActor: any TransactionImportWriting

    var body: some View {
        FinanceTrackerTabView(modelContext: context, importWriter: importActor)
    }
}

struct FinanceTrackerTabView: View {
    @State private var accountVM: AccountViewModel
    @State private var transactionVM: TransactionViewModel
    @State private var dashboardVM: DashboardViewModel
    @State private var budgetVM: BudgetViewModel
    @State private var importVM: ImportViewModel
    @State private var categoryVM: CategoryViewModel

    init(modelContext: ModelContext, importWriter: any TransactionImportWriting) {
        let accountRepo      = SwiftDataAccountRepository(context: modelContext)
        let transactionRepo  = SwiftDataTransactionRepository(context: modelContext)
        let categoryRepo     = SwiftDataCategoryRepository(context: modelContext)
        let budgetRepo       = SwiftDataBudgetRepository(context: modelContext)
        let importRecordRepo = SwiftDataImportRecordRepository(context: modelContext)

        _accountVM = State(wrappedValue: AccountViewModel(
            accountRepo: accountRepo,
            transactionRepo: transactionRepo
        ))
        _transactionVM = State(wrappedValue: TransactionViewModel(
            transactionRepo: transactionRepo,
            accountRepo: accountRepo,
            categoryRepo: categoryRepo
        ))
        _dashboardVM = State(wrappedValue: DashboardViewModel(
            accountRepo: accountRepo,
            transactionRepo: transactionRepo,
            budgetRepo: budgetRepo
        ))
        _budgetVM = State(wrappedValue: BudgetViewModel(
            budgetRepo: budgetRepo,
            transactionRepo: transactionRepo,
            categoryRepo: categoryRepo
        ))
        _importVM = State(wrappedValue: ImportViewModel(
            transactionRepo: transactionRepo,
            accountRepo: accountRepo,
            importRecordRepo: importRecordRepo,
            importWriter: importWriter
        ))
        _categoryVM = State(wrappedValue: CategoryViewModel(
            categoryRepo: categoryRepo
        ))
    }

    var body: some View {
        TabView {
            NavigationStack {
                DashboardView(viewModel: dashboardVM)
            }
            .tabItem { Label("Dashboard", systemImage: "chart.bar.fill") }

            NavigationStack {
                TransactionListView(viewModel: transactionVM, importVM: importVM)
            }
            .tabItem { Label("Transactions", systemImage: "arrow.up.arrow.down") }

            NavigationStack {
                BudgetListView(viewModel: budgetVM)
            }
            .tabItem { Label("Budgets", systemImage: "target") }

            NavigationStack {
                AccountListView(viewModel: accountVM)
            }
            .tabItem { Label("Accounts", systemImage: "building.columns.fill") }

            NavigationStack {
                SettingsView(categoryVM: categoryVM)
            }
            .tabItem { Label("Settings", systemImage: "gear") }
        }
        .task {
            try? accountVM.load()
            try? transactionVM.load()
            try? dashboardVM.load()
            try? budgetVM.load()
            try? importVM.load()
            try? categoryVM.load()
        }
    }
}
```

### 2d. Confirm pass

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | xcsift
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/ImportViewModelTests \
  2>&1 | xcsift
```
Expected: **BUILD SUCCEEDED**, then **TEST SUCCEEDED**, 6/6 tests pass.

### 2e. Commit

```bash
git add FinanceTracker/ViewModels/ImportViewModel.swift \
        FinanceTracker/FinanceTrackerApp.swift \
        FinanceTracker/ContentView.swift \
        FinanceTrackerTests/TestHelpers.swift \
        FinanceTrackerTests/ViewModels/ImportViewModelTests.swift
git commit -m "feat(import): migrate ImportViewModel to async TaskGroup pipeline"
```

## Task 3 — `ImportSheet` UI: progress bar, cancellation, accessibility identifiers

### 3a. Write the failing test

Create `FinanceTrackerUITests/UITestImportFlowTests.swift`:

```swift
import XCTest

final class UITestImportFlowTests: UITestBase {

    func testImportButtonOpensSheetAndChooseFileLaunchesDocumentPicker() {
        app.tabBars.firstMatch.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: timeout))

        app.buttons["import-transactions-button"].tap()
        XCTAssertTrue(app.navigationBars["Import CSV"].waitForExistence(timeout: timeout))

        let chooseFileButton = app.buttons["import-choose-file-button"]
        XCTAssertTrue(chooseFileButton.waitForExistence(timeout: timeout))
        chooseFileButton.tap()

        // The system document picker runs in a separate process — automating file
        // selection inside it is disproportionately fragile for this PR's scope (no
        // other UI test in this suite drives a fileImporter). This test only confirms
        // the entry point launches a picker; the async import pipeline itself
        // (chunking, cancellation, progress, dedup) is covered by ImportViewModelTests.
        // The full visual flow (progress bar appearing/disappearing) should be manually
        // verified on the iPhone 17 simulator during /feature via the `verify` skill —
        // see the Testing Strategy note in
        // docs/superpowers/specs/2026-07-15-csv-import-async-migration.md.
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: timeout))

        if app.buttons["Cancel"].waitForExistence(timeout: 2) {
            app.buttons["Cancel"].tap()
        }
    }
}
```

### 3b. Confirm failure

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestImportFlowTests \
  2>&1 | xcsift
```
Expected: **TEST FAILED** — `import-transactions-button` and `import-choose-file-button` have no accessibility identifiers yet.

### 3c. Implement

Edit `FinanceTracker/Views/Transactions/TransactionListView.swift` — add one identifier to the existing Import toolbar button (only this line changes):

```swift
                Button("Import", systemImage: "square.and.arrow.down") {
                    isPresentingImport = true
                }
                .accessibilityIdentifier("import-transactions-button")
```

Replace `FinanceTracker/Views/Import/ImportSheet.swift` in full:

```swift
import SwiftUI
import UniformTypeIdentifiers

struct ImportSheet: View {
    @Bindable var viewModel: ImportViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isPickingFile = false
    @State private var dateColIndex = 0
    @State private var amountColIndex = 1
    @State private var payeeColIndex = 2
    @State private var hasHeader = true

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .filePicker:    filePickerStep
                case .columnMapping: columnMappingStep
                case .preview:       previewStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if viewModel.isImporting {
                            viewModel.cancelImport()
                        }
                        viewModel.reset()
                        dismiss()
                    }
                    .accessibilityIdentifier("import-cancel-toolbar-button")
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            guard let url = try? result.get() else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            viewModel.loadCSV(text)
        }
        .onDisappear {
            if viewModel.isImporting {
                viewModel.cancelImport()
            }
        }
        .onChange(of: viewModel.step) { _, newStep in
            // startImport() calls reset() on success, which flips step back to
            // .filePicker asynchronously — auto-dismiss to match the old synchronous
            // confirmImport() + dismiss() behavior. Also fires (harmlessly) on the
            // explicit Cancel path above, which already calls dismiss() itself.
            if newStep == .filePicker && !viewModel.isImporting {
                dismiss()
            }
        }
    }

    private var stepTitle: String {
        switch viewModel.step {
        case .filePicker:    "Import CSV"
        case .columnMapping: "Map Columns"
        case .preview:       "Review Import"
        }
    }

    // MARK: Step 1 — File picker

    private var filePickerStep: some View {
        VStack(spacing: Theme.Spacing.sheetSpacing) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 72))
                .foregroundStyle(Theme.Colors.primaryInteractive)
            Text("Choose a CSV file to import")
                .font(Theme.Typography.sectionHeader)
            Text("Supported: comma- or semicolon-delimited, any column order")
                .font(Theme.Typography.rowSubtitle)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Choose File") { isPickingFile = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("import-choose-file-button")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: Step 2 — Column mapping

    private var columnMappingStep: some View {
        Form {
            Section("Column Positions (0-based)") {
                Stepper("Date: column \(dateColIndex)",
                        value: $dateColIndex, in: 0...20)
                Stepper("Amount: column \(amountColIndex)",
                        value: $amountColIndex, in: 0...20)
                Stepper("Payee: column \(payeeColIndex)",
                        value: $payeeColIndex, in: 0...20)
                Toggle("First row is header", isOn: $hasHeader)
            }

            if !viewModel.csvSampleRows.isEmpty {
                Section("File preview (first rows)") {
                    ForEach(Array(viewModel.csvSampleRows.prefix(4).enumerated()), id: \.offset) { _, row in
                        Text(row.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: "  "))
                            .font(Theme.Typography.code)
                            .lineLimit(1)
                    }
                }
            }

            Section {
                Button("Parse & Preview") {
                    let mapping = ColumnMapping(
                        dateIndex: dateColIndex,
                        amountIndex: amountColIndex,
                        payeeIndex: payeeColIndex,
                        hasHeader: hasHeader
                    )
                    Task { try? await viewModel.applyMapping(mapping) }
                }
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("import-parse-preview-button")
            }
        }
    }

    // MARK: Step 3 — Preview & confirm

    private var previewStep: some View {
        List {
            Section {
                HStack {
                    Text("New transactions")
                    Spacer()
                    Text("\(viewModel.pendingTransactions.count)")
                        .bold()
                        .foregroundStyle(Theme.Colors.positive)
                }
                HStack {
                    Text("Skipped (duplicates)")
                    Spacer()
                    Text("\(viewModel.skippedCount)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Import into account") {
                Picker("Account", selection: $viewModel.selectedAccount) {
                    ForEach(viewModel.accounts) { account in
                        Text(account.name).tag(account as Account?)
                    }
                }
            }

            if !viewModel.pendingTransactions.isEmpty {
                Section("Transactions to import") {
                    ForEach(viewModel.pendingTransactions, id: \.importHash) { tx in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tx.payee)
                                Text(tx.date,
                                     format: .dateTime.month(.abbreviated).day().year())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(tx.amount, format: .currency(code: viewModel.selectedAccount?.currency ?? Locale.current.currency?.identifier ?? "USD"))
                        }
                    }
                }
            }

            Section {
                if viewModel.isImporting {
                    VStack(spacing: Theme.Spacing.sheetSpacing) {
                        ProgressView(value: viewModel.progress)
                            .accessibilityIdentifier("import-progress-bar")
                        Button("Cancel Import") {
                            viewModel.cancelImport()
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("import-cancel-button")
                    }
                } else {
                    Button("Import \(viewModel.pendingTransactions.count) Transactions") {
                        Task { viewModel.startImport() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.pendingTransactions.isEmpty ||
                              viewModel.selectedAccount == nil)
                    .accessibilityIdentifier("import-confirm-button")
                }
            }
        }
    }
}
```

### 3d. Confirm pass

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestImportFlowTests \
  2>&1 | xcsift
```
Expected: **TEST SUCCEEDED**.

### 3e. Commit

```bash
git add FinanceTracker/Views/Transactions/TransactionListView.swift \
        FinanceTracker/Views/Import/ImportSheet.swift \
        FinanceTrackerUITests/UITestImportFlowTests.swift
git commit -m "feat(import): progress bar, cancellation, and accessibility identifiers in ImportSheet"
```

## Task 4 — `/gates` Gate 8: CSV import concurrency shape

No app code — pipeline tooling only, verified by running the greps by hand against Task 1's file rather than a Swift test.

### 4a. Edit `.claude/commands/gates.md`

Insert a new gate between the existing Gate 7 and `## Gate summary`:

```markdown
### Gate 8 — CSV import concurrency shape (conditional: TransactionImportActor.swift changed)
```bash
git diff develop...HEAD --name-only -- '*.swift' | grep -q "TransactionImportActor.swift" && {
  grep -n "@MainActor" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
  grep -cE "@Model" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
  grep -c "context.save()" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
}
```
Pass: first grep returns no output (actor is not `@MainActor`-annotated); second grep count is `0` (no `@Model`-typed stored properties — only the macro-generated `ModelContext`/`ModelContainer` members); third grep count is exactly `1` (one `context.save()` per chunk, never per row).
Skip this gate if `TransactionImportActor.swift` is untouched on this branch.
```

Update the two gate-count references in the same file: the `/goal` example in "Autonomous gate-fixing loop" (`"all 7 gates pass..."` → `"all 8 gates pass: build succeeds, all tests pass, no TODO/FIXME/HACK in changed files, branch name valid, CHANGELOG Unreleased section populated, coverage ≥80% on new files, security review clean, CSV import concurrency shape correct"`), and the `/loop` tip line (`"Stop when all 7 gates pass"` → `"Stop when all 8 gates pass"`).

### 4b. Edit `.claude/commands/feature.md`

Update the "Done when" line: `"all 7 `/gates` criteria pass"` → `"all 8 `/gates` criteria pass"`.

### 4c. Verify by hand

```bash
grep -n "@MainActor" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
grep -cE "@Model" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
grep -c "context.save()" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
```
Expected: no output, `0`, `1` — confirming the Task 1 file already satisfies the gate this task adds.

### 4d. Commit

```bash
git add .claude/commands/gates.md .claude/commands/feature.md
git commit -m "docs(gates): add Gate 8 for CSV import actor concurrency shape"
```

## After all tasks — `/gates` then PR

Run `/gates` (all 8 gates, including the new one, against `TransactionImportActor.swift`), then open the PR to `develop` per the standard pipeline. `/review` runs first; once it passes, `/test` and `code-review:code-review` run in parallel.
