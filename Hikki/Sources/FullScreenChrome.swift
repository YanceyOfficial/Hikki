import SwiftUI

extension View {
    /// Full screen (macOS), Chrome's way: the toolbar row and the traffic lights stay, and the columns start
    /// below that row exactly as they do in a window. AppKit keeps the window buttons in place in full
    /// screen but fades them to alpha 0 until the menu bar comes down; here they are held visible. (Photos'
    /// hide-and-slide-in bar kept landing on the sidebar's search field without a background; given up.)
    func fullScreenChrome() -> some View {
        #if os(macOS)
            modifier(FullScreenChrome())
        #else
            self
        #endif
    }
}

#if os(macOS)
    import AppKit

    /// `HIKKI_DEBUG_FULLSCREEN` forces the full-screen layout on in a window (screenshots).
    private let debugFullScreen = ProcessInfo.processInfo.environment["HIKKI_DEBUG_FULLSCREEN"] != nil

    struct FullScreenChrome: ViewModifier {
        @State private var isFullScreen = debugFullScreen

        func body(content: Content) -> some View {
            content
                .windowToolbarFullScreenVisibility(.visible)
                // A toolbar with a background is one the columns sit below, not under: in full screen the
                // window's own title bar inset is gone, and a transparent toolbar put the sidebar's search
                // field in the toolbar row.
                .toolbarBackgroundVisibility(isFullScreen ? .visible : .automatic, for: .windowToolbar)
                .background(FullScreenObserver(isFullScreen: $isFullScreen))
        }
    }

    /// Keeps the traffic lights shown in full screen and reports whether the hosting window is in full
    /// screen (now, and as it enters or leaves).
    private struct FullScreenObserver: NSViewRepresentable {
        @Binding var isFullScreen: Bool

        func makeCoordinator() -> Coordinator { Coordinator(isFullScreen: $isFullScreen) }

        func makeNSView(context: Context) -> WindowProbe {
            let view = WindowProbe()
            // Attach the moment the view lands in a window (and again if it moves to another).
            view.onWindow = { [coordinator = context.coordinator] window in coordinator.attach(to: window) }
            return view
        }

        func updateNSView(_ view: WindowProbe, context: Context) {
            context.coordinator.attach(to: view.window)
        }

        static func dismantleNSView(_ view: WindowProbe, coordinator: Coordinator) {
            coordinator.detach()
        }

        /// An empty view that tells when it is in a window.
        final class WindowProbe: NSView {
            var onWindow: ((NSWindow?) -> Void)?

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                onWindow?(window)
            }
        }

        final class Coordinator {
            private let isFullScreen: Binding<Bool>
            private weak var window: NSWindow?
            private var observers: [any NSObjectProtocol] = []
            private var buttonWatchers: [NSKeyValueObservation] = []

            init(isFullScreen: Binding<Bool>) {
                self.isFullScreen = isFullScreen
            }

            func attach(to window: NSWindow?) {
                guard let window, window !== self.window else { return }
                detach()
                self.window = window
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.holdWindowButtons()
                            self?.update(true)
                        }
                    },
                    center.addObserver(forName: NSWindow.willExitFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.releaseWindowButtons() }
                    },
                    center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.update(false) }
                    },
                ]
                let fullScreen = window.styleMask.contains(.fullScreen)
                if fullScreen { holdWindowButtons() }
                update(fullScreen)
            }

            func detach() {
                releaseWindowButtons()
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                window = nil
            }

            private var buttons: [NSButton] {
                [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
            }

            /// In full screen AppKit keeps the traffic lights in the title bar but fades them out until the
            /// menu bar comes down; they stay opaque here, as Chrome's do, and are put back whenever AppKit
            /// fades them again.
            private func holdWindowButtons() {
                releaseWindowButtons()
                for button in buttons {
                    button.alphaValue = 1
                    buttonWatchers.append(
                        button.observe(\.alphaValue, options: [.new]) { button, _ in
                            MainActor.assumeIsolated {
                                if button.alphaValue < 1 { button.alphaValue = 1 }
                            }
                        })
                }
            }

            /// Leaving full screen: AppKit owns them again.
            private func releaseWindowButtons() {
                buttonWatchers.forEach { $0.invalidate() }
                buttonWatchers = []
            }

            private func update(_ value: Bool) {
                if debugFullScreen { return }
                if isFullScreen.wrappedValue != value { isFullScreen.wrappedValue = value }
            }

        }
    }
#endif
