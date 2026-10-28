#if os(iOS)
    import XCTest

    /// Not a regression test: walks through Hikki on an iPhone at a watchable pace so App Review gets a screen recording
    /// with the first version — first launch, writing a page and its actions. Runs only when
    /// the runner gets HIKKI_RECORD (`TEST_RUNNER_HIKKI_RECORD=1`); record the simulator meanwhile with
    /// `xcrun simctl io <udid> recordVideo`.
    @MainActor
    final class ReviewDemoRecording: XCTestCase {
        func testRecordReviewWalkthrough() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["HIKKI_RECORD"] != nil, "recording only")
            continueAfterFailure = false
            let data = NSTemporaryDirectory() + "hikki-review-\(UUID().uuidString)"

            // First launch: no account, a workspace kept on this device.
            let app = launch(data: data)
            let start = app.buttons["onboarding-start"].firstMatch
            XCTAssertTrue(start.waitForExistence(timeout: 30))
            sleep(2)
            start.tap()
            let name = app.textFields["onboarding-name"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            sleep(1)
            name.typeText("My Notes")
            sleep(1)
            app.buttons["onboarding-continue"].firstMatch.tap()
            let device = app.buttons["onboarding-device"].firstMatch
            XCTAssertTrue(device.waitForExistence(timeout: 10))
            sleep(2)
            device.tap()
            sleep(1)
            app.buttons["onboarding-create"].firstMatch.tap()
            sleep(3)

            // A page: a title, a line, then a to-do list from the keyboard bar's + panel.
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(newPage.waitForExistence(timeout: 15))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            title.tap()
            sleep(1)
            title.typeText("Weekend in Kyoto\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(body.waitForExistence(timeout: 10))
            body.typeText("Two days in March, when the cherry trees open.\n")
            sleep(1)
            let addBlock = app.buttons["Add block"].firstMatch
            XCTAssertTrue(addBlock.waitForExistence(timeout: 10))
            addBlock.tap()
            sleep(2)
            let todo = app.buttons["keyboard-block-taskList"].firstMatch
            XCTAssertTrue(todo.waitForExistence(timeout: 5))
            todo.tap()
            sleep(1)
            body.typeText("Book the train\nPack a camera")
            sleep(2)
            // The bar's end button puts the keyboard away.
            app.buttons["hide-keyboard"].firstMatch.tap()
            sleep(2)

            // The page's actions: history, export, share, move.
            let more = app.buttons["page-more"].firstMatch
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            sleep(1)
            more.tap()
            sleep(4)
            app.swipeDown(velocity: .slow)
            sleep(2)
            app.navigationBars.buttons.firstMatch.tap()
            sleep(4)
            // The unlock after the trial isn't filmed here: a UI test runs without the StoreKit configuration, so the
            // sheet would say the App Store can't be reached.
        }

        private func launch(data: String, environment: [String: String] = [:]) -> XCUIApplication {
            let app = XCUIApplication()
            app.launchEnvironment["HIKKI_DATA_DIR"] = data
            app.launchEnvironment["HIKKI_FRESH_TABS"] = "1"
            app.launchEnvironment.merge(environment) { _, new in new }
            app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()
            return app
        }
    }
#endif
