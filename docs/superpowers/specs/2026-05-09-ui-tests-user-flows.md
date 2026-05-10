# UI Tests for User Flows — Design Spec

**Date:** 2026-05-09
**Status:** Draft

## Overview

Add meaningful XCUITest coverage for the five core user flows in FinanceTracker: tab navigation, add account, add transaction, add budget, and add category. The existing `FinanceTrackerUITests` target contains only Xcode-generated stubs. This spec replaces those stubs with real flows, adds accessibility identifiers to interactive elements so tests are resilient to label changes, and introduces a `--uitesting` launch argument that switches SwiftData to an in-memory store for clean per-run isolation.

CSV Import is explicitly deferred — the system `UIDocumentPickerViewController` cannot be driven by XCUITest without a custom test host.

## Decisions & Constraints

| Decision | Choice | Rationale |
|---|---|---|
| Test isolation | `--uitesting` launch arg → `isStoredInMemoryOnly: true` | Clean state per run; no disk residue; minimal production code change |
| Element targeting | `.accessibilityIdentifier()` on buttons and fields | Survives copy/label changes; standard iOS practice |
| Test framework | XCUITest (`import XCTest`) | Swift Testing has no XCUIApplication support; UI tests must use XCTest |
| CSV Import | Deferred | System file picker is not automatable with XCUITest |
| Test data setup | UI-driven (no seed data) | Keeps test-only logic out of the app target; exercises add flows as side effect |

## Architecture

No domain layer changes. Two layers are touched:

**App entry point** (`FinanceTrackerApp.swift`):
- Check `CommandLine.arguments.contains("--uitesting")` and set `isStoredInMemoryOnly: true` when present.

**Views** (5 files — accessibility identifiers only):
- `AddAccountSheet`, `AccountListView`
- `AddTransactionSheet`, `TransactionListView`
- `AddBudgetSheet`, `BudgetListView`
- `AddCategorySheet`, `SettingsView`

**UITest target** (`FinanceTrackerUITests/`):
- Replace stubs with 5 test files + a shared base class.

## Data Models

No changes.

## Domain Services

No changes.

## Navigation

No new screens. Tests exercise existing navigation: tab bar → list → sheet → dismiss.

## Accessibility Identifiers

All identifiers to add:

| View | Element | Identifier |
|---|---|---|
| `ContentView` (TabView) | Dashboard tab | `"tab-dashboard"` |
| `ContentView` (TabView) | Transactions tab | `"tab-transactions"` |
| `ContentView` (TabView) | Budgets tab | `"tab-budgets"` |
| `ContentView` (TabView) | Accounts tab | `"tab-accounts"` |
| `ContentView` (TabView) | Settings tab | `"tab-settings"` |
| `AccountListView` | Add toolbar button | `"add-account-button"` |
| `AddAccountSheet` | Name text field | `"account-name-field"` |
| `AddAccountSheet` | Confirm "Add" button | `"add-account-confirm"` |
| `TransactionListView` | Add toolbar button | `"add-transaction-button"` |
| `AddTransactionSheet` | Payee text field | `"transaction-payee-field"` |
| `AddTransactionSheet` | Amount text field | `"transaction-amount-field"` |
| `AddTransactionSheet` | Confirm "Add" button | `"add-transaction-confirm"` |
| `BudgetListView` | Add toolbar button | `"add-budget-button"` |
| `AddBudgetSheet` | Monthly limit field | `"budget-limit-field"` |
| `AddBudgetSheet` | Confirm "Add" button | `"add-budget-confirm"` |
| `SettingsView` | Add toolbar button | `"add-category-button"` |
| `AddCategorySheet` | Name text field | `"category-name-field"` |
| `AddCategorySheet` | Confirm "Add" button | `"add-category-confirm"` |

## Test File Structure

```
FinanceTrackerUITests/
  UITestBase.swift                    — shared XCTestCase subclass; launches app with --uitesting
  UITestSmokeTests.swift              — app launch + all 5 tabs visible
  UITestAccountFlowTests.swift        — add account → appears in Accounts list
  UITestTransactionFlowTests.swift    — add account → add transaction → appears in Transactions list
  UITestBudgetFlowTests.swift         — add category → add budget → appears in Budgets list
  UITestCategoryFlowTests.swift       — add category → appears in Settings list
```

**`UITestBase`** (shared setup):
```swift
class UITestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
}
```

**Test coverage per file:**

`UITestSmokeTests`:
- `testAppLaunchesAndShowsTabBar` — 5 tab bar items exist after launch

`UITestAccountFlowTests`:
- `testAddAccountAppearsInList` — tap Accounts tab → tap add → fill name "Test Checking" + type Checking → confirm → verify "Test Checking" cell visible

`UITestTransactionFlowTests`:
- `testAddTransactionAppearsInList` — add account via UI → tap Transactions tab → tap add → fill payee "Coffee Shop" + amount "12.50" + select account → confirm → verify "Coffee Shop" visible in list

`UITestBudgetFlowTests`:
- `testAddBudgetAppearsInList` — add category "Groceries" via Settings → tap Budgets tab → tap add → select "Groceries" + limit "500" → confirm → verify "Groceries" budget row visible

`UITestCategoryFlowTests`:
- `testAddCategoryAppearsInSettings` — tap Settings tab → tap add → fill name "Transport" → confirm → verify "Transport" visible in list

## App Entry Point Change

```swift
// FinanceTrackerApp.swift
let isUITesting = CommandLine.arguments.contains("--uitesting")
let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
```

## Future Extension Points

- **Seed data via launch arg**: If test setup via UI becomes too slow, add `--seed-data` to pre-populate an account + category. Plugs into `FinanceTrackerApp.swift` alongside `--uitesting`.
- **Delete flows**: Swipe-to-delete tests per entity type — deferred until flows are stable.
- **Dashboard assertions**: Net worth calculation after adding accounts — deferred until add-account tests are green.
- **Error state flows**: Empty states, disabled Add buttons — deferred.

## Testing Strategy

| What | How | Framework |
|---|---|---|
| In-memory store switches on `--uitesting` | Manual verification (launch, confirm no data persists) | — |
| Tab bar accessible | `UITestSmokeTests` | XCUITest |
| Add account end-to-end | `UITestAccountFlowTests` | XCUITest |
| Add transaction end-to-end | `UITestTransactionFlowTests` | XCUITest |
| Add budget end-to-end | `UITestBudgetFlowTests` | XCUITest |
| Add category end-to-end | `UITestCategoryFlowTests` | XCUITest |
| Accessibility identifiers present | Covered implicitly — tests fail if identifier missing | XCUITest |
