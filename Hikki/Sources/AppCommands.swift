import HikkiCore
import SwiftUI

/// Menu bar (macOS, iPadOS). Keys come from the registry (design/shortcuts.json → `Shortcut`), as the user rebound
/// them (`ShortcutStore`, observed: the menus follow a change at once). Items bound
/// `app` or `both` get them here. Formatting items (`editor`) have none: ProseMirror owns ⌘B/⌘I/⌘Z inside the
/// editor, and binding them here too would toggle twice.
struct AppCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.navigator) private var navigator
    @FocusedValue(\.lockedPage) private var lockedPage
    @FocusedValue(\.favoritePage) private var favoritePage
    @FocusedValue(\.aiChat) private var aiChat

    var body: some Commands {
        // Settings… (⌘,): the Settings dialog over the window in front. With none (the Mac, every window closed or
        // only the menu bar's Hikki), the main window comes up first and shows it.
        CommandGroup(replacing: .appSettings) {
            Button("app:settings.open") {
                if let navigator {
                    navigator.isShowingSettings = true
                } else {
                    #if os(macOS)
                        MenuBarRequests.shared.post(.settings)
                    #endif
                }
            }
            .keyboardShortcut(Shortcut.settings.keyboardShortcut)
        }
        CommandGroup(replacing: .newItem) {
            Button("app:page.new") { navigator?.newPage() }
                .keyboardShortcut(Shortcut.newPage.keyboardShortcut)
            // Tabs are the Mac's (`Navigator.usesTabs`).
            if Navigator.usesTabs {
                Button("app:tabs.new") { navigator?.openInNewTab(.home) }
                    .keyboardShortcut(Shortcut.newTab.keyboardShortcut)
            }
            Button("app:tabs.close") {
                // ⌘W with Settings open closes Settings, not the tab under it.
                if navigator?.isShowingSettings == true {
                    navigator?.isShowingSettings = false
                    return
                }
                guard let navigator else {
                    // A window without tabs: ⌘W closes it.
                    #if os(macOS)
                        NSApp.keyWindow?.performClose(nil)
                    #endif
                    return
                }
                if !navigator.closeTab(navigator.tabs.activeID) { closeWindow() }
            }
            .keyboardShortcut(Shortcut.closeTab.keyboardShortcut)
            .disabled(!Navigator.usesTabs && navigator?.isShowingSettings != true)
            if Navigator.usesTabs {
                Button("app:tabs.reopenClosed") { navigator?.reopenClosedTab() }
                    .keyboardShortcut(Shortcut.reopenClosedTab.keyboardShortcut)
                    .disabled(navigator?.canReopenClosedTab != true)
            }
            // A new chat with AI about the page: while the side panel shows the conversation, with one to clear.
            Button("app:shortcut.newChat") { aiChat?.clear() }
                .keyboardShortcut(Shortcut.newChat.keyboardShortcut)
                .disabled(
                    navigator?.isShowingInspector != true || navigator?.inspectorMode != .ai || aiChat?.messages.isEmpty != false)
            Divider()
            Button("app:import.menu") { navigator?.importFiles(into: nil) }
                .disabled(navigator == nil)
            Divider()
            Button("app:menu.search") { navigator?.isSearching = true }
                .keyboardShortcut(Shortcut.search.keyboardShortcut)
        }
        // Edit → Find: in-page find (the editor's panel). The page handles these keys itself when it has
        // focus; the menu covers the rest (focus elsewhere in the window, iPad keyboards).
        CommandGroup(replacing: .textEditing) {
            Button("app:find.find") { editor?.find(.find) }
                .keyboardShortcut(Shortcut.find.keyboardShortcut)
            Button("app:find.replace") { editor?.find(.replace) }
                .keyboardShortcut(Shortcut.findReplace.keyboardShortcut)
            Button("app:find.next") { editor?.find(.next) }
                .keyboardShortcut(Shortcut.findNext.keyboardShortcut)
            Button("app:find.previous") { editor?.find(.previous) }
                .keyboardShortcut(Shortcut.findPrevious.keyboardShortcut)
        }
        // View → Show/Hide Outline (⌥⌘I): the side panel on the outline.
        CommandGroup(after: .sidebar) {
            let outlineOpen = navigator?.isShowingInspector == true && navigator?.inspectorMode == .outline
            Button(outlineOpen ? "app:menu.hideOutline" : "app:menu.showOutline") {
                navigator?.toggleInspector(.outline)
            }
            .keyboardShortcut(Shortcut.toggleInspector.keyboardShortcut)
            .disabled(navigator == nil)
            Button(navigator?.isSplit == true ? "app:menu.hideSplit" : "app:menu.showSplit") {
                navigator?.toggleSplit()
            }
            .keyboardShortcut(Shortcut.toggleSplit.keyboardShortcut)
            .disabled(navigator == nil || navigator?.splitAllowed == false)
        }
        // The page menu, as the page's ⋯ has it (`PageActions`): every item acts on the open page (the focused side
        // of a split) and is off on Home / Trash.
        CommandMenu("app:menu.page") {
            let onPage = navigator?.route.pageID != nil
            Button(favoritePage == true ? "app:page.unfavorite" : "app:page.favorite") {
                navigator?.toggleFavoriteCurrentPage()
            }
            .keyboardShortcut(Shortcut.favoritePage.keyboardShortcut)
            .disabled(favoritePage == nil)
            Button(lockedPage == true ? "app:page.unlock" : "app:page.lock") {
                navigator?.toggleLockCurrentPage()
            }
            .keyboardShortcut(Shortcut.lockPage.keyboardShortcut)
            .disabled(lockedPage == nil)
            Divider()
            Button("app:page.copyLink") { navigator?.copyCurrentPageLink() }
                .keyboardShortcut(Shortcut.copyPageLink.keyboardShortcut)
                .disabled(!onPage)
            Button("app:page.duplicate") { navigator?.duplicateCurrentPage() }
                .keyboardShortcut(Shortcut.duplicatePage.keyboardShortcut)
                .disabled(!onPage)
            Button("app:page.moveTo") { navigator?.moveCurrentPage() }
                .keyboardShortcut(Shortcut.movePage.keyboardShortcut)
                .disabled(!onPage)
            Divider()
            Button("app:history.open") { navigator?.showHistoryOfCurrentPage() }
                .keyboardShortcut(Shortcut.pageHistory.keyboardShortcut)
                .disabled(!onPage)
            Menu("app:export.menu") {
                ForEach(PageExport.Format.allCases) { format in
                    if format == .markdown {
                        Button(format.title) { navigator?.exportCurrentPage(as: format) }
                            .keyboardShortcut(Shortcut.exportMarkdown.keyboardShortcut)
                    } else {
                        Button(format.title) { navigator?.exportCurrentPage(as: format) }
                    }
                }
            }
            .disabled(!onPage)
            Divider()
            // Asks first (`TrashConfirmation`), as every other way in.
            Button("app:page.moveToTrash", role: .destructive) { navigator?.trashCurrentPage() }
                .keyboardShortcut(Shortcut.moveToTrash.keyboardShortcut)
                .disabled(!onPage)
        }
        CommandMenu("app:menu.go") {
            Button("app:chrome.back") { navigator?.goBack() }
                .keyboardShortcut(Shortcut.back.keyboardShortcut)
                .disabled(navigator?.tabs.canGoBack != true)
            Button("app:chrome.forward") { navigator?.goForward() }
                .keyboardShortcut(Shortcut.forward.keyboardShortcut)
                .disabled(navigator?.tabs.canGoForward != true)
            Divider()
            Button("app:tabs.next") { navigator?.selectNeighborTab(1) }
                .keyboardShortcut(Shortcut.nextTab.keyboardShortcut)
            Button("app:tabs.previous") { navigator?.selectNeighborTab(-1) }
                .keyboardShortcut(Shortcut.previousTab.keyboardShortcut)
            if Navigator.usesTabs {
                Divider()
                // ⌘1…⌘9: the nth tab, ⌘9 the last (browsers').
                ForEach(Array(Self.tabShortcuts.enumerated()), id: \.offset) { offset, shortcut in
                    Button("app:tabs.number \(String(offset + 1))") { navigator?.selectTab(number: offset + 1) }
                        .keyboardShortcut(shortcut.keyboardShortcut)
                        .disabled(navigator == nil)
                }
            }
            Divider()
            Button("app:nav.home") { navigator?.go(.home) }
            Button("app:nav.trash") { navigator?.go(.trash) }
        }
        CommandMenu("app:menu.format") {
            ForEach(EditorCommand.menuGroups, id: \.self) { group in
                ForEach(group) { command in
                    Button(command.title) { editor?.exec(command) }
                }
                Divider()
            }
        }
    }

    /// ⌘1…⌘9, in order.
    private static let tabShortcuts: [Shortcut] = [.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .tab9]

    private func closeWindow() {
        #if os(macOS)
            MainWindows.closeOrHide(NSApp.keyWindow)
        #endif
    }
}
