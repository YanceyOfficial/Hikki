import XCTest

/// End-to-end: SwiftUI shell ⇄ WKWebView bridge ⇄ SQLite, through the real UI.
@MainActor
final class EditorFlowTests: XCTestCase {
    private let dataDir = NSTemporaryDirectory() + "hikki-uitest-\(UUID().uuidString)"

    /// `workspace: nil` starts from a fresh install (onboarding); otherwise a device workspace is seeded.
    private func launch(
        language: String? = nil, workspace: String? = "Test", shortcutOverrides: String = "{}",
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["HIKKI_DATA_DIR"] = dataDir
        app.launchEnvironment.merge(environment) { _, new in new }
        if let workspace { app.launchEnvironment["HIKKI_WORKSPACE"] = workspace }
        // Preferences outlive the data directory (UserDefaults): every test starts with the inspector closed.
        app.launchArguments += [
            "-inspector.visible", "NO", "-inspector.tab", "outline", "-settings.page", "workspace",
            "-shortcutOverrides", "<\(Data(shortcutOverrides.utf8).map { String(format: "%02x", $0) }.joined())>",
        ]
        if let language { app.launchArguments += ["-AppleLanguages", "(\(language))", "-AppleLocale", language] }
        app.launch()
        return app
    }

    /// iPhone's home screen: the tree opens a page's subpages, a row opens the page, ⋯ opens its actions sheet, and
    /// All pages lists every page under day headings.
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

        let child = app.buttons["page-row-N4 文法"].firstMatch
        XCTAssertFalse(child.exists)
        app.buttons["page-expand-日本語を勉強する"].firstMatch.tap()
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
        let header = app.buttons["workspace-menu"].firstMatch
        let more = app.buttons["workspace-more"].firstMatch
        let menu = header.waitForExistence(timeout: 5) ? header : more
        XCTAssertTrue(waitOrDumpTree(menu, in: app))
        menu.tap()
        let open = app.buttons["settings-open"].firstMatch
        XCTAssertTrue(waitOrDumpTree(open, in: app))
        open.tap()

        app.descendants(matching: .any)["settings-page-workspace"].firstMatch.tap()
        let name = app.textFields["settings-name"].firstMatch
        XCTAssertTrue(waitOrDumpTree(name, in: app))
        attachScreenshot(app, "settings")
        // The field is trailing-aligned: tap its right edge so the caret lands after the text.
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10) + "Atlas\n")
        app.buttons["settings-close"].firstMatch.tap()
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Atlas"].firstMatch, in: app), "renamed workspace not shown")
    }

    #if os(iOS)
        /// Settings → Shortcuts on iPad: a rebound shortcut shows its keys and resets; the key cap records a press and
        /// refuses one without ⌘/⌃/⌥. (XCUITest on iOS delivers typed keys without their modifiers, so recording a
        /// whole combo is covered by the unit tests and the Mac.)
        func testSettingsRebindsAShortcut() throws {
            continueAfterFailure = false
            let app = launch(shortcutOverrides: #"{"bold":{"key":"j","modifiers":["command","shift"]}}"#)
            let header = app.buttons["workspace-menu"].firstMatch
            let more = app.buttons["workspace-more"].firstMatch
            let menu = header.waitForExistence(timeout: 5) ? header : more
            XCTAssertTrue(waitOrDumpTree(menu, in: app))
            menu.tap()
            app.buttons["settings-open"].firstMatch.tap()
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

    /// The page's ⋯ menu opens the in-page find panel (⌘F does too, with a keyboard: covered by the
    /// editor's unit tests — the simulator's software keyboard doesn't deliver ⌘ shortcuts).
    func testFindInPageFromPageMenu() throws {
        continueAfterFailure = false
        let app = launch()
        let newPage = app.buttons["new-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(newPage, in: app))
        newPage.tap()
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app), "editor never became editable")
        title.tap()
        title.typeText("Find me")

        let more = app.buttons["page-more"].firstMatch
        XCTAssertTrue(waitOrDumpTree(more, in: app))
        more.tap()
        let item = app.buttons["find-in-page"].firstMatch
        XCTAssertTrue(waitOrDumpTree(item, in: app), "no Find in Page item")
        item.tap()
        let field = app.webViews.textFields["Find"].firstMatch
        XCTAssertTrue(waitOrDumpTree(field, in: app), "find panel did not open")
        // The panel sits below the toolbar (window.hikki.setInsets), not under its glass.
        XCTAssertGreaterThan(field.frame.minY, app.navigationBars.firstMatch.frame.maxY - 1, "find panel under the toolbar")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "find-panel"
        shot.lifetime = .keepAlways
        add(shot)
    }

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
        let row = app.descendants(matching: .any)["page-row-Imported note"].firstMatch
        XCTAssertTrue(waitOrDumpTree(row, in: app, timeout: 15), "imported page missing from the sidebar")
        let title = app.webViews.textViews["Page title"].firstMatch
        XCTAssertTrue(waitOrDumpTree(title, in: app))
        let opened = NSPredicate(format: "value == %@", "Imported note")
        wait(for: [expectation(for: opened, evaluatedWith: title)], timeout: 10)
        XCTAssertTrue(waitOrDumpTree(app.webViews.staticTexts["bold"].firstMatch, in: app), "imported body missing")
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

    /// iPad: a sidebar page dropped onto a tab shows there; dropped on a tab's edge it opens in a new tab.
    func testDragPageOntoTabStripOpensIt() throws {
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

    /// iPad / Mac (window toolbar): the inspector lists the page's headings, one jumps there, Info shows the counts.
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

    /// iPad / Mac: split view puts a second page beside the first, each in its own editor; the pane closes again.
    func testSplitViewShowsTwoPages() throws {
        continueAfterFailure = false
        let app = launch()
        guard app.buttons["nav-home"].waitForExistence(timeout: 10) else {
            throw XCTSkip("needs a wide window — run on iPad or Mac")
        }
        createPage(app, title: "Notes")
        createPage(app, title: "Textbook")
        // The inspector (the left page's) closes with a split, and can't open while it lasts.
        let inspectorToggle = app.descendants(matching: .any)["inspector-toggle"].firstMatch
        XCTAssertTrue(waitOrDumpTree(inspectorToggle, in: app))
        inspectorToggle.tap()
        XCTAssertTrue(waitOrDumpTree(app.descendants(matching: .any)["inspector-outline"].firstMatch, in: app))
        openInSplit(app, "Notes")
        XCTAssertFalse(app.descendants(matching: .any)["inspector-outline"].waitForExistence(timeout: 2))
        XCTAssertFalse(inspectorToggle.isEnabled)
        // Two editors: the tab's page and the pane's.
        let second = app.webViews.element(boundBy: 1)
        XCTAssertTrue(second.waitForExistence(timeout: 10), "no second editor in the pane")
        XCTAssertTrue(waitOrDumpTree(app.webViews.textViews.matching(NSPredicate(format: "value == %@", "Notes")).firstMatch, in: app))
        attachScreenshot(app, "split-view")
        app.descendants(matching: .any)["split-close"].firstMatch.tap()
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
        let change = app.descendants(matching: .any)["split-change"].firstMatch
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
        let item = app.descendants(matching: .any)["open-in-split"].firstMatch
        XCTAssertTrue(waitOrDumpTree(item, in: app))
        item.tap()
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
