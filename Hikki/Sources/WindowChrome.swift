#if os(macOS)
    import AppKit
    import ObjectiveC
    import HikkiUI
    import SwiftUI

    /// Configures the hosting NSWindow for a Notion-style custom title bar: transparent title bar,
    /// content under it, an empty toolbar for height — only the traffic lights show, over our sidebar header.
    ///
    /// SwiftUI re-installs a window toolbar whenever navigation state changes (e.g. a new
    /// `navigationTitle` after switching pages), which brought back an opaque title-bar layer over our
    /// tab strip. So the configuration is re-applied whenever the window's toolbar or title visibility
    /// changes, not just once. (Hiding the window toolbar via SwiftUI also hid the traffic lights.)
    struct WindowChrome: NSViewRepresentable {
        /// Reports where the traffic lights are, so the custom title-bar row can line up with them.
        var onMeasure: (ChromeMetrics) -> Void = { _ in }

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            context.coordinator.onMeasure = onMeasure
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            context.coordinator.onMeasure = onMeasure
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        }

        final class Coordinator {
            private weak var window: NSWindow?
            var onMeasure: (ChromeMetrics) -> Void = { _ in }
            private var lastMetrics: ChromeMetrics?
            private var observations: [NSKeyValueObservation] = []
            private var resizeObservers: [NSObjectProtocol] = []

            func attach(to window: NSWindow?) {
                guard let window else { return }
                if window !== self.window {
                    self.window = window
                    // KVO callbacks are nonisolated; hop to the main actor before touching the window.
                    let reapply: @Sendable () -> Void = { [weak self] in Task { @MainActor in self?.reapply() } }
                    resizeObservers = [
                        NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification,
                        NSWindow.didExitFullScreenNotification, NSWindow.didBecomeKeyNotification,
                    ].map { name in
                        NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { _ in reapply() }
                    }
                    observations = [
                        window.observe(\.toolbar) { _, _ in reapply() },
                        window.observe(\.titleVisibility) { _, _ in reapply() },
                        window.observe(\.titlebarAppearsTransparent) { _, _ in reapply() },
                    ]
                }
                Self.configure(window)
                installLayoutHook(window)
                measure(window)
            }

            private func reapply() {
                if let window {
                    Self.configure(window)
                    installLayoutHook(window)
                    measure(window)
                }
            }

            /// AppKit re-lays out the title bar on its own — e.g. when the split view's sidebar collapses or
            /// expands — without any window notification, putting the traffic lights back at its default height.
            /// Notification-driven fixes either showed that for a frame (async) or fought AppKit's layout
            /// (sync: the zoom button bounced ~100×/s). So the buttons' title-bar view gets a layout hook that
            /// re-centres them right after AppKit's own layout, in the same pass.
            private func installLayoutHook(_ window: NSWindow) {
                guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
                TitlebarLayoutHook.install(on: titlebar)
            }

            /// Title-bar row height = 2 × the traffic lights' center from the top; inset = past the zoom button.
            private func measure(_ window: NSWindow) {
                guard let close = window.standardWindowButton(.closeButton),
                    let zoom = window.standardWindowButton(.zoomButton),
                    let content = window.contentView
                else { return }
                let closeFrame = close.convert(close.bounds, to: content)
                let zoomFrame = zoom.convert(zoom.bounds, to: content)
                let centerFromTop = content.isFlipped ? closeFrame.midY : content.bounds.height - closeFrame.midY
                let metrics = ChromeMetrics(barHeight: (centerFromTop * 2).rounded(), leadingInset: (zoomFrame.maxX + Spacing.s3).rounded())
                guard metrics != lastMetrics, metrics.barHeight > 0 else { return }
                lastMetrics = metrics
                onMeasure(metrics)
            }

            /// Target title-bar height. The traffic lights are re-centred in it by resizing their
            /// container and moving the buttons (re-applied after resizes / full screen, which reset them).
            /// Native routes were tried and rejected: keeping SwiftUI's toolbar covered our tab strip,
            /// swapping in our own toolbar crashed (SwiftUI and AppKit fought over it), and a titlebar
            /// accessory covered the tab strip too.
            static let barHeight: CGFloat = 46

            static func configure(_ window: NSWindow) {
                if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
                if window.titleVisibility != .hidden { window.titleVisibility = .hidden }
                if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
                if window.toolbar != nil { window.toolbar = nil }
                window.tabbingMode = .disallowed  // we have our own tabs
                let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
                    window.standardWindowButton($0)
                }
                buttons.forEach { $0.isHidden = false }
                positionTrafficLights(buttons, in: window)
            }

            fileprivate static func positionTrafficLights(_ buttons: [NSButton], in window: NSWindow) {
                guard !window.styleMask.contains(.fullScreen), let titlebar = buttons.first?.superview,
                    let container = titlebar.superview
                else { return }
                var frame = container.frame
                if abs(frame.height - barHeight) > 0.5 {
                    frame.origin.y += frame.height - barHeight
                    frame.size.height = barHeight
                    container.frame = frame
                }
                for button in buttons {
                    let y = ((titlebar.bounds.height - button.frame.height) / 2).rounded()
                    if abs(button.frame.origin.y - y) > 0.5 { button.setFrameOrigin(NSPoint(x: button.frame.origin.x, y: y)) }
                }
            }
        }
    }

    /// Gives one AppKit title-bar view a `layout()` override (an isa-swizzled subclass, like KVO does) that
    /// calls AppKit's layout and then re-centres the traffic lights. The subclass is created once per
    /// original class; installing twice is a no-op.
    private enum TitlebarLayoutHook {
        private static let suffix = "_HikkiTrafficLights"

        static func install(on view: NSView) {
            let original: AnyClass = type(of: view)
            let name = NSStringFromClass(original)
            guard !name.hasSuffix(suffix) else { return }
            let subclass: AnyClass
            if let existing = NSClassFromString(name + suffix) {
                subclass = existing
            } else {
                guard let created = objc_allocateClassPair(original, name + suffix, 0),
                    let method = class_getInstanceMethod(original, #selector(NSView.layout))
                else { return }
                typealias Layout = @convention(c) (NSView, Selector) -> Void
                let superLayout = unsafeBitCast(method_getImplementation(method), to: Layout.self)
                let layout: @convention(block) (NSView) -> Void = { view in
                    superLayout(view, #selector(NSView.layout))
                    MainActor.assumeIsolated {
                        guard let window = view.window else { return }
                        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap {
                            window.standardWindowButton($0)
                        }
                        WindowChrome.Coordinator.positionTrafficLights(buttons, in: window)
                    }
                }
                class_addMethod(created, #selector(NSView.layout), imp_implementationWithBlock(layout), method_getTypeEncoding(method))
                objc_registerClassPair(created)
                subclass = created
            }
            object_setClass(view, subclass)
        }
    }
#endif
