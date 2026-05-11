# UI Tests for User Flows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task.

**Goal:** Add XCUITest coverage for 5 core user flows — tab navigation, add account, add transaction, add budget, add category — with per-run isolation via an in-memory SwiftData store and accessibility identifiers for stable element targeting.

**Architecture:** A `--uitesting` launch argument switches `ModelConfiguration` to `isStoredInMemoryOnly: true`; a shared `UITestBase` class launches the app with this flag before each test; accessibility identifiers added to 8 view files let tests find elements without coupling to display text.

**Tech Stack:** SwiftUI, SwiftData, XCUITest (`import XCTest` — NOT `import Testing`), iPhone 17 simulator (iOS 26.4).

**All commands run from:** `/Users/akshaypimprikar/Desktop/FinanceTracker/` (git root, contains `FinanceTracker.xcodeproj`)

---

## Task 1 — Infrastructure: in-memory store switch + UITestBase

### 1a. Modify `FinanceTracker/FinanceTrackerApp.swift`

Full file after change (add `isUITesting` flag, replace hardcoded `false`):

```swift
import SwiftUI
import SwiftData

@main
struct FinanceTrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Account.self,
            Transaction.self,
            Category.self,
            Budget.self,
            ImportRecord.self,
        ])
        let isUITesting = CommandLine.arguments.contains("--uitesting")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: isUITesting)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
```

### 1b. Delete existing stubs

```bash
rm FinanceTrackerUITests/FinanceTrackerUITests.swift
rm FinanceTrackerUITests/FinanceTrackerUITestsLaunchTests.swift
```

### 1c. Create `FinanceTrackerUITests/UITestBase.swift`

```swift
import XCTest

class UITestBase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }
}
```

### 1d. Verify build succeeds

```bash
xcodebuild build \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Commit

```bash
git add FinanceTracker/FinanceTrackerApp.swift \
        FinanceTrackerUITests/UITestBase.swift
git rm FinanceTrackerUITests/FinanceTrackerUITests.swift \
       FinanceTrackerUITests/FinanceTrackerUITestsLaunchTests.swift
git commit -m "feat: --uitesting launch arg for in-memory SwiftData isolation + UITestBase"
```

---

## Task 2 — Smoke test: app launch and tab navigation

### 2a. Create `FinanceTrackerUITests/UITestSmokeTests.swift`

```swift
import XCTest

final class UITestSmokeTests: UITestBase {

    func testAllTabsExistAfterLaunch() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Dashboard"].waitForExistence(timeout: 3))
        XCTAssertTrue(tabBar.buttons["Transactions"].exists)
        XCTAssertTrue(tabBar.buttons["Budgets"].exists)
        XCTAssertTrue(tabBar.buttons["Accounts"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
    }

    func testAllTabsAreNavigable() {
        let tabBar = app.tabBars.firstMatch

        tabBar.buttons["Accounts"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 3))

        tabBar.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 3))

        tabBar.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 3))

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))

        tabBar.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: 3))
    }
}
```

### 2b. Run smoke tests

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestSmokeTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST SUCCEEDED **`

### Commit

```bash
git add FinanceTrackerUITests/UITestSmokeTests.swift
git commit -m "test(ui): smoke tests — app launch and tab navigation"
```

---

## Task 3 — Category flow: add category → appears in Settings list

### 3a. Create `FinanceTrackerUITests/UITestCategoryFlowTests.swift`

```swift
import XCTest

final class UITestCategoryFlowTests: UITestBase {

    func testAddCategoryAppearsInSettingsList() {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        app.buttons["add-category-button"].tap()

        let nameField = app.textFields["category-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Transport")

        app.buttons["add-category-confirm"].tap()

        XCTAssertTrue(app.staticTexts["Transport"].waitForExistence(timeout: 3))
    }
}
```

### 3b. Run to confirm failure (identifiers not yet added)

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestCategoryFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST FAILED **`

### 3c. Add accessibility identifiers

**`FinanceTracker/Views/Settings/SettingsView.swift`** — toolbar button:

```swift
Button("Add", systemImage: "plus") { isPresentingAdd = true }
    .accessibilityIdentifier("add-category-button")
```

**`FinanceTracker/Views/Settings/AddCategorySheet.swift`** — name field and confirm button:

```swift
// name field:
TextField("Name", text: $name)
    .accessibilityIdentifier("category-name-field")

// confirm button (inside ToolbarItem placement: .confirmationAction):
Button("Add") {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    try? categoryVM.add(name: name, icon: icon, colorHex: "#888888", type: type)
    dismiss()
}
.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
.accessibilityIdentifier("add-category-confirm")
```

### 3d. Run to confirm pass

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestCategoryFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST SUCCEEDED **`

