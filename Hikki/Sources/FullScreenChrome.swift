import SwiftUI

extension View {
    /// Full screen (macOS), Chrome's way: the menu bar stays, and with it the traffic lights and the toolbar
    /// row; the columns start below that row exactly as they do in a window. AppKit decides the menu bar
    /// through the window delegate's full-screen presentation options — SwiftUI owns that delegate, so a
    /// proxy answers that one question and forwards everything else. (Photos' hide-and-slide-in bar kept
    /// landing on the sidebar's search field without a background; the user gave up on it.)
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

    /// Installs the delegate proxy, keeps the traffic lights shown in full screen, and reports whether the
    /// hosting window is in full screen (now, and as it enters or leaves).
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
            private let proxy = FullScreenDelegateProxy()
            private weak var window: NSWindow?
            private var observers: [any NSObjectProtocol] = []

            init(isFullScreen: Binding<Bool>) {
                self.isFullScreen = isFullScreen
            }

            func attach(to window: NSWindow?) {
                guard let window else { return }
                // SwiftUI may put its own delegate back; ours wraps whatever is there.
                if window.delegate !== proxy {
                    proxy.original = window.delegate
                    window.delegate = proxy
                }
                guard window !== self.window else { return }
                detach()
                self.window = window
                let center = NotificationCenter.default
                observers = [
                    center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated {
                            self?.showWindowButtons()
                            self?.update(true)
                        }
                    },
                    center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.update(false) }
                    },
                ]
                let fullScreen = window.styleMask.contains(.fullScreen)
                if fullScreen { showWindowButtons() }
                update(fullScreen)
            }

            func detach() {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                window = nil
            }

            /// AppKit hides the traffic lights on entering full screen; they come back (Chrome keeps them).
            private func showWindowButtons() {
                for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                    window?.standardWindowButton(kind)?.isHidden = false
                }
            }

            private func update(_ value: Bool) {
                if debugFullScreen { return }
                if isFullScreen.wrappedValue != value { isFullScreen.wrappedValue = value }
            }
        }
    }

    /// Answers the full-screen presentation options — keep the menu bar — and forwards every other delegate
    /// call to SwiftUI's own window delegate.
    // Message forwarding is answered on whatever thread AppKit asks from, so the class steps out of the
    // app's main-actor default; the delegate call itself is main-actor, as AppKit promises.
    nonisolated private final class FullScreenDelegateProxy: NSObject, NSWindowDelegate {
        weak var original: NSWindowDelegate?

        override func responds(to aSelector: Selector!) -> Bool {
            super.responds(to: aSelector) || original?.responds(to: aSelector) == true
        }

        override func forwardingTarget(for aSelector: Selector!) -> Any? { original }

        @MainActor func window(
            _ window: NSWindow, willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions
        ) -> NSApplication.PresentationOptions {
            proposedOptions.subtracting(.autoHideMenuBar)
        }
    }
#endif
