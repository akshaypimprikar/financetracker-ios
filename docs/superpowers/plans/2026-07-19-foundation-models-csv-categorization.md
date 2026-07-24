# Foundation Models Spike — CSV Payee→Category Suggestion Implementation Plan

**Goal:** During CSV import preview, suggest a category per unique payee via on-device `FoundationModels` inference, let the user accept/override it through a chip + `Menu`, and persist the choice onto the imported `Transaction`.
**Architecture:** New `CategorySuggesting` Domain Service protocol (zero SwiftData imports) + `FoundationModelsCategorySuggester` adapter, called once per unique payee from `ImportViewModel.loadSuggestions()`. Accepted category flows through a new `ParsedTransaction.categoryID` field into `TransactionImportActor.save`, which resolves it to a `Category` via a cached private lookup (mirrors the existing `resolveAccount` pattern) and attaches it to each new `Transaction`.
**Tech Stack:** SwiftUI, SwiftData, `FoundationModels` (`SystemLanguageModel`, `@Generable`, `@Guide`), Swift Testing.
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains FinanceTracker.xcodeproj)

**Source documents:**
- Spec: `docs/superpowers/specs/2026-07-19-foundation-models-csv-categorization.md`
- Owner sign-off + design tokens: `.claude/context/decisions.md` (2026-07-21 entry), `FinanceTracker/Theme/Chips.swift`, `docs/design-system.md` § Suggestion Chips

**Design decisions this plan makes that weren't explicit in the spec** (small, implementation-level, consistent with everything already approved — flagged here rather than silently invented):
1. **`loadSuggestions()` is a separate, explicitly-awaited method — not auto-triggered inside `applyMapping()`.** The View's "Parse & Preview" button calls both in sequence. This keeps every existing `ImportViewModelTests` call site that only calls `applyMapping()` completely unaffected (no accidental real-`FoundationModelsCategorySuggester` invocation in unrelated tests), and keeps suggestion-loading independently testable/awaitable.
2. **"Accept" and "override" are the same interaction.** The chip is always wrapped in one `Menu` populated from `viewModel.categories`. Tapping the suggested name inside that menu *is* accepting it — there's no separate accept affordance. This matches the spec's own wording ("a way to override it inline, e.g. a Menu") and avoids inventing a second interaction with no design token.
3. **Chip visual state: sparkle (unconfirmed) vs. plain (confirmed).** While `tx.categoryID == nil`, the chip shows the sparkle glyph at the confidence opacity from `Theme.Chips` plus `suggestion.categoryName` (Option A styling, already approved). Once the user has picked anything via the menu (`tx.categoryID != nil`), the chip drops the sparkle and shows the resolved category's name — since it's no longer "the model's guess," it's the user's confirmed choice. No new token needed: this reuses the same capsule/background/foreground, just conditionally omits the icon.
4. **Confidence→opacity mapping lives in the View, not the Domain Service.** `CategorySuggesting`/`CategorySuggestion` stay UI-agnostic (no `Theme` import) — `ImportSheet.swift` does the `Confidence` → `Theme.Chips.confidenceHigh/Medium/Low` switch itself. Keeps the Domain Service testable without SwiftUI and matches the zero-SwiftData-import rule's spirit of layer independence.

---

## Task 1 — `ParsedTransaction.categoryID` field

**File:** `FinanceTracker/Services/CSVImportService.swift`

Change:
```swift
struct ParsedTransaction: Sendable {
    let date: Date
    let amount: Decimal
    let payee: String
    let importHash: String
    var categoryID: UUID? = nil   // NEW — mutable, defaulted; never affects importHash
}
```
Nothing else in this file changes. Every existing `ParsedTransaction(date:amount:payee:importHash:)` call site (in `CSVImportServiceTests.swift`, `TransactionImportActorTests.swift`, and `CSVImportService.parse` itself) keeps compiling unchanged because the new field is defaulted.