### Commit

```bash
git add FinanceTrackerUITests/UITestCategoryFlowTests.swift \
        FinanceTracker/Views/Settings/SettingsView.swift \
        FinanceTracker/Views/Settings/AddCategorySheet.swift
git commit -m "test(ui): category flow + accessibility identifiers for Settings/AddCategorySheet"
```

---

## Task 4 — Account flow: add account → appears in Accounts list

### 4a. Create `FinanceTrackerUITests/UITestAccountFlowTests.swift`

```swift
import XCTest

final class UITestAccountFlowTests: UITestBase {

    func testAddAccountAppearsInList() {
        app.tabBars.firstMatch.buttons["Accounts"].tap()
        app.buttons["add-account-button"].tap()

        let nameField = app.textFields["account-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText("Test Checking")

        app.buttons["add-account-confirm"].tap()

        XCTAssertTrue(app.staticTexts["Test Checking"].waitForExistence(timeout: 3))
    }
}
```

### 4b. Run to confirm failure

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestAccountFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST FAILED **`

### 4c. Add accessibility identifiers

**`FinanceTracker/Views/Accounts/AccountListView.swift`** — toolbar button:

```swift
Button("Add", systemImage: "plus") { isPresentingAdd = true }
    .accessibilityIdentifier("add-account-button")
```

**`FinanceTracker/Views/Accounts/AddAccountSheet.swift`** — name field and confirm button:

```swift
// name field:
TextField("Name", text: $name)
    .accessibilityIdentifier("account-name-field")

// confirm button (inside ToolbarItem placement: .confirmationAction):
Button("Add") {
    let balance = Decimal(string: openingBalanceText) ?? 0
    try? viewModel.addAccount(
        name: name, type: type, currency: currency,
        colorHex: colorHex, icon: icon,
        openingBalance: balance
    )
    dismiss()
}
.disabled(!canAdd)
.accessibilityIdentifier("add-account-confirm")
```

### 4d. Run to confirm pass

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestAccountFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST SUCCEEDED **`

### Commit

```bash
git add FinanceTrackerUITests/UITestAccountFlowTests.swift \
        FinanceTracker/Views/Accounts/AccountListView.swift \
        FinanceTracker/Views/Accounts/AddAccountSheet.swift
git commit -m "test(ui): account flow + accessibility identifiers for AccountListView/AddAccountSheet"
```

---

## Task 5 — Transaction flow: add account → add transaction → appears in Transactions list

The transaction form auto-selects the first account in `.onAppear`, so creating an account in setUp is sufficient — no explicit account picker interaction required.

### 5a. Create `FinanceTrackerUITests/UITestTransactionFlowTests.swift`

```swift
import XCTest

final class UITestTransactionFlowTests: UITestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        createAccount(name: "Checking")
    }

    func testAddTransactionAppearsInList() {
        app.tabBars.firstMatch.buttons["Transactions"].tap()
        app.buttons["add-transaction-button"].tap()

        let payeeField = app.textFields["transaction-payee-field"]
        XCTAssertTrue(payeeField.waitForExistence(timeout: 3))
        payeeField.tap()
        payeeField.typeText("Coffee Shop")

        let amountField = app.textFields["transaction-amount-field"]
        amountField.tap()
        amountField.typeText("12.50")

        app.buttons["add-transaction-confirm"].tap()

        XCTAssertTrue(app.staticTexts["Coffee Shop"].waitForExistence(timeout: 3))
    }

    private func createAccount(name: String) {
        app.tabBars.firstMatch.buttons["Accounts"].tap()
        app.buttons["add-account-button"].tap()
        let nameField = app.textFields["account-name-field"]
        guard nameField.waitForExistence(timeout: 3) else { return }
        nameField.tap()
        nameField.typeText(name)
        app.buttons["add-account-confirm"].tap()
        _ = app.staticTexts[name].waitForExistence(timeout: 3)
    }
}
```

### 5b. Run to confirm failure

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestTransactionFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST FAILED **`

### 5c. Add accessibility identifiers

**`FinanceTracker/Views/Transactions/TransactionListView.swift`** — add toolbar button:

```swift
Button("Add", systemImage: "plus") { isPresentingAdd = true }
    .accessibilityIdentifier("add-transaction-button")
```

**`FinanceTracker/Views/Transactions/AddTransactionSheet.swift`** — payee field, amount field, confirm button:

```swift
// payee field:
TextField("Payee", text: $payee)
    .accessibilityIdentifier("transaction-payee-field")

