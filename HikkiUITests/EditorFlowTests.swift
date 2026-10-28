import XCTest

/// End-to-end: SwiftUI shell ⇄ WKWebView bridge ⇄ SQLite, through the real UI.
@MainActor
final class EditorFlowTests: XCTestCase {
    private let dataDir = NSTemporaryDirectory() + "hikki-uitest-\(UUID().uuidString)"

    /// `workspace: nil` starts from a fresh install (onboarding); otherwise a device workspace is seeded.
    private func launch(
        language: String? = nil, workspace: String? = "Test", shortcutOverrides: String = "{}",
        environment: [String: String] = [:], arguments: [String] = [], settingsPage: String? = "workspace"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += arguments
        app.launchEnvironment["HIKKI_DATA_DIR"] = dataDir
        // The window's tabs (a split among them) are saved with the scene and would carry over from the last test.
        app.launchEnvironment["HIKKI_FRESH_TABS"] = "1"
        app.launchEnvironment.merge(environment) { _, new in new }
        if let workspace { app.launchEnvironment["HIKKI_WORKSPACE"] = workspace }
        // Preferences outlive the data directory (UserDefaults): every test starts with the inspector closed.
        app.launchArguments += [
            "-inspector.visible", "NO", "-inspector.tab", "outline",
            "-shortcutOverrides", "<\(Data(shortcutOverrides.utf8).map { String(format: "%02x", $0) }.joined())>",
        ]
        // Fixed in the argument domain, so a page picked in Settings isn't remembered; nil leaves it to the app.
        if let settingsPage { app.launchArguments += ["-settings.page", settingsPage] }
        if let language { app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language] }
        app.launch()
        return app
    }

    /// The trial is over (HIKKI_ACCESS=expired): pages still open but don't take typing, the read-only bar says so,
    /// and New Page asks for the unlock instead of making one.
    func testAfterTheTrialPagesAreReadOnly() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_ACCESS": "expired", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["read-only-bar"].firstMatch, in: app, timeout: 30))
        // The page shows, as a locked page does: its words are there, but nothing in it is editable.
        XCTAssertTrue(waitOrDumpTree(app.webViews.staticTexts.firstMatch, in: app, timeout: 30))
        sleep(2)
        XCTAssertFalse(app.webViews.textViews["Page content"].firstMatch.exists, "a read-only page is editable")
        // The title stays a (read-only) text field: typing into it changes nothing.
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app))
        let before = title.value as? String
        title.tap()
        app.typeText("zz")
        sleep(1)
        XCTAssertEqual(title.value as? String, before, "a read-only title took typing")
        #if os(iOS)
            if !app.buttons["new-page"].firstMatch.exists {
                // iPhone: New Page is on Home.
                app.navigationBars.buttons["BackButton"].firstMatch.tap()
            }
        #endif
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        XCTAssertTrue(app.descendants(matching: .any)["unlock-sheet"].firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(app, "unlock-sheet")
        XCTAssertFalse(app.buttons["unlock-buy"].firstMatch.isEnabled, "a Debug run has no store product to sell")
    }

    /// Ask AI's model menu (iPhone sheet): starring a model lists it first under Favorites, the star stays when the
    /// menu opens again, and picking a model names it in the composer.
    func testStarringAModelPutsItFirst() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone Ask AI sheet") }
        #else
            throw XCTSkip("the iPhone Ask AI sheet")
        #endif
        // The stars live in UserDefaults, which outlive a run (a launch argument would pin them: the argument domain
        // wins over what the app writes), so an earlier run's star is taken off first.
        let app = launch(environment: ["HIKKI_OPEN_AI": "1"], arguments: ["-ai.model", "auto"])
        let menu = app.buttons["ai-chat-model"].firstMatch
        XCTAssertTrue(waitOrDumpTree(menu, in: app), "the model menu is missing")
        menu.tap()
        let haiku = app.buttons["model-claude-haiku-5-5"].firstMatch
        let sonnet = app.buttons["model-claude-sonnet-5-5"].firstMatch
        let star = app.buttons["model-star-claude-haiku-5-5"].firstMatch
        XCTAssertTrue(waitOrDumpTree(haiku, in: app))
        if haiku.frame.minY < sonnet.frame.minY {
            star.tap()
            let unstarred = NSPredicate { _, _ in haiku.frame.minY > sonnet.frame.minY }
            wait(for: [expectation(for: unstarred, evaluatedWith: nil)], timeout: 5)
        }
        // Haiku sits under "Other models", below the recommended Sonnet.
        XCTAssertGreaterThan(haiku.frame.minY, sonnet.frame.minY)
        star.tap()
        let first = NSPredicate { _, _ in haiku.frame.minY < sonnet.frame.minY }
        wait(for: [expectation(for: first, evaluatedWith: nil)], timeout: 5)
        attachScreenshot(app, "model-starred")
        haiku.tap()
        let named = NSPredicate { _, _ in menu.label.contains("Haiku") && !haiku.exists }
        wait(for: [expectation(for: named, evaluatedWith: nil)], timeout: 5)
        menu.tap()
        XCTAssertTrue(waitOrDumpTree(haiku, in: app))
        XCTAssertLessThan(haiku.frame.minY, sonnet.frame.minY, "the star was kept")
    }

    /// iPhone's home screen: the drawer's tree opens a page's subpages, a row opens the page, ⋯ opens its actions
    /// sheet, and All pages lists every page under day headings.
    func testPhoneHomeOpensPagesAndTheirActions() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
        #else
            throw XCTSkip("the iPhone layout")
        #endif
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1"])
        let allPages = app.buttons["nav-home"].firstMatch
        XCTAssertTrue(waitOrDumpTree(allPages, in: app))

        // The tree is in the drawer: closed, its rows are not there.
        XCTAssertFalse(app.buttons["page-expand-日本語を勉強する"].firstMatch.exists)
        app.buttons["drawer-toggle"].firstMatch.tap()
        let child = app.buttons["page-row-N4 文法"].firstMatch
        XCTAssertFalse(child.exists)
        tapWhenSettled(app.buttons["page-expand-日本語を勉強する"].firstMatch)
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        child.tap()

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        XCTAssertTrue(app.buttons["ask-ai-page"].firstMatch.exists)
        more.tap()
        XCTAssertTrue(app.buttons["page-history"].firstMatch.waitForExistence(timeout: 5))
        app.swipeDown(velocity: .fast)
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(allPages.waitForExistence(timeout: 5))
        allPages.tap()
        XCTAssertTrue(app.buttons["home-row-Career Planning"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-new-page"].firstMatch.exists)
    }

    /// iPhone: the page tree is a side drawer (Notion's). ☰ opens it, a tap on the dimmed home closes it, a swipe from
    /// the left opens it again; a parent expands, its child opens, and the page is on screen with the drawer gone.
    func testPhoneDrawerOpensAPage() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
        #else
            throw XCTSkip("the iPhone layout")
        #endif
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1"])
        let toggle = app.buttons["drawer-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(toggle, in: app))
        let parent = app.buttons["page-expand-日本語を勉強する"].firstMatch
        XCTAssertFalse(parent.exists, "the closed drawer is hidden")

        toggle.tap()
        XCTAssertTrue(waitOrDumpTree(parent, in: app))
        XCTAssertTrue(app.buttons["drawer-all-pages"].firstMatch.exists)
        XCTAssertTrue(app.buttons["drawer-trash"].firstMatch.exists)
        XCTAssertTrue(app.buttons["drawer-settings"].firstMatch.exists)
        XCTAssertTrue(app.buttons["drawer-new-page"].firstMatch.exists)
        // No ⋯ / + on the rows: their actions are on a long press.
        XCTAssertFalse(app.buttons["page-add-日本語を勉強する"].firstMatch.exists)
        attachScreenshot(app, "drawer-open")
        tapWhenSettled(app.descendants(matching: .any)["drawer-close"].firstMatch)
        let closed = NSPredicate { _, _ in !parent.exists }
        wait(for: [expectation(for: closed, evaluatedWith: nil)], timeout: 5)

        // A swipe from the left edge, over the tiles (not the cards' own horizontal list).
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.2))
        start.press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)))
        XCTAssertTrue(waitOrDumpTree(parent, in: app), "the swipe did not open the drawer")
        tapWhenSettled(parent)
        let child = app.buttons["page-row-N4 文法"].firstMatch
        XCTAssertTrue(child.waitForExistence(timeout: 5))
        child.tap()

        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app, timeout: 30))
        let opened = NSPredicate(format: "value == %@", "N4 文法")
        wait(for: [expectation(for: opened, evaluatedWith: title)], timeout: 15)
        XCTAssertTrue(app.buttons["page-more"].firstMatch.exists)
        XCTAssertFalse(app.buttons["drawer-all-pages"].firstMatch.exists, "the drawer closed")
    }

    /// iPhone: leaving the app while typing in a page (keyboard up) and coming back — or relaunching — keeps the body
    /// right under the title (it was drawn far down the screen once, with the keyboard's room left above it).
    func testPhoneBodyStaysUnderTheTitleAfterLeavingWhileTyping() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
        #else
            throw XCTSkip("the iPhone layout")
        #endif
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30))
        let line = body.staticTexts["山へ行くんですか。"].firstMatch
        XCTAssertTrue(waitOrDumpTree(line, in: app))
        let gap = { () -> CGFloat in
            let title = app.webViews.staticTexts["N4 文法"].firstMatch
            return body.staticTexts.element(boundBy: 0).frame.minY - title.frame.maxY
        }
        let before = gap()
        line.tap()
        sleep(1)
        app.typeText("x")
        sleep(3)
        attachScreenshot(app, "typing")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        sleep(3)
        attachScreenshot(app, "back")
        XCTAssertLessThan(abs(gap() - before), 40, "the body moved away from the title after coming back")
        app.terminate()
        app.launchEnvironment["HIKKI_DEBUG_NAV"] = "demo-46ffce8"
        app.launch()
        XCTAssertTrue(waitOrDumpTree(app.webViews.textViews["Page content"].firstMatch, in: app, timeout: 30))
        sleep(2)
        attachScreenshot(app, "relaunched")
        XCTAssertLessThan(abs(gap() - before), 40, "the body moved away from the title after relaunching")
    }

    /// A reported failure shows as a toast with its code and incident id; "Copy details" and × take it away.
    func testAFailureShowsAToastWithItsCode() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEBUG_TOAST": "1"])
        let toast = app.descendants(matching: .any).matching(identifier: "toast").firstMatch
        XCTAssertTrue(waitOrDumpTree(toast, in: app))
        XCTAssertTrue(app.staticTexts["Couldn't save the page."].firstMatch.exists)
        let reference = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "HK-2001 · ")).firstMatch
        XCTAssertTrue(reference.exists, "the toast names its code and incident")
        attachScreenshot(app, "toasts")
        app.buttons["toast-action"].firstMatch.tap()
        let gone = NSPredicate(format: "exists == false")
        wait(for: [expectation(for: gone, evaluatedWith: reference)], timeout: 5)
    }

    /// First launch: welcome → name → "this device only" → the named workspace opens, and stays bound on relaunch.
    func testOnboardingCreatesNamedWorkspace() throws {
        continueAfterFailure = false
        var app = launch(workspace: nil)
        let start = app.buttons["onboarding-start"].firstMatch
        XCTAssertTrue(waitOrDumpTree(start, in: app))
        start.tap()
        let name = app.textFields["onboarding-name"].firstMatch
        XCTAssertTrue(waitOrDumpTree(name, in: app))
        XCTAssertFalse((name.value as? String ?? "").isEmpty, "no suggested name")
        attachScreenshot(app, "onboarding-name")
        // The suggestion arrives focused and selected, so typing replaces it.
        sleep(1)
        name.typeText("Field Notes")
        XCTAssertEqual(name.value as? String, "Field Notes")
        app.buttons["onboarding-continue"].firstMatch.tap()
        let device = app.buttons["onboarding-device"].firstMatch
        XCTAssertTrue(waitOrDumpTree(device, in: app))
        device.tap()
        app.buttons["onboarding-create"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Field Notes"].firstMatch, in: app), "workspace name not shown")

        app.terminate()
        app = launch(workspace: nil)
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Field Notes"].firstMatch, in: app), "workspace not persisted")
        XCTAssertFalse(app.buttons["onboarding-start"].exists)
    }

    #if os(macOS)
        /// Toggling the sidebar re-lays out the title bar; the traffic lights must stay centred in our 46pt bar.
        func testTrafficLightsStayCenteredWhenSidebarToggles() throws {
            continueAfterFailure = false
            let app = launch()
            let close = app.buttons["_XCUI:CloseWindow"].firstMatch
            let toggle = app.buttons["Hide Sidebar"].firstMatch
            XCTAssertTrue(waitOrDumpTree(toggle, in: app))
            sleep(1)
            let expected = close.frame.midY - app.windows.firstMatch.frame.minY
            toggle.click()
            sleep(1)
            XCTAssertEqual(close.frame.midY - app.windows.firstMatch.frame.minY, expected, accuracy: 0.5, "moved after hiding the sidebar")
            app.buttons["Show Sidebar"].firstMatch.click()
            sleep(1)
            XCTAssertEqual(close.frame.midY - app.windows.firstMatch.frame.minY, expected, accuracy: 0.5, "moved after showing the sidebar")
        }
    #endif

    #if os(iOS)
        /// Page context menu (long press on iPhone): Duplicate adds a sibling copy; Rename opens the page with
        /// the title selected, so typing replaces it.
        func testPageContextMenuDuplicateAndRename() throws {
            continueAfterFailure = false
            let app = launch()
            createPage(app, title: "Draft")
            backToSidebarIfNeeded(app)
            openDrawerIfNeeded(app)
            let row = app.buttons["page-row-Draft"].firstMatch
            XCTAssertTrue(waitOrDumpTree(row, in: app))
            row.press(forDuration: 1.0)
            let duplicate = app.buttons["Duplicate"].firstMatch
            XCTAssertTrue(waitOrDumpTree(duplicate, in: app))
            duplicate.tap()
            let rows = app.buttons.matching(identifier: "page-row-Draft")
            XCTAssertTrue(waitOrDumpTree(rows.element(boundBy: 1), in: app), "no duplicate row")

            app.buttons.matching(identifier: "page-row-Draft").element(boundBy: 0).press(forDuration: 1.0)
            let rename = app.buttons["Rename"].firstMatch
            XCTAssertTrue(waitOrDumpTree(rename, in: app))
            rename.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app, timeout: 15))
            sleep(1)
            title.typeText("Final")
            XCTAssertEqual(title.value as? String, "Final")
        }
    #endif

    /// Workspace menu → Settings: renaming the workspace there updates the sidebar.
    func testSettingsRenamesWorkspace() throws {
        continueAfterFailure = false
        let app = launch(workspace: "Old Name")
        openSettings(app)

        app.descendants(matching: .any)["settings-page-workspace"].firstMatch.tap()
        let name = app.textFields["settings-name"].firstMatch
        XCTAssertTrue(waitOrDumpTree(name, in: app))
        attachScreenshot(app, "settings")
        // The field is trailing-aligned: tap its right edge so the caret lands after the text.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Atlas\n")
        app.buttons["settings-close"].firstMatch.tap()
        openDrawerIfNeeded(app)
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Atlas"].firstMatch, in: app), "renamed workspace not shown")
    }

    /// Page ⋯ → Publish… asks first (ISSUE-224): two ways to share, Publish closed until the privacy check is made
    /// (and, listed in Hikki Shared, a tag picked), and Cancel publishes nothing.
    func testPublishLinkAsksFirst() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app, timeout: 30))
        more.tap()
        let publish = app.buttons["publish-link"].firstMatch
        XCTAssertTrue(waitOrDumpTree(publish, in: app), "no Publish Link entry")
        publish.tap()
        let sheet = app.descendants(matching: .any)["publish-sheet"].firstMatch
        XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the publish sheet did not open")
        // Two ways to share, the link one chosen; Publish waits for the privacy check.
        XCTAssertTrue(app.buttons["publish-mode-link"].firstMatch.exists, "no link-only choice")
        XCTAssertTrue(app.buttons["publish-mode-listed"].firstMatch.exists, "no Hikki Shared choice")
        let confirm = app.buttons["publish-confirm"].firstMatch
        XCTAssertTrue(confirm.exists, "no Publish button")
        XCTAssertFalse(confirm.isEnabled, "Publish is open before the privacy check")
        // Listed, it needs a tag too: a tag isn't enough on its own, the check still is.
        app.buttons["publish-mode-listed"].firstMatch.tap()
        app.buttons["publish-tag-study"].firstMatch.tap()
        XCTAssertFalse(confirm.isEnabled, "a listed page may go up without the privacy check")
        // The check sits at the foot of the sheet's scroll, under the pinned Cancel / Publish bar on a phone.
        let check = app.descendants(matching: .any)["publish-check"].firstMatch
        sheet.swipeUp()
        check.tap()
        XCTAssertTrue(confirm.isEnabled, "Publish stayed closed with the check and a tag")
        app.buttons["publish-tag-study"].firstMatch.tap()
        XCTAssertFalse(confirm.isEnabled, "a listed page may go up without a tag")
        app.buttons["publish-tag-study"].firstMatch.tap()
        XCTAssertTrue(confirm.isEnabled, "picking the tag again didn't open Publish")
        attachScreenshot(app, "publish-sheet")
        app.buttons["publish-cancel"].firstMatch.tap()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5), "the sheet stayed")
        more.tap()
        XCTAssertTrue(waitOrDumpTree(app.buttons["publish-link"].firstMatch, in: app), "the page counts as published after Cancel")
    }

    /// "Save to Hikki" asks first (ISSUE-224): any web page can open a hikki://shared link, so the link alone imports
    /// nothing — an alert names what happens, and Cancel leaves the workspace as it was.
    func testSaveToHikkiLinkAsksFirst() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        XCTAssertTrue(waitOrDumpTree(app.buttons["page-more"].firstMatch, in: app, timeout: 30))
        // Through the system, as a link from Safari arrives (XCUIApplication.open relaunched the app blank).
        XCUIDevice.shared.system.open(URL(string: "hikki://shared/test-record-1#key")!)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let openPrompt = springboard.buttons["Open"].firstMatch
        if openPrompt.waitForExistence(timeout: 3) { openPrompt.tap() }
        let save = app.buttons["confirm-save-shared"].firstMatch
        XCTAssertTrue(waitOrDumpTree(save, in: app), "a Save to Hikki link imported without asking")
        app.buttons["cancel-save-shared"].firstMatch.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "the question stayed after Cancel")
    }

    /// Settings → Import & Export is a page of its own (ISSUE-226): a drop zone, the three ways in — documents, a
    /// Hikki export, a Notion export — and the export below.
    func testImportExportPageShowsItsSources() throws {
        continueAfterFailure = false
        let app = launch()
        openSettings(app)
        let page = app.descendants(matching: .any)["settings-page-transfer"].firstMatch
        XCTAssertTrue(waitOrDumpTree(page, in: app), "no Import & Export page")
        page.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["drop-zone"].firstMatch, in: app), "no drop zone")
        for source in ["settings-import", "settings-import-hikki", "settings-import-notion", "settings-export"] {
            XCTAssertTrue(app.buttons[source].firstMatch.exists, "no \(source)")
        }
        attachScreenshot(app, "import-export")
        app.buttons["settings-close"].firstMatch.tap()
    }

    /// Settings on Mac/iPad is a dialog over the window: its pages in a sidebar, the close button dismisses it, and
    /// it opens again on the page last shown. (iPhone keeps its hub list.)
    func testSettingsDialogRemembersItsPage() throws {
        continueAfterFailure = false
        let app = launch(settingsPage: nil)
        guard app.buttons["workspace-menu"].firstMatch.waitForExistence(timeout: 5) else {
            throw XCTSkip("iPhone: Settings is the hub list")
        }
        openSettings(app)
        let about = app.descendants(matching: .any)["settings-page-about"].firstMatch
        XCTAssertTrue(waitOrDumpTree(about, in: app))
        about.tap()
        let diagnostics = app.descendants(matching: .any)["settings-diagnostics"].firstMatch
        XCTAssertTrue(waitOrDumpTree(diagnostics, in: app), "About not shown")
        attachScreenshot(app, "settings-dialog")
        app.buttons["settings-close"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["settings-close"].firstMatch.waitForNonExistence(timeout: 5),
            "the close button didn't dismiss Settings")

        openSettings(app)
        XCTAssertTrue(waitOrDumpTree(diagnostics, in: app), "reopened on another page")
        // About → Logs opens from inside the dialog (pushed on iPad, a sheet over it on the Mac).
        app.descendants(matching: .any)["settings-logs"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["logs-level"].firstMatch, in: app), "no logs")
    }

    #if os(iOS)
        /// Settings → Shortcuts on iPad: a rebound shortcut shows its keys and resets; the key cap records a press and
        /// refuses one without ⌘/⌃/⌥. (XCUITest on iOS delivers typed keys without their modifiers, so recording a
        /// whole combo is covered by the unit tests and the Mac.)
        func testSettingsRebindsAShortcut() throws {
            continueAfterFailure = false
            let app = launch(shortcutOverrides: #"{"bold":{"key":"j","modifiers":["command","shift"]}}"#)
            openSettings(app)
            app.descendants(matching: .any)["settings-page-shortcuts"].firstMatch.tap()

            let search = app.textFields["shortcuts-search"].firstMatch
            XCTAssertTrue(waitOrDumpTree(search, in: app))
            search.tap()
            search.typeText("Bold")
            let cap = app.buttons["shortcut-bold"].firstMatch
            XCTAssertTrue(waitOrDumpTree(cap, in: app))
            XCTAssertEqual(cap.value as? String, "⇧⌘J")
            let reset = app.buttons["shortcut-bold-reset"].firstMatch
            XCTAssertTrue(reset.exists, "a rebound shortcut offers its default back")
            attachScreenshot(app, "shortcuts-rebound")

            // A plain key is refused, with the reason under the row; the keys stay.
            cap.tap()
            app.typeKey("k", modifierFlags: [])
            XCTAssertTrue(waitOrDumpTree(app.staticTexts["shortcut-refusal"].firstMatch, in: app), "no refusal")
            XCTAssertEqual(cap.value as? String, "⇧⌘J")
            attachScreenshot(app, "shortcuts-refused")

            reset.tap()
            XCTAssertEqual(cap.value as? String, "⌘B")
            XCTAssertFalse(reset.exists)
        }
    #endif

    /// Simplified Chinese end to end: native chrome from the String Catalog, the web editor via setLocale.
    func testSimplifiedChineseUI() throws {
        continueAfterFailure = false
        let app = launch(language: "zh-Hans")
        // The Home tab (toolbar on Mac/iPad, the sidebar row on iPhone) carries the localized name.
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["主页"].firstMatch, in: app), "native chrome not localized")
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let title = app.webViews.textViews["页面标题"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app, timeout: 15), "editor not localized (title field label)")
        XCTAssertEqual(title.placeholderValue, "无标题")
    }

    func testTypedTitleIsSavedAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        var app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()

        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Hello Hikki")
        // Past the 400 ms debounce so the change reaches SQLite.
        sleep(2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "editing"
        shot.lifetime = .keepAlways
        add(shot)

        #if os(iOS)
            let hide = app.buttons["hide-keyboard"].firstMatch
            XCTAssertTrue(waitOrDumpTree(hide, in: app), "hide-keyboard button missing from keyboard toolbar")
            hide.tap()
            let keyboardGone = NSPredicate(format: "count == 0")
            wait(for: [expectation(for: keyboardGone, evaluatedWith: app.keyboards)], timeout: 5)
        #endif

        app.terminate()
        app = launch()
        #if os(iOS)
            if app.navigationBars.buttons.firstMatch.exists, !app.staticTexts["Hello Hikki"].exists {
                app.navigationBars.buttons.firstMatch.tap()
            }
        #endif
        XCTAssertTrue(
            app.staticTexts["Hello Hikki"].firstMatch.waitForExistence(timeout: 10), "saved title missing from sidebar after relaunch")
    }

    #if os(iOS)
        /// The keyboard bar's panels take the keyboard's place: + inserts a block and the keyboard comes back; Aa
        /// puts the keyboard down and stays until the bar's keyboard button brings it back.
        func testKeyboardBarPanels() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.tap()

            // Every tool is a finger's target.
            let addBlock = app.buttons["Add block"].firstMatch
            XCTAssertTrue(waitOrDumpTree(addBlock, in: app))
            XCTAssertGreaterThanOrEqual(addBlock.frame.width, 44, "a bar tool narrower than a finger")
            XCTAssertGreaterThanOrEqual(addBlock.frame.height, 44, "a bar tool shorter than a finger")
            addBlock.tap()
            let blocks = app.descendants(matching: .any)["keyboard-block-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(blocks, in: app), "+ panel did not open")
            attach(app, "plus-panel")
            // A swipe down is only ever the panel's scroll, scrolled into the catalog or back at its top (Notion's):
            // it never closes the panel.
            blocks.swipeUp(velocity: .fast)
            blocks.swipeDown(velocity: .slow)
            XCTAssertTrue(blocks.exists, "a swipe down inside the scrolled panel closed it")
            blocks.swipeDown(velocity: .fast)
            blocks.swipeDown(velocity: .fast)
            XCTAssertTrue(blocks.exists, "a swipe down at the panel's top closed it")
            // The keyboard button closes it (the keyboard back, or with a hardware keyboard nothing in its place).
            app.buttons["show-keyboard"].firstMatch.tap()
            let closed = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: closed, evaluatedWith: blocks)], timeout: 5)
            body.tap()
            XCTAssertTrue(waitOrDumpTree(addBlock, in: app), "the keyboard bar did not come back")
            addBlock.tap()
            XCTAssertTrue(waitOrDumpTree(blocks, in: app), "+ panel did not open again")
            app.buttons["keyboard-block-heading2"].firstMatch.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not come back")
            XCTAssertFalse(blocks.exists)
            body.typeText("Day one")
            XCTAssertTrue(waitOrDumpTree(app.webViews.staticTexts["Day one"].firstMatch, in: app), "heading text missing")

            // A software keyboard on screen (a phone): the panel takes its place — the keyboard goes, the bar stays above
            // the panel, and its keyboard button brings the keyboard back. A hardware keyboard (this simulator has one
            // attached; the software keyboard stays off screen): the panel still shows, and the keyboard button closes it.
            let keyboard = app.keyboards.firstMatch
            let softwareKeyboard = keyboard.exists && keyboard.frame.minY < app.frame.maxY - 1
            app.buttons["Format"].firstMatch.tap()
            let format = app.descendants(matching: .any)["keyboard-format-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(format, in: app), "Aa panel did not open")
            attach(app, "format-panel")
            let gone = NSPredicate(format: "exists == false")
            if softwareKeyboard {
                let noKeyboard = NSPredicate(format: "count == 0")
                wait(for: [expectation(for: noKeyboard, evaluatedWith: app.keyboards)], timeout: 5)
                let showKeyboard = app.buttons["show-keyboard"].firstMatch
                XCTAssertTrue(showKeyboard.isHittable, "the bar should stay above the Aa panel")
                showKeyboard.tap()
                wait(for: [expectation(for: gone, evaluatedWith: format)], timeout: 5)
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard did not come back after Aa")
            } else {
                format.swipeDown(velocity: .fast)
                XCTAssertTrue(format.exists, "a swipe down closed the Aa panel")
                app.buttons["show-keyboard"].firstMatch.tap()
                wait(for: [expectation(for: gone, evaluatedWith: format)], timeout: 5)
            }
        }

        /// On a phone a drawing is only looked at: "/" offers no Drawing, and one already in a page (imported here) opens
        /// in Excalidraw's view mode — no tools, no Library — with Close, which leaves the page as it was.
        func testDrawingIsReadOnlyOnAPhone() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
            continueAfterFailure = false
            let source = dataDir + "-drawing.html"
            let elements = #"[{"id":"r1","type":"rectangle","x":0,"y":0,"width":120,"height":80}]"#
            try "<h1>Sketch</h1><p>Before</p><div data-type=\"drawing\" data-elements='\(elements)'></div>"
                .write(toFile: source, atomically: true, encoding: .utf8)
            let app = launch(environment: ["HIKKI_IMPORT_FILE": source])
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30), "the imported page did not open")
            let block = app.webViews.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Drawing'")).firstMatch
            XCTAssertTrue(waitOrDumpTree(block, in: app), "the drawing block is missing")

            // No Drawing in the "/" menu here.
            app.webViews.staticTexts["Before"].firstMatch.tap()
            body.typeText("\n/drawing")
            XCTAssertTrue(waitOrDumpTree(app.webViews.otherElements["Excalidraw"].firstMatch, in: app), "no \"/\" menu")
            XCTAssertFalse(app.webViews.otherElements["Drawing"].exists, "\"/\" offers a Drawing on a phone")
            body.typeText(XCUIKeyboardKey.escape.rawValue)

            block.tap()
            let close = app.webViews.buttons["Close"].firstMatch
            XCTAssertTrue(waitOrDumpTree(close, in: app, timeout: 30), "the drawing did not open")
            attach(app, "drawing-read-only")
            XCTAssertFalse(app.webViews.buttons["Done"].exists, "a drawing opened to edit on a phone")
            XCTAssertFalse(app.webViews.otherElements["Rectangle"].exists, "Excalidraw's tools show on a phone")
            XCTAssertFalse(app.webViews.switches["Library"].exists, "Excalidraw's Library shows on a phone")
            close.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: close)], timeout: 5)
            XCTAssertTrue(block.exists, "the drawing block went away")
        }

        /// A drawing (an iPad — a phone only looks at drawings): "/" Drawing adds one and opens Excalidraw over the page
        /// (its fonts and code bundled, served by the app's scheme), without the Mac's Library; a rectangle drawn and
        /// Done leave the block showing the drawing's preview. Typing in it comes without the page's keyboard bar.
        func testDrawingOpensDrawsAndShowsItsPreview() throws {
            guard UIDevice.current.userInterfaceIdiom != .phone else { throw XCTSkip("drawings are read-only on a phone") }
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Sketch\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.tap()
            let barFormat = app.buttons["Format"].firstMatch
            XCTAssertTrue(barFormat.waitForExistence(timeout: 5), "the keyboard bar is missing on the page")
            // "/" Drawing (the + panel lists it too, a few pages in).
            body.typeText("/drawing")
            XCTAssertTrue(waitOrDumpTree(app.webViews.otherElements["Drawing"].firstMatch, in: app), "no Drawing in the \"/\" menu")
            body.typeText("\n")

            let done = app.webViews.buttons["Done"].firstMatch
            XCTAssertTrue(waitOrDumpTree(done, in: app, timeout: 30), "the drawing editor did not open")
            let rectangle = app.webViews.otherElements["Rectangle"].firstMatch
            XCTAssertTrue(waitOrDumpTree(rectangle, in: app), "Excalidraw's toolbar is missing")
            // The Library is the Mac's: no button for it here.
            XCTAssertFalse(app.webViews.switches["Library"].exists, "Excalidraw's Library shows on iOS")
            rectangle.tap()
            let window = app.windows.firstMatch
            let from = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            let to = window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.55))
            from.press(forDuration: 0.1, thenDragTo: to)
            // A text in the drawing: Excalidraw's own field takes the keyboard, and the page's bar stays away.
            let text = app.webViews.otherElements["Text"].firstMatch
            XCTAssertTrue(waitOrDumpTree(text, in: app), "Excalidraw's Text tool is missing")
            text.tap()
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.75)).tap()
            // A software keyboard comes up unless a hardware one is connected (a simulator's default on iPad).
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 3)
            app.typeText("Hi")
            attach(app, "drawing-editor")
            XCTAssertFalse(barFormat.exists, "the page's keyboard bar showed over the drawing")
            // A tap on the canvas ends the text.
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.3)).tap()
            wait(for: [expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: app.keyboards)], timeout: 5)
            done.tap()

            // The block is read out as "Drawing: <its words>" only once it shows its picture (empty, it is
            // "Empty drawing — …").
            let preview = app.webViews.buttons.matching(NSPredicate(format: "label == 'Drawing: Hi'")).firstMatch
            XCTAssertTrue(waitOrDumpTree(preview, in: app, timeout: 20), "the drawing's preview is not in the page")
            XCTAssertFalse(done.exists, "the drawing editor stayed open")
            XCTAssertGreaterThan(preview.frame.height, 20)
            attach(app, "drawing-preview")
        }

        /// With words selected (a Chinese keyboard offers them for conversion meanwhile), Aa still puts the software
        /// keyboard down for its panel; putting the keyboard away lets go of the selection.
        func testFormatPanelOnASelection() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("点点滴滴 hello world")
            let line = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'world'")).firstMatch
            XCTAssertTrue(waitOrDumpTree(line, in: app))
            line.doubleTap()
            attach(app, "selected")
            let keyboard = app.keyboards.firstMatch
            XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
            let softwareKeyboard = keyboard.frame.minY < app.frame.maxY - 1
            app.buttons["Format"].firstMatch.tap()
            let format = app.descendants(matching: .any)["keyboard-format-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(format, in: app), "Aa panel did not open")
            attach(app, "format-on-selection")
            if softwareKeyboard {
                let noKeyboard = NSPredicate(format: "count == 0")
                wait(for: [expectation(for: noKeyboard, evaluatedWith: app.keyboards)], timeout: 5)
            }
            // The bar shows B · I · U · S itself with a selection: the panel doesn't repeat them.
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Bold'")).count, 1, "the marks row repeated the bar's")

            // The colour tool has a panel of its own: the colours alone, Aa not marked.
            app.buttons["Colour"].firstMatch.tap()
            let colors = app.descendants(matching: .any)["keyboard-color-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(colors, in: app), "the colour panel did not open")
            XCTAssertFalse(format.exists, "Aa's panel stayed under the colour panel")
            XCTAssertFalse(app.buttons["Format"].firstMatch.isSelected, "Aa marked while the colour panel is open")
            XCTAssertTrue(app.buttons["Colour"].firstMatch.isSelected, "the colour tool isn't marked for its panel")
            attach(app, "color-panel")
        }

        /// Only the page paints a selection: UIKit's highlight, which fills the whole line box in the tint, never shows
        /// around the page's own paint (it showed as a grey band above the selected word).
        func testOnlyThePagePaintsASelection() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("Supercalifragilistic")
            let line = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Supercali'")).firstMatch
            XCTAssertTrue(waitOrDumpTree(line, in: app))
            line.doubleTap()
            // The selection's paint fades in (the block tint's motion).
            Thread.sleep(forTimeInterval: 1)
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "selection"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Looked for around the selected line only (the star and the edit menu are tinted too).
            let scale = shot.image.size.width * shot.image.scale / app.frame.width
            let around = line.frame.insetBy(dx: 0, dy: -20)
            let region = CGRect(
                x: around.minX * scale, y: around.minY * scale, width: around.width * scale, height: around.height * scale)
            // UIKit's highlight drawn over it greys the page's paint: then none of its own colour shows at all.
            let band = try XCTUnwrap(
                SelectionPixels(shot.image, in: region), "the page's selection paint is covered by another highlight")
            XCTAssertEqual(band.foreign, 0, "something other than the page paints the selection: \(band)")
        }

        /// A pinch never magnifies the page (it is an editor, not a document): the words keep their size.
        func testPinchDoesNotZoomThePage() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Zoom\n")
            app.typeText("The quick brown fox")
            app.buttons["hide-keyboard"].firstMatch.tap()
            let line = app.webViews.staticTexts["The quick brown fox"].firstMatch
            XCTAssertTrue(waitOrDumpTree(line, in: app))
            let before = line.frame
            app.webViews.firstMatch.pinch(withScale: 2.5, velocity: 1)
            sleep(1)
            let after = line.frame
            XCTAssertEqual(after.width, before.width, accuracy: 1, "the page zoomed under a pinch")
            XCTAssertEqual(after.height, before.height, accuracy: 1, "the page zoomed under a pinch")
        }

        /// Aa's panel takes the keyboard's place through the content view's input view (with a hardware keyboard too:
        /// this simulator has one), and the bar's ✕ brings the keyboard back for typing. Once the content view carries
        /// our runtime subclass it must still be found: before, the swap never ran and Aa left the keyboard where it was.
        func testFormatPanelTakesTheKeyboardsPlace() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("Hello world")
            // The keyboard bar is up (alone at the foot with this simulator's hardware keyboard): the page's floating
            // bar has stepped aside for it.
            XCTAssertFalse(app.buttons["ask-ai-page"].waitForExistence(timeout: 1), "the floating bar stayed under the keyboard bar")

            app.buttons["Format"].firstMatch.tap()
            let format = app.descendants(matching: .any)["keyboard-format-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(format, in: app), "Aa panel did not take the keyboard's place")
            attach(app, "format-in-keyboards-place")
            let showKeyboard = app.buttons["show-keyboard"].firstMatch
            XCTAssertTrue(showKeyboard.isHittable, "the bar should stay above the panel")
            showKeyboard.tap()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: format)], timeout: 5)
            body.typeText(" again")
            XCTAssertTrue(
                waitOrDumpTree(app.webViews.staticTexts["Hello world again"].firstMatch, in: app), "typing did not resume")
        }

        /// The system text size (Dynamic Type) reaches both halves of the screen: the page's words and the native bar.
        func testPageFollowsTheSystemTextSize() throws {
            continueAfterFailure = false
            func measure(_ app: XCUIApplication) -> (line: CGFloat, prompt: CGFloat) {
                let newPage = app.buttons["new-page"].firstMatch
                XCTAssertTrue(waitOrDumpTree(newPage, in: app))
                newPage.tap()
                let title = app.webViews.textViews["Page title"].firstMatch
                XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
                title.tap()
                title.typeText("Size\n")
                app.typeText("The quick brown fox")
                app.buttons["hide-keyboard"].firstMatch.tap()
                let line = app.webViews.staticTexts["The quick brown fox"].firstMatch
                XCTAssertTrue(waitOrDumpTree(line, in: app))
                let prompt = app.buttons["ask-ai-page"].firstMatch
                XCTAssertTrue(waitOrDumpTree(prompt, in: app), "the floating bar is missing")
                return (line.frame.height, prompt.staticTexts.firstMatch.frame.height)
            }
            var app = launch()
            let base = measure(app)
            app.terminate()
            app = launch(arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"])
            let large = measure(app)
            attach(app, "text-size-xxxl")
            XCTAssertGreaterThan(large.line, base.line * 1.2, "the page's words didn't follow the text size")
            XCTAssertGreaterThan(large.prompt, base.prompt * 1.15, "the native bar's words didn't follow the text size")
        }

        /// iPhone: the page's ⋯ sheet says what only Hikki can say — where the page's file lives and whose AI key is
        /// in use (a device workspace here, no key).
        func testPageSheetSaysWhereThePageLives() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Facts\n")
            let hide = app.buttons["hide-keyboard"].firstMatch
            if hide.waitForExistence(timeout: 3) { hide.tap() }
            app.buttons["page-more"].firstMatch.tap()
            XCTAssertTrue(
                waitOrDumpTree(app.staticTexts["On this device"].firstMatch, in: app), "the sheet doesn't say where the page lives")
            XCTAssertTrue(app.staticTexts["No key — Settings → AI"].firstMatch.exists, "the sheet doesn't say whose AI")
            attach(app, "page-sheet-facts")
        }

        /// iOS: the page's own menus draw SF Symbols (lib/sf-icons.ts) — the "/" menu, for a look at the glyphs beside
        /// the native chrome.
        func testPageMenusDrawSFGlyphsOnIOS() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Glyphs\n")
            // The list blocks: every one of them has a symbol (the headings keep Phosphor's H1–H4).
            app.typeText("/list")
            let row = app.webViews.otherElements["Bulleted list"].firstMatch
            XCTAssertTrue(waitOrDumpTree(row, in: app), "no \"/\" menu")
            attach(app, "slash-menu-sf-glyphs")
        }

        /// iPhone: the floating bar's Outline lists the page's headings in a sheet; one picked closes it.
        func testOutlineSheetOnAPhone() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Outline page\n")
            app.typeText("# First section\nSome words here.\n## Second section\nMore words.")
            app.buttons["hide-keyboard"].firstMatch.tap()
            let outline = app.buttons["open-inspector"].firstMatch
            XCTAssertTrue(waitOrDumpTree(outline, in: app), "the floating bar's Outline is missing")
            outline.tap()
            let row = app.buttons["outline-Second section"].firstMatch
            XCTAssertTrue(waitOrDumpTree(row, in: app), "the sheet did not list the headings")
            attach(app, "outline-sheet")
            row.tap()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: row)], timeout: 5)
        }

        /// The bar's AI and link fields are native, over the keyboard, on the word at the caret; ⋯ opens the block's
        /// actions as a sheet, whose Duplicate copies the block.
        func testKeyboardBarFieldsAndBlockActions() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("Hello world")

            app.buttons["Ask AI"].firstMatch.tap()
            let ai = app.descendants(matching: .any)["keyboard-ai-composer"].firstMatch
            XCTAssertTrue(waitOrDumpTree(ai, in: app), "the AI field did not open")
            XCTAssertTrue(app.buttons["keyboard-ai-improve"].firstMatch.exists, "AI's presets missing")
            attach(app, "ai-composer")
            app.buttons["keyboard-composer-close"].firstMatch.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: ai)], timeout: 5)

            // Link is a selection's tool: select "world" first (a tap gives the page its focus back, then the double tap
            // on the word selects it — the line's middle is the space between the words).
            let line = body.staticTexts["Hello world"].firstMatch
            XCTAssertTrue(waitOrDumpTree(line, in: app))
            let world = line.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
            world.tap()
            world.doubleTap()
            attach(app, "selected")
            let link = app.buttons["Link"].firstMatch
            XCTAssertTrue(waitOrDumpTree(link, in: app), "no Link with the word selected")
            link.tap()
            let field = app.textFields["keyboard-link-field"].firstMatch
            XCTAssertTrue(waitOrDumpTree(field, in: app), "the link field did not open")
            attach(app, "link-composer")
            field.typeText("https://example.com\n")
            XCTAssertTrue(app.webViews.links["world"].firstMatch.waitForExistence(timeout: 5), "the word at the caret wasn't linked")

            body.tap()
            app.buttons["More actions"].firstMatch.tap()
            let sheet = app.descendants(matching: .any)["block-actions-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the ⋯ sheet did not open")
            attach(app, "block-actions")
            app.buttons["block-action-duplicate"].firstMatch.tap()
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)
            let copies = NSPredicate(format: "count == 2")
            wait(for: [expectation(for: copies, evaluatedWith: app.webViews.links.matching(identifier: "world"))], timeout: 5)
        }

        /// ⋯ → Move to sends the caret's block to the end of the page picked: it leaves this page and is stored on
        /// that one.
        func testBlockActionsMoveABlockToAnotherPage() throws {
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
            continueAfterFailure = false
            let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30))
            let line = body.staticTexts["山へ行くんですか。"].firstMatch
            XCTAssertTrue(waitOrDumpTree(line, in: app))
            line.tap()
            app.buttons["More actions"].firstMatch.tap()
            let sheet = app.descendants(matching: .any)["block-actions-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the ⋯ sheet did not open")
            app.buttons["block-action-moveTo"].firstMatch.tap()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(waitOrDumpTree(search, in: app), "the page list has no search")
            search.tap()
            search.typeText("OKR")
            let target = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'block-move-'")).firstMatch
            XCTAssertTrue(waitOrDumpTree(target, in: app), "OKRs isn't offered")
            attach(app, "move-to")
            target.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)
            wait(for: [expectation(for: gone, evaluatedWith: line)], timeout: 10)
            attach(app, "moved-away")
            // It is on OKRs now, stored: open that page afresh.
            app.terminate()
            let again = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-250d3d"])
            let moved = again.webViews.staticTexts["山へ行くんですか。"].firstMatch
            XCTAssertTrue(waitOrDumpTree(moved, in: again, timeout: 30), "the block isn't on the page it moved to")
            XCTAssertTrue(again.webViews.staticTexts["OKRs"].firstMatch.exists, "a different page opened")
            attach(again, "moved")
        }

        /// The bar's comment opens a native field over the keyboard; the page stays where it was (the page's own sheet
        /// focusing its field scrolled the page to its end) and sending closes it.
        func testKeyboardBarCommentKeepsThePlace() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            for line in 1...30 { body.typeText("Line number \(line) of the page\n") }
            app.swipeDown(velocity: .fast)
            app.swipeDown(velocity: .fast)
            let line = app.webViews.staticTexts["Line number 3 of the page"].firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 5))
            line.doubleTap()

            app.buttons["Comment"].firstMatch.tap()
            let composer = app.descendants(matching: .any)["keyboard-comment-composer"].firstMatch
            XCTAssertTrue(waitOrDumpTree(composer, in: app), "the comment field did not open")
            attach(app, "comment-composer")
            XCTAssertFalse(app.webViews.textFields["Add a comment…"].exists, "the page's own comment sheet opened")
            XCTAssertTrue(line.isHittable, "the page scrolled away from the passage")
            XCTAssertFalse(app.menuItems["Copy"].exists, "the page's edit menu stayed over it")
            app.textFields["keyboard-comment-field"].firstMatch.typeText("Check this\n")
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: composer)], timeout: 5)
            attach(app, "comment-sent")
            // The comment's mark splits line 3 into pieces; the line above it stands for the place.
            XCTAssertTrue(
                app.webViews.staticTexts["Line number 2 of the page"].firstMatch.isHittable, "the page scrolled away after sending")
        }

        /// A tap on a commented passage (keyboard down) opens the thread in a native sheet, not the page's: a reply
        /// shows in it, and resolving closes it and takes the passage's highlight away.
        func testCommentThreadOpensInANativeSheet() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("Peak is mid November")
            let line = app.webViews.staticTexts["Peak is mid November"].firstMatch
            XCTAssertTrue(line.waitForExistence(timeout: 5))
            line.doubleTap()
            app.buttons["Comment"].firstMatch.tap()
            let field = app.textFields["keyboard-comment-field"].firstMatch
            XCTAssertTrue(waitOrDumpTree(field, in: app), "the comment field did not open")
            field.typeText("Check this\n")
            let hide = app.buttons["hide-keyboard"].firstMatch
            if hide.waitForExistence(timeout: 3) { hide.tap() }

            // The passage, now split by the comment's mark: tap the commented word.
            let passage = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS 'mid'")).firstMatch
            XCTAssertTrue(passage.waitForExistence(timeout: 5))
            passage.tap()
            let sheet = app.descendants(matching: .any)["comment-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the native thread sheet did not open")
            XCTAssertFalse(app.webViews.otherElements["comment-sheet"].exists, "the page's own sheet opened too")
            XCTAssertTrue(app.staticTexts["Check this"].firstMatch.exists, "the thread's first comment is missing")
            attach(app, "thread-sheet")

            let reply = app.textFields["comment-sheet-field"].firstMatch
            reply.tap()
            reply.typeText("Agreed\n")
            XCTAssertTrue(app.staticTexts["Agreed"].firstMatch.waitForExistence(timeout: 5), "the reply did not show")
            attach(app, "thread-replied")

            app.buttons["comment-sheet-resolve"].firstMatch.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)
        }

        /// The page ⋯ menu's Cover… opens the native cover sheet, not the page's: on a page without a cover its picker
        /// (a gradient picked becomes the cover), with one its actions (Remove takes it away).
        func testCoverSheetIsNative() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Trip\n")
            let hide = app.buttons["hide-keyboard"].firstMatch
            if hide.waitForExistence(timeout: 3) { hide.tap() }
            let gone = NSPredicate(format: "exists == false")

            func openCover() {
                app.buttons["page-more"].firstMatch.tap()
                let row = app.descendants(matching: .any)["page-cover"].firstMatch
                XCTAssertTrue(waitOrDumpTree(row, in: app), "Cover… missing from the page menu")
                row.tap()
            }

            openCover()
            let tabs = app.descendants(matching: .any)["cover-tabs"].firstMatch
            XCTAssertTrue(waitOrDumpTree(tabs, in: app), "the native picker did not open")
            XCTAssertFalse(app.webViews.otherElements["cover-sheet"].exists, "the page's own sheet opened too")
            attach(app, "cover-picker")
            app.buttons["cover-gradient-ocean"].firstMatch.tap()
            wait(for: [expectation(for: gone, evaluatedWith: tabs)], timeout: 5)

            // Now with a cover: its actions.
            openCover()
            let remove = app.buttons["cover-sheet-remove"].firstMatch
            XCTAssertTrue(waitOrDumpTree(remove, in: app), "the cover's actions did not open — the pick wasn't kept")
            XCTAssertTrue(app.buttons["cover-sheet-change"].firstMatch.exists)
            attach(app, "cover-actions")
            remove.tap()
            wait(for: [expectation(for: gone, evaluatedWith: remove)], timeout: 5)

            // Removed: the picker again.
            openCover()
            XCTAssertTrue(waitOrDumpTree(tabs, in: app), "the cover was not removed")
        }

        /// The page icon's picker on a phone is native: a search finds an emoji and picks it, Remove takes it off.
        func testIconPickerIsNative() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Pets\n")
            let hide = app.buttons["hide-keyboard"].firstMatch
            if hide.waitForExistence(timeout: 3) { hide.tap() }
            let gone = NSPredicate(format: "exists == false")

            let add = app.webViews.buttons["Add icon"].firstMatch
            XCTAssertTrue(waitOrDumpTree(add, in: app))
            add.tap()
            let change = app.webViews.buttons["Change icon"].firstMatch
            XCTAssertTrue(waitOrDumpTree(change, in: app))
            change.tap()
            let sheet = app.descendants(matching: .any)["icon-picker-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the native picker did not open")
            XCTAssertFalse(app.webViews.otherElements["icon-sheet"].exists, "the page's own sheet opened too")
            let search = app.textFields["icon-search"].firstMatch
            XCTAssertTrue(waitOrDumpTree(search, in: app))
            attach(app, "icon-picker")
            search.tap()
            search.typeText("dog face")
            let dog = app.buttons["dog face"].firstMatch
            XCTAssertTrue(waitOrDumpTree(dog, in: app), "the search found no dog")
            dog.tap()
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)

            // Picked: it is recent now, and Remove takes the icon off the page.
            change.tap()
            XCTAssertTrue(waitOrDumpTree(app.staticTexts["Recent"].firstMatch, in: app), "the pick isn't among the recent ones")
            let remove = app.buttons["icon-remove"].firstMatch
            XCTAssertTrue(remove.exists)
            remove.tap()
            XCTAssertTrue(waitOrDumpTree(add, in: app), "the icon was not removed")
        }

        /// "@tom" puts tomorrow's date; on a phone a tap on the chip opens the native sheet, whose reminder comes back
        /// to the chip — and Home lists it under Upcoming.
        func testDateMentionOpensANativeSheet() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Trip\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            body.typeText("Book the ryokan @tom")
            let remindRow = app.webViews.descendants(matching: .any)["Remind me Tomorrow"].firstMatch
            XCTAssertTrue(waitOrDumpTree(remindRow, in: app), "no date in the menu")
            attach(app, "date-menu")
            body.typeText("\n")
            let chip = app.webViews.descendants(matching: .any)["Tomorrow"].firstMatch
            XCTAssertTrue(waitOrDumpTree(chip, in: app), "no date chip")
            let hide = app.buttons["hide-keyboard"].firstMatch
            if hide.waitForExistence(timeout: 3) { hide.tap() }

            chip.tap()
            let sheet = app.descendants(matching: .any)["date-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the native date sheet did not open")
            XCTAssertFalse(app.webViews.otherElements["date-popover"].exists, "the page's own popover opened too")
            app.buttons["date-sheet-remind"].firstMatch.tap()
            let onTheDay = app.buttons["On the day (09:00)"].firstMatch
            XCTAssertTrue(waitOrDumpTree(onTheDay, in: app), "no reminder choices")
            onTheDay.tap()
            attach(app, "date-sheet")
            app.buttons["date-sheet-done"].firstMatch.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)

            // The chip took the reminder: the sheet opens on it again.
            chip.tap()
            XCTAssertTrue(waitOrDumpTree(sheet, in: app))
            XCTAssertTrue(app.buttons["date-sheet-mark-done"].firstMatch.exists, "the reminder didn't reach the chip")
            app.buttons["date-sheet-done"].firstMatch.tap()
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)

            app.navigationBars.buttons.element(boundBy: 0).tap()
            let upcoming = app.descendants(matching: .any)["upcoming-row"].firstMatch
            XCTAssertTrue(waitOrDumpTree(upcoming, in: app), "Home lists nothing upcoming")
            XCTAssertTrue(app.staticTexts["Book the ryokan"].firstMatch.exists)
            attach(app, "home-upcoming")
        }

        /// Photo opens our own sheet of sources (camera and scan only where the device has them), not the page's file
        /// input.
        func testKeyboardBarPhotoOpensTheMediaSheet() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Plan\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")

            app.buttons["Photo"].firstMatch.tap()
            let sheet = app.descendants(matching: .any)["media-source-sheet"].firstMatch
            XCTAssertTrue(waitOrDumpTree(sheet, in: app), "the media sheet did not open")
            XCTAssertTrue(app.buttons["media-source-library"].firstMatch.exists, "Photos missing")
            XCTAssertTrue(app.buttons["media-source-files"].firstMatch.exists, "Files missing")
            attach(app, "media-sheet")
            sheet.swipeDown(velocity: .fast)
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: sheet)], timeout: 5)
        }

        private func attach(_ app: XCUIApplication, _ name: String) {
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = name
            shot.lifetime = .keepAlways
            add(shot)
        }
    #endif

    func testSlashMenuInsertsTodoList() throws {
        continueAfterFailure = false
        let app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()

        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Plan\n")
        // Type into the body once it's there: keystrokes sent while focus is still moving from the title
        // were occasionally lost (flaky on the simulator).
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
        body.tap()
        body.typeText("/todo")

        let item = app.webViews.descendants(matching: .any)["To-do list"].firstMatch
        XCTAssertTrue(waitOrDumpTree(item, in: app), "slash menu did not show the To-do item")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "slash-menu"
        shot.lifetime = .keepAlways
        add(shot)
        item.tap()

        XCTAssertTrue(waitOrDumpTree(app.webViews.switches.firstMatch, in: app), "to-do checkbox not inserted")
        XCTAssertFalse(app.webViews.descendants(matching: .any)["To-do list"].exists, "menu should close after choosing")
    }

    /// The page's ⋯ menu opens find in page (⌘F does too, with a keyboard: covered by the editor's unit tests — the
    /// simulator's software keyboard doesn't deliver ⌘ shortcuts). On the Mac the page's panel; on the iPhone a native
    /// bar (ISSUE-225) whose typing searches the page, whose ‹ › step the matches and whose Done closes it.
    func testFindInPageFromPageMenu() throws {
        continueAfterFailure = false
        let app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Find me\n")
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
        body.typeText("find me twice: me")

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        let item = app.buttons["find-in-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(item, in: app), "no Find in Page item")
        item.tap()
        #if os(iOS)
            let field = app.textFields["find-bar-field"].firstMatch
            XCTAssertTrue(waitOrDumpTree(field, in: app), "the native find bar did not open")
            XCTAssertFalse(app.webViews.textFields["Find"].firstMatch.exists, "the page's own find panel opened too")
            // The bar takes the keyboard; the floating bar steps aside.
            XCTAssertFalse(app.buttons["edit-page"].firstMatch.exists, "the floating bar stayed under the find bar")
            field.typeText("me")
            let count = app.staticTexts["find-bar-count"].firstMatch
            XCTAssertTrue(waitOrDumpTree(count, in: app), "no count beside the term")
            let twoMatches = NSPredicate(format: "label == '1 / 2'")
            wait(for: [expectation(for: twoMatches, evaluatedWith: count)], timeout: 10)
            attach(app, "find-bar")
            app.buttons["find-bar-next"].firstMatch.tap()
            wait(for: [expectation(for: NSPredicate(format: "label == '2 / 2'"), evaluatedWith: count)], timeout: 10)
            app.buttons["find-bar-previous"].firstMatch.tap()
            wait(for: [expectation(for: twoMatches, evaluatedWith: count)], timeout: 10)
            app.buttons["find-bar-done"].firstMatch.tap()
            wait(for: [expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: field)], timeout: 10)
            XCTAssertTrue(waitOrDumpTree(app.buttons["edit-page"].firstMatch, in: app), "the floating bar did not come back")
        #else
            let field = app.webViews.textFields["Find"].firstMatch
            XCTAssertTrue(waitOrDumpTree(field, in: app), "find panel did not open")
            // The panel sits below the toolbar (window.hikki.setInsets), not under its glass.
            XCTAssertGreaterThan(field.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1, "find panel under the toolbar")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "find-panel"
            shot.lifetime = .keepAlways
            add(shot)
        #endif
    }

    #if os(iOS)
        /// A formula is edited in a native card over the keyboard on the iPhone (ISSUE-225): "+" → Block equation
        /// opens it for the new block, Done keeps what was typed (the page file carries it); a second one cancelled goes
        /// away again.
        func testFormulaOpensANativeComposer() throws {
            continueAfterFailure = false
            let app = launch()
            let newPage = app.buttons["new-page"].firstMatch
            XCTAssertTrue(waitOrDumpTree(newPage, in: app))
            newPage.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
            title.tap()
            title.typeText("Math\n")
            let body = app.webViews.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app), "body missing")
            // A line of words first, so the caret has a line to come back to beside the equations.
            body.tap()
            body.typeText("Area\n")

            let addBlock = app.buttons["Add block"].firstMatch
            XCTAssertTrue(waitOrDumpTree(addBlock, in: app))
            addBlock.tap()
            let blocks = app.descendants(matching: .any)["keyboard-block-panel"].firstMatch
            XCTAssertTrue(waitOrDumpTree(blocks, in: app), "+ panel did not open")
            let equation = app.buttons["keyboard-block-blockMath"].firstMatch
            if !equation.exists { blocks.swipeUp() }
            XCTAssertTrue(waitOrDumpTree(equation, in: app), "no Block equation in the + panel")
            equation.tap()

            let card = app.descendants(matching: .any)["math-composer"].firstMatch
            XCTAssertTrue(waitOrDumpTree(card, in: app), "the formula card did not open")
            XCTAssertFalse(app.webViews.textViews["Formula (LaTeX)"].firstMatch.exists, "the page's own formula panel opened too")
            let field = app.descendants(matching: .any)["math-composer-field"].firstMatch
            XCTAssertTrue(waitOrDumpTree(field, in: app), "no source field")
            field.tap()
            field.typeText("x^2")
            attach(app, "math-composer")
            app.buttons["math-composer-done"].firstMatch.tap()
            let gone = NSPredicate(format: "exists == false")
            wait(for: [expectation(for: gone, evaluatedWith: card)], timeout: 10)
            XCTAssertTrue(waitForPageFile(containing: "\"latex\":\"x^2\""), "the formula never reached the page file")

            // A second equation, cancelled: nothing of it stays. The caret goes back to the words (a tap on the
            // equation would open its card again); the page scrolled for the card, so it comes back up first.
            app.webViews.firstMatch.swipeDown()
            body.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 40, dy: 14)).tap()
            XCTAssertTrue(waitOrDumpTree(addBlock, in: app), "the keyboard bar did not come back")
            addBlock.tap()
            XCTAssertTrue(waitOrDumpTree(blocks, in: app), "+ panel did not open again")
            if !equation.exists { blocks.swipeUp() }
            XCTAssertTrue(waitOrDumpTree(equation, in: app))
            equation.tap()
            XCTAssertTrue(waitOrDumpTree(card, in: app), "the formula card did not open again")
            app.buttons["math-composer-cancel"].firstMatch.tap()
            wait(for: [expectation(for: gone, evaluatedWith: card)], timeout: 10)
            sleep(3)
            XCTAssertEqual(pageFileOccurrences(of: "\"type\":\"blockMath\""), 1, "the cancelled equation stayed")
        }

        /// Whether any page file under the test's data directory holds `needle` within the autosave's time.
        private func waitForPageFile(containing needle: String, timeout: TimeInterval = 15) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if pageFileOccurrences(of: needle) > 0 { return true }
                sleep(1)
            }
            return false
        }

        /// How often `needle` occurs across the page files under the test's data directory.
        private func pageFileOccurrences(of needle: String) -> Int {
            let pages = URL(fileURLWithPath: dataDir).appending(path: "Workspace/pages")
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: pages.path) else { return 0 }
            return names.reduce(0) { total, name in
                guard let text = try? String(contentsOf: pages.appending(path: name), encoding: .utf8) else { return total }
                // The file is pretty-printed; the needle is written without spaces.
                return total + text.filter { !$0.isWhitespace }.components(separatedBy: needle).count - 1
            }
        }
    #endif

    /// Page ⋯ → Lock page: a lock appears in the toolbar and the page is read-only; the lock unlocks it again.
    func testLockPageFromPageMenu() throws {
        continueAfterFailure = false
        let app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Keep")

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        let lock = app.buttons["lock-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(lock, in: app), "no Lock page item")
        lock.tap()
        let indicator = app.buttons["lock-indicator"].firstMatch
        XCTAssertTrue(waitOrDumpTree(indicator, in: app), "no lock in the toolbar")
        // The menu now offers to unlock; the toolbar lock does the same.
        more.tap()
        XCTAssertTrue(waitOrDumpTree(app.buttons["lock-toggle"].firstMatch, in: app))
        XCTAssertEqual(app.buttons["lock-toggle"].firstMatch.label, "Unlock page")
        app.buttons["lock-toggle"].firstMatch.tap()
        XCTAssertTrue(indicator.waitForNonExistence(timeout: 5), "lock stayed after unlocking")
        // Editable again (the caret may land at either end; typing getting through is the point).
        title.tap()
        title.typeText(" going")
        XCTAssertTrue(waitOrDumpTree(app.webViews.textViews["Page title"].firstMatch, in: app))
        XCTAssertTrue(
            (title.value as? String)?.contains("going") == true,
            "title not editable after unlocking: \(String(describing: title.value))")
    }

    /// Page ⋯ → Page History…: an earlier version is listed with its preview, and restoring it puts it back.
    /// A one-second session (`HIKKI_HISTORY_INTERVAL`) instead of ten minutes, so the second edit keeps the first.
    func testPageHistoryRestoresAnEarlierVersion() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_HISTORY_INTERVAL": "1"])
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Alpha")
        sleep(3)  // saved, and the session is over
        title.typeText(" Beta")
        sleep(3)  // this save keeps "Alpha" as a version
        XCTAssertEqual(title.value as? String, "Alpha Beta")

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        let history = app.buttons["page-history"].firstMatch
        XCTAssertTrue(waitOrDumpTree(history, in: app), "no Page History item")
        history.tap()
        let version = app.descendants(matching: .any)["history-version-0"].firstMatch
        XCTAssertTrue(waitOrDumpTree(version, in: app), "no version listed")
        version.tap()  // a sheet on iPad is compact: the list pushes the version
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Alpha"].firstMatch, in: app), "preview doesn't show the version")
        attachScreenshot(app, "page-history")
        let restore = app.buttons["history-restore"].firstMatch
        XCTAssertTrue(waitOrDumpTree(restore, in: app))
        restore.tap()
        XCTAssertTrue(restore.waitForNonExistence(timeout: 5), "history stayed open after restoring")
        let restored = NSPredicate(format: "value == %@", "Alpha")
        wait(for: [expectation(for: restored, evaluatedWith: app.webViews.textViews["Page title"].firstMatch)], timeout: 10)

        // Restoring kept the page as it was: "Alpha Beta" is now a version too.
        more.tap()
        XCTAssertTrue(waitOrDumpTree(history, in: app))
        history.tap()
        let newest = app.descendants(matching: .any)["history-version-0"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newest, in: app))
        newest.tap()
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Alpha Beta"].firstMatch, in: app), "the restored-over page wasn't kept")
    }

    /// Page ⋯ → Export → Markdown writes the page (`HIKKI_EXPORT_DIR` skips the save panel, which runs out of
    /// process), and a Markdown file imports as a new page (`HIKKI_IMPORT_FILE`, the file picker's stand-in).
    func testExportAndImportMarkdown() throws {
        continueAfterFailure = false
        let exportDir = dataDir + "-export"
        try FileManager.default.createDirectory(atPath: exportDir, withIntermediateDirectories: true)
        var app = launch(environment: ["HIKKI_EXPORT_DIR": exportDir])
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let field = app.webViews.textViews["Page title"].firstMatch
        // A cold simulator takes a while to start the web content process.
        XCTAssertTrue(waitOrDumpTree(field, in: app, timeout: 30), "editor never became editable")
        field.tap()
        field.typeText("Exported")
        sleep(1)
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app))
        body.tap()
        body.typeText("Hello world")
        sleep(1)

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        let export = app.buttons["page-export"].firstMatch
        XCTAssertTrue(waitOrDumpTree(export, in: app), "no Export menu")
        export.tap()
        let markdown = app.buttons["export-markdown"].firstMatch
        XCTAssertTrue(waitOrDumpTree(markdown, in: app), "no Markdown item")
        markdown.tap()
        let file = exportDir + "/Exported.md"
        let written = expectation(for: NSPredicate { _, _ in FileManager.default.fileExists(atPath: file) }, evaluatedWith: nil)
        wait(for: [written], timeout: 10)
        let text = try String(contentsOfFile: file, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("# Exported\n"), text)
        XCTAssertTrue(text.contains("Hello world"), text)

        app.terminate()
        let source = dataDir + "-import.md"
        try "# Imported note\n\nSome **bold** text.\n".write(toFile: source, atomically: true, encoding: .utf8)
        app = launch(environment: ["HIKKI_IMPORT_FILE": source])
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app, timeout: 15))
        let opened = NSPredicate(format: "value == %@", "Imported note")
        wait(for: [expectation(for: opened, evaluatedWith: title)], timeout: 10)
        XCTAssertTrue(waitOrDumpTree(app.webViews.staticTexts["bold"].firstMatch, in: app), "imported body missing")
        backToSidebarIfNeeded(app)
        openDrawerIfNeeded(app)
        let row = app.descendants(matching: .any)["page-row-Imported note"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app), "imported page missing from the sidebar")
    }

    /// A big workspace (500 top-level pages, `HIKKI_DEMO_PAGES`): typing in a page saves it every couple of seconds and
    /// so changes the page tree, which must not make the sidebar's rows draw themselves again — only the sidebar's own
    /// list (a cheap flattening) re-runs. Counts come from `HIKKI_DEBUG_SIDEBAR_STATS`; they are printed
    /// ("sidebar-stats") for before/after comparisons.
    func testSidebarRowsStayPutWhileTyping() throws {
        continueAfterFailure = false
        let statsFile = dataDir + "-sidebar-stats.json"
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "500", "HIKKI_DEBUG_SIDEBAR_STATS": statsFile])
        guard app.buttons["nav-home"].waitForExistence(timeout: 15) else {
            throw XCTSkip("needs the page sidebar — run on iPad or Mac")
        }
        let first = app.descendants(matching: .any)["page-row-Page 001"].firstMatch
        XCTAssertTrue(waitOrDumpTree(first, in: app, timeout: 20))
        func stats() -> (sidebar: Int, rows: Int, cells: Int) {
            let data = (try? Data(contentsOf: URL(filePath: statsFile))) ?? Data()
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Int] ?? [:]
            return (json["sidebar"] ?? 0, json["rows"] ?? 0, json["cells"] ?? 0)
        }
        sleep(2)
        let launched = stats()
        // Flicks through the list and back, from fixed points in the sidebar (rows scroll away under the pointer).
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let low = origin.withOffset(CGVector(dx: first.frame.midX, dy: first.frame.midY + 400))
        let high = origin.withOffset(CGVector(dx: first.frame.midX, dy: first.frame.midY + 40))
        for _ in 0..<8 { low.press(forDuration: 0.05, thenDragTo: high, withVelocity: .fast, thenHoldForDuration: 0) }
        for _ in 0..<8 { high.press(forDuration: 0.05, thenDragTo: low, withVelocity: .fast, thenHoldForDuration: 0) }
        sleep(2)
        let scrolled = stats()

        first.tap()
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30), "editor never became editable")
        body.tap()
        sleep(3)
        let opened = stats()
        for word in ["alpha ", "beta ", "gamma ", "delta ", "epsilon "] {
            body.typeText(word)
            sleep(3)  // past the save debounce: each word is a save, a tree change
        }
        let typed = stats()
        let report =
            "sidebar-stats launch rows=\(launched.rows) cells=\(launched.cells) sidebar=\(launched.sidebar); "
            + "scroll rows=\(scrolled.rows - launched.rows) cells=\(scrolled.cells - launched.cells) "
            + "sidebar=\(scrolled.sidebar - launched.sidebar); "
            + "open rows=\(opened.rows - scrolled.rows) cells=\(opened.cells - scrolled.cells) "
            + "sidebar=\(opened.sidebar - scrolled.sidebar); "
            + "typing rows=\(typed.rows - opened.rows) cells=\(typed.cells - opened.cells) "
            + "sidebar=\(typed.sidebar - opened.sidebar)"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "sidebar-stats"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(typed.sidebar, opened.sidebar, "the saves never reached the sidebar — nothing measured")
        // The edited page's own row may redraw (its word count / edited time ride along); the other rows must not.
        XCTAssertLessThanOrEqual(typed.rows - opened.rows, 10, report)
        XCTAssertLessThanOrEqual(typed.cells - opened.cells, 10, report)
        // Opening a page moves the selection: the row it leaves and the row it lands on, nothing else.
        XCTAssertLessThanOrEqual(opened.cells - scrolled.cells, 6, report)
    }

    /// Selecting in a page and collapsing the selection again must not re-run the window's body (ISSUE-261: read there,
    /// each selection change rebuilt the whole window — about a second on a long page in a Debug build). Counts come
    /// from `HIKKI_DEBUG_SIDEBAR_STATS` ("windows").
    func testSelectingDoesNotRedrawTheWindow() throws {
        continueAfterFailure = false
        let statsFile = dataDir + "-window-stats.json"
        let app = launch(environment: [
            "HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8", "HIKKI_DEBUG_SIDEBAR_STATS": statsFile,
        ])
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30), "editor never became editable")
        func windows() -> Int {
            let data = (try? Data(contentsOf: URL(filePath: statsFile))) ?? Data()
            return ((try? JSONSerialization.jsonObject(with: data)) as? [String: Int])?["windows"] ?? 0
        }
        let word = body.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.08))
        word.tap()
        sleep(3)
        let before = windows()
        XCTAssertGreaterThan(before, 0, "no counts written — nothing measured")
        for _ in 0..<3 {
            word.doubleTap()  // a word selected
            sleep(1)
            word.tap()  // collapsed again
            sleep(1)
        }
        let report = "window bodies while selecting: \(windows() - before)"
        let attachment = XCTAttachment(string: report)
        attachment.name = "window-stats"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(windows() - before, 0, report)
    }

    /// An attachment opened from a page shows over it (a sheet / full-screen cover), not in a tab of its own; Close
    /// brings the page back (`HIKKI_SHOW_FILE` stands in for clicking the attachment; the file is missing, so the
    /// viewer says so).
    func testAttachmentOpensOverThePage() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_SHOW_FILE": "missing.pdf"])
        let close = app.buttons["pdf-sheet-close"].firstMatch
        XCTAssertTrue(waitOrDumpTree(close, in: app, timeout: 15), "the viewer did not open over the page")
        XCTAssertFalse(app.descendants(matching: .any)["tab-missing.pdf"].exists, "the file opened as a tab")
        close.tap()
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: close)
        wait(for: [gone], timeout: 10)
    }

    /// A page's Import… (its context menu) takes several files at once and makes them its subpages
    /// (`HIKKI_PICK_FILES` stands in for the file picker).
    func testImportIntoAPage() throws {
        continueAfterFailure = false
        let first = dataDir + "-child-a.md"
        let second = dataDir + "-child-b.md"
        try "# Child A\n\nOne.\n".write(toFile: first, atomically: true, encoding: .utf8)
        try "# Child B\n\nTwo.\n".write(toFile: second, atomically: true, encoding: .utf8)
        let app = launch(environment: ["HIKKI_PICK_FILES": "\(first)|\(second)"])
        createPage(app, title: "Parent")
        backToSidebarIfNeeded(app)
        openDrawerIfNeeded(app)
        let row = app.descendants(matching: .any)["page-row-Parent"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app))
        #if os(macOS)
            row.rightClick()
            let item = app.menuItems["page-import"].firstMatch
        #else
            row.press(forDuration: 1.0)
            // iOS context menus keep an item's label, not its identifier.
            let item = app.buttons["Import into Page…"].firstMatch
        #endif
        XCTAssertTrue(waitOrDumpTree(item, in: app), "no Import… in the page menu")
        item.tap()
        backToSidebarIfNeeded(app)
        openDrawerIfNeeded(app)
        for title in ["Child A", "Child B"] {
            let child = app.descendants(matching: .any)["page-row-\(title)"].firstMatch
            XCTAssertTrue(waitOrDumpTree(child, in: app, timeout: 15), "\(title) was not imported")
            // The Mac/iPad tree names each row's outline level (the iPhone drawer's rows don't).
            if let level = child.value as? String, level.hasPrefix("level") {
                XCTAssertEqual(level, "level 2", "\(title) is not a subpage")
            }
        }
    }

    /// Settings → Import & Export, by its launch stand-ins for the pickers: a folder imports as a page tree (a folder
    /// is a page, `Trip.md` beside `Trip/` is that folder's page), and the workspace exports as JSON mirroring it.
    func testBulkImportThenExportMirrorsTheTree() throws {
        continueAfterFailure = false
        let fm = FileManager.default
        let source = dataDir + "-bulk"
        let exportDir = dataDir + "-bulk-export"
        try fm.createDirectory(atPath: source + "/Trip", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: source + "/Recipes", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: exportDir, withIntermediateDirectories: true)
        try "# Trip\n\nPlans.\n".write(toFile: source + "/Trip.md", atomically: true, encoding: .utf8)
        try "# Day one\n\nMuseum.\n".write(toFile: source + "/Trip/Day 1.md", atomically: true, encoding: .utf8)
        try "<h1>Soup</h1><p>Miso.</p>".write(toFile: source + "/Recipes/Soup.html", atomically: true, encoding: .utf8)

        let app = launch(environment: ["HIKKI_BULK_IMPORT": source, "HIKKI_BULK_EXPORT": "json|" + exportDir])
        openDrawerIfNeeded(app)
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["page-row-Trip"].firstMatch, in: app, timeout: 30))
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["page-row-Recipes"].firstMatch, in: app))

        // The export: one new folder in the destination, the tree inside it.
        var folder: String?
        let written = expectation(
            for: NSPredicate { _, _ in
                guard let name = try? fm.contentsOfDirectory(atPath: exportDir).first else { return false }
                folder = exportDir + "/" + name
                return fm.fileExists(atPath: exportDir + "/" + name + "/Recipes/Soup.json")
                    && fm.fileExists(atPath: exportDir + "/" + name + "/Trip/Day one.json")
            }, evaluatedWith: nil)
        wait(for: [written], timeout: 20)
        let root = try XCTUnwrap(folder)
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: root).sorted(), ["Recipes", "Recipes.json", "Trip", "Trip.json"])
        let day = try String(contentsOfFile: root + "/Trip/Day one.json", encoding: .utf8)
        XCTAssertTrue(day.contains("Museum."), day)
    }

    /// An export's Markdown comes back as it was: siblings in their order, not by name; the front matter isn't page
    /// text; and a link to a page that had to take a new id here (its own is a demo page's) follows it.
    func testBulkMarkdownImportKeepsOrderAndLinks() throws {
        continueAfterFailure = false
        let fm = FileManager.default
        let source = dataDir + "-bulk-md"
        let exportDir = dataDir + "-bulk-md-export"
        try fm.createDirectory(atPath: source, withIntermediateDirectories: true)
        try fm.createDirectory(atPath: exportDir, withIntermediateDirectories: true)
        let taken = "demo-95cb6b3a"  // "Travel" among the demo pages
        try "---\nhikki-id: \(taken)\nhikki-order: 0\n---\n\n# Zebra\n\nStripes.\n"
            .write(toFile: source + "/Zebra.md", atomically: true, encoding: .utf8)
        try "---\nhikki-id: apple-1\nhikki-order: 1\n---\n\n# Apple\n\nSee [Zebra](hikki://page/\(taken)).\n"
            .write(toFile: source + "/Apple.md", atomically: true, encoding: .utf8)

        let app = launch(environment: [
            "HIKKI_DEMO_PAGES": "1", "HIKKI_BULK_IMPORT": source, "HIKKI_BULK_EXPORT": "json|" + exportDir,
        ])
        openDrawerIfNeeded(app)
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["page-row-Apple"].firstMatch, in: app, timeout: 30))

        var folder: String?
        let written = expectation(
            for: NSPredicate { _, _ in
                guard let name = try? fm.contentsOfDirectory(atPath: exportDir).first else { return false }
                folder = exportDir + "/" + name
                return fm.fileExists(atPath: exportDir + "/" + name + "/Apple.json")
            }, evaluatedWith: nil)
        wait(for: [written], timeout: 20)
        func page(_ name: String) throws -> (fields: [String: Any], text: String) {
            let data = try Data(contentsOf: URL(filePath: try XCTUnwrap(folder) + "/" + name + ".json"))
            let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            return (fields, String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\\/", with: "/"))
        }
        let zebra = try page("Zebra")
        let apple = try page("Apple")
        let zebraID = try XCTUnwrap(zebra.fields["id"] as? String)
        XCTAssertNotEqual(zebraID, taken, "the demo page's id was taken over")
        XCTAssertEqual(apple.fields["id"] as? String, "apple-1", "a free id wasn't kept")
        XCTAssertLessThan(
            try XCTUnwrap(zebra.fields["sortKey"] as? Double), try XCTUnwrap(apple.fields["sortKey"] as? Double),
            "siblings came back by name")
        XCTAssertTrue(apple.text.contains("hikki://page/\(zebraID)"), apple.text)
        XCTAssertFalse(zebra.text.contains("hikki-id"), "the front matter became page text")
    }

    /// Regression: on iPhone, tag-based List selection didn't navigate; rows must be NavigationLinks.
    func testSidebarRowsNavigate() throws {
        continueAfterFailure = false
        let app = launch()
        // The sidebar's place: an icon on Mac/iPad, a row on iPhone — the same identifier.
        let trashRow = app.descendants(matching: .any)["nav-trash"].firstMatch
        XCTAssertTrue(waitOrDumpTree(trashRow, in: app))
        tapWhenSettled(trashRow)
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Trash is empty"].firstMatch, in: app), "Trash row did not navigate")
        backToSidebarIfNeeded(app)
        tapWhenSettled(app.descendants(matching: .any)["nav-home"].firstMatch)
        XCTAssertTrue(waitOrDumpTree(app.buttons["home-new-page"].firstMatch, in: app), "Home row did not navigate")
    }

    func testFavoriteTrashAndRestore() throws {
        continueAfterFailure = false
        let app = launch()
        createPage(app, title: "Trash me")

        let favorite = app.buttons["favorite-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(favorite, in: app))
        favorite.tap()

        app.buttons["page-more"].firstMatch.tap()
        let trash = app.buttons["Move to Trash"].firstMatch
        XCTAssertTrue(waitOrDumpTree(trash, in: app), "Move to Trash missing from the page menu")
        trash.tap()
        // It asks first (TrashConfirmation): the dialog names the page, and its own Move to Trash confirms — an alert
        // on iOS (over the iPhone's ⋯ sheet, whose row has the same label), a sheet on the Mac.
        XCTAssertTrue(
            waitOrDumpTree(app.staticTexts["Move “Trash me” to Trash?"].firstMatch, in: app),
            "Move to Trash did not ask first")
        let dialog = app.alerts.count > 0 ? app.alerts.firstMatch : app.sheets.firstMatch
        let confirm = dialog.buttons["Move to Trash"].firstMatch
        XCTAssertTrue(waitOrDumpTree(confirm, in: app), "the confirmation has no Move to Trash")
        confirm.tap()

        // The page leaves the tree (and favorites) and shows up in Trash.
        backToSidebarIfNeeded(app)
        // The sidebar's place: an icon on Mac/iPad, a row on iPhone — the same identifier.
        let trashRow = app.descendants(matching: .any)["nav-trash"].firstMatch
        XCTAssertTrue(waitOrDumpTree(trashRow, in: app))
        tapWhenSettled(trashRow)
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Trash me"].firstMatch, in: app), "trashed page not listed in Trash")
        attachScreenshot(app, "trash")
        app.buttons["Restore"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Trash is empty"].firstMatch, in: app))
    }

    /// Move to: the page menu opens Notion's picker — a search, a pick — and the page moves inside the page picked;
    /// opened again, the workspace row offers the top level, which it no longer is at.
    func testMoveToPicksAPageBySearch() throws {
        continueAfterFailure = false
        let app = launch()
        createPage(app, title: "Move target")
        backToSidebarIfNeeded(app)
        createPage(app, title: "Move me")

        openMovePicker(app)
        let top = app.descendants(matching: .any)["move-target-top"].firstMatch
        XCTAssertTrue(waitOrDumpTree(top, in: app))
        XCTAssertFalse(top.label.contains("Top level"), "a top-level page was offered the top level")
        let field = app.textFields["move-search"].firstMatch
        XCTAssertTrue(waitOrDumpTree(field, in: app))
        tapWhenSettled(field)  // iPhone: the field doesn't take the keyboard by itself
        field.typeText("target")
        let hit = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'move-target-' AND label CONTAINS 'Move target'")
        ).firstMatch
        XCTAssertTrue(waitOrDumpTree(hit, in: app), "the picker's search did not find the page")
        attachScreenshot(app, "move-picker")
        hit.tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "the picker stayed up after a pick")

        openMovePicker(app)
        XCTAssertTrue(waitOrDumpTree(top, in: app))
        XCTAssertTrue(top.label.contains("Top level"), "the moved page still reads as top level")
    }

    /// The open page's ⋯ → Move to.
    private func openMovePicker(_ app: XCUIApplication) {
        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        // iPadOS menus drop the item's identifier: there it is found by its (English) title.
        let move = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'page-move' OR (identifier == '' AND label == 'Move to')")
        ).firstMatch
        XCTAssertTrue(waitOrDumpTree(move, in: app))
        move.tap()
    }

    func testSearchFindsChineseTitleByPinyinInitials() throws {
        continueAfterFailure = false
        let app = launch()
        createPage(app, title: "产品路线图")
        backToSidebarIfNeeded(app)

        let search = app.buttons["sidebar-search"].firstMatch
        XCTAssertTrue(waitOrDumpTree(search, in: app))
        search.tap()
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(waitOrDumpTree(field, in: app))
        field.typeText("cplxt")
        let hit = app.staticTexts["产品路线图"].firstMatch
        XCTAssertTrue(waitOrDumpTree(hit, in: app), "pinyin-initials search did not find the page")
        attachScreenshot(app, "search")
        hit.tap()
        XCTAssertTrue(waitOrDumpTree(app.buttons["favorite-toggle"].firstMatch, in: app), "page did not open from search")
    }

    /// Mac/iPad: a favorite keeps its own row in the tree too. The two lists share one lazy stack, and with the same
    /// ids the tree's row came out blank.
    func testFavoriteStaysInTheTree() throws {
        continueAfterFailure = false
        // The demo pages start with a favorite (日本語を勉強する, at the top level), so both lists hold it from launch.
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1"])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the custom (regular-width) sidebar — run on iPad or Mac")
        }
        let row = app.descendants(matching: .any)["page-row-日本語を勉強する"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app), "the favorite's row left the tree")
        XCTAssertTrue(row.isHittable, "the favorite's row in the tree is drawn empty")
        attachScreenshot(app, "favorite-in-tree")
    }

    /// iPad (custom sidebar): drag a page onto another to nest it, then onto the top edge to move it back
    /// out in front. Nesting is read from each row's accessibility value ("level N").
    func testSidebarDragNestsAndReorders() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the custom (regular-width) sidebar — run on iPad or Mac")
        }
        createPage(app, title: "Alpha")
        createPage(app, title: "Beta")
        let alpha = app.descendants(matching: .any)["page-row-Alpha"].firstMatch
        let beta = app.descendants(matching: .any)["page-row-Beta"].firstMatch
        XCTAssertTrue(waitOrDumpTree(beta, in: app))
        XCTAssertEqual(beta.value as? String, "level 1")

        // Middle of Alpha → Beta becomes its child (indented, listed after Alpha).
        // Lift, then move slowly and hold over the target — like a person; a fast move after a long
        // press just leaves the context menu open on touch devices.
        beta.press(forDuration: 0.6, thenDragTo: alpha, withVelocity: .slow, thenHoldForDuration: 0.6)
        let nested = NSPredicate { _, _ in (beta.value as? String) == "level 2" && beta.frame.minY > alpha.frame.minY }
        wait(for: [expectation(for: nested, evaluatedWith: nil)], timeout: 5)
        attachScreenshot(app, "drag-nested")

        // Top edge of Alpha → Beta goes before Alpha at the top level.
        let topEdge = alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
        beta.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.6, thenDragTo: topEdge, withVelocity: .slow, thenHoldForDuration: 0.6)
        let reordered = NSPredicate { _, _ in (beta.value as? String) == "level 1" && beta.frame.minY < alpha.frame.minY }
        wait(for: [expectation(for: reordered, evaluatedWith: nil)], timeout: 5)
        attachScreenshot(app, "drag-reordered")
    }

    /// iPad: a sidebar page dragged into the page body lands as a link to it (its title as the text).
    func testDragPageIntoEditorDropsLink() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the sidebar beside the page — run on iPad or Mac")
        }
        createPage(app, title: "Alpha")
        createPage(app, title: "Beta")
        let alpha = app.descendants(matching: .any)["page-row-Alpha"].firstMatch
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(alpha, in: app))
        XCTAssertTrue(waitOrDumpTree(body, in: app))
        // A coordinate target needs a coordinate source (XCUIElement only drags to elements).
        alpha.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.6, thenDragTo: body.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)),
                withVelocity: .slow, thenHoldForDuration: 0.6)
        let link = app.webViews.links["Alpha"].firstMatch
        XCTAssertTrue(waitOrDumpTree(link, in: app, timeout: 5), "the dropped page did not become a link")
        attachScreenshot(app, "drag-link")
    }

    #if os(iOS)
        /// iPad / an unfolded iPhone Duo: no bar over the page — no tabs; a sidebar pick opens in place and back returns.
        func testPadShowsOnePageWithoutTabs() throws {
            continueAfterFailure = false
            let app = launch()
            guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
                throw XCTSkip("needs the sidebar beside the page — run on iPad")
            }
            createPage(app, title: "Alpha")
            createPage(app, title: "Beta")
            app.descendants(matching: .any)["page-row-Alpha"].firstMatch.tap()
            let title = app.webViews.textViews["Page title"].firstMatch
            let shows = { (text: String) in
                XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", text), object: title)
            }
            XCTAssertEqual(XCTWaiter.wait(for: [shows("Alpha")], timeout: 5), .completed)
            XCTAssertFalse(app.descendants(matching: .any)["tab-Alpha"].exists, "a tab strip over the page")
            XCTAssertFalse(app.descendants(matching: .any)["tab-Beta"].exists, "Beta kept a tab of its own")
            app.buttons["chrome-back"].firstMatch.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [shows("Beta")], timeout: 5), .completed, "back did not return to the page before")
        }
    #endif

    /// iPad: a sidebar page dropped onto a tab shows there; dropped on a tab's edge it opens in a new tab.
    func testDragPageOntoTabStripOpensIt() throws {
        #if os(iOS)
            throw XCTSkip("tabs are the Mac's: iPad shows one page at a time")
        #endif
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the sidebar beside the page — run on iPad or Mac")
        }
        createPage(app, title: "Alpha")
        createPage(app, title: "Beta")
        let alphaRow = app.descendants(matching: .any)["page-row-Alpha"].firstMatch
        let betaTab = app.descendants(matching: .any)["tab-Beta"].firstMatch
        XCTAssertTrue(waitOrDumpTree(alphaRow, in: app))
        XCTAssertTrue(waitOrDumpTree(betaTab, in: app))
        // Onto the tab: it now shows Alpha.
        alphaRow.press(forDuration: 0.6, thenDragTo: betaTab, withVelocity: .slow, thenHoldForDuration: 0.6)
        let alphaTab = app.descendants(matching: .any)["tab-Alpha"].firstMatch
        XCTAssertTrue(waitOrDumpTree(alphaTab, in: app, timeout: 5), "the tab did not switch to the dropped page")
        XCTAssertFalse(app.descendants(matching: .any)["tab-Beta"].exists)
        // Onto that tab's left edge: Beta opens in a new tab before it.
        let betaRow = app.descendants(matching: .any)["page-row-Beta"].firstMatch
        betaRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.6, thenDragTo: alphaTab.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(waitOrDumpTree(betaTab, in: app, timeout: 5), "the dropped page did not open as a tab")
        XCTAssertTrue(alphaTab.exists)
        XCTAssertLessThan(betaTab.frame.minX, alphaTab.frame.minX)
        attachScreenshot(app, "drag-tab")
    }

    /// Visual record of the main screens (run on an iPad destination for the regular-width layout).
    func testCaptureScreens() throws {
        let app = launch()
        createPage(app, title: "Welcome to Hikki")
        let addIcon = app.webViews.buttons["Add icon"].firstMatch
        if addIcon.waitForExistence(timeout: 5) { addIcon.tap() }
        let addCover = app.webViews.buttons["Add cover"].firstMatch
        if addCover.waitForExistence(timeout: 5) { addCover.tap() }
        let title = app.webViews.textViews["Page title"].firstMatch
        title.tap()
        title.typeText("\nA local-first notebook.")
        sleep(1)
        attachScreenshot(app, "page")
        backToSidebarIfNeeded(app)
        let navHome = app.buttons["nav-home"].firstMatch
        if navHome.exists { navHome.tap() } else { app.staticTexts["Home"].firstMatch.tap() }
        sleep(1)
        attachScreenshot(app, "home")
        app.buttons["sidebar-search"].firstMatch.tap()
        sleep(1)
        attachScreenshot(app, "search")
    }

    // MARK: - Helpers

    /// A page link to a page that no longer exists says so (a toast) instead of doing nothing.
    func testLinkToAMissingPageSaysSo() throws {
        continueAfterFailure = false
        let source = dataDir + "-links.md"
        try "# Links\n\nSee [Gone](hikki://page/nope-0000) for more.\n".write(toFile: source, atomically: true, encoding: .utf8)
        let app = launch(environment: ["HIKKI_IMPORT_FILE": source])
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30), "the imported page did not open")
        let link = app.webViews.links["Gone"].firstMatch
        XCTAssertTrue(waitOrDumpTree(link, in: app))
        link.tap()
        let toast = app.staticTexts["The page this link points to no longer exists."].firstMatch
        XCTAssertTrue(waitOrDumpTree(toast, in: app, timeout: 5), "a link to a missing page did nothing")
        attachScreenshot(app, "missing-link-toast")
    }

    /// iPad / Mac (window toolbar): the inspector lists the page's headings, one jumps there, Info shows the counts.
    /// iPhone, a workspace in iCloud: Home pulls to refresh.
    func testHomePullsToRefreshFromICloud() throws {
        #if os(macOS)
            throw XCTSkip("pull to refresh is iOS's")
        #else
            continueAfterFailure = false
            let app = launch(environment: ["HIKKI_WORKSPACE_ICLOUD": "1", "HIKKI_DEMO_PAGES": "1"])
            let blank = app.buttons["home-new-blank"].firstMatch
            guard blank.waitForExistence(timeout: 10) else { throw XCTSkip("the iPhone layout") }
            let home = app.scrollViews.containing(.button, identifier: "home-new-blank").firstMatch
            let start = home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            start.press(
                forDuration: 0.05, thenDragTo: home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)),
                withVelocity: .slow, thenHoldForDuration: 1)
            // Without an account the pull settles before its spinner can be seen: the app's log says it ran.
            let log = URL(fileURLWithPath: dataDir).appending(path: "logs/hikki.log")
            let pulled = NSPredicate { _, _ in
                ((try? String(contentsOf: log, encoding: .utf8)) ?? "").contains("cloud refresh pulled")
            }
            wait(for: [expectation(for: pulled, evaluatedWith: nil)], timeout: 5)
            XCTAssertTrue(blank.waitForExistence(timeout: 10))
        #endif
    }

    /// iPad (and an unfolded iPhone Duo): opening the page's panel hides the sidebar, closing it brings it back.
    func testPadPanelHidesTheSidebar() throws {
        #if os(macOS)
            throw XCTSkip("the Mac's window grows instead")
        #else
            continueAfterFailure = false
            let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
            guard app.buttons["nav-home"].waitForExistence(timeout: 10) else { throw XCTSkip("the iPad layout") }
            let search = app.descendants(matching: .any)["sidebar-search"].firstMatch
            let shown = NSPredicate(format: "isHittable == true")
            let hidden = NSPredicate(format: "exists == false OR isHittable == false")
            wait(for: [expectation(for: shown, evaluatedWith: search)], timeout: 10)
            let toggle = app.buttons["inspector-toggle"].firstMatch
            XCTAssertTrue(waitOrDumpTree(toggle, in: app))
            toggle.tap()
            wait(for: [expectation(for: hidden, evaluatedWith: search)], timeout: 5)
            attachScreenshot(app, "panel-without-sidebar")
            toggle.tap()
            wait(for: [expectation(for: shown, evaluatedWith: search)], timeout: 5)
        #endif
    }

    func testInspectorShowsOutlineAndCounts() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the window toolbar — run on iPad or Mac")
        }
        createPage(app, title: "Outline page")
        // Return leaves the title for the body; "# " and "## " are the Markdown shortcuts for headings.
        app.webViews.textViews["Page title"].firstMatch.typeText("\n")
        app.typeText("# First section\nSome words here.\n## Second section\nMore words.")
        sleep(1)
        let toggle = app.buttons["inspector-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(toggle, in: app))
        toggle.tap()
        let row = app.buttons["outline-Second section"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app), "the inspector did not list the headings")
        attachScreenshot(app, "inspector-outline")
        row.tap()
        // The outline follows the page: the section jumped to is the one marked.
        let selected = expectation(for: NSPredicate(format: "isSelected == true"), evaluatedWith: row)
        wait(for: [selected], timeout: 5)
        // The AI button shows the panel's other mode.
        app.descendants(matching: .any)["ai-toggle"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["inspector-ai"].firstMatch, in: app))
        attachScreenshot(app, "inspector-ai")
        toggle.tap()
    }

    /// Comments end to end: a word selected in the page, Comment, a comment sent — it lands in the workspace's store
    /// and the side panel lists it.
    func testCommentingOnAPassage() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_OPEN_TABS": "demo-46ffce8"])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30))
        sleep(1)
        // A word selected from the keyboard (a double tap in the web view selects unreliably on the simulator),
        // then Comment's shortcut.
        body.staticTexts.element(boundBy: 1).tap()
        body.typeKey(.rightArrow, modifierFlags: .command)
        body.typeKey(.leftArrow, modifierFlags: [.shift, .alternate])
        body.typeKey("m", modifierFlags: [.command, .shift])
        let field = app.webViews.textFields["Add a comment…"].firstMatch
        XCTAssertTrue(waitOrDumpTree(field, in: app), "no comment composer")
        field.tap()
        field.typeText("Hearsay or appearance?\n")
        sleep(1)

        let toggle = app.descendants(matching: .any)["comments-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(toggle, in: app))
        toggle.tap()
        let row = app.descendants(matching: .any)["comment-row"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app), "the side panel lists no thread")
        XCTAssertTrue(app.staticTexts["Hearsay or appearance?"].firstMatch.exists)
    }

    /// iPhone: a comment is written in a bottom sheet; a tap on the commented passage opens the thread in the sheet
    /// without bringing the keyboard up (the tap doesn't place the caret); a tap on the dimmed page closes it.
    func testPhoneCommentSheet() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("the iPhone layout") }
        #else
            throw XCTSkip("the iPhone layout")
        #endif
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        let body = app.webViews.textViews["Page content"].firstMatch
        XCTAssertTrue(waitOrDumpTree(body, in: app, timeout: 30))
        // By its start: a draft's highlight splits the line into runs.
        let line = body.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "山へ行く")).firstMatch
        XCTAssertTrue(waitOrDumpTree(line, in: app))
        let composer = app.webViews.textFields["Add a comment…"].firstMatch
        // Keys the simulator sends right after a tap are sometimes lost while the keyboard comes up: tap and try again.
        for attempt in 0..<3 where !composer.exists {
            line.tap()
            if attempt == 0 {
                // A fresh simulator's keyboard first shows its "slide to type" tip.
                let tip = app.buttons["Continue"].firstMatch
                if tip.waitForExistence(timeout: 2) { tip.tap() }
            }
            sleep(2)
            // The whole line, from the keyboard, then Comment's shortcut.
            body.typeKey(.rightArrow, modifierFlags: .command)
            body.typeKey(.leftArrow, modifierFlags: [.shift, .command])
            body.typeKey("m", modifierFlags: [.command, .shift])
            _ = composer.waitForExistence(timeout: 4)
        }
        XCTAssertTrue(waitOrDumpTree(composer, in: app), "no comment sheet")
        composer.typeText("Hearsay or appearance?\n")
        let reply = app.webViews.textFields["Reply…"].firstMatch
        XCTAssertTrue(waitOrDumpTree(reply, in: app), "the sheet doesn't show the new thread")
        attachScreenshot(app, "sheet-after-send")
        // The dimmed page above the sheet closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)).tap()
        XCTAssertTrue(reply.waitForNonExistence(timeout: 5), "a tap on the scrim didn't close the sheet")
        sleep(1)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "the keyboard stayed up after the sheet closed")

        // A tap on the passage: the thread, and no keyboard.
        // The commented part of the line (its own text run once marked; the keys may have caught part of the line).
        let passage = body.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "山へ行く")).firstMatch
        passage.tap()
        XCTAssertTrue(waitOrDumpTree(reply, in: app), "a tap on the passage didn't open its thread")
        sleep(1)
        XCTAssertTrue(app.staticTexts["Hearsay or appearance?"].firstMatch.exists)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "a tap on the passage brought the keyboard up")
        attachScreenshot(app, "sheet-from-tap")
        // Its field sits above the floating bottom bar, not under it.
        let bar = app.buttons["edit-page"].firstMatch
        XCTAssertTrue(bar.exists)
        XCTAssertLessThanOrEqual(reply.frame.maxY, bar.frame.minY + 1, "the reply field is under the bottom bar")
        // The reply field takes the keyboard; the sheet rides above it.
        reply.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
        let keyboard = app.keyboards.firstMatch.frame
        XCTAssertLessThanOrEqual(reply.frame.maxY, keyboard.minY + 1, "the reply field is under the keyboard")
        attachScreenshot(app, "sheet-keyboard")
    }

    /// Split view: once the pane's page has loaded, the left page still takes typing — and the pane's too.
    func testBothSidesOfASplitTakeTyping() throws {
        continueAfterFailure = false
        let app = launch(environment: [
            "HIKKI_DEMO_PAGES": "1", "HIKKI_OPEN_TABS": "demo-46ffce8", "HIKKI_OPEN_SPLIT": "demo-dba8e9bf",
        ])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        let second = app.webViews.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 20), "no second editor in the pane")
        sleep(2)
        let views = [app.webViews.element(boundBy: 0), second].sorted { $0.frame.minX < $1.frame.minX }
        for (side, word) in [(views[0], "Zebra"), (views[1], "Quokka")] {
            let body = side.textViews["Page content"].firstMatch
            XCTAssertTrue(waitOrDumpTree(body, in: app))
            body.tap()
            sleep(1)
            body.typeText(word)
            let typed = expectation(
                for: NSPredicate { _, _ in (body.value as? String)?.contains(word) == true }, evaluatedWith: nil)
            wait(for: [typed], timeout: 5)
        }
        attachScreenshot(app, "split-typing")
    }

    /// Home in a side of a split view, too narrow for the table's columns, lists its pages instead — the table scrolled
    /// sideways and slid under the sidebar.
    func testHomeInANarrowSideListsItsPages() throws {
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_OPEN_SPLIT": "demo-46ffce8"])
        guard app.descendants(matching: .any)["split-divider"].firstMatch.waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        let row = app.buttons["home-row-Career Planning"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app), "Home's list missing")
        XCTAssertFalse(app.descendants(matching: .any)["home-table"].exists, "the table was kept")
        XCTAssertTrue(row.isHittable)
        row.tap()
        XCTAssertTrue(app.webViews.textViews["Page content"].firstMatch.waitForExistence(timeout: 10), "the page didn't open")
    }

    /// iPad: on a page (its tools crowding the toolbar) back and forward stay two buttons — as an iOS ControlGroup they
    /// folded into a menu with no label, an empty circle.
    func testBackForwardStayButtonsOnACrowdedToolbar() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the iPad toolbar") }
        #else
            throw XCTSkip("the iPad toolbar")
        #endif
        continueAfterFailure = false
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8"])
        XCTAssertTrue(waitOrDumpTree(app.buttons["ai-toggle"].firstMatch, in: app))
        XCTAssertTrue(app.buttons["Back"].firstMatch.isHittable, "back folded away")
        XCTAssertTrue(app.buttons["Forward"].firstMatch.isHittable, "forward folded away")
    }

    /// iPad: with the inspector open the tabs stay clear of back/forward. The strip was moved left by half the panel
    /// (right on a Mac, whose toolbar centres it over page and panel), and on iPad that slid it under the buttons.
    func testTabsStayClearOfBackForwardWithTheInspectorOpen() throws {
        #if os(iOS)
            guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("the iPad toolbar") }
        #else
            throw XCTSkip("the iPad toolbar")
        #endif
        continueAfterFailure = false
        // Two pages visited, so back/forward have something to do.
        let app = launch(environment: ["HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-dba8e9bf,demo-46ffce8"])
        let forward = app.buttons["Forward"].firstMatch
        let tab = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab-'")).firstMatch
        let ai = app.buttons["ai-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(ai, in: app))
        ai.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["ai-chat-field"].firstMatch, in: app))
        XCTAssertTrue(tab.exists && forward.exists)
        sleep(1)
        XCTAssertGreaterThanOrEqual(tab.frame.minX, forward.frame.maxX, "the tab slid under back/forward")
        attachScreenshot(app, "tabs-with-inspector")
    }

    /// The divider's grip sits over the pages' edges (they run up to the hairline) and still takes the drag: dragging it
    /// widens one side, a double-tap / double-click puts the boundary back in the middle.
    func testDraggingTheDividerResizesTheSides() throws {
        continueAfterFailure = false
        let app = launch(environment: [
            "HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8", "HIKKI_OPEN_SPLIT": "demo-dba8e9bf",
        ])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        let divider = app.descendants(matching: .any)["split-divider"].firstMatch
        let pane = app.descendants(matching: .any)["split-pane"].firstMatch
        XCTAssertTrue(waitOrDumpTree(divider, in: app))
        XCTAssertTrue(waitOrDumpTree(pane, in: app))
        // The middle first: the fraction is a preference, kept from earlier runs.
        divider.doubleTap()
        sleep(1)
        let half = pane.frame.width
        let grip = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        // Not far: on an iPad each side has little to give before it reaches `Size.splitMin`.
        grip.press(forDuration: 0.2, thenDragTo: grip.withOffset(CGVector(dx: -40, dy: 0)))
        sleep(1)
        XCTAssertGreaterThan(pane.frame.width, half + 25, "dragging the grip didn't move the boundary")
        divider.doubleTap()
        sleep(1)
        XCTAssertEqual(pane.frame.width, half, accuracy: 2, "a double-tap didn't put it back in the middle")
    }

    /// Opening split view keeps the left page on screen: the left side was built anew as the window split, and the
    /// window's one web view went with the old one (a blank left side, its editor gone from the screen).
    func testTheLeftPageStaysWhenTheWindowSplits() throws {
        continueAfterFailure = false
        let app = launch(environment: [
            "HIKKI_DEMO_PAGES": "1", "HIKKI_DEBUG_NAV": "demo-46ffce8", "HIKKI_OPEN_SPLIT": "demo-dba8e9bf",
        ])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        XCTAssertTrue(app.webViews.element(boundBy: 1).waitForExistence(timeout: 20), "no second editor in the pane")
        sleep(3)
        // The left page's own words ("雨が降りそうです。"), on screen in the window's left half.
        let middle = app.windows.firstMatch.frame.midX
        let words = app.webViews.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "降りそう"))
            .allElementsBoundByIndex
            .filter { $0.isHittable && $0.frame.maxX <= middle }
        XCTAssertFalse(words.isEmpty, "the left page's text is on screen")
        attachScreenshot(app, "split-left-page")
    }

    /// iPad / Mac: split view puts a second page beside the first, each in its own editor — two equal sides, each with its
    /// own tools and panel; they swap, and a side closes again.
    func testSplitViewShowsTwoPages() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        createPage(app, title: "Notes")
        createPage(app, title: "Textbook")
        // The page's panel stays open as the window splits: it is the leading side's.
        let inspectorToggle = app.descendants(matching: .any)["inspector-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(inspectorToggle, in: app))
        inspectorToggle.tap()
        let outlines = app.descendants(matching: .any).matching(identifier: "inspector-outline")
        XCTAssertTrue(waitOrDumpTree(outlines.firstMatch, in: app))
        openInSplit(app, "Notes")
        // Two editors: the tab's page and the one beside it.
        let second = app.webViews.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 10), "no second editor beside the page")
        XCTAssertTrue(waitOrDumpTree(app.webViews.textViews.matching(NSPredicate(format: "value == %@", "Notes")).firstMatch, in: app))
        XCTAssertTrue(outlines.firstMatch.exists, "the leading side's panel closed with the split")
        // The trailing side has the same tools: its own panel opens beside its page.
        let trailingOutline = app.descendants(matching: .any)["inspector-toggle-trailing"].firstMatch
        XCTAssertTrue(waitOrDumpTree(trailingOutline, in: app))
        trailingOutline.tap()
        let deadline = Date().addingTimeInterval(5)
        while outlines.count < 2 && Date() < deadline { usleep(200_000) }
        XCTAssertEqual(outlines.count, 2, "each side shows its own panel")
        attachScreenshot(app, "split-view")
        // The two tabs of the split are joined in the strip (the Mac's); swapping trades their places.
        #if os(macOS)
            XCTAssertTrue(app.descendants(matching: .any)["tab-split"].firstMatch.exists)
            let tabX = { (title: String) in app.descendants(matching: .any)["tab-\(title)"].firstMatch.frame.minX }
            XCTAssertLessThan(tabX("Textbook"), tabX("Notes"))
        #endif
        app.descendants(matching: .any)["split-swap-trailing"].firstMatch.tap()
        sleep(1)
        #if os(macOS)
            XCTAssertLessThan(tabX("Notes"), tabX("Textbook"), "the sides did not swap")
        #endif
        attachScreenshot(app, "split-swapped")
        app.descendants(matching: .any)["split-close-trailing"].firstMatch.tap()
        XCTAssertFalse(app.descendants(matching: .any)["split-pane"].waitForExistence(timeout: 2))
    }

    /// A sidebar page dragged onto the split pane shows there — onto an empty pane, then onto the pane's bar to switch —
    /// and the pane's title offers the picker again.
    func testDraggingPagesIntoTheSplitPane() throws {
        continueAfterFailure = false
        // An empty pane from the start (⌘\ in the app; the simulator's synthesized keys carry no modifiers).
        let app = launch(environment: ["HIKKI_OPEN_SPLIT": "picker"])
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        createPage(app, title: "Notes")
        createPage(app, title: "Textbook")
        createPage(app, title: "Draft")
        let pane = app.descendants(matching: .any)["split-pane"].firstMatch
        XCTAssertTrue(waitOrDumpTree(pane, in: app))

        let notesRow = app.descendants(matching: .any)["page-row-Notes"].firstMatch
        notesRow.press(forDuration: 0.6, thenDragTo: pane, withVelocity: .slow, thenHoldForDuration: 0.6)
        let change = app.descendants(matching: .any)["split-change-trailing"].firstMatch
        XCTAssertTrue(waitOrDumpTree(change, in: app, timeout: 5), "the dropped page did not open in the pane")
        let pageTitle = { (title: String) in
            app.webViews.textViews.matching(NSPredicate(format: "value == %@", title)).firstMatch
        }
        XCTAssertTrue(waitOrDumpTree(pageTitle("Notes"), in: app, timeout: 10))

        // Onto the bar of a pane that shows a page: it switches.
        let textbookRow = app.descendants(matching: .any)["page-row-Textbook"].firstMatch
        textbookRow.press(forDuration: 0.6, thenDragTo: change, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(waitOrDumpTree(pageTitle("Textbook"), in: app, timeout: 10), "the pane did not switch pages")
        attachScreenshot(app, "split-dropped")

        // The title is a chooser: recent pages, and "More…" for the whole picker.
        change.tap()
        let more = app.descendants(matching: .any)["split-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["split-pick-Notes"].firstMatch, in: app))
    }

    /// The same page on both sides (write on the left, read on the right): an edit on one side shows on the other.
    func testSamePageOnBothSidesShowsEdits() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        createPage(app, title: "Shared")
        openInSplit(app, "Shared")
        let titles = app.webViews.textViews.matching(NSPredicate(format: "label == %@", "Page title"))
        let shared = titles.matching(NSPredicate(format: "value == %@", "Shared"))
        XCTAssertTrue(waitOrDumpTree(shared.element(boundBy: 1), in: app, timeout: 10), "not on both sides")
        // Typed into one side's body, it shows on the other once saved. (The right side: in the simulator the pane's
        // web view keeps the keyboard after it loads.)
        let bodies = app.webViews.textViews.matching(NSPredicate(format: "label == %@", "Page content"))
        let right = bodies.allElementsBoundByIndex.max { $0.frame.minX < $1.frame.minX }!
        right.tap()
        sleep(1)
        app.typeText("written on one side")
        attachScreenshot(app, "split-same-page-typed")
        let copies = app.webViews.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@", "written on one side", "written on one side"))
        let deadline = Date().addingTimeInterval(10)
        while copies.count < 2 && Date() < deadline { usleep(250_000) }
        XCTAssertGreaterThanOrEqual(copies.count, 2, "the other side didn't show the edit")
        attachScreenshot(app, "split-same-page")
    }

    /// Each tab keeps its place: a long page scrolled down, another tab shown, then back — still scrolled.
    func testATabKeepsItsScrollPosition() throws {
        #if os(iOS)
            throw XCTSkip("tabs are the Mac's: iPad shows one page at a time")
        #endif
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the window toolbar's tabs — run on iPad or Mac")
        }
        createPage(app, title: "Other")
        createPage(app, title: "Long")
        app.webViews.textViews["Page title"].firstMatch.typeText("\n")
        app.typeText((1...60).map { "Line \($0)" }.joined(separator: "\n"))
        sleep(1)
        let page = app.webViews.firstMatch
        let title = app.webViews.textViews["Page title"].firstMatch
        for _ in 0..<4 { page.swipeDown() }
        XCTAssertTrue(title.isHittable, "the page should start at its top for this test")
        for _ in 0..<3 { page.swipeUp(velocity: .slow) }
        sleep(1)
        XCTAssertFalse(title.isHittable, "the page did not scroll")

        // Another page from the sidebar opens in a tab of its own; then back to Long's tab.
        app.descendants(matching: .any)["page-row-Other"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["tab-Other"].firstMatch, in: app))
        let longTab = app.descendants(matching: .any)["tab-Long"].firstMatch
        XCTAssertTrue(waitOrDumpTree(longTab, in: app))
        sleep(1)
        longTab.tap()
        sleep(2)
        XCTAssertFalse(app.webViews.textViews["Page title"].firstMatch.isHittable, "the tab came back at its top")
        attachScreenshot(app, "tab-scroll-restored")
    }

    /// A sidebar page dropped on the right edge of the open page opens beside it. (Not at the screen's very edge: iPadOS
    /// takes a link dropped there as "open in a new window".)
    func testDroppingAPageOnTheRightEdgeOpensSplitView() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        createPage(app, title: "Notes")
        createPage(app, title: "Textbook")
        let page = app.webViews.firstMatch
        let notesRow = app.descendants(matching: .any)["page-row-Notes"].firstMatch
        notesRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.6, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.8)
        XCTAssertTrue(
            waitOrDumpTree(app.descendants(matching: .any)["split-pane"].firstMatch, in: app, timeout: 5),
            "dropping on the right edge did not open split view")
        XCTAssertTrue(
            waitOrDumpTree(
                app.webViews.textViews.matching(NSPredicate(format: "value == %@", "Notes")).firstMatch, in: app,
                timeout: 10))
        attachScreenshot(app, "split-edge-drop")
    }

    /// A sidebar row's "Open in Split View" (its context menu).
    private func openInSplit(_ app: XCUIApplication, _ title: String) {
        let row = app.descendants(matching: .any)["page-row-\(title)"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app))
        row.press(forDuration: 1.2)
        // iPadOS's context menus drop the item's identifier: its title finds it there.
        let item = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'open-in-split' OR label == 'Open in Split View'")).firstMatch
        XCTAssertTrue(waitOrDumpTree(item, in: app))
        item.tap()
    }

    /// A tab's context menu (Chrome's): Duplicate copies it beside itself, Close Tabs to the Right and Close Other
    /// Tabs leave the one it was opened on, New Tab to the Right opens Home after it.
    func testTabContextMenu() throws {
        #if os(iOS)
            throw XCTSkip("tabs are the Mac's: iPad shows one page at a time")
        #endif
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs the window toolbar's tabs — run on iPad or Mac")
        }
        createPage(app, title: "Alpha")
        createPage(app, title: "Beta")  // in Alpha's tab
        app.descendants(matching: .any)["page-row-Alpha"].firstMatch.tap()  // a tab of its own
        let tabs = { (title: String) in app.descendants(matching: .any).matching(identifier: "tab-\(title)") }
        XCTAssertTrue(waitOrDumpTree(tabs("Alpha").firstMatch, in: app))
        XCTAssertTrue(waitOrDumpTree(tabs("Beta").firstMatch, in: app))

        func run(_ command: String, on tab: XCUIElement) {
            #if os(macOS)
                tab.rightClick()
                let item = app.menuItems["tab-menu-\(command)"].firstMatch
            #else
                tab.press(forDuration: 1)
                let item = app.buttons["tab-menu-\(command)"].firstMatch
            #endif
            XCTAssertTrue(waitOrDumpTree(item, in: app, timeout: 5), "no \(command) in the tab menu")
            item.tap()
            sleep(1)
        }

        run("duplicate", on: tabs("Alpha").firstMatch)
        XCTAssertEqual(tabs("Alpha").count, 2)
        run("closeToRight", on: tabs("Beta").firstMatch)
        XCTAssertEqual(tabs("Alpha").count, 0)
        XCTAssertTrue(tabs("Beta").firstMatch.exists)
        run("newToRight", on: tabs("Beta").firstMatch)
        XCTAssertTrue(waitOrDumpTree(tabs("Home").firstMatch, in: app, timeout: 5))
        XCTAssertLessThan(tabs("Beta").firstMatch.frame.minX, tabs("Home").firstMatch.frame.minX)
        run("closeOthers", on: tabs("Beta").firstMatch)
        XCTAssertEqual(tabs("Home").count, 0)
        XCTAssertEqual(tabs("Beta").count, 1)
    }

    private func createPage(_ app: XCUIApplication, title: String) {
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let field = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(field, in: app), "editor never became editable")
        field.tap()
        field.typeText(title)
        sleep(1)  // past the save debounce
    }

    /// On iPhone the sidebar is a separate screen behind the page.
    private func backToSidebarIfNeeded(_ app: XCUIApplication) {
        #if os(iOS)
            let back = app.navigationBars.buttons["BackButton"]
            if back.exists {
                back.tap()
                // Wait for the pop to finish; taps during the transition are dropped.
                _ = app.buttons["sidebar-search"].waitForExistence(timeout: 5)
            }
        #endif
    }

    /// On iPhone the page tree is in Home's side drawer: opens it (no-op elsewhere, or when it is open).
    /// Settings: the workspace menu's Settings on Mac/iPad, the drawer's on iPhone.
    private func openSettings(_ app: XCUIApplication) {
        let header = app.buttons["workspace-menu"].firstMatch
        if header.waitForExistence(timeout: 5) {
            header.tap()
            // iPadOS menus drop the item's identifier: there it is found by its (English) title.
            let open = app.buttons.matching(
                NSPredicate(format: "identifier == 'settings-open' OR (identifier == '' AND label == 'Settings')")
            ).firstMatch
            XCTAssertTrue(waitOrDumpTree(open, in: app))
            open.tap()
        } else {
            openDrawerIfNeeded(app)
            let open = app.buttons["drawer-settings"].firstMatch
            XCTAssertTrue(waitOrDumpTree(open, in: app))
            open.tap()
        }
    }

    private func openDrawerIfNeeded(_ app: XCUIApplication) {
        let toggle = app.buttons["drawer-toggle"].firstMatch
        guard toggle.waitForExistence(timeout: 3), !app.buttons["drawer-all-pages"].firstMatch.exists else { return }
        tapWhenSettled(toggle)
        _ = app.buttons["drawer-all-pages"].firstMatch.waitForExistence(timeout: 5)
    }

    private func tapWhenSettled(_ element: XCUIElement) {
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: element)
        wait(for: [hittable], timeout: 5)
        element.tap()
    }

    private func attachScreenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
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

