import HikkiUI
import SwiftUI

extension View {
    /// Photos' full screen (macOS): the toolbar hides with the menu bar and slides back in with it as a
    /// detached bar over the content — and, while the window is in full screen, that bar always has the
    /// system's translucent background. Without the background the bar only got one when scrolled content
    /// happened to lie under it (the scroll edge effect), so the traffic lights sometimes sat bare on the
    /// sidebar's search field. In a window the toolbar stays transparent, as everywhere else.
    func fullScreenToolbarBackground() -> some View {
        #if os(macOS)
            modifier(FullScreenToolbarBackground())
        #else
            self
        #endif
    }
}

#if os(macOS)
    import AppKit

    /// `HIKKI_DEBUG_FULLSCREEN` forces the full-screen look on in a window (screenshots).
    private let debugFullScreen = ProcessInfo.processInfo.environment["HIKKI_DEBUG_FULLSCREEN"] != nil

    struct FullScreenToolbarBackground: ViewModifier {
        @State private var isFullScreen = debugFullScreen

        func body(content: Content) -> some View {
            content
                .windowToolbarFullScreenVisibility(.onHover)
                .toolbarBackgroundVisibility(isFullScreen ? .visible : .automatic, for: .windowToolbar)
                .background(FullScreenObserver(isFullScreen: $isFullScreen))
        }
    }

    /// Reports whether the hosting window is in full screen (now, and as it enters or leaves).
    private struct FullScreenObserver: NSViewRepresentable {
        @Binding var isFullScreen: Bool

        func makeCoordinator() -> Coordinator { Coordinator(isFullScreen: $isFullScreen) }

        func makeNSView(context: Context) -> WindowProbe {
            let view = WindowProbe()
            // Attach the moment the view lands in a window (and again if it moves to another): a one-off
            // look after creation missed windows that weren't there yet.
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
                        MainActor.assumeIsolated { self?.update(true) }
                    },
                    center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) {
                        [weak self] _ in
                        MainActor.assumeIsolated { self?.update(false) }
                    },
                ]
                update(window.styleMask.contains(.fullScreen))
            }

            func detach() {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                window = nil
            }

            private func update(_ value: Bool) {
                if debugFullScreen { return }
                if isFullScreen.wrappedValue != value { isFullScreen.wrappedValue = value }
            }
        }
    }
#endif
