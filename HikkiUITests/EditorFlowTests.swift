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
        title.typeText("Plan\n/todo")

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

    /// Regression: on iPhone, tag-based List selection didn't navigate; rows must be NavigationLinks.
    func testSidebarRowsNavigate() throws {
        continueAfterFailure = false
        let app = launch()
        let trashRow = app.staticTexts["Trash"].firstMatch
        XCTAssertTrue(waitOrDumpTree(trashRow, in: app))
        tapWhenSettled(trashRow)
        XCTAssertTrue(waitOrDumpTree(app.staticTexts["Trash is empty"].firstMatch, in: app), "Trash row did not navigate")
        backToSidebarIfNeeded(app)
        tapWhenSettled(app.staticTexts["Home"].firstMatch)
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
        let trashRow = app.staticTexts["Trash"].firstMatch
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
