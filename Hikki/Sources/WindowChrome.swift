#if os(macOS)
    import AppKit
    import SwiftUI

    /// Configures the hosting NSWindow for a Notion-style custom title bar: transparent title bar,
    /// content under it, no toolbar — only the traffic lights remain, over our sidebar header.
    struct WindowChrome: NSViewRepresentable {
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { configure(view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { configure(view.window) }
        }

        private func configure(_ window: NSWindow?) {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.toolbar = nil
            window.isMovableByWindowBackground = false
            window.tabbingMode = .disallowed // we have our own tabs
        }
    }
#endif
