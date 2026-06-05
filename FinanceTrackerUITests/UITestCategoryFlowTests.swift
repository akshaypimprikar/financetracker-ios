import XCTest

final class UITestCategoryFlowTests: UITestBase {

    func testAddCategoryAppearsInSettingsList() {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        app.buttons["add-category-button"].tap()

        let nameField = app.textFields["category-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText("Transport")

        // Wait for SwiftUI to re-evaluate the disabled modifier before tapping
        let confirmButton = app.buttons["add-category-confirm"]
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: confirmButton)
        waitForExpectations(timeout: timeout)
        confirmButton.tap()

        // Synchronize on sheet dismissal before asserting list contents
        let sheetNavBar = app.navigationBars["New Category"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetNavBar)
        waitForExpectations(timeout: timeout)

        XCTAssertTrue(app.staticTexts["Transport"].waitForExistence(timeout: timeout))
    }
}
