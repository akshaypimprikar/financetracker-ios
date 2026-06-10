import XCTest

final class UITestTransactionFlowTests: UITestBase {

    override func setUpWithError() throws {
        try super.setUpWithError()
        createAccount(name: "Checking")
    }

    func testAddTransactionAppearsInList() {
        app.tabBars.firstMatch.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: timeout))
        app.buttons["add-transaction-button"].tap()

        let payeeField = app.textFields["transaction-payee-field"]
        XCTAssertTrue(payeeField.waitForExistence(timeout: timeout))
        payeeField.tap()
        payeeField.typeText("Coffee Shop")

        let amountField = app.textFields["transaction-amount-field"]
        amountField.tap()
        amountField.typeText("12.50")
        tapWhenEnabled(app.buttons["add-transaction-confirm"])

        XCTAssertTrue(app.staticTexts["Coffee Shop"].waitForExistence(timeout: timeout))
    }

    private func createAccount(name: String) {
        app.tabBars.firstMatch.buttons["Accounts"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: timeout))
        app.buttons["add-account-button"].tap()
        let nameField = app.textFields["account-name-field"]
        guard nameField.waitForExistence(timeout: timeout) else { return }
        nameField.tap()
        nameField.typeText(name)
        tapWhenEnabled(app.buttons["add-account-confirm"])
        _ = app.staticTexts[name].waitForExistence(timeout: timeout)
    }
}
