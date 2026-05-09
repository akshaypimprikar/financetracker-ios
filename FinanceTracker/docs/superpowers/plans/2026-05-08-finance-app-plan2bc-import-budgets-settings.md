# FinanceTracker — Plan 2b+2c: CSV Import + Budgets + Settings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the full 5-tab app by adding (1) CSV import flow with 3-step sheet and dedup, (2) Budgets tab with per-category monthly budget tracking, and (3) Settings tab with category management.

**Architecture:** Same MVVM + Repository pattern as Plan 2a. `ImportViewModel`, `BudgetViewModel`, and `CategoryViewModel` hold all state. Views are pure layout. New `ImportRecordRepositoryProtocol` + SwiftData implementation required for the audit log.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, `@Observable`, Apple Testing (`@Suite` / `@Test` / `#expect`), UniformTypeIdentifiers (for file picker).

**Branch:** `feature/plan-2bc-import-budgets-settings` (cut from `main`)

**All commands run from:** `/Users/akshaypimprikar/Desktop/FinanceTracker/FinanceTracker/` (the directory containing `FinanceTracker.xcodeproj`)

> **Simulator:** Always `iPhone 17` — iOS 26.4 only ships with iPhone 17.

> **File inclusion:** `PBXFileSystemSynchronizedRootGroup` — any `.swift` file placed inside `FinanceTracker/`, `FinanceTrackerTests/`, or `FinanceTrackerUITests/` compiles automatically. Never edit `project.pbxproj`.

---

## File Map

### Create

```
FinanceTracker/
├── Repositories/
│   ├── Protocols/
│   │   └── ImportRecordRepositoryProtocol.swift
│   └── SwiftData/
│       └── SwiftDataImportRecordRepository.swift
├── ViewModels/
│   ├── ImportViewModel.swift
│   ├── BudgetViewModel.swift
│   └── CategoryViewModel.swift
└── Views/
    ├── Import/
    │   └── ImportSheet.swift
    ├── Budgets/
    │   ├── BudgetListView.swift
    │   ├── BudgetDetailView.swift
    │   └── AddBudgetSheet.swift
    └── Settings/
        ├── SettingsView.swift
        └── AddCategorySheet.swift

FinanceTrackerTests/
└── ViewModels/
    ├── ImportViewModelTests.swift
    └── BudgetViewModelTests.swift
```

### Modify

```
FinanceTracker/ContentView.swift
    — add BudgetViewModel, ImportViewModel, CategoryViewModel; wire Budgets + Settings tabs; replace stub text

FinanceTracker/Views/Transactions/TransactionListView.swift
    — add importVM parameter + Import toolbar button + ImportSheet sheet
```

---

## Task 1: ImportRecordRepositoryProtocol + SwiftData implementation

**Files:**
- Create: `FinanceTracker/Repositories/Protocols/ImportRecordRepositoryProtocol.swift`
- Create: `FinanceTracker/Repositories/SwiftData/SwiftDataImportRecordRepository.swift`

- [ ] **Step 1: Create `FinanceTracker/Repositories/Protocols/ImportRecordRepositoryProtocol.swift`**

```swift
import Foundation

protocol ImportRecordRepositoryProtocol {
    func fetchAll() throws -> [ImportRecord]
    func save(_ record: ImportRecord) throws
}
```

- [ ] **Step 2: Create `FinanceTracker/Repositories/SwiftData/SwiftDataImportRecordRepository.swift`**

```swift
import Foundation
import SwiftData

struct SwiftDataImportRecordRepository: ImportRecordRepositoryProtocol {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() throws -> [ImportRecord] {
        let descriptor = FetchDescriptor<ImportRecord>(
            sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    func save(_ record: ImportRecord) throws {
        context.insert(record)
        try context.save()
    }
}
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/Repositories/Protocols/ImportRecordRepositoryProtocol.swift \
        FinanceTracker/Repositories/SwiftData/SwiftDataImportRecordRepository.swift
git commit -m "feat: add ImportRecordRepositoryProtocol and SwiftData implementation"
```

---

## Task 2: ImportViewModel

