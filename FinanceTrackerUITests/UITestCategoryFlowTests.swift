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

        // Navigate away and back so SettingsView.onAppear re-fetches categories.
        // SettingsView starts empty (ContentUnavailableView) and transitions to a
        // populated Section on first add — @Observable propagation alone is not
        // reliable enough on slow CI for this structural list change.
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: timeout))
        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))

        XCTAssertTrue(app.staticTexts["Transport"].waitForExistence(timeout: timeout))
    }
}
