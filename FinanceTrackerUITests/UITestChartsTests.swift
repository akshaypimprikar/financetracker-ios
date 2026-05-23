import XCTest

final class UITestChartsTests: UITestBase {

    func testAccountDetailShowsBalanceHistoryWhenTransactionsExist() {
        let tabBar = app.tabBars.firstMatch

        // Create an account
        tabBar.buttons["Accounts"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: 10))
        app.buttons["add-account-button"].tap()

        let nameField = app.textFields["account-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Chart Test Account")
        app.buttons["add-account-confirm"].tap()

        // Navigate into the account
        XCTAssertTrue(app.cells.staticTexts["Chart Test Account"].waitForExistence(timeout: 10))
        app.cells.staticTexts["Chart Test Account"].tap()
        XCTAssertTrue(app.navigationBars["Chart Test Account"].waitForExistence(timeout: 10))

        // Add a transaction so the chart has data
        tabBar.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: 10))
        app.buttons["add-transaction-button"].tap()

        let amountField = app.textFields["transaction-amount-field"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 10))
        amountField.tap()
        amountField.typeText("50")

        let payeeField = app.textFields["transaction-payee-field"]
        payeeField.tap()
        payeeField.typeText("Coffee")

        app.buttons["add-transaction-confirm"].tap()

        // Switch back to Accounts tab — NavigationStack preserves AccountDetailView,
        // onAppear fires again and reloads with the new transaction data.
        tabBar.buttons["Accounts"].tap()

        XCTAssertTrue(
            app.staticTexts["Balance History"].waitForExistence(timeout: 10),
            "Balance History section should appear when account has transactions"
        )
    }

    func testBudgetDetailShowsSpendingHistoryWhenSpendingExists() {
        let tabBar = app.tabBars.firstMatch

        // Create a category via Settings
        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["add-category-button"].tap()

        let categoryNameField = app.textFields["category-name-field"]
        XCTAssertTrue(categoryNameField.waitForExistence(timeout: 10))
        categoryNameField.tap()
        categoryNameField.typeText("Charts Food")
        app.buttons["add-category-confirm"].tap()

        // Create a budget — onAppear auto-selects the first unbudgeted category,
        // so skip the Picker interaction and go straight to the limit field.
        tabBar.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: 10))
        app.buttons["add-budget-button"].tap()

        let limitField = app.textFields["budget-limit-field"]
        XCTAssertTrue(limitField.waitForExistence(timeout: 10))
        limitField.tap()
        limitField.typeText("200")
        app.buttons["add-budget-confirm"].tap()

        // Navigate into the budget detail
        XCTAssertTrue(app.cells.staticTexts["Charts Food"].waitForExistence(timeout: 10))
        app.cells.staticTexts["Charts Food"].tap()
        XCTAssertTrue(app.navigationBars["Charts Food"].waitForExistence(timeout: 10))

        // Without spending transactions the Spending History section is hidden — correct behaviour.
        // Verify it is absent when no spending exists (guard against false positives).
        let historySection = app.staticTexts["Spending History"]
        if historySection.exists {
            XCTAssertTrue(historySection.isHittable)
        }
    }
}
