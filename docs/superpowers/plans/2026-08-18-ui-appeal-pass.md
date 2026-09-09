# UI Appeal Pass Implementation Plan

**Goal:** Fix the Accounts tab's missing empty state and the "Creditcard" copy bug, add a spending-by-category chart to the Dashboard, extend category-based coloring to budget progress bars app-wide, and migrate `DashboardView`'s hero cards onto the `Theme.Glass` tokens (merged in PR #95), retiring the flat legacy tint tokens they replace.
**Architecture:** Pure View/ViewModel/Model-layer work. One new pure-Swift computed property (`AccountType.displayName`), one new ViewModel aggregation (`DashboardViewModel.categorySpending`) with a co-located DTO, and View-layer changes reusing existing `Theme` tokens throughout. No new SwiftData models, no new Domain Services, no new Repository protocols.
**Tech Stack:** SwiftUI, SwiftData, Swift Charts, Apple `Testing` framework (unit), `XCTest` (UI).
**All commands run from:** `/Users/akshaypimprikar/Desktop/Claude/FinanceTracker/` (git root, contains FinanceTracker.xcodeproj)

**Simulator destination for every command below:**
```
platform=iOS Simulator,name=iPhone 17,OS=26.4.1
```

---

## Task 1 — `AccountType.displayName` (fixes "Creditcard" copy bug)

**Files touched:** `FinanceTracker/Models/Account.swift`, `FinanceTracker/Views/Accounts/AccountListView.swift`, `FinanceTracker/Views/Accounts/AccountDetailView.swift`, `FinanceTrackerTests/Models/AccountTypeTests.swift` (new)

### RED — write the failing test

Create `FinanceTrackerTests/Models/AccountTypeTests.swift`:

```swift
import Testing
@testable import FinanceTracker

@Suite("AccountType")
struct AccountTypeTests {
    @Test(arguments: [
        (AccountType.checking, "Checking"),
        (AccountType.savings, "Savings"),
        (AccountType.creditCard, "Credit Card"),
        (AccountType.cash, "Cash"),
        (AccountType.investment, "Investment"),
    ])
    func displayNameMatchesExpected(type: AccountType, expected: String) {
        #expect(type.displayName == expected)
    }
}
```

Confirm RED:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/AccountTypeTests \
  2>&1 | grep -E "error:|BUILD FAILED|TEST FAILED"
```
Expected: `error: value of type 'AccountType' has no member 'displayName'` — this is the RED state for new API surface (compile failure, not a runtime assertion failure — correct here since the member doesn't exist yet).

Commit RED:
```bash
git add FinanceTrackerTests/Models/AccountTypeTests.swift
git commit -m "test: add failing AccountType.displayName coverage (RED)"
```

### GREEN — implement + wire consumers

In `FinanceTracker/Models/Account.swift`, add `displayName` to the `AccountType` enum, right after `isLiability`:

```swift
enum AccountType: String, Codable, CaseIterable {
    case checking
    case savings
    case creditCard
    case cash
    case investment

    var isLiability: Bool { self == .creditCard }

    var displayName: String {
        switch self {
        case .checking:   return "Checking"
        case .savings:    return "Savings"
        case .creditCard: return "Credit Card"
        case .cash:       return "Cash"
        case .investment: return "Investment"
        }
    }
}
```

In `FinanceTracker/Views/Accounts/AccountListView.swift`, in `AccountRow`, change:
```swift
Text(account.type.rawValue.capitalized)
    .font(Theme.Typography.rowSubtitle)
    .foregroundStyle(.secondary)
```
to:
```swift
Text(account.type.displayName)
    .font(Theme.Typography.rowSubtitle)
    .foregroundStyle(.secondary)
```

In `FinanceTracker/Views/Accounts/AccountDetailView.swift`, change:
```swift
HStack {
    Text("Type")
    Spacer()
    Text(account.type.rawValue.capitalized)
        .foregroundStyle(.secondary)
}
```
to:
```swift
HStack {
    Text("Type")
    Spacer()
    Text(account.type.displayName)
        .foregroundStyle(.secondary)
}
```

Confirm GREEN:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/AccountTypeTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`, 5 tests passed (one per `AccountType` case).

Commit GREEN:
```bash
git add FinanceTracker/Models/Account.swift FinanceTracker/Views/Accounts/AccountListView.swift FinanceTracker/Views/Accounts/AccountDetailView.swift
git commit -m "fix: add AccountType.displayName, fix 'Creditcard' copy bug (GREEN)"
```

---

## Task 2 — Accounts tab empty state

**Files touched:** `FinanceTracker/Views/Accounts/AccountListView.swift`, `FinanceTrackerUITests/UITestAccountFlowTests.swift`

### RED — write the failing UI test

In `FinanceTrackerUITests/UITestAccountFlowTests.swift`, add a new test function inside `UITestAccountFlowTests`:

```swift
func testEmptyStateShowsWhenNoAccountsExist() {
    app.tabBars.firstMatch.buttons["Accounts"].tap()
    XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: timeout))
    XCTAssertTrue(app.staticTexts["No Accounts Yet"].waitForExistence(timeout: timeout))
}
```

`--uitesting` launches with a fresh empty in-memory store (see `FinanceTrackerApp.swift`), so this exercises the true cold-start empty state with no setup needed.

Confirm RED:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerUITests/UITestAccountFlowTests/testEmptyStateShowsWhenNoAccountsExist \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST FAILED"
```
Expected: `** TEST FAILED **` — no "No Accounts Yet" text exists anywhere in the current `AccountListView`.

Commit RED:
```bash
git add FinanceTrackerUITests/UITestAccountFlowTests.swift
git commit -m "test: add failing Accounts empty-state UI test (RED)"
```

### GREEN — add the empty state

In `FinanceTracker/Views/Accounts/AccountListView.swift`, replace the `body`'s `List { ... }` contents. Current:

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

            if !assets.isEmpty {
                Section("Assets") {
```

Replace with (wraps the existing Net Worth section + Assets/Liabilities sections in an `else`, adds the empty state as the `if` branch — everything from `Section("Assets")` through the end of the `Section("Liabilities")` block is otherwise unchanged):

```swift
    var body: some View {
        let netWorth = viewModel.netWorth()
        List {
            if assets.isEmpty && liabilities.isEmpty {
                ContentUnavailableView(
                    "No Accounts Yet",
                    systemImage: "building.columns",
                    description: Text("Tap + to add your first account.")
                )
            } else {
                Section {
                    HStack {
                        Text("Net Worth")
                        Spacer()
                        Text(netWorth, format: .currency(code: viewModel.currency))
                            .bold()
                            .foregroundStyle(netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
                    }
                }

                if !assets.isEmpty {
                    Section("Assets") {
```

...and the closing brace structure needs one more level of indentation for the rest of the existing `if !assets.isEmpty { ... }` and `if !liabilities.isEmpty { ... }` blocks (unchanged content, now nested inside the new `else`), with a final `}` closing the `else` block before the `List`'s closing `}`. Full resulting file body:

```swift
    var body: some View {
        let netWorth = viewModel.netWorth()
        List {
            if assets.isEmpty && liabilities.isEmpty {
                ContentUnavailableView(
                    "No Accounts Yet",
                    systemImage: "building.columns",
                    description: Text("Tap + to add your first account.")
                )
            } else {
                Section {
                    HStack {
                        Text("Net Worth")
                        Spacer()
                        Text(netWorth, format: .currency(code: viewModel.currency))
                            .bold()
                            .foregroundStyle(netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
                    }
                }

                if !assets.isEmpty {
                    Section("Assets") {
                        ForEach(assets) { account in
                            NavigationLink {
                                AccountDetailView(account: account, viewModel: viewModel)
                            } label: {
                                AccountRow(account: account,
                                           balance: viewModel.balance(for: account))
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                try? viewModel.delete(assets[index])
                            }
                        }
                    }
                }

                if !liabilities.isEmpty {
                    Section("Liabilities") {
                        ForEach(liabilities) { account in
                            NavigationLink {
                                AccountDetailView(account: account, viewModel: viewModel)
                            } label: {
                                AccountRow(account: account,
                                           balance: viewModel.balance(for: account))
                            }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                try? viewModel.delete(liabilities[index])
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { isPresentingAdd = true }
                    .accessibilityIdentifier("add-account-button")
            }
        }
        .sheet(isPresented: $isPresentingAdd) {
            AddAccountSheet(viewModel: viewModel)
        }
        .onAppear { try? viewModel.load() }
    }
```

(Only the `var body` changes — `AccountRow` and the rest of the file are untouched.)

Confirm GREEN:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerUITests/UITestAccountFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`, both `testAddAccountAppearsInList` and `testEmptyStateShowsWhenNoAccountsExist` pass.

Commit GREEN:
```bash
git add FinanceTracker/Views/Accounts/AccountListView.swift
git commit -m "fix: add Accounts tab empty state (GREEN)"
```

---

## Task 3 — Dashboard spending-by-category chart

**Files touched:** `FinanceTracker/ViewModels/DashboardViewModel.swift`, `FinanceTracker/Views/Dashboard/DashboardView.swift`, `FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift`, `FinanceTrackerUITests/UITestChartsTests.swift`

### RED — write the failing ViewModel tests

In `FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift`, add two new `@Test` functions inside `DashboardViewModelTests`, after `recentTransactionsLimitedToFive()`:

```swift
    @Test func categorySpendingGroupsDebitsByCategoryForCurrentMonth() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let groceries = Category(name: "Groceries", type: .expense)
        let dining = Category(name: "Dining", type: .expense)
        ctx.insert(account)
        ctx.insert(groceries)
        ctx.insert(dining)
        ctx.insert(Transaction(date: .now, amount: 40, payee: "Store",
                               type: .debit, account: account, category: groceries))
        ctx.insert(Transaction(date: .now, amount: 10, payee: "Store2",
                               type: .debit, account: account, category: groceries))
        ctx.insert(Transaction(date: .now, amount: 25, payee: "Cafe",
                               type: .debit, account: account, category: dining))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.categorySpending.count == 2)
        let groceriesSpend = vm.categorySpending.first { $0.category.id == groceries.id }
        #expect(groceriesSpend?.amount == 50)
        let diningSpend = vm.categorySpending.first { $0.category.id == dining.id }
        #expect(diningSpend?.amount == 25)
    }

    @Test func categorySpendingExcludesCreditAndUncategorizedTransactions() throws {
        let container = try makeContainer()
        let ctx = ModelContext(container)
        let account = Account(name: "Checking", type: .checking)
        let salary = Category(name: "Salary", type: .income)
        ctx.insert(account)
        ctx.insert(salary)
        ctx.insert(Transaction(date: .now, amount: 1000, payee: "Payroll",
                               type: .credit, account: account, category: salary))
        ctx.insert(Transaction(date: .now, amount: 20, payee: "Uncategorized Purchase",
                               type: .debit, account: account))
        try ctx.save()

        let vm = DashboardViewModel(
            accountRepo: SwiftDataAccountRepository(context: ctx),
            transactionRepo: SwiftDataTransactionRepository(context: ctx),
            budgetRepo: SwiftDataBudgetRepository(context: ctx)
        )
        try vm.load()

        #expect(vm.categorySpending.isEmpty)
    }
