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
