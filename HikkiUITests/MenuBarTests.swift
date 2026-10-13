#if os(macOS)
    import XCTest

    /// The menu bar extra (Settings → General → Menu bar): its menu reaches the main window.
    @MainActor
    final class MenuBarTests: XCTestCase {
        private let dataDir = NSTemporaryDirectory() + "hikki-uitest-\(UUID().uuidString)"

        func testNewPageFromTheMenuBarOpensInTheMainWindow() throws {
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["HIKKI_DATA_DIR"] = dataDir
            app.launchEnvironment["HIKKI_WORKSPACE"] = "Test"
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en"]
            app.launch()
            XCTAssertTrue(app.buttons["new-page"].firstMatch.waitForExistence(timeout: 10), "app did not open")

            let item = app.statusItems.firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 10), "no status item in the menu bar")
            item.click()
            let newPage = app.menuItems["New Page"].firstMatch
            XCTAssertTrue(newPage.waitForExistence(timeout: 5), "the menu did not open")
            newPage.click()

            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15), "no page opened from the menu bar")
        }
    }
#endif
