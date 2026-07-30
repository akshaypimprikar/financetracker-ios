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
        tapWhenEnabled(app.buttons["add-category-confirm"])

        // Synchronize on sheet dismissal before asserting list contents
        let sheetNavBar = app.navigationBars["New Category"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetNavBar)
        waitForExpectations(timeout: timeout)

        // Navigate away and back so SettingsView.onAppear re-fetches categories.
        // SettingsView starts empty (ContentUnavailableView); the first add is a
        // structural List change that @Observable alone doesn't propagate reliably
        // on CI before the assertion window closes.
        let tabBar = app.tabBars.firstMatch
        tabBar.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: timeout))
        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))

        // In iOS 26, a bare Label in a List row may surface as a cell element
        // rather than a staticText. Wait on cells["Transport"] first; fall back to
        // staticTexts["Transport"] in case the representation differs.
        let categoryCell = app.cells["Transport"]
        let categoryText = app.staticTexts["Transport"]
        XCTAssertTrue(
            categoryCell.waitForExistence(timeout: timeout) || categoryText.exists,
            "Transport should appear in the Settings category list"
        )
    }

    func testDuplicateCategoryNameShowsWarningAndBlocksAdd() {
        app.tabBars.firstMatch.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))
        app.buttons["add-category-button"].tap()

        let nameField = app.textFields["category-name-field"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.tap()
        nameField.typeText("Travel")
        tapWhenEnabled(app.buttons["add-category-confirm"])

        let sheetNavBar = app.navigationBars["New Category"]
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetNavBar)
        waitForExpectations(timeout: timeout)

        app.buttons["add-category-button"].tap()
        let secondNameField = app.textFields["category-name-field"]
        XCTAssertTrue(secondNameField.waitForExistence(timeout: timeout))
        secondNameField.tap()
        secondNameField.typeText("travel")   // case-insensitive near-duplicate of "Travel"

        XCTAssertTrue(app.staticTexts["category-duplicate-warning"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.buttons["add-category-confirm"].isEnabled)
    }
}
