import XCTest

final class UITestCategoryFlowTests: UITestBase {

    func testAddCategoryAppearsInSettingsList() {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        app.buttons["add-category-button"].tap()

        let nameField = app.textFields["category-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText("Transport")

        app.buttons["add-category-confirm"].tap()

        // Synchronize on sheet dismissal before asserting list contents
        let sheetNavBar = app.navigationBars["New Category"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetNavBar)
        waitForExpectations(timeout: 10)

        XCTAssertTrue(app.staticTexts["Transport"].waitForExistence(timeout: 10))
    }
}
