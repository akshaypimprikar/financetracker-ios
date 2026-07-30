import XCTest

final class UITestBudgetFlowTests: UITestBase {

    func testAddBudgetAppearsInList() {
        createCategory(name: "Groceries")

        app.tabBars.firstMatch.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: timeout))
        app.buttons["add-budget-button"].tap()

        let limitField = app.textFields["budget-limit-field"]
        XCTAssertTrue(limitField.waitForExistence(timeout: timeout))
        limitField.tap()
        limitField.typeText("500")
        tapWhenEnabled(app.buttons["add-budget-confirm"])

        XCTAssertTrue(app.staticTexts["Groceries"].waitForExistence(timeout: timeout))
    }

    private func createCategory(name: String) {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        app.buttons["add-category-button"].tap()
        let nameField = app.textFields["category-name-field"]
        guard nameField.waitForExistence(timeout: timeout) else { return }
        nameField.tap()
        nameField.typeText(name)
        tapWhenEnabled(app.buttons["add-category-confirm"])
        _ = app.staticTexts[name].waitForExistence(timeout: timeout)
    }
}
