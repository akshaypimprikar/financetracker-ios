# Re-render Cleanup Pass Implementation Plan

**Goal:** Fix 5 confirmed re-render/redundant-work issues across the Budgets/Transactions/Accounts Views and ViewModels, all sourced from the same Instruments profiling session, in one PR.
**Architecture:** Views + ViewModels layer only. No Domain Service, Repository, or `@Model` changes. Task 1 (`TransactionViewModel.filteredTransactions` memoization) is the only task with real unit-testable behavior; Tasks 2-5 are View-only fixes with no business logic to unit test (per CLAUDE.md, Views contain no business logic) — each is verified by successful compilation + the full existing suite passing with zero regressions, plus manual verification, matching the spec's Testing Strategy.
**Tech Stack:** SwiftUI, `@Observable` (Observation framework), Swift Testing (`@Suite`/`@Test`/`#expect`).
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains FinanceTracker.xcodeproj)

---

## Task 1 — Memoize `TransactionViewModel.filteredTransactions`

**File:** `FinanceTracker/ViewModels/TransactionViewModel.swift`
**Test file:** `FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift`

### RED — write the failing tests first

Append to `FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift`, inside the `TransactionViewModelTests` struct, before the closing `}`:

```swift
    @Test func filteredTransactionsIsMemoizedAcrossRepeatedAccess() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 1)
    }

    @Test func filteredTransactionsCacheInvalidatesOnSearchTextChange() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: account))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        vm.searchText = "coffee"
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }

    @Test func filteredTransactionsCacheInvalidatesOnSelectedAccountChange() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let checking = Account(name: "Checking", type: .checking)
        ctx.insert(checking)
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Coffee",
                               type: .debit, account: checking))
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        vm.selectedAccount = checking
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }

    @Test func filteredTransactionsCacheInvalidatesOnReload() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        ctx.insert(account)
        try ctx.save()

        let vm = TransactionViewModel(
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            accountRepo: SwiftDataAccountRepository(context: ctx),
            categoryRepo: SwiftDataCategoryRepository(context: ctx)
        )
        try vm.load()

        _ = vm.filteredTransactions
        try vm.add(date: .now, amount: 50, payee: "Grocery", notes: nil,
                   type: .debit, account: account, toAccount: nil, category: nil)
        _ = vm.filteredTransactions

        #expect(vm.filterComputeCount == 2)
    }
```

