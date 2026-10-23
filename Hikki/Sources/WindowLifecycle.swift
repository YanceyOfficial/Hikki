#if os(macOS)
    import AppKit
    import SwiftUI

    /// macOS window lifecycle, like Notes or Music: closing the last main window only hides it (tabs, the
    /// open page and the editor stay as they were) and clicking the Dock icon brings the same window back instead of
    /// a fresh one. Settings is a sheet on the window, so it goes and comes back with it.
    enum MainWindows {
        /// The red button or ⌘W on the last tab. Other main windows (Open in new window) close for real.
        @MainActor static func closeOrHide(_ window: NSWindow?) {
            guard let window else { return }
            if visibleMain().count > 1 {
                window.close()
            } else {
                window.orderOut(nil)
            }
        }

        /// Menu bar: bring Hikki forward with its main window (the hidden one if the last was closed).
        @MainActor static func showMain() {
            NSApp.activate()
            if let window = visibleMain().first(where: \.isKeyWindow) ?? visibleMain().first {
                window.makeKeyAndOrderFront(nil)
            } else {
                _ = showHidden()
            }
        }

        @MainActor static func showHidden() -> Bool {
            guard let window = NSApp.windows.first(where: { isMain($0) && !$0.isVisible }) else { return false }
            window.makeKeyAndOrderFront(nil)
            return true
        }

        /// The main window a request from the menu bar (or a menu with no window in front) is for: the key one (or
        /// the one under the key sheet), else the frontmost visible one.
        @MainActor static func requestTarget() -> NSWindow? {
            if let key = NSApp.keyWindow, isMain(key) { return key }
            if let owner = NSApp.keyWindow?.sheetParent, isMain(owner) { return owner }
            return visibleMain().first
        }

        /// Front to back.
        @MainActor private static func visibleMain() -> [NSWindow] {
            NSApp.orderedWindows.filter { isMain($0) && $0.isVisible }
        }

        /// Our document windows: titled, normal level, not panels/sheets.
        @MainActor private static func isMain(_ window: NSWindow) -> Bool {
            window.styleMask.contains(.titled) && window.level == .normal && !(window is NSPanel)
                && window.sheetParent == nil
        }
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        /// iCloud's pushes (another device saved): `CKSyncEngine` takes them once the app is registered.
        func applicationDidFinishLaunching(_ notification: Notification) {
            NSApplication.shared.registerForRemoteNotifications()
        }

        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

        /// ⌘Q: every editor's last typing and the workspace folder's queued writes reach the disk first.
        func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
            SaveOnExit.flushAll(model: AppModel.current, reason: "quit") {
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }

        /// Dock click with nothing on screen: bring back the hidden window rather than letting SwiftUI open a new one.
        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
            if !hasVisibleWindows, MainWindows.showHidden() { return false }
            return true
        }
    }

    /// Routes the window's close button through `MainWindows.closeOrHide`, and keeps the toolbar icons-only: the
    /// "Icon and Text / Icon Only" menu a right click on it offers is switched off (the items have no text to show).
    struct HideOnClose: NSViewRepresentable {
        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        }

        final class Coordinator: NSObject {
            private weak var window: NSWindow?

            func attach(to window: NSWindow?) {
                if let toolbar = window?.toolbar {
                    toolbar.displayMode = .iconOnly
                    toolbar.allowsDisplayModeCustomization = false
                }
                guard let window, let close = window.standardWindowButton(.closeButton) else { return }
                self.window = window
                close.target = self
                close.action = #selector(closeClicked)
            }

            @objc private func closeClicked() {
                MainWindows.closeOrHide(window)
            }
        }
    }
#endif
