import XCTest

/// End-to-end: SwiftUI shell ⇄ WKWebView bridge ⇄ SQLite, through the real UI.
@MainActor
final class EditorFlowTests: XCTestCase {
    private let dataDir = NSTemporaryDirectory() + "hikki-uitest-\(UUID().uuidString)"

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HIKKI_DATA_DIR"] = dataDir
        app.launch()
        return app
    }

    func testTypedTitleIsSavedAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        var app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()

        let editor = app.webViews.textViews.firstMatch
        XCTAssertTrue(waitOrDumpTree(editor, in: app), "editor never became editable")
        editor.tap()
        editor.typeText("Hello Hikki")
        // Past the 400 ms debounce so the change reaches SQLite.
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "editing"
        shot.lifetime = .keepAlways
        add(shot)

        app.terminate()
        app = launch()
        #if os(iOS)
            if app.navigationBars.buttons.firstMatch.exists, !app.staticTexts["Hello Hikki"].exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        #endif
        XCTAssertTrue(app.staticTexts["Hello Hikki"].firstMatch.waitForExistence(timeout: 10), "saved title missing from sidebar after relaunch")
    }

    /// On failure, attaches the accessibility tree to the result bundle — the fastest way to see why a query missed.
    private func waitOrDumpTree(_ element: XCUIElement, in app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        if element.waitForExistence(timeout: timeout) { return true }
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "ui-tree"
        tree.lifetime = .keepAlways
        add(tree)
        return false
    }
}