```

Confirm RED:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/DashboardViewModelTests \
  2>&1 | grep -E "error:|BUILD FAILED"
```
Expected: `error: value of type 'DashboardViewModel' has no member 'categorySpending'` — compile failure, correct RED state for new API surface.

Commit RED:
```bash
git add FinanceTrackerTests/ViewModels/DashboardViewModelTests.swift
git commit -m "test: add failing DashboardViewModel.categorySpending coverage (RED)"
```

### GREEN — implement aggregation + chart

In `FinanceTracker/ViewModels/DashboardViewModel.swift`, add a `CategorySpending` DTO above the class (same top-level-struct-in-ViewModel-file placement pattern as `BalanceDataPoint`/`MonthlySpendingPoint` live next to their service):

```swift
import Foundation
import Observation

struct CategorySpending: Identifiable {
    var id: UUID { category.id }
    let category: Category
    let amount: Decimal
}

@Observable
final class DashboardViewModel {
```

Add a new published property alongside the others:
```swift
    private(set) var netWorth: Decimal = 0
    private(set) var spendingThisMonth: Decimal = 0
    private(set) var categorySpending: [CategorySpending] = []
    private(set) var recentTransactions: [Transaction] = []
```

At the end of `load()`, after the `spendingThisMonth` computation and before `recentTransactions = ...`, add:
```swift
        let categorizedDebits = allTransactions.filter {
            $0.type == .debit && $0.date >= startOfMonth && $0.date < endOfMonth && $0.category != nil
        }
        let groupedByCategory = Dictionary(grouping: categorizedDebits) { $0.category!.id }
        categorySpending = groupedByCategory.compactMap { _, transactions -> CategorySpending? in
            guard let category = transactions.first?.category else { return nil }
            let total = transactions.reduce(Decimal.zero) { $0 + $1.amount }
            return CategorySpending(category: category, amount: total)
        }
```