#if os(iOS)
    import UIKit

    /// What a screenshot shows around the page's selection paint (the tone's light wash) inside `region` (pixels):
    /// `foreign` counts the pixels in the rows just above it, inside its width, that are neither the page's white nor
    /// its paint — another highlight drawn over a taller box than the text's (UIKit's showed as a band above it).
    struct SelectionPixels: CustomStringConvertible {
        let painted: CGRect
        let foreign: Int
        let sample: String

        init?(_ image: UIImage, in region: CGRect) {
            guard let cg = image.cgImage else { return nil }
            let width = cg.width
            let height = cg.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            guard
                let context = CGContext(
                    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let i = (y * width + x) * 4
                return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
            }
            // The paint: a light pink (red well above green and blue, all of them light).
            func isPaint(_ c: (Int, Int, Int)) -> Bool { c.0 > 225 && c.1 > 185 && c.0 - c.1 > 10 && c.2 > c.1 - 4 }
            var minX = width
            var minY = height
            var maxX = -1
            var maxY = -1
            let xs = max(0, Int(region.minX))..<min(width, Int(region.maxX))
            let ys = max(0, Int(region.minY))..<min(height, Int(region.maxY))
            for y in ys {
                for x in xs where isPaint(rgb(x, y)) {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
            guard maxX - minX > 200, maxY - minY > 10 else { return nil }
            painted = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            // Inside the paint's width, clear of the handles (bar, ball and shadow) at its ends.
            let inset = 70
            let columns = (minX + inset)...(maxX - inset)
            let rows = max(0, minY - 14)..<minY
            var foreign = 0
            var first = ""
            for y in rows {
                for x in columns {
                    let c = rgb(x, y)
                    let white = c.0 > 248 && c.1 > 248 && c.2 > 248
                    if !white && !isPaint(c) {
                        foreign += 1
                        if first.isEmpty { first = "rgb\(c) at \(x),\(y)" }
                    }
                }
            }
            self.foreign = foreign
            sample = first
        }

        var description: String { "\(foreign) pixels around \(painted), first \(sample)" }
    }
#endif