**Files:**
- Create: `FinanceTrackerTests/ViewModels/ImportViewModelTests.swift`
- Create: `FinanceTracker/ViewModels/ImportViewModel.swift`

The import flow has three steps:
1. **filePicker** — user selects a CSV file
2. **columnMapping** — user specifies which column index maps to date/amount/payee
3. **preview** — user sees new-vs-skipped counts, picks target account, confirms

- [ ] **Step 1: Create `FinanceTrackerTests/ViewModels/ImportViewModelTests.swift`**

```swift
import Testing
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
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)

        #expect(vm.step == .columnMapping)
        #expect(!vm.csvSampleRows.isEmpty)
    }

    @Test func applyMappingParsesTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,1200.00,Rent"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)

        #expect(vm.step == .preview)
        #expect(vm.pendingTransactions.count == 2)
        #expect(vm.skippedCount == 0)
    }

    @Test func applyMappingDeduplicatesExistingTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
        let hash = CSVImportService.importHash(
            date: date, amount: Decimal(string: "25.50")!, payee: "Coffee Shop"
        )
        let existing = Transaction(
            date: date, amount: Decimal(string: "25.50")!, payee: "Coffee Shop",
            type: .debit, importHash: hash, account: account
        )
        ctx.insert(existing)
        try ctx.save()

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop\n2026-05-02,50.00,Grocery"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)

        #expect(vm.pendingTransactions.count == 1)
        #expect(vm.skippedCount == 1)
        #expect(vm.pendingTransactions[0].payee == "Grocery")
    }

    @Test func confirmImportSavesTransactionsAndRecord() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = ImportViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            importRecordRepo: SwiftDataImportRecordRepository(context: ctx)
        )
        try vm.load()

        let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
        vm.loadCSV(csv)
        let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
        try vm.applyMapping(mapping)
        try vm.confirmImport(filename: "test.csv")

        let txs = try SwiftDataTransactionRepository(context: ctx).fetchAll()
        let records = try SwiftDataImportRecordRepository(context: ctx).fetchAll()

        #expect(txs.count == 1)
        #expect(txs[0].payee == "Coffee Shop")
        #expect(records.count == 1)
        #expect(records[0].transactionCount == 1)
        #expect(vm.step == .filePicker)
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/ImportViewModel \
  2>&1 | grep -E "error:|BUILD" | head -5
```

Expected: `error: cannot find type 'ImportViewModel'`

- [ ] **Step 3: Create `FinanceTracker/ViewModels/ImportViewModel.swift`**

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
    var selectedAccount: Account?

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let importRecordRepo: any ImportRecordRepositoryProtocol
    private let importService: CSVImportService

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        importRecordRepo: any ImportRecordRepositoryProtocol,
        importService: CSVImportService = CSVImportService()
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.importRecordRepo = importRecordRepo
        self.importService = importService
    }

    func load() throws {
        accounts = try accountRepo.fetchAll()
        if selectedAccount == nil { selectedAccount = accounts.first }
    }

    func loadCSV(_ text: String) {
        rawCSVText = text
        let delimiter: Character = text.contains(";") ? ";" : ","
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        csvSampleRows = lines.prefix(5).map {
            $0.components(separatedBy: String(delimiter))
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        step = .columnMapping
    }

    func applyMapping(_ mapping: ColumnMapping) throws {
        let parsed = try importService.parse(csv: rawCSVText, mapping: mapping)
        var existingHashes = Set<String>()
        for p in parsed {
            if try transactionRepo.existsWithHash(p.importHash) {
                existingHashes.insert(p.importHash)
            }
        }
        let deduped = importService.deduplicated(parsed: parsed, existingHashes: existingHashes)
        pendingTransactions = deduped
        skippedCount = parsed.count - deduped.count
        step = .preview
    }

    func confirmImport(filename: String = "import.csv") throws {
        guard let account = selectedAccount else { return }
        for parsed in pendingTransactions {
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account
            )
            try transactionRepo.save(tx)
        }
        let record = ImportRecord(
            filename: filename,
            transactionCount: pendingTransactions.count
        )
        try importRecordRepo.save(record)
        reset()
    }

    func reset() {
        step = .filePicker
        rawCSVText = ""
        csvSampleRows = []
        pendingTransactions = []
        skippedCount = 0
    }
}
```

- [ ] **Step 4: Run tests — expect 4 pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/ImportViewModel \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 4 tests passed

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/ViewModels/ImportViewModel.swift \
        FinanceTrackerTests/ViewModels/ImportViewModelTests.swift
git commit -m "feat: add ImportViewModel with 3-step state machine and tests"
```