// amount field:
TextField("Amount", text: $amountText)
    .keyboardType(.decimalPad)
    .accessibilityIdentifier("transaction-amount-field")

// confirm button (inside ToolbarItem placement: .confirmationAction):
Button("Add") {
    guard let account = selectedAccount,
          let amount = Decimal(string: amountText) else { return }
    try? viewModel.add(
        date: date, amount: amount, payee: payee,
        notes: notes.isEmpty ? nil : notes,
        type: type, account: account,
        toAccount: isTransfer ? selectedToAccount : nil,
        category: isTransfer ? nil : viewModel.categories.first { $0.id == selectedCategoryID }
    )
    dismiss()
}
.disabled(!canAdd)
.accessibilityIdentifier("add-transaction-confirm")
```

### 5d. Run to confirm pass

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestTransactionFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST SUCCEEDED **`

### Commit

```bash
git add FinanceTrackerUITests/UITestTransactionFlowTests.swift \
        FinanceTracker/Views/Transactions/TransactionListView.swift \
        FinanceTracker/Views/Transactions/AddTransactionSheet.swift
git commit -m "test(ui): transaction flow + accessibility identifiers for TransactionListView/AddTransactionSheet"
```

---

## Task 6 — Budget flow: add category → add budget → appears in Budgets list

The budget add button is disabled when `viewModel.unbudgetedCategories.isEmpty`. Creating a category in setUp unlocks it. The budget form auto-selects the first unbudgeted category in `.onAppear`.

### 6a. Create `FinanceTrackerUITests/UITestBudgetFlowTests.swift`

```swift
import XCTest

final class UITestBudgetFlowTests: UITestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        createCategory(name: "Groceries")
    }

    func testAddBudgetAppearsInList() {
        app.tabBars.firstMatch.buttons["Budgets"].tap()
        app.buttons["add-budget-button"].tap()

        let limitField = app.textFields["budget-limit-field"]
        XCTAssertTrue(limitField.waitForExistence(timeout: 3))
        limitField.tap()
        limitField.typeText("500")

        app.buttons["add-budget-confirm"].tap()

        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: 3))
    }

    private func createCategory(name: String) {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        app.buttons["add-category-button"].tap()
        let nameField = app.textFields["category-name-field"]
        guard nameField.waitForExistence(timeout: 3) else { return }
        nameField.tap()
        nameField.typeText(name)
        app.buttons["add-category-confirm"].tap()
        _ = app.staticTexts[name].waitForExistence(timeout: 3)
    }
}
```

### 6b. Run to confirm failure

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestBudgetFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST FAILED **`

### 6c. Add accessibility identifiers

**`FinanceTracker/Views/Budgets/BudgetListView.swift`** — toolbar button:

```swift
Button("Add", systemImage: "plus") { isPresentingAdd = true }
    .disabled(viewModel.unbudgetedCategories.isEmpty)
    .accessibilityIdentifier("add-budget-button")
```

**`FinanceTracker/Views/Budgets/AddBudgetSheet.swift`** — limit field and confirm button:

```swift
// limit field:
TextField("Monthly limit", text: $limitText)
    .keyboardType(.decimalPad)
    .accessibilityIdentifier("budget-limit-field")

// confirm button (inside ToolbarItem placement: .confirmationAction):
Button("Add") {
    guard let cat = viewModel.unbudgetedCategories.first(where: { $0.id == selectedCategoryID }),
          let limit = Decimal(string: limitText) else { return }
    try? viewModel.add(category: cat, monthlyLimit: limit)
    dismiss()
}
.disabled(!canAdd)
.accessibilityIdentifier("add-budget-confirm")
```

### 6d. Run to confirm pass

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests/UITestBudgetFlowTests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: `** TEST SUCCEEDED **`

### Commit

```bash
git add FinanceTrackerUITests/UITestBudgetFlowTests.swift \
        FinanceTracker/Views/Budgets/BudgetListView.swift \
        FinanceTracker/Views/Budgets/AddBudgetSheet.swift
git commit -m "test(ui): budget flow + accessibility identifiers for BudgetListView/AddBudgetSheet"
```

---

## Task 7 — Full UI test suite

Run all UI tests to confirm no regressions across flows.

```bash
xcodebuild test \
  -project FinanceTracker.xcodeproj \
  -scheme FinanceTracker \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FinanceTrackerUITests \
  2>&1 | grep -E "Test.*passed|Test.*failed|TEST SUCCEEDED|TEST FAILED|error:"
```

Expected: 6 tests pass, `** TEST SUCCEEDED **`

Open PR to `develop`.