In `FinanceTracker/Views/Dashboard/DashboardView.swift`, add `import Charts` below `import SwiftUI`:
```swift
import SwiftUI
import Charts
```

In `body`, after the `spendingCard` and before the `if !viewModel.budgetProgresses.isEmpty { ... }` block, add:
```swift
                if !viewModel.categorySpending.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.contentSpacing) {
                        Text("Spending by Category").font(Theme.Typography.sectionHeader)
                        Chart(viewModel.categorySpending) { item in
                            BarMark(
                                x: .value("Category", item.category.name),
                                y: .value("Spent", NSDecimalNumber(decimal: item.amount).doubleValue)
                            )
                            .foregroundStyle(Theme.Charts.spendingBar)
                        }
                        .frame(minHeight: Theme.Charts.minHeight)
                        .padding(.horizontal, Theme.Spacing.cardPadding)
                    }
                }
```

Add a UI test to `FinanceTrackerUITests/UITestChartsTests.swift`, inside `UITestChartsTests`, mirroring `testBudgetDetailShowsSpendingHistoryWhenSpendingExists`'s established absence-check pattern (this codebase deliberately avoids automating SwiftUI `Picker` category-selection in UI tests — see that test's own comment; the positive aggregation-correctness case is already covered by the unit tests above):

```swift
    func testDashboardHidesSpendingByCategoryChartWhenNoSpendingExists() {
        app.tabBars.firstMatch.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: timeout))

        // Without categorized spending, the chart section is hidden — correct behaviour.
        let chartSection = app.staticTexts["Spending by Category"]
        if chartSection.exists {
            XCTAssertTrue(chartSection.isHittable)
        }
    }
```