---

## Task 3: ImportSheet (3-step UI)

**Files:**
- Create: `FinanceTracker/Views/Import/ImportSheet.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Import/ImportSheet.swift`**

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
                case .filePicker:   filePickerStep
                case .columnMapping: columnMappingStep
                case .preview:      previewStep
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.reset()
                        dismiss()
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText]
        ) { result in
            guard let url = try? result.get(),
                  url.startAccessingSecurityScopedResource(),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return }
            url.stopAccessingSecurityScopedResource()
            viewModel.loadCSV(text)
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
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 72))
                .foregroundStyle(.teal)
            Text("Choose a CSV file to import")
                .font(.headline)
            Text("Supported: comma- or semicolon-delimited, any column order")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Choose File") { isPickingFile = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
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
                            .font(.caption.monospaced())
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
                    try? viewModel.applyMapping(mapping)
                }
                .frame(maxWidth: .infinity)
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
                        .foregroundStyle(.green)
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
                            Text(tx.amount, format: .currency(code: "USD"))
                        }
                    }
                }
            }

            Section {
                Button("Import \(viewModel.pendingTransactions.count) Transactions") {
                    try? viewModel.confirmImport()
                    dismiss()
                }
                .frame(maxWidth: .infinity)
                .disabled(viewModel.pendingTransactions.isEmpty ||
                          viewModel.selectedAccount == nil)
            }
        }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add FinanceTracker/Views/Import/ImportSheet.swift
git commit -m "feat: add 3-step ImportSheet (file picker → column mapping → preview)"
```

---

## Task 4: Wire import button into TransactionListView

**Files:**
- Modify: `FinanceTracker/Views/Transactions/TransactionListView.swift`

- [ ] **Step 1: Open `FinanceTracker/Views/Transactions/TransactionListView.swift` and replace its content**

Add `importVM` parameter and an Import toolbar button alongside the existing Add button, and a second sheet modifier for `ImportSheet`.

```swift
import SwiftUI

struct TransactionListView: View {
    @Bindable var viewModel: TransactionViewModel
    @Bindable var importVM: ImportViewModel
    @State private var isPresentingAdd = false
    @State private var isPresentingImport = false

    var body: some View {
        List {
            if !viewModel.accounts.isEmpty {
                accountFilterPicker
            }

            ForEach(viewModel.filteredTransactions) { tx in
                NavigationLink {
                    TransactionDetailView(transaction: tx, viewModel: viewModel)
                } label: {
                    TransactionRow(transaction: tx)
                }
            }
            .onDelete { indexSet in
                let txs = viewModel.filteredTransactions
                for index in indexSet {
                    try? viewModel.delete(txs[index])
                }
            }
        }
        .searchable(text: $viewModel.searchText, prompt: "Search payee")
        .navigationTitle("Transactions")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") {
                    isPresentingImport = true
                }
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddTransactionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $isPresentingImport) {
            ImportSheet(viewModel: importVM)
                .onDisappear { try? viewModel.load() }
        }
        .onAppear { try? viewModel.load() }
    }

    private var accountFilterPicker: some View {
        Picker("Account", selection: $viewModel.selectedAccount) {
            Text("All accounts").tag(nil as Account?)
            ForEach(viewModel.accounts) { account in
                Text(account.name).tag(account as Account?)
            }
        }
        .pickerStyle(.menu)
    }
}
```

- [ ] **Step 2: Verify build — expect error for missing importVM argument at call site in ContentView**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | head -5
```

Expected: error about `TransactionListView` call site in `ContentView.swift` missing `importVM`. That's correct — we fix ContentView in Task 9.

