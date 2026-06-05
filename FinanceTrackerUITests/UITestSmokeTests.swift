import XCTest

final class UITestSmokeTests: UITestBase {

    func testAllTabsExistAfterLaunch() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.buttons["Dashboard"].waitForExistence(timeout: timeout))
        XCTAssertTrue(tabBar.buttons["Transactions"].exists)
        XCTAssertTrue(tabBar.buttons["Budgets"].exists)
        XCTAssertTrue(tabBar.buttons["Accounts"].exists)
        XCTAssertTrue(tabBar.buttons["Settings"].exists)
    }

    func testAllTabsAreNavigable() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: timeout))

        tabBar.buttons["Accounts"].tap()
        XCTAssertTrue(app.navigationBars["Accounts"].waitForExistence(timeout: timeout))

        tabBar.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: timeout))

        tabBar.buttons["Budgets"].tap()
        XCTAssertTrue(app.navigationBars["Budgets"].waitForExistence(timeout: timeout))

        tabBar.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: timeout))

        tabBar.buttons["Dashboard"].tap()
        XCTAssertTrue(app.navigationBars["Dashboard"].waitForExistence(timeout: timeout))
    }
}
