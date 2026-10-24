#if os(macOS)
    import AppKit
    import XCTest

    /// Not a regression test: drives the Unsplash cover flow at a watchable pace so it can be screen-recorded
    /// (Unsplash production review). Runs only when the runner gets HIKKI_RECORD — pass
    /// `TEST_RUNNER_HIKKI_RECORD=1` to xcodebuild. Attaches the window frame (points) and flow timing to the result for cropping
    /// (the runner is sandboxed and can't write to /tmp).
    @MainActor
    final class UnsplashDemoRecording: XCTestCase {
        func testRecordUnsplashCoverFlow() throws {
            try XCTSkipUnless(ProcessInfo.processInfo.environment["HIKKI_RECORD"] != nil, "recording only")
            continueAfterFailure = false
            let app = XCUIApplication()
            app.launchEnvironment["HIKKI_DATA_DIR"] = NSTemporaryDirectory() + "hikki-record-\(UUID().uuidString)"
            app.launchEnvironment["HIKKI_WORKSPACE"] = "Travel"
            app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-AppleLanguages", "(en)"]
            app.launch()

            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(newPage.waitForExistence(timeout: 15))
            newPage.click()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 15))
            title.click()
            paste("Trip to Iceland", into: app)

            let window = app.windows.firstMatch
            let f = window.frame
            let started = Date().timeIntervalSince1970
            sleep(1)

            let addCover = app.webViews.buttons["Add cover"].firstMatch
            XCTAssertTrue(addCover.waitForExistence(timeout: 5))
            addCover.hover()
            usleep(600_000)
            addCover.click()
            sleep(1)

            // A menu trigger: exposed as a pop-up button on macOS.
            let change = app.webViews.popUpButtons["Change cover"].firstMatch
            XCTAssertTrue(change.waitForExistence(timeout: 5))
            change.hover()
            usleep(600_000)
            change.click()
            sleep(1)

            let tab =
                app.webViews.radioButtons["Unsplash"].exists
                ? app.webViews.radioButtons["Unsplash"].firstMatch : app.webViews.tabs["Unsplash"].firstMatch
            XCTAssertTrue(tab.waitForExistence(timeout: 5))
            tab.click()
            sleep(2)  // a random batch of landscape photos loads first

            let search =
                app.webViews.searchFields["Search Unsplash"].exists
                ? app.webViews.searchFields["Search Unsplash"].firstMatch : app.webViews.textFields["Search Unsplash"].firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 5))
            search.click()
            paste("iceland", into: app)
            sleep(3)

            // Linger on the credits, then pick the first result.
            let credit = app.webViews.links["Unsplash"].firstMatch
            XCTAssertTrue(credit.waitForExistence(timeout: 10))
            credit.hover()
            sleep(2)
            // Credits read "Photo by <author> on <Unsplash>" under each photo: aim just above the first author link.
            let author = app.webViews.links.element(boundBy: 0)
            let target = author.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -40))
            target.hover()
            sleep(1)
            target.click()
            sleep(3)

            // Close the picker and show the page with its new cover.
            app.typeKey(.escape, modifierFlags: [])
            sleep(3)
            let ended = Date().timeIntervalSince1970
            let info = "\(Int(f.minX)) \(Int(f.minY)) \(Int(f.width)) \(Int(f.height)) \(started) \(ended)\n"
            let attachment = XCTAttachment(string: info)
            attachment.name = "recording-frame"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        /// Pastes instead of typing: synthesized keystrokes go through the active input method (a Chinese IME
        /// turns "to " into 头).
        private func paste(_ text: String, into app: XCUIApplication) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            app.typeKey("v", modifierFlags: .command)
        }
    }
#endif