- [ ] **Step 3: Commit**

```bash
git add FinanceTracker/Views/Transactions/TransactionListView.swift
git commit -m "feat: add Import button and ImportSheet to TransactionListView"
```

---

## Task 5: BudgetViewModel

**Files:**
- Create: `FinanceTrackerTests/ViewModels/BudgetViewModelTests.swift`
- Create: `FinanceTracker/ViewModels/BudgetViewModel.swift`

- [ ] **Step 1: Create `FinanceTrackerTests/ViewModels/BudgetViewModelTests.swift`**

```swift
import Testing
import SwiftData
@testable import FinanceTracker

@Suite("BudgetViewModel")
struct BudgetViewModelTests {

    func startOfMay2026() -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 1))!
    }

    @Test func loadFetchesBudgetsForSelectedMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 500, month: startOfMay2026(), category: category)
        ctx.insert(category); ctx.insert(budget)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.budgets.count == 1)
        #expect(vm.budgets[0].0.category.name == "Food")
    }

    @Test func addBudgetPersistsAndRefreshes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let category = Category(name: "Transport", type: .expense)
        ctx.insert(category)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()
        #expect(vm.budgets.isEmpty)

        try vm.add(category: category, monthlyLimit: 200)

        #expect(vm.budgets.count == 1)
        #expect(vm.budgets[0].0.monthlyLimit == 200)
    }

    @Test func progressReflectsSpending() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let category = Category(name: "Food", type: .expense)
        let budget = Budget(monthlyLimit: 200, month: startOfMay2026(), category: category)
        ctx.insert(account); ctx.insert(category); ctx.insert(budget)
        let txDate = Calendar.current.date(from: DateComponents(year: 2026, month: 5, day: 15))!
        ctx.insert(Transaction(date: txDate, amount: 80, payee: "Grocery",
                               type: .debit, account: account, category: category))
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.budgets[0].1.spent == 80)
        #expect(vm.budgets[0].1.remaining == 120)
        #expect(vm.budgets[0].1.isOverBudget == false)
    }

    @Test func unbudgetedCategoriesExcludesBudgetedOnes() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let food = Category(name: "Food", type: .expense)
        let transport = Category(name: "Transport", type: .expense)
        let budget = Budget(monthlyLimit: 200, month: startOfMay2026(), category: food)
        ctx.insert(food); ctx.insert(transport); ctx.insert(budget)
        try ctx.save()

        let vm = BudgetViewModel(
            budgetRepo: SwiftDataBudgetRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        vm.selectedMonth = startOfMay2026()
        try vm.load()

        #expect(vm.unbudgetedCategories.count == 1)
        #expect(vm.unbudgetedCategories[0].name == "Transport")
    }
}
```

- [ ] **Step 2: Run tests — expect BUILD ERROR**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/BudgetViewModel \
  2>&1 | grep -E "error:|BUILD" | head -5
```

Expected: `error: cannot find type 'BudgetViewModel'`

- [ ] **Step 3: Create `FinanceTracker/ViewModels/BudgetViewModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class BudgetViewModel {
    private(set) var budgets: [(Budget, BudgetProgress)] = []
    private(set) var categories: [Category] = []
    var selectedMonth: Date = {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: .now)) ?? .now
    }()

    private let budgetRepo: any BudgetRepositoryProtocol
    private let transactionRepo: any TransactionRepositoryProtocol
    private let categoryRepo: any CategoryRepositoryProtocol
    private let budgetCalcService: BudgetCalculationService

    init(
        budgetRepo: any BudgetRepositoryProtocol,
        transactionRepo: any TransactionRepositoryProtocol,
        categoryRepo: any CategoryRepositoryProtocol,
        budgetCalcService: BudgetCalculationService = BudgetCalculationService()
    ) {
        self.budgetRepo = budgetRepo
        self.transactionRepo = transactionRepo
        self.categoryRepo = categoryRepo
        self.budgetCalcService = budgetCalcService
    }

    func load() throws {
        categories = try categoryRepo.fetchAll()
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let end = cal.date(byAdding: .month, value: 1, to: start)!
        let allBudgets = try budgetRepo.fetchAll(for: selectedMonth)
        let allTx = try transactionRepo.fetchAll()

        budgets = allBudgets.map { budget in
            let txs = allTx.filter {
                $0.category?.id == budget.category.id &&
                $0.date >= start && $0.date < end
            }
            return (budget, budgetCalcService.progress(budget: budget, transactions: txs))
        }
    }

    func add(category: Category, monthlyLimit: Decimal) throws {
        let cal = Calendar.current
        let month = cal.date(from: cal.dateComponents([.year, .month], from: selectedMonth))!
        let budget = Budget(monthlyLimit: monthlyLimit, month: month, category: category)
        try budgetRepo.save(budget)
        try load()
    }

    func delete(_ budget: Budget) throws {
        try budgetRepo.delete(budget)
        try load()
    }

    var unbudgetedCategories: [Category] {
        let budgetedIDs = Set(budgets.map { $0.0.category.id })
        return categories.filter { !budgetedIDs.contains($0.id) }
    }
}
```

- [ ] **Step 4: Run tests — expect 4 pass**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerTests/BudgetViewModel \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```