Run to confirm failure — these reference `vm.filterComputeCount`, which does not exist yet, so this fails at **compile time** (expected — the API doesn't exist until the implementation step; this is a valid RED for TDD when adding new observable surface, same as any other "write the test against an API that doesn't exist yet" cycle):

```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/TransactionViewModelTests \
  2>&1 | grep -E "error:|BUILD FAILED"
```
Expected: `error: value of type 'TransactionViewModel' has no member 'filterComputeCount'`.

Commit RED:
```bash
git add FinanceTrackerTests/ViewModels/TransactionViewModelTests.swift
git commit -m "test: add filteredTransactions memoization tests (RED)"
```

### GREEN — implement

Replace the full contents of `FinanceTracker/ViewModels/TransactionViewModel.swift` with:

```swift
import Foundation
import Observation

@Observable
final class TransactionViewModel {
    private(set) var transactions: [Transaction] = [] {
        didSet { invalidateFilteredTransactionsCache() }
    }
    private(set) var accounts: [Account] = []
    private(set) var categories: [Category] = []
    var searchText: String = "" {
        didSet { invalidateFilteredTransactionsCache() }
    }
    var selectedAccount: Account? {
        didSet { invalidateFilteredTransactionsCache() }
    }

    private var cachedFilteredTransactions: [Transaction]?
    private(set) var filterComputeCount = 0

    private let transactionRepo: any TransactionRepositoryProtocol
    private let accountRepo: any AccountRepositoryProtocol
    private let categoryRepo: any CategoryRepositoryProtocol

    init(
        transactionRepo: any TransactionRepositoryProtocol,
        accountRepo: any AccountRepositoryProtocol,
        categoryRepo: any CategoryRepositoryProtocol
    ) {
        self.transactionRepo = transactionRepo
        self.accountRepo = accountRepo
        self.categoryRepo = categoryRepo
    }

    func load() throws {
        transactions = try transactionRepo.fetchAll()
        accounts = try accountRepo.fetchAll()
        categories = try categoryRepo.fetchAll()
    }

    var filteredTransactions: [Transaction] {
        if let cachedFilteredTransactions {
            return cachedFilteredTransactions
        }
        filterComputeCount += 1
        var result = transactions
        if !searchText.isEmpty {
            result = result.filter {
                $0.payee.localizedCaseInsensitiveContains(searchText)
            }
        }
        if let selectedAccount {
            result = result.filter { $0.account.id == selectedAccount.id }
        }
        let sorted = result.sorted { $0.date > $1.date }
        cachedFilteredTransactions = sorted
        return sorted
    }

    private func invalidateFilteredTransactionsCache() {
        cachedFilteredTransactions = nil
    }

    func add(
        date: Date,
        amount: Decimal,
        payee: String,
        notes: String?,
        type: TransactionType,
        account: Account,
        toAccount: Account?,
        category: Category?
    ) throws {
        let tx = Transaction(
            date: date, amount: amount, payee: payee, notes: notes,
            type: type, account: account, toAccount: toAccount, category: category
        )
        try transactionRepo.save(tx)
        transactions = try transactionRepo.fetchAll()
    }

    func delete(_ transaction: Transaction) throws {
        try transactionRepo.delete(transaction)
        transactions = try transactionRepo.fetchAll()
    }
}
```

Confirm pass:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/TransactionViewModelTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|BUILD"
```
Expected: all `TransactionViewModelTests` pass, including the 4 new tests and the 4 pre-existing ones (`loadFetchesAllTransactions`, `addTransactionPersistsAndRefreshes`, `searchTextFiltersPayee`, `selectedAccountFiltersTransactions`) unchanged.

Commit GREEN:
```bash
git add FinanceTracker/ViewModels/TransactionViewModel.swift
git commit -m "perf: memoize TransactionViewModel.filteredTransactions (GREEN)"
```

---

## Task 2 — Dedupe `AccountListView`'s duplicate `netWorth()` call

**File:** `FinanceTracker/Views/Accounts/AccountListView.swift`
**No test file** — View-only, no business logic to unit test (CLAUDE.md: "Views: no business logic"). `AccountViewModelTests`'s existing `netWorthExcludesArchivedAccounts` test already pins `netWorth()`'s behavior and needs no changes, since its signature and logic are untouched — only the View now calls it once instead of twice. Verify via compile + full suite pass + manual check that Net Worth still displays and colors correctly.

Replace lines 14-25 of `FinanceTracker/Views/Accounts/AccountListView.swift` (the `var body: some View {` opening through the closing of the Net Worth `Section`) — i.e. replace:

```swift
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Net Worth")
                    Spacer()
                    Text(viewModel.netWorth(),
                         format: .currency(code: viewModel.currency))
                    .bold()
                    .foregroundStyle(viewModel.netWorth() >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
                }
            }
```

with:

```swift
    var body: some View {
        let netWorth = viewModel.netWorth()
        List {
            Section {
                HStack {
                    Text("Net Worth")
                    Spacer()
                    Text(netWorth, format: .currency(code: viewModel.currency))
                        .bold()
                        .foregroundStyle(netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
                }
            }
```

Build to confirm it compiles (no test suite change for this task):
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Commit (single commit, no RED/GREEN split — no test exists for this task):
```bash
git add FinanceTracker/Views/Accounts/AccountListView.swift
git commit -m "perf: compute AccountListView net worth once per render"
```

---

## Task 3 — Debounce `BudgetListView`'s `.onChange(selectedMonth)`

**File:** `FinanceTracker/Views/Budgets/BudgetListView.swift`
**No test file** — View-only, timing-based behavior not meaningfully unit-testable (per spec's Testing Strategy). `BudgetViewModelTests` already covers `load()` correctness and needs no changes. Verify via compile + full suite pass + manual check that rapid month changes in the picker settle to correct, non-stale budget data.

Replace lines 1-20 of `FinanceTracker/Views/Budgets/BudgetListView.swift` (imports through the closing of the `DatePicker`'s `Section`) — i.e. replace:

```swift
import SwiftUI

struct BudgetListView: View {
    @Bindable var viewModel: BudgetViewModel
    @Bindable var categoryVM: CategoryViewModel
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
```

with:

```swift
import SwiftUI

struct BudgetListView: View {
    @Bindable var viewModel: BudgetViewModel
    @Bindable var categoryVM: CategoryViewModel
    @State private var isPresentingAdd = false
    @State private var loadTask: Task<Void, Never>?

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
                    loadTask?.cancel()
                    loadTask = Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        guard !Task.isCancelled else { return }
                        try? viewModel.load()
                    }
                }
            }
```

Build to confirm it compiles:
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Commit:
```bash
git add FinanceTracker/Views/Budgets/BudgetListView.swift
git commit -m "perf: debounce BudgetListView month-change reload"
```

---

## Task 4 — Drop unused `@Bindable` in `BudgetDetailView`

**File:** `FinanceTracker/Views/Budgets/BudgetDetailView.swift`
**No test file** — correctness/clarity cleanup, not a behavior change (per spec: `@Bindable` vs. plain `let` doesn't change `@Observable`'s tracking granularity). Verify via compile + full suite pass — a successful build confirms no `$viewModel.x` binding was actually in use, since those would fail to compile against a plain `let`.

In `FinanceTracker/Views/Budgets/BudgetDetailView.swift`, change line 7 from:
```swift
    @Bindable var viewModel: BudgetViewModel
```
to:
```swift
    let viewModel: BudgetViewModel
```

Build to confirm it compiles (this is also the functional check — if any `$viewModel` binding existed, this step would fail):
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Commit:
```bash
git add FinanceTracker/Views/Budgets/BudgetDetailView.swift
git commit -m "chore: drop unused @Bindable in BudgetDetailView"
```

---

## Task 5 — Drop unused `@Bindable` in `TransactionDetailView`

**File:** `FinanceTracker/Views/Transactions/TransactionDetailView.swift`
**No test file** — same rationale as Task 4.

In `FinanceTracker/Views/Transactions/TransactionDetailView.swift`, change line 5 from:
```swift
    @Bindable var viewModel: TransactionViewModel
```
to:
```swift
    let viewModel: TransactionViewModel
```

Build to confirm it compiles:
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | tail -5
```
Expected: `** BUILD SUCCEEDED **`.

Commit:
```bash
git add FinanceTracker/Views/Transactions/TransactionDetailView.swift
git commit -m "chore: drop unused @Bindable in TransactionDetailView"
```

---

## Final verification (after all 5 tasks)

Run the full test suite to confirm zero regressions across all 5 changes:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | grep -E "TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`.

Manual verification (per spec's Testing Strategy, for the 4 View-only tasks):
- Accounts tab: Net Worth displays correctly, color still reflects sign (green/default for positive, destructive-red for negative).
- Budgets tab: change the month picker several times in quick succession; confirm the budget list settles to the correct month's data with no stale/dropped state.
- Budgets tab: open a budget's detail screen, confirm Delete Budget still works (exercises `BudgetDetailView`'s now-plain `viewModel.delete(budget)` call).
- Transactions tab: open a transaction's detail screen, confirm Delete still works (exercises `TransactionDetailView`'s now-plain `viewModel.delete(transaction)` call).

## CHANGELOG

Append to the `## [Unreleased]` section of `CHANGELOG.md` under `### Fixed` (create the section if absent):
```
- **Re-render cleanup pass** — memoized `TransactionViewModel.filteredTransactions` (previously re-filtered/re-sorted on every access); `AccountListView` now computes `netWorth()` once per render instead of twice (each call does one repository fetch per account); `BudgetListView`'s month-change reload is now debounced (150ms); dropped unused `@Bindable` in `BudgetDetailView`/`TransactionDetailView` (no `$viewModel` bindings existed in either). All 5 fixes sourced from the same Instruments profiling session; see `docs/superpowers/specs/2026-08-16-re-render-cleanup-pass.md`.
```

## Done when
All 5 tasks committed (Task 1 as separate RED/GREEN commits, Tasks 2-5 as single commits each — see each task's rationale for why no test exists), full test suite passes, CHANGELOG updated, PR opened to `develop` via `/gates` → `/feature`'s normal flow.