**TDD:**
1. Add to `FinanceTrackerTests/Services/CSVImportServiceTests.swift`:
```swift
@Test func parsedTransactionDefaultsCategoryIDToNil() throws {
    let csv = "date,amount,payee\n2026-05-01,25.50,Coffee Shop"
    let mapping = ColumnMapping(dateIndex: 0, amountIndex: 1, payeeIndex: 2, hasHeader: true)
    let results = try CSVImportService().parse(csv: csv, mapping: mapping)
    #expect(results[0].categoryID == nil)
}

@Test func categoryIDDoesNotAffectImportHash() {
    let date = Date(timeIntervalSince1970: 1_000_000)
    var tx = ParsedTransaction(date: date, amount: 25, payee: "Coffee", importHash: CSVImportService.importHash(date: date, amount: 25, payee: "Coffee"))
    let hashBefore = tx.importHash
    tx.categoryID = UUID()
    #expect(tx.importHash == hashBefore)
}
```
2. Run: `xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/CSVImportServiceTests` — confirm both new tests fail to compile/fail (field doesn't exist yet).
3. Apply the change above.
4. Re-run the same command — expect `** TEST SUCCEEDED **`, all `CSVImportServiceTests` (now 9 tests) passing.
5. Commit: `git add FinanceTracker/Services/CSVImportService.swift FinanceTrackerTests/Services/CSVImportServiceTests.swift && git commit -m "feat(import): add optional categoryID field to ParsedTransaction"`

---

## Task 2 — `CategorySuggesting` protocol + `CategorySuggestion` types

**File (new):** `FinanceTracker/Services/CategorySuggesting.swift`
```swift
import Foundation
import FoundationModels

/// Domain Service protocol — zero SwiftData imports. `Category` is referenced as a
/// plain type here, matching the existing BudgetCalculationService precedent; @Model
/// classes don't require importing SwiftData to be referenced by name.
protocol CategorySuggesting: Sendable {
    /// Backed by SystemLanguageModel.default.availability == .available.
    /// Checked once per import session (preview step), not per row.
    var isAvailable: Bool { get }

    /// Suggests a category for one payee from the given candidates.
    /// Returns nil if unavailable, if the model errors, or if its chosen
    /// categoryName doesn't case-insensitively match any candidate name
    /// (fails safe — no suggestion is always a valid outcome).
    func suggestCategory(payee: String, candidates: [Category]) async -> CategorySuggestion?
}

@Generable
struct CategorySuggestion: Sendable {
    @Guide(description: "The single best-matching category name from the list of existing category names provided in the prompt. Must be copied exactly from that list, character-for-character, or the literal string \"Uncategorized\" if none plausibly fit.")
    let categoryName: String

    @Guide(description: "Confidence that this suggestion is correct")
    let confidence: Confidence

    @Generable
    enum Confidence: String, Sendable {
        case high, medium, low
    }
}
```

No test file for this task — it's declarations only (protocol + `@Generable` structs, no logic to unit test), consistent with the spec's Testing Strategy: "Unit (Domain Service): none possible against the real `FoundationModelsCategorySuggester` in CI." `ImportViewModel`'s tests (Task 5) exercise this protocol via a fake.

Verify it compiles standalone and satisfies Gate 9 (no `import SwiftData` in this file):
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
grep -c "^import SwiftData" FinanceTracker/Services/CategorySuggesting.swift   # expect: 0
```
Commit: `git add FinanceTracker/Services/CategorySuggesting.swift && git commit -m "feat(import): add CategorySuggesting protocol and CategorySuggestion @Generable type"`

---

## Task 3 — `FoundationModelsCategorySuggester` adapter

**File (new):** `FinanceTracker/Services/FoundationModelsCategorySuggester.swift`
```swift
import Foundation
import FoundationModels

/// The one concrete CategorySuggesting implementation the app ships. Not itself
/// unit-testable in CI — requires live Apple Intelligence-eligible hardware or an
/// Apple Intelligence-enabled host Mac's Simulator (see decisions.md 2026-07-21).
/// ImportViewModelTests exercises the ViewModel against FakeCategorySuggesting instead.
struct FoundationModelsCategorySuggester: CategorySuggesting {
    var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    func suggestCategory(payee: String, candidates: [Category]) async -> CategorySuggestion? {
        guard isAvailable, !candidates.isEmpty else { return nil }

        let categoryNames = candidates.map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(model: SystemLanguageModel.default) {
            "You categorize personal finance transactions by payee name. Always pick from the exact category names given, or say Uncategorized if none fit."
        }

        let prompt = """
        Payee: \(payee)
        Existing categories: \(categoryNames)

        Suggest the single best-matching category for this payee from the list above.
        """

        guard let response = try? await session.respond(to: prompt, generating: CategorySuggestion.self) else {
            return nil
        }

        let suggestion = response.content
        guard candidates.contains(where: {
            $0.name.caseInsensitiveCompare(suggestion.categoryName) == .orderedSame
        }) else {
            return nil
        }
        return suggestion
    }
}
```

**Note for whoever implements this task:** `LanguageModelSession`'s exact initializer/`respond` argument labels are the one part of this plan not verified against Xcode's live API surface (the framework was very new at spec time). If the compiler rejects the exact call shown, the structural pattern — build a session with an explicit `SystemLanguageModel()`/`.default`, call `respond(to:generating:)`, read `.content` — is what must be preserved; adjust argument labels to match, don't change the explicit-model/no-swappable-provider decision itself.

No CI-runnable unit test (per Testing Strategy). Verify it compiles and satisfies Gate 9:
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
grep -c "^import SwiftData" FinanceTracker/Services/FoundationModelsCategorySuggester.swift   # expect: 0
```
Commit: `git add FinanceTracker/Services/FoundationModelsCategorySuggester.swift && git commit -m "feat(import): add FoundationModelsCategorySuggester adapter"`

---

## Task 4 — `FakeCategorySuggesting` test double

**File:** `FinanceTrackerTests/TestHelpers.swift` — add alongside `FakeTransactionImportWriting`:
```swift
actor FakeCategorySuggesting: CategorySuggesting {
    nonisolated let isAvailable: Bool
    private(set) var suggestCallCount = 0
    private var suggestionsByPayee: [String: CategorySuggestion]

    init(isAvailable: Bool = true, suggestionsByPayee: [String: CategorySuggestion] = [:]) {
        self.isAvailable = isAvailable
        self.suggestionsByPayee = suggestionsByPayee
    }

    func suggestCategory(payee: String, candidates: [Category]) async -> CategorySuggestion? {
        suggestCallCount += 1
        return suggestionsByPayee[payee]
    }
}
```
No standalone test — this fixture is exercised by Task 5's `ImportViewModelTests` additions. Verify it compiles:
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```
Commit: `git add FinanceTrackerTests/TestHelpers.swift && git commit -m "test(import): add FakeCategorySuggesting fixture"`

---

## Task 5 — Wire `CategorySuggesting` + `CategoryRepositoryProtocol` into `ImportViewModel`

**File:** `FinanceTracker/ViewModels/ImportViewModel.swift`

Add two new stored dependencies, two new published properties, and two new methods:
```swift
private(set) var categories: [Category] = []
private(set) var suggestions: [String: CategorySuggestion] = [:]   // keyed by payee

private let categoryRepo: any CategoryRepositoryProtocol
private let categorySuggester: any CategorySuggesting
```
Update `init`:
```swift
init(
    accountRepo: any AccountRepositoryProtocol,
    importRecordRepo: any ImportRecordRepositoryProtocol,
    importWriter: any TransactionImportWriting,
    categoryRepo: any CategoryRepositoryProtocol,
    categorySuggester: any CategorySuggesting = FoundationModelsCategorySuggester(),
    importService: CSVImportService = CSVImportService(),
    chunkSize: Int = 300
) {
    self.accountRepo = accountRepo
    self.importRecordRepo = importRecordRepo
    self.importWriter = importWriter
    self.categoryRepo = categoryRepo
    self.categorySuggester = categorySuggester
    self.importService = importService
    self.chunkSize = chunkSize
}
```
`categorySuggester` is defaulted (mirrors the existing `importService: CSVImportService = CSVImportService()` precedent in this same initializer) — most tests never touch suggestions and don't need to inject a fake. `categoryRepo` is **not** defaulted, matching `accountRepo`/`importRecordRepo`/`importWriter`, all required.

Update `load()`:
```swift
func load() throws {
    accounts = try accountRepo.fetchAll()
    if selectedAccount == nil { selectedAccount = accounts.first }
    categories = try categoryRepo.fetchAll()
}
```
Add two new methods (place after `applyMapping`):
```swift
func loadSuggestions() async {
    guard categorySuggester.isAvailable, !categories.isEmpty else { return }
    let uniquePayees = Set(pendingTransactions.map(\.payee))
    for payee in uniquePayees {
        if let suggestion = await categorySuggester.suggestCategory(payee: payee, candidates: categories) {
            suggestions[payee] = suggestion
        }
    }
}

func setCategory(categoryID: UUID, forPayee payee: String) {
    for index in pendingTransactions.indices where pendingTransactions[index].payee == payee {
        pendingTransactions[index].categoryID = categoryID
    }
}
```

**Update every existing `ImportViewModel(...)` call site** in `FinanceTrackerTests/ViewModels/ImportViewModelTests.swift` (10 sites) to add `categoryRepo: SwiftDataCategoryRepository(context: ctx)` as a new argument — e.g.:
```swift
let vm = ImportViewModel(
    accountRepo: SwiftDataAccountRepository(context: ctx),
    importRecordRepo: SwiftDataImportRecordRepository(context: ctx),
    importWriter: FakeTransactionImportWriting(),
    categoryRepo: SwiftDataCategoryRepository(context: ctx)
)
```
Apply this same one-line addition to all 10 existing `ImportViewModel(` constructions in that file (every test currently listed: `loadCSVAdvancesToColumnMapping`, `applyMappingParsesTransactions`, `applyMappingDeduplicatesAgainstExistingHashes`, `startImportChunksAndReportsCompletionProgress`, `startImportIgnoresSecondCallWhileFirstIsInFlight`, `cancelImportClearsPendingTransactionsToPreventStaleRetry`, `staleTaskCompletionDoesNotClobberNewerSession`, `startImportDoesNotWriteImportRecordWhenNoChunkSucceeds`, `startImportWritesPartialAuditRecordWhenSomeChunksSucceedBeforeFailure`, `resetClearsImportFailure`). The `startImportReportsRecordSaveFailureSeparatelyFromChunkFailure` test's `ImportViewModel(...)` call gets the same addition too.

**TDD — add new tests to the same file:**
```swift
@Test func loadSuggestionsPopulatesOneSuggestionPerUniquePayee() async throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let coffee = Category(name: "Coffee", type: .expense)
    let shopping = Category(name: "Shopping", type: .expense)
    ctx.insert(coffee)
    ctx.insert(shopping)
    try ctx.save()

    let fake = FakeCategorySuggesting(suggestionsByPayee: [
        "Starbucks": CategorySuggestion(categoryName: "Coffee", confidence: .high),
        "Amazon": CategorySuggestion(categoryName: "Shopping", confidence: .medium),
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
    #expect(vm.suggestions["Starbucks"]?.categoryName == "Coffee")
    #expect(vm.suggestions["Amazon"]?.categoryName == "Shopping")
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
```

Run:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/ImportViewModelTests
```
Expect this to fail to compile first (new params/methods don't exist), then apply the `ImportViewModel.swift` change and all 10 call-site updates, then re-run — expect `** TEST SUCCEEDED **`, all `ImportViewModelTests` (now 13 tests) passing.

Commit: `git add FinanceTracker/ViewModels/ImportViewModel.swift FinanceTrackerTests/ViewModels/ImportViewModelTests.swift && git commit -m "feat(import): wire CategorySuggesting into ImportViewModel — loadSuggestions, setCategory"`

---

## Task 6 — Attach resolved category in `TransactionImportActor.save`

**File:** `FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift`

```swift
import Foundation
import SwiftData

@ModelActor
actor TransactionImportActor: TransactionImportWriting {
    private var cachedAccount: (id: UUID, account: Account)?
    private var cachedCategories: [UUID: Category] = [:]

    func existingHashes() async throws -> Set<String> {
        var descriptor = FetchDescriptor<Transaction>()
        descriptor.propertiesToFetch = [\.importHash]
        let all = try modelContext.fetch(descriptor)
        return Set(all.compactMap(\.importHash))
    }

    func save(chunk: [ParsedTransaction], accountID: UUID) async throws {
        try Task.checkCancellation()
        let account = try resolveAccount(id: accountID)
        for parsed in chunk {
            let category = parsed.categoryID.flatMap { resolveCategory(id: $0) }
            let tx = Transaction(
                date: parsed.date,
                amount: parsed.amount,
                payee: parsed.payee,
                type: .debit,
                importHash: parsed.importHash,
                account: account,
                category: category
            )
            modelContext.insert(tx)
        }
        try modelContext.save()   // ONE save() per chunk, never per row — unchanged
    }

    private func resolveAccount(id: UUID) throws -> Account {
        if let cachedAccount, cachedAccount.id == id {
            return cachedAccount.account
        }
        var descriptor = FetchDescriptor<Account>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let account = try modelContext.fetch(descriptor).first else {
            throw TransactionImportError.accountNotFound
        }
        cachedAccount = (id, account)
        return account
    }

    /// Mirrors resolveAccount's cache pattern, but never throws — a category is
    /// optional on Transaction, so a stale/missing categoryID (e.g. deleted between
    /// preview and import) degrades to an uncategorized transaction rather than
    /// failing the whole chunk. Stays private — never crosses the actor's public
    /// boundary, so this doesn't violate Gate 8's "no @Model type crossing the
    /// actor's public boundary" check, identical to how cachedAccount already works.
    private func resolveCategory(id: UUID) -> Category? {
        if let cached = cachedCategories[id] {
            return cached
        }
        var descriptor = FetchDescriptor<Category>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let category = try? modelContext.fetch(descriptor).first else {
            return nil
        }
        cachedCategories[id] = category
        return category
    }
}
```

**TDD — add to `FinanceTrackerTests/Repositories/TransactionImportActorTests.swift`:**
```swift
@Test func saveAttachesCategoryWhenCategoryIDResolves() async throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let account = Account(name: "Checking", type: .checking)
    let category = Category(name: "Coffee", type: .expense)
    ctx.insert(account)
    ctx.insert(category)
    try ctx.save()

    let actor = TransactionImportActor(modelContainer: container)
    let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1", categoryID: category.id)]
    try await actor.save(chunk: chunk, accountID: account.id)

    let saved = try ctx.fetch(FetchDescriptor<Transaction>())
    #expect(saved.count == 1)
    #expect(saved[0].category?.id == category.id)
}

@Test func saveLeavesCategoryNilWhenCategoryIDIsNil() async throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let account = Account(name: "Checking", type: .checking)
    ctx.insert(account)
    try ctx.save()

    let actor = TransactionImportActor(modelContainer: container)
    let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1")]   // categoryID defaults nil
    try await actor.save(chunk: chunk, accountID: account.id)

    let saved = try ctx.fetch(FetchDescriptor<Transaction>())
    #expect(saved[0].category == nil)
}

@Test func saveLeavesCategoryNilWhenCategoryIDDoesNotResolve() async throws {
    let container = try makeContainer()
    let ctx = ModelContext(container)
    let account = Account(name: "Checking", type: .checking)
    ctx.insert(account)
    try ctx.save()

    let actor = TransactionImportActor(modelContainer: container)
    let chunk = [ParsedTransaction(date: .now, amount: 6.40, payee: "Starbucks", importHash: "h1", categoryID: UUID())]   // unresolvable ID
    try await actor.save(chunk: chunk, accountID: account.id)   // must not throw

    let saved = try ctx.fetch(FetchDescriptor<Transaction>())
    #expect(saved.count == 1)
    #expect(saved[0].category == nil)   // fails safe, not a hard failure
}
```

Run:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FinanceTrackerTests/TransactionImportActorTests
```
Confirm failure first (new `categoryID:` init arg + `.category` assertions don't exist against old behavior), apply the change, re-run — expect `** TEST SUCCEEDED **`, all `TransactionImportActorTests` (now 7 tests) passing.

Also re-run Gate 8's own check to confirm this task didn't regress it:
```bash
git diff develop...HEAD --name-only -- '*.swift' | grep -q "TransactionImportActor.swift" && grep -n "@MainActor" FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift
```
Expect: no `@MainActor` match (empty output past the grep pipe's first clause).

Commit: `git add FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift FinanceTrackerTests/Repositories/TransactionImportActorTests.swift && git commit -m "feat(import): resolve and attach categoryID to Transaction in TransactionImportActor.save"`

---

## Task 7 — Wire `categoryRepo` into `ImportViewModel`'s production init call

**File:** `FinanceTracker/ContentView.swift`

`categoryRepo` already exists locally in `FinanceTrackerTabView.init` (used for `transactionVM`/`budgetVM`/`categoryVM`). Add it to the existing `ImportViewModel(...)` call:
```swift
_importVM = State(wrappedValue: ImportViewModel(
    accountRepo: accountRepo,
    importRecordRepo: importRecordRepo,
    importWriter: importWriter,
    categoryRepo: categoryRepo
))
```
`categorySuggester` is omitted — uses its default `FoundationModelsCategorySuggester()`, no other app-root wiring needed (no change to `FinanceTrackerApp.swift`).

No new test — this is DI wiring only, covered by a full build.
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expect `** BUILD SUCCEEDED **`.

Commit: `git add FinanceTracker/ContentView.swift && git commit -m "feat(import): wire categoryRepo into production ImportViewModel instantiation"`

---

## Task 8 — Category suggestion chip in `ImportSheet.previewStep`

**File:** `FinanceTracker/Views/Import/ImportSheet.swift`

Replace the row inside `previewStep`'s "Transactions to import" `Section`:
```swift
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
                VStack(alignment: .trailing, spacing: Theme.Spacing.tight) {
                    categoryChip(for: tx)
                    Text(tx.amount, format: .currency(code: viewModel.selectedAccount?.currency ?? Locale.current.currency?.identifier ?? "USD"))
                }
            }
        }
    }
}
```

Update the "Parse & Preview" button's action to also load suggestions:
```swift
Button("Parse & Preview") {
    let mapping = ColumnMapping(
        dateIndex: dateColIndex,
        amountIndex: amountColIndex,
        payeeIndex: payeeColIndex,
        hasHeader: hasHeader
    )
    Task {
        try? await viewModel.applyMapping(mapping)
        await viewModel.loadSuggestions()
    }
}
.frame(maxWidth: .infinity)
.accessibilityIdentifier("import-parse-preview-button")
```

Add these new private members to `ImportSheet` (place near the bottom, alongside the existing `private func failureMessage`/`pluralized`/`stepTitle` helpers):
```swift
@ViewBuilder
private func categoryChip(for tx: ParsedTransaction) -> some View {
    if let categoryID = tx.categoryID,
       let category = viewModel.categories.first(where: { $0.id == categoryID }) {
        categoryMenu(for: tx) {
            chipLabel(text: category.name, sparkleOpacity: nil)
        }
        .accessibilityIdentifier("import-category-chip-\(tx.importHash)")
    } else if let suggestion = viewModel.suggestions[tx.payee] {
        categoryMenu(for: tx) {
            chipLabel(text: suggestion.categoryName, sparkleOpacity: opacity(for: suggestion.confidence))
        }
        .accessibilityIdentifier("import-category-chip-\(tx.importHash)")
    }
}

private func chipLabel(text: String, sparkleOpacity: Double?) -> some View {
    HStack(spacing: Theme.Spacing.tight) {
        if let sparkleOpacity {
            Image(systemName: "sparkle")
                .opacity(sparkleOpacity)
        }
        Text(text)
            .font(Theme.Typography.chipLabel)
    }
    .padding(.horizontal, Theme.Spacing.contentSpacing)
    .padding(.vertical, Theme.Spacing.compact)
    .background(Theme.Chips.suggestionBackground)
    .foregroundStyle(Theme.Colors.primaryInteractive)
    .clipShape(Capsule())
}

@ViewBuilder
private func categoryMenu<Label: View>(
    for tx: ParsedTransaction,
    @ViewBuilder label: () -> Label
) -> some View {
    Menu {
        ForEach(viewModel.categories) { category in
            Button(category.name) {
                viewModel.setCategory(categoryID: category.id, forPayee: tx.payee)
            }
        }
    } label: {
        label()
    }
}

private func opacity(for confidence: CategorySuggestion.Confidence) -> Double {
    switch confidence {
    case .high:   Theme.Chips.confidenceHigh
    case .medium: Theme.Chips.confidenceMedium
    case .low:    Theme.Chips.confidenceLow
    }
}
```

No dedicated unit test — this codebase doesn't unit-test SwiftUI view bodies (only `UITestImportFlowTests.swift`/XCUITest covers view-level flows, and per the spec's Testing Strategy, a new UI test here is optional). Verify with a full build + the full existing test suite to confirm no regression:
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```
Expect `** BUILD SUCCEEDED **` then `** TEST SUCCEEDED **` (full suite, including the existing `UITestImportFlowTests` — unaffected since it never reaches the preview step).

Commit: `git add FinanceTracker/Views/Import/ImportSheet.swift && git commit -m "feat(import): render category suggestion chip with Menu override in ImportSheet preview step"`

---

## Task 9 — CHANGELOG + manual on-device verification

**File:** `CHANGELOG.md` — add to `[Unreleased]`:
```
- Add on-device category suggestion during CSV import — `CategorySuggesting`/`FoundationModelsCategorySuggester` (explicit `SystemLanguageModel`, zero network calls) suggest a category per unique payee in the preview step; accepted/overridden choices persist onto `Transaction.category` via a new `ParsedTransaction.categoryID` field
```

**Manual verification (required before `/release`, not automatable):**
Per the spec's Testing Strategy and the 2026-07-21 decisions.md clarification, exercise the real `FoundationModelsCategorySuggester` with a real CSV on either a physical A17 Pro+ device or the iPhone 17 Simulator with Apple Intelligence enabled on the host Mac (macOS Tahoe 26+, Xcode 26+). Confirm:
- Suggestions appear for payees that plausibly match an existing category, sparkle opacity visibly differs across high/medium/low confidence
- No chip appears when a payee doesn't plausibly match anything (fails safe)
- Tapping a chip opens the category `Menu`; picking any category (including the suggested one) updates the chip to the plain (no-sparkle) confirmed state
- Importing persists the chosen category onto the resulting `Transaction` (spot-check via the Transactions tab after import)
- On a non-eligible device/Simulator (or with Apple Intelligence disabled on the host Mac), the import flow behaves exactly as it does today — no chips, no error

Run the full suite one more time after all tasks to confirm the whole feature branch is green:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker -destination 'platform=iOS Simulator,name=iPhone 17'
```

Commit: `git add CHANGELOG.md && git commit -m "docs(changelog): add category suggestion entry to Unreleased"`

---

## Summary of new/changed files

| File | Change |
|---|---|
| `FinanceTracker/Services/CSVImportService.swift` | Add `ParsedTransaction.categoryID` |
| `FinanceTracker/Services/CategorySuggesting.swift` | New — protocol + `CategorySuggestion`/`Confidence` |
| `FinanceTracker/Services/FoundationModelsCategorySuggester.swift` | New — concrete adapter |
| `FinanceTracker/ViewModels/ImportViewModel.swift` | Add `categoryRepo`/`categorySuggester` deps, `categories`/`suggestions` state, `loadSuggestions()`/`setCategory()` |
| `FinanceTracker/Repositories/SwiftData/TransactionImportActor.swift` | Add `resolveCategory`, attach category in `save` |
| `FinanceTracker/ContentView.swift` | Pass `categoryRepo` into `ImportViewModel` init |
| `FinanceTracker/Views/Import/ImportSheet.swift` | Render chip + `Menu`, call `loadSuggestions()` |
| `FinanceTrackerTests/TestHelpers.swift` | Add `FakeCategorySuggesting` |
| `FinanceTrackerTests/Services/CSVImportServiceTests.swift` | +2 tests |
| `FinanceTrackerTests/ViewModels/ImportViewModelTests.swift` | +3 tests, 10 call sites updated |
| `FinanceTrackerTests/Repositories/TransactionImportActorTests.swift` | +3 tests |
| `CHANGELOG.md` | `[Unreleased]` entry |

**Not touched:** `Category.swift`, `Transaction.swift`, `TransactionImportWriting.swift`'s protocol signature, `CSVImportService.parse()`'s logic, `FinanceTrackerApp.swift`.

## Done when
User reviews and approves this plan. Then hand off to `/feature`. After the PR is open, `/review` runs first; once it passes, `/test` and `code-review:code-review` run in parallel.
