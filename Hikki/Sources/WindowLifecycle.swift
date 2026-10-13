#if os(macOS)
    import AppKit
    import SwiftUI

    /// macOS window lifecycle, like Notes or Music: closing the last main window only hides it (tabs, the
    /// open page and the editor stay as they were), Settings closes along with it, and clicking the Dock icon
    /// brings the same window back instead of a fresh one.
    enum MainWindows {
        /// The red button or ⌘W on the last tab. Other main windows (Open in new window) close for real.
        @MainActor static func closeOrHide(_ window: NSWindow?) {
            guard let window else { return }
            if visibleMain().count > 1 {
                window.close()
            } else {
                window.orderOut(nil)
                closeSettings()
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

        @MainActor private static func closeSettings() {
            for window in NSApp.windows where isSettings(window) { window.close() }
        }

        @MainActor private static func visibleMain() -> [NSWindow] {
            NSApp.windows.filter { isMain($0) && $0.isVisible }
        }

        /// Our document windows: titled, normal level, not Settings, not panels/sheets.
        @MainActor private static func isMain(_ window: NSWindow) -> Bool {
            window.styleMask.contains(.titled) && window.level == .normal && !isSettings(window) && !(window is NSPanel)
                && window.sheetParent == nil
        }

        @MainActor private static func isSettings(_ window: NSWindow) -> Bool {
            window.identifier?.rawValue.localizedCaseInsensitiveContains("settings") == true
        }
    }

    final class AppDelegate: NSObject, NSApplicationDelegate {
        func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

        /// Dock click with nothing on screen: bring back the hidden window rather than letting SwiftUI open a new one.
        func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
            if !hasVisibleWindows, MainWindows.showHidden() { return false }
            return true
        }
    }

    /// Routes the window's close button through `MainWindows.closeOrHide`.
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
