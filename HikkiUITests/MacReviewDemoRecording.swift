#if os(macOS)
    import AppKit
    import XCTest

    /// Not a regression test: walks through Hikki on the Mac at a watchable pace so App Review gets a screen recording
    /// with the first version — first launch, writing a page, its outline, search, the page's menu and Settings. Runs
    /// only when the runner gets HIKKI_RECORD (`TEST_RUNNER_HIKKI_RECORD=1`); record the screen meanwhile with
    /// `screencapture -v -V <s>`. Text goes in by paste: synthesized keys go through the active input method.
    @MainActor
    final class MacReviewDemoRecording: XCTestCase {
        func testRecordMacReviewWalkthrough() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["HIKKI_RECORD"] != nil, "recording only")
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["HIKKI_DATA_DIR"] = NSTemporaryDirectory() + "hikki-review-\(UUID().uuidString)"
            app.launchEnvironment["HIKKI_FRESH_TABS"] = "1"
            app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            app.launch()

            // First launch: no account, a workspace kept on this Mac.
            let start = element("onboarding-start", in: app)
            XCTAssertTrue(start.waitForExistence(timeout: 30))
            sleep(2)
            start.click()
            let name = app.textFields["onboarding-name"].firstMatch
            XCTAssertTrue(name.waitForExistence(timeout: 10))
            name.click()
            app.typeKey("a", modifierFlags: .command)
            paste("My Notes", into: app)
            sleep(1)
            element("onboarding-continue", in: app).click()
            let device = element("onboarding-device", in: app)
            XCTAssertTrue(device.waitForExistence(timeout: 10))
            sleep(2)
            device.click()
            sleep(1)
            element("onboarding-create", in: app).click()
            sleep(3)

            // A page: a title, then a few lines with headings for the outline.
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(newPage.waitForExistence(timeout: 15))
            newPage.click()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            title.click()
            sleep(1)
            paste("Weekend in Kyoto", into: app)
            app.typeKey(.return, modifierFlags: [])
            sleep(1)
            // Headings and the to-do list through the editor's own shortcuts (⌥⌘2, ⌥⌘4).
            line("Two days in March, when the cherry trees open.", in: app)
            line("Saturday", block: "2", in: app)
            line("Fushimi Inari early, before the crowds.", in: app)
            line("Sunday", block: "2", in: app)
            line("Philosopher's Path, then tea in Gion.", in: app)
            line("Book the train", block: "4", in: app)
            paste("Pack a camera", into: app)
            sleep(2)

            // The outline beside the page.
            let outline = element("inspector-toggle", in: app)
            XCTAssertTrue(outline.waitForExistence(timeout: 10))
            outline.click()
            sleep(4)
            outline.click()
            sleep(2)

            // Search finds the page by its words.
            app.typeKey("k", modifierFlags: .command)
            let search = element("search-field", in: app)
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            sleep(1)
            paste("cherry", into: app)
            sleep(4)
            app.typeKey(.escape, modifierFlags: [])
            sleep(2)

            // The page's actions: history, export, share, move…
            let more = element("page-more", in: app)
            XCTAssertTrue(more.waitForExistence(timeout: 10))
            more.click()
            sleep(4)
            app.typeKey(.escape, modifierFlags: [])
            sleep(1)

            // Settings, ending on About.
            app.typeKey(",", modifierFlags: .command)
            let about = element("settings-page-about", in: app)
            XCTAssertTrue(about.waitForExistence(timeout: 10))
            sleep(2)
            element("settings-page-ai", in: app).click()
            sleep(3)
            about.click()
            sleep(3)
            element("settings-close", in: app).click()
            sleep(2)
            // The unlock after the trial isn't filmed here: a UI test runs without the StoreKit configuration.
        }

        private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
            app.descendants(matching: .any)[id].firstMatch
        }

        /// One line of the page, turned into a block first by its ⌥⌘ shortcut when `block` names its key, then Return.
        private func line(_ text: String, block: String? = nil, in app: XCUIApplication) {
            if let block { app.typeKey(block, modifierFlags: [.command, .option]) }
            paste(text, into: app)
            app.typeKey(.return, modifierFlags: [])
            usleep(700_000)
        }

        private func paste(_ text: String, into app: XCUIApplication) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            app.typeKey("v", modifierFlags: .command)
        }
    }
#endif
