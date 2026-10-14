import SwiftUI

/// Menu bar (macOS, iPadOS). Keys come from the registry (design/shortcuts.json → `Shortcut`), as the user rebound
/// them (`ShortcutStore`, observed: the menus follow a change at once). Items bound
/// `app` or `both` get them here. Formatting items (`editor`) have none: ProseMirror owns ⌘B/⌘I/⌘Z inside the
/// editor, and binding them here too would toggle twice.
struct AppCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @FocusedValue(\.navigator) private var navigator
    @FocusedValue(\.lockedPage) private var lockedPage

    var body: some Commands {
        #if os(iOS)
            // iPad menu bar: ⌘, opens the settings sheet (macOS has a real Settings scene).
            CommandGroup(replacing: .appSettings) {
                Button("app:settings.open") { navigator?.isShowingSettings = true }
                    .keyboardShortcut(Shortcut.settings.keyboardShortcut)
            }
        #endif
        CommandGroup(replacing: .newItem) {
            Button("app:page.new") { navigator?.newPage() }
                .keyboardShortcut(Shortcut.newPage.keyboardShortcut)
            Button("app:tabs.new") { navigator?.openInNewTab(.home) }
                .keyboardShortcut(Shortcut.newTab.keyboardShortcut)
            Button("app:tabs.close") {
                guard let navigator else {
                    // Settings (or another window without tabs): ⌘W closes it.
                    #if os(macOS)
                        NSApp.keyWindow?.performClose(nil)
                    #endif
                    return
                }
                if !navigator.closeTab(navigator.tabs.activeID) { closeWindow() }
            }
            .keyboardShortcut(Shortcut.closeTab.keyboardShortcut)
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
        // View → Show/Hide Inspector (⌥⌘0, Xcode's).
        CommandGroup(after: .sidebar) {
            Button(navigator?.isShowingInspector == true ? "app:menu.hideInspector" : "app:menu.showInspector") {
                navigator?.isShowingInspector.toggle()
            }
            .keyboardShortcut(Shortcut.toggleInspector.keyboardShortcut)
            // Split: the inspector would describe the left page from beside the right one.
            .disabled(navigator == nil || navigator?.isSplit == true)
            Button(navigator?.isSplit == true ? "app:menu.hideSplit" : "app:menu.showSplit") {
                navigator?.toggleSplit()
            }
            .keyboardShortcut(Shortcut.toggleSplit.keyboardShortcut)
            .disabled(navigator == nil)
        }
        CommandMenu("app:menu.page") {
            Button("app:page.copyLink") { navigator?.copyCurrentPageLink() }
                .keyboardShortcut(Shortcut.copyPageLink.keyboardShortcut)
                .disabled(navigator?.route.pageID == nil)
            Button(lockedPage == true ? "app:page.unlock" : "app:page.lock") {
                navigator?.toggleLockCurrentPage()
            }
            .keyboardShortcut(Shortcut.lockPage.keyboardShortcut)
            .disabled(lockedPage == nil)
        }
        CommandMenu("app:menu.go") {
            Button("app:chrome.back") { navigator?.goBack() }
                .keyboardShortcut(Shortcut.back.keyboardShortcut)
                .disabled(navigator?.tabs.active.canGoBack != true)
            Button("app:chrome.forward") { navigator?.goForward() }
                .keyboardShortcut(Shortcut.forward.keyboardShortcut)
                .disabled(navigator?.tabs.active.canGoForward != true)
            Divider()
            Button("app:tabs.next") { navigator?.selectNeighborTab(1) }
                .keyboardShortcut(Shortcut.nextTab.keyboardShortcut)
            Button("app:tabs.previous") { navigator?.selectNeighborTab(-1) }
                .keyboardShortcut(Shortcut.previousTab.keyboardShortcut)
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

    private func closeWindow() {
        #if os(macOS)
            MainWindows.closeOrHide(NSApp.keyWindow)
        #endif
    }
}