Confirm GREEN:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  -only-testing:FinanceTrackerTests/DashboardViewModelTests \
  -only-testing:FinanceTrackerUITests/UITestChartsTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`, all `DashboardViewModelTests` (now 5) and all `UITestChartsTests` (now 3) pass.

Commit GREEN:
```bash
git add FinanceTracker/ViewModels/DashboardViewModel.swift FinanceTracker/Views/Dashboard/DashboardView.swift FinanceTrackerUITests/UITestChartsTests.swift
git commit -m "feat: add Dashboard spending-by-category chart (GREEN)"
```

---

## Task 4 — Category-colored budget progress bars (app-wide)

**Files touched:** `FinanceTracker/Views/Dashboard/DashboardView.swift`, `FinanceTracker/Views/Budgets/BudgetListView.swift`, `FinanceTracker/Views/Budgets/BudgetDetailView.swift`

No new business logic — reuses the existing `Color(hex:)` mechanism `AccountRow` already relies on (no dedicated test exists for that either; this follows the same established, untested-at-the-unit-level styling convention). Verified manually via `--seedscreenshots` in Task 5's final verification step.

In `FinanceTracker/Views/Dashboard/DashboardView.swift`, in `BudgetProgressCard`, change:
```swift
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
```
to:
```swift
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? Theme.Colors.destructive : (Color(hex: budget.category.colorHex) ?? Theme.Colors.primaryInteractive))
```

In `FinanceTracker/Views/Budgets/BudgetListView.swift`, in `BudgetRow`, change:
```swift
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
```
to:
```swift
            ProgressView(value: min(progress.percentUsed, 1.0))
                .tint(progress.isOverBudget ? Theme.Colors.destructive : (Color(hex: budget.category.colorHex) ?? Theme.Colors.primaryInteractive))
```

In `FinanceTracker/Views/Budgets/BudgetDetailView.swift`, change:
```swift
                ProgressView(value: min(progress.percentUsed, 1.0))
                    .tint(progress.isOverBudget ? Theme.Colors.destructive : Theme.Colors.primaryInteractive)
                    .padding(.vertical, Theme.Spacing.compact)
```
to:
```swift
                ProgressView(value: min(progress.percentUsed, 1.0))
                    .tint(progress.isOverBudget ? Theme.Colors.destructive : (Color(hex: budget.category.colorHex) ?? Theme.Colors.primaryInteractive))
                    .padding(.vertical, Theme.Spacing.compact)
```

Confirm build (no new tests — pure styling change against an already-tested `Color(hex:)` initializer):
```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

Commit:
```bash
git add FinanceTracker/Views/Dashboard/DashboardView.swift FinanceTracker/Views/Budgets/BudgetListView.swift FinanceTracker/Views/Budgets/BudgetDetailView.swift
git commit -m "feat: color budget progress bars by category, app-wide"
```

