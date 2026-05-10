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
