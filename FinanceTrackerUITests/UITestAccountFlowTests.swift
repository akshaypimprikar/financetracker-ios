import XCTest

final class UITestAccountFlowTests: UITestBase {

    func testAddAccountAppearsInList() {
        app.tabBars.firstMatch.buttons["Accounts"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: timeout))
        app.buttons["add-account-button"].tap()

        let nameField = app.textFields["account-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText("Test Checking")

        app.buttons["add-account-confirm"].tap()

        XCTAssertTrue(app.staticTexts["Test Checking"].waitForExistence(timeout: timeout))
    }
}