Expected: 4 tests passed

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/ViewModels/BudgetViewModel.swift \
        FinanceTrackerTests/ViewModels/BudgetViewModelTests.swift
git commit -m "feat: add BudgetViewModel with month selection, progress, and tests"
```

---

## Task 6: BudgetListView + AddBudgetSheet

**Files:**
- Create: `FinanceTracker/Views/Budgets/BudgetListView.swift`
- Create: `FinanceTracker/Views/Budgets/AddBudgetSheet.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Budgets/BudgetListView.swift`**

```swift
import SwiftUI

struct BudgetListView: View {
    @Bindable var viewModel: BudgetViewModel
    @State private var isPresentingAdd = false

    var body: some View {
        List {
            Section {
                DatePicker(
                    "Month",
                    selection: $viewModel.selectedMonth,
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .onChange(of: viewModel.selectedMonth) {
                    try? viewModel.load()
                }
            }

            if viewModel.budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets",
                    systemImage: "target",
                    description: Text("Tap + to set a budget for a category")
                )
            } else {
                Section("This month") {
                    ForEach(viewModel.budgets, id: \.0.id) { budget, progress in
                        NavigationLink {
                            BudgetDetailView(budget: budget, progress: progress,
                                             viewModel: viewModel)
                        } label: {
                            BudgetRow(budget: budget, progress: progress)
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? viewModel.delete(viewModel.budgets[index].0)
                        }
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
                    .disabled(viewModel.unbudgetedCategories.isEmpty)
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddBudgetSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }
}

private struct BudgetRow: View {
    let budget: Budget
    let progress: BudgetProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(budget.category.name, systemImage: budget.category.icon)
                    .font(.subheadline.bold())
                Spacer()
                Text(progress.spent, format: .currency(code: "USD"))
                    .bold()
                    .foregroundStyle(progress.isOverBudget ? .red : .primary)
                Text("/ \(progress.limit.formatted(.currency(code: "USD")))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? .red : .accentColor)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Budgets/AddBudgetSheet.swift`**

```swift
import SwiftUI

struct AddBudgetSheet: View {
    @Bindable var viewModel: BudgetViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: Category?
    @State private var limitText = ""

    private var canAdd: Bool {
        selectedCategory != nil && Decimal(string: limitText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Select").tag(nil as Category?)
                        ForEach(viewModel.unbudgetedCategories) { cat in
                            Text(cat.name).tag(cat as Category?)
                        }
                    }
                    TextField("Monthly limit", text: $limitText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let cat = selectedCategory,
                              let limit = Decimal(string: limitText) else { return }
                        try? viewModel.add(category: cat, monthlyLimit: limit)
                        dismiss()
                    }
                    .disabled(!canAdd)
                }
            }
        }
        .onAppear {
            selectedCategory = viewModel.unbudgetedCategories.first
        }
    }
}
```

- [ ] **Step 3: Verify build (BudgetDetailView still missing)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | head -5
```

Expected: error about `BudgetDetailView` only (plus the ContentView call-site error from Task 4).

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/Views/Budgets/BudgetListView.swift \
        FinanceTracker/Views/Budgets/AddBudgetSheet.swift
git commit -m "feat: add BudgetListView with month picker and AddBudgetSheet"
```

---

## Task 7: BudgetDetailView

**Files:**
- Create: `FinanceTracker/Views/Budgets/BudgetDetailView.swift`

- [ ] **Step 1: Create `FinanceTracker/Views/Budgets/BudgetDetailView.swift`**

```swift
import SwiftUI

struct BudgetDetailView: View {
    let budget: Budget
    let progress: BudgetProgress
    @Bindable var viewModel: BudgetViewModel

    var body: some View {
        List {
            Section("Progress") {
                HStack {
                    Text("Spent")
                    Spacer()
                    Text(progress.spent, format: .currency(code: "USD"))
                        .bold()
                        .foregroundStyle(progress.isOverBudget ? .red : .primary)
                }
                HStack {
                    Text("Limit")
                    Spacer()
                    Text(progress.limit, format: .currency(code: "USD"))
                }
                HStack {
                    Text("Remaining")
                    Spacer()
                    Text(progress.remaining, format: .currency(code: "USD"))
                        .foregroundStyle(progress.remaining < 0 ? .red : .green)
                }
                ProgressView(value: min(progress.percentUsed, 1.0))
                    .tint(progress.isOverBudget ? .red : .accentColor)
                    .padding(.vertical, 4)
            }

            Section("Category") {
                Label(budget.category.name, systemImage: budget.category.icon)
                LabeledContent("Type", value: budget.category.type.rawValue.capitalized)
            }
        }
        .navigationTitle(budget.category.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Delete Budget", role: .destructive) {
                    try? viewModel.delete(budget)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Verify build (only ContentView call-site errors remain)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | grep -v "ContentView" | head -5
```

Expected: no errors other than `ContentView` call-site issues.

- [ ] **Step 3: Commit**

```bash
git add FinanceTracker/Views/Budgets/BudgetDetailView.swift
git commit -m "feat: add BudgetDetailView with progress summary and delete action"
```

---

## Task 8: CategoryViewModel + SettingsView + AddCategorySheet

**Files:**
- Create: `FinanceTracker/ViewModels/CategoryViewModel.swift`
- Create: `FinanceTracker/Views/Settings/SettingsView.swift`
- Create: `FinanceTracker/Views/Settings/AddCategorySheet.swift`

- [ ] **Step 1: Create `FinanceTracker/ViewModels/CategoryViewModel.swift`**

```swift
import Foundation
import Observation

@Observable
final class CategoryViewModel {
    private(set) var categories: [Category] = []

    private let categoryRepo: any CategoryRepositoryProtocol

    init(categoryRepo: any CategoryRepositoryProtocol) {
        self.categoryRepo = categoryRepo
    }

    func load() throws {
        categories = try categoryRepo.fetchAll()
    }

    func add(name: String, icon: String, colorHex: String, type: CategoryType) throws {
        let category = Category(name: name, icon: icon, colorHex: colorHex, type: type)
        try categoryRepo.save(category)
        try load()
    }

    func delete(_ category: Category) throws {
        try categoryRepo.delete(category)
        try load()
    }
}
```

- [ ] **Step 2: Create `FinanceTracker/Views/Settings/SettingsView.swift`**

```swift
import SwiftUI

struct SettingsView: View {
    @Bindable var categoryVM: CategoryViewModel
    @State private var isPresentingAdd = false

    private var expenseCategories: [Category] {
        categoryVM.categories.filter { $0.type == .expense }
    }
    private var incomeCategories: [Category] {
        categoryVM.categories.filter { $0.type == .income }
    }

    var body: some View {
        List {
            if !expenseCategories.isEmpty {
                Section("Expense Categories") {
                    ForEach(expenseCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? categoryVM.delete(expenseCategories[index])
                        }
                    }
                }
            }

            if !incomeCategories.isEmpty {
                Section("Income Categories") {
                    ForEach(incomeCategories) { cat in
                        Label(cat.name, systemImage: cat.icon)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            try? categoryVM.delete(incomeCategories[index])
                        }
                    }
                }
            }

            if categoryVM.categories.isEmpty {
                ContentUnavailableView(
                    "No Categories",
                    systemImage: "tag",
                    description: Text("Tap + to add a category")
                )
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddCategorySheet(categoryVM: categoryVM)
        }
        .onAppear { try? categoryVM.load() }
    }
}
```

- [ ] **Step 3: Create `FinanceTracker/Views/Settings/AddCategorySheet.swift`**

```swift
import SwiftUI

struct AddCategorySheet: View {
    @Bindable var categoryVM: CategoryViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = CategoryType.expense
    @State private var icon = "tag.fill"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(CategoryType.allCases, id: \.self) { t in
                            Text(t.rawValue.capitalized).tag(t)
                        }
                    }
                    TextField("Icon (SF Symbol name)", text: $icon)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        try? categoryVM.add(name: name, icon: icon,
                                            colorHex: "#888888", type: type)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
```

- [ ] **Step 4: Verify build (only ContentView call-site errors remain)**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep "error:" | grep -v "ContentView" | head -5
```

Expected: no errors outside ContentView.

- [ ] **Step 5: Commit**

```bash
git add FinanceTracker/ViewModels/CategoryViewModel.swift \
        FinanceTracker/Views/Settings/SettingsView.swift \
        FinanceTracker/Views/Settings/AddCategorySheet.swift
git commit -m "feat: add CategoryViewModel, SettingsView, and AddCategorySheet"
```

---

## Task 9: Wire everything into ContentView

**Files:**
- Modify: `FinanceTracker/ContentView.swift`

- [ ] **Step 1: Replace the entire content of `FinanceTracker/ContentView.swift`**

```swift
import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context

    var body: some View {
        FinanceTrackerTabView(modelContext: context)
    }
}

struct FinanceTrackerTabView: View {
    @State private var accountVM: AccountViewModel
    @State private var transactionVM: TransactionViewModel
    @State private var dashboardVM: DashboardViewModel
    @State private var budgetVM: BudgetViewModel
    @State private var importVM: ImportViewModel
    @State private var categoryVM: CategoryViewModel

    init(modelContext: ModelContext) {
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
            importRecordRepo: importRecordRepo
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

- [ ] **Step 2: Verify build succeeds**

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Run full test suite**

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add FinanceTracker/ContentView.swift
git commit -m "feat: wire BudgetViewModel, ImportViewModel, CategoryViewModel into FinanceTrackerTabView"
```

---

## Final Checklist

- [ ] `ImportRecordRepositoryProtocol` + `SwiftDataImportRecordRepository` compile
- [ ] `ImportViewModel` — 4 tests passing (loadCSV, applyMapping, dedup, confirmImport)
- [ ] `ImportSheet` — 3-step sheet builds and presents from TransactionListView
- [ ] `BudgetViewModel` — 4 tests passing (load, add, progress, unbudgeted)
- [ ] `BudgetListView` shows budgets with progress bars, month picker, add + delete
- [ ] `AddBudgetSheet` only shows categories not yet budgeted this month
- [ ] `BudgetDetailView` shows progress breakdown + delete action
- [ ] `CategoryViewModel` wraps categoryRepo with load/add/delete
- [ ] `SettingsView` groups expense/income categories, allows add + swipe-to-delete
- [ ] `AddCategorySheet` saves new category via CategoryViewModel
- [ ] `ContentView` wires all 6 ViewModels from a single ModelContext
- [ ] All 5 tabs functional (no stub text remaining)
- [ ] Full `xcodebuild test` suite green
- [ ] No `Double` for money in any new code
- [ ] No business logic in any View file

---

## What comes next

**Plan 3 — Multi-Agent Workflow:** Claude Code command files (`.claude/commands/spec.md`, `plan.md`, `feature.md`, `test.md`, `review.md`, `bugfix.md`, `release.md`) and updated `CLAUDE.md` with architecture enforcement rules for agents.
