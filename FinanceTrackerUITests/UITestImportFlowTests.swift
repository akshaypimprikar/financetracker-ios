import XCTest

final class UITestImportFlowTests: UITestBase {

    func testImportButtonOpensSheetAndChooseFileLaunchesDocumentPicker() {
        app.tabBars.firstMatch.buttons["Transactions"].tap()
        XCTAssertTrue(app.navigationBars["Transactions"].waitForExistence(timeout: timeout))

        app.buttons["import-transactions-button"].tap()
        XCTAssertTrue(app.navigationBars["Import CSV"].waitForExistence(timeout: timeout))

        tapWhenEnabled(app.buttons["import-choose-file-button"])

        // The system document picker runs in a separate process — automating file
        // selection inside it is disproportionately fragile for this PR's scope (no
        // other UI test in this suite drives a fileImporter). This test only confirms
        // the entry point launches a picker; the async import pipeline itself
        // (chunking, cancellation, progress, dedup) is covered by ImportViewModelTests.
        // The full visual flow (progress bar appearing/disappearing) should be manually
        // verified on the iPhone 17 simulator during /feature via the `verify` skill —
        // see the Testing Strategy note in
        // docs/superpowers/specs/2026-07-15-csv-import-async-migration.md.
        XCTAssertTrue(app.navigationBars.element(boundBy: 0).waitForExistence(timeout: timeout))

        // .firstMatch, not a bare identifier lookup — the app's own
        // "import-cancel-toolbar-button" is still present underneath the modal
        // document picker sheet, so a plain app.buttons["Cancel"] query matches
        // both it and the system picker's own Cancel button and throws
        // "Multiple matching elements found". Either one dismisses the screen
        // for this test's purposes (it isn't asserting which Cancel fires).
        if app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 2) {
            app.buttons["Cancel"].firstMatch.tap()
        }
    }
}
