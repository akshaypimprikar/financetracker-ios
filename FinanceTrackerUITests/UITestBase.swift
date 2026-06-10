import XCTest

class UITestBase: XCTestCase {
    var app: XCUIApplication!
    let timeout: TimeInterval = 30

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Waits for a confirm button to become enabled, then taps it.
    /// SwiftUI TextField bindings update asynchronously; on fast CI the
    /// disabled modifier may not reflect typed text until the next render cycle.
    func tapWhenEnabled(_ button: XCUIElement) {
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: timeout)
        button.tap()
    }
}