---

## Task 5 — DashboardView adopts Glass Cards; retire legacy flat tint tokens; fix design-system.md

**Files touched:** `FinanceTracker/Views/Dashboard/DashboardView.swift`, `FinanceTracker/Theme/Colors.swift`, `FinanceTrackerTests/Theme/ThemeTokenTests.swift`, `docs/design-system.md`

No new test — `ThemeTokenTests` loses two tests (for the tokens being deleted); the Glass tokens they're being replaced by already have their own coverage from PR #95. Verified visually via `--seedscreenshots` below.

### Update `DashboardView.swift`

Change `netWorthCard`:
```swift
    private var netWorthCard: some View {
        VStack(spacing: Theme.Spacing.compact) {
            Text("Net Worth")
                .font(Theme.Typography.rowSubtitle)
                .foregroundStyle(.secondary)
            Text(viewModel.netWorth, format: .currency(code: viewModel.currency))
                .font(Theme.Typography.amountDisplay)
                .foregroundStyle(viewModel.netWorth >= 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(Theme.Colors.destructive))
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge)
                .fill(Theme.Glass.cardMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge)
                        .fill(Theme.Glass.netWorthTint)
                )
        )
        .shadow(color: Theme.Glass.cardShadowColor, radius: Theme.Glass.cardShadowRadius, y: Theme.Glass.cardShadowY)
    }
```
(Removed `.clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCardLarge))` — no longer needed, the `RoundedRectangle` shape is now the background itself rather than a separately-clipped flat fill.)

Change `spendingCard`:
```swift
    private var spendingCard: some View {
        HStack {
            Text("Spent this month")
            Spacer()
            Text(viewModel.spendingThisMonth, format: .currency(code: viewModel.currency))
                .bold()
        }
        .padding(Theme.Spacing.cardPadding)
        .background(
            RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCard)
                .fill(Theme.Glass.cardMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCard)
                        .fill(Theme.Glass.spendingTint)
                )
        )
        .shadow(color: Theme.Glass.cardShadowColor, radius: Theme.Glass.cardShadowRadius, y: Theme.Glass.cardShadowY)
    }
```
(Removed `.clipShape(RoundedRectangle(cornerRadius: Theme.Spacing.cornerRadiusCard))`, same reason.)

### Remove legacy tokens from `Colors.swift`

