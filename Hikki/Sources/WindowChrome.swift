#if os(macOS)
    import AppKit
    import SwiftUI

    /// Configures the hosting NSWindow for a Notion-style custom title bar: transparent title bar,
    /// content under it, no toolbar — only the traffic lights remain, over our sidebar header.
    ///
    /// SwiftUI re-installs a window toolbar whenever navigation state changes (e.g. a new
    /// `navigationTitle` after switching pages), which brought back an opaque title-bar layer over our
    /// tab strip. So the configuration is re-applied whenever the window's toolbar or title visibility
    /// changes, not just once. (Hiding the window toolbar via SwiftUI also hid the traffic lights.)
    struct WindowChrome: NSViewRepresentable {
        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        }

        final class Coordinator {
            private weak var window: NSWindow?
            private var observations: [NSKeyValueObservation] = []

            func attach(to window: NSWindow?) {
                guard let window else { return }
                if window !== self.window {
                    self.window = window
                    // KVO callbacks are nonisolated; hop to the main actor before touching the window.
                    let reapply: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.reapply() } }
                    observations = [
                        window.observe(\.toolbar) { _, _ in reapply() },
                        window.observe(\.titleVisibility) { _, _ in reapply() },
                        window.observe(\.titlebarAppearsTransparent) { _, _ in reapply() },
                    ]
                }
                Self.configure(window)
            }

            private func reapply() {
                if let window { Self.configure(window) }
            }

            static func configure(_ window: NSWindow) {
                if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
                if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
                if window.toolbar != nil { window.toolbar = nil }
                window.tabbingMode = .disallowed // we have our own tabs
                for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    window.standardWindowButton(button)?.isHidden = false
                }
            }
        }
    }
#endif
