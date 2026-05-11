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