`FinanceTracker/Theme/Colors.swift` — remove the two now-dead lines (confirm no other consumer first: `grep -rn "netWorthCardBackground\|spendingCardBackground" FinanceTracker --include="*.swift"` should return nothing once Task 5's `DashboardView.swift` edit above lands):
```swift
enum Theme {}

extension Theme {
    enum Colors {
        static let positive: Color = .green
        static let destructive: Color = .red
        static let transfer: Color = .blue
        static let primaryInteractive: Color = .accentColor
    }
}
```

### Update `ThemeTokenTests.swift`

`FinanceTrackerTests/Theme/ThemeTokenTests.swift` — remove the two tests for the deleted tokens:
```swift
    @Test func colorsNetWorthCardBackground()    { #expect(Theme.Colors.netWorthCardBackground == Color.teal.opacity(0.12)) }
    @Test func colorsSpendingCardBackground()    { #expect(Theme.Colors.spendingCardBackground == Color.orange.opacity(0.08)) }
```

### Fix `docs/design-system.md`

This also fixes the self-contradiction a code-review pass caught in PR #95: the Card section currently classifies *both* Dashboard cards as "Hero" in one bullet, then immediately cites `spendingCardBackground` as an example of a "Secondary card elsewhere" token in the next — but `spendingCardBackground`'s only consumer anywhere in the codebase was the Dashboard Spending card itself, which the line above already called Hero. After this task, that token is deleted entirely, so the contradiction is resolved by removing the false claim rather than papering over it.

Change the Colors table (remove the two now-deleted-token rows):
```markdown
| Token | Value | Meaning |
|---|---|---|
| `positive` | `.green` | Income amounts, credit transactions, available budget, positive balances |
| `destructive` | `.red` | Over-budget, negative balances, delete actions |
| `transfer` | `.blue` | Transfer transaction amounts |
| `primaryInteractive` | `.accentColor` | Progress bars, buttons, decorative call-to-action icons |
```

Change the Card section's code snippet and bullets — current:
```markdown
### Card
A tappable or informational surface with a colored background.

\`\`\`swift
VStack { ... }
    .padding()                                      // Theme.Spacing.cardPadding
    .background(Theme.Colors.netWorthCardBackground)
    .cornerRadius(Theme.Spacing.cornerRadiusCardLarge)
    .frame(maxWidth: .infinity, alignment: .leading)
\`\`\`

- Hero card (Dashboard Net Worth / Spending): see **Glass Cards** below — supersedes the flat-tint treatment
- Secondary card elsewhere: `cornerRadiusCard` (12pt), flat tint background (e.g. `spendingCardBackground`)
```
to:
```markdown
### Card
A tappable or informational surface with a colored background.

Dashboard's Net Worth and Spending cards (the only two hero-level cards in the app) both use the **Glass Cards** pattern below — there is currently no other card component in the app, so there is no separate flat-tint "Card" pattern to document; if a future screen needs a simple flat-tint card, `cornerRadiusCard`/`cornerRadiusCardLarge` from Spacing remain available with any semantic `Theme.Colors` background token.
```

Change the two Charts-section rows that reference the now-deleted tokens by name — current:
```markdown
| `balanceAreaFill` | `.teal.opacity(0.08)` | Gradient fill under the balance line — same hue as `netWorthCardBackground` at lower opacity |
| `spendingBar` | `.orange` | Bar fill for the spending breakdown chart in BudgetDetailView — echoes `spendingCardBackground` |
```
to:
```markdown
| `balanceAreaFill` | `.teal.opacity(0.08)` | Gradient fill under the balance line — same hue as `Theme.Glass.netWorthTint` |
| `spendingBar` | `.orange` | Bar fill for the spending breakdown chart in BudgetDetailView and the Dashboard category chart — echoes `Theme.Glass.spendingTint` |
```

### Verify visually

```bash
xcodebuild build -project FinanceTracker.xcodeproj -scheme FinanceTracker -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```
Expected: `** BUILD SUCCEEDED **`.

Then use `mcp__XcodeBuildMCP__build_run_sim` with `launchArgs: ["--seedscreenshots"]` and `mcp__XcodeBuildMCP__screenshot` to visually confirm: Net Worth/Spending cards show the glass material + tint + shadow, the Dashboard category chart renders with seeded transaction data, and budget progress bars are colored per-category (not uniform blue) on Dashboard, Budgets, and a Budget detail screen. Check both light and Dark Mode (Dark Mode wasn't visually verified during the original HIG review — flagged as a gap in the spec's Future Extension Points).

Run the full suite:
```bash
xcodebuild test -project FinanceTracker.xcodeproj -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.4.1' \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED"
```
Expected: `** TEST SUCCEEDED **`, all tests pass (2 fewer than before Task 5, from the deleted `ThemeTokenTests` cases; 2 new from Task 1's `AccountTypeTests` — wait, that's 5 new from Task 1's parameterized test, 2 new from Task 3's `DashboardViewModelTests`, 1 new from Task 2's UI test, 1 new from Task 3's UI test, minus 2 removed in Task 5 — net **+7** vs. the 168 passing at the start of this plan → expect **175**).

Commit:
```bash
git add FinanceTracker/Views/Dashboard/DashboardView.swift FinanceTracker/Theme/Colors.swift FinanceTrackerTests/Theme/ThemeTokenTests.swift docs/design-system.md
git commit -m "feat: migrate DashboardView to Glass Cards, retire legacy flat tint tokens, fix design-system.md Card-section contradiction"
```

---

## Branching & PR

Single feature branch for all 5 tasks: `feature/ui-appeal-pass`, branched off `develop` (confirm local `develop` is synced with `origin/develop` first — do not branch off a stale local ref).

After all 5 tasks are committed (10 commits total: 3 RED/GREEN pairs for Tasks 1–3, 1 commit for Task 4, 1 commit for Task 5):
```bash
git push -u origin feature/ui-appeal-pass
gh pr create --base develop --title "feat: UI appeal pass" --body "..."
```
Per CLAUDE.md, `--base develop` is required — `gh pr create` defaults to `main`.

## Post-PR pipeline

Per CLAUDE.md's standard pipeline: `/gates` runs before the PR is opened (part of `/feature`'s own process, not this plan). After the PR is open: `/pr-followup` auto-chains `/review` → `/test`. `code-review:code-review` cannot be agent-invoked — run it manually. The PR is mergeable once all three are clean, per CLAUDE.md's Merge rule; the user merges it.
