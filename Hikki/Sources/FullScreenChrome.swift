import HikkiCore
import SwiftUI

extension View {
    /// Full screen (macOS), Xcode's and Safari's way: the toolbar row stays, and the columns start below it
    /// exactly as they do in a window; the traffic lights come down with the menu bar into that row. AppKit
    /// moves the toolbar into its own full-screen window and does not draw the window buttons there until
    /// the menu bar shows — holding their alpha or hidden state changes nothing — so Chrome's always-visible
    /// lights would have to be drawn by hand. (Photos' hide-and-slide-in bar kept landing on the sidebar's
    /// search field without a background; given up.)
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

    /// Reports whether the hosting window is in full screen — read from the window's style mask whenever it
    /// could have changed (entering, leaving, a resize, becoming key), so a window restored straight into
    /// full screen counts too.
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

            init(isFullScreen: Binding<Bool>) {
                self.isFullScreen = isFullScreen
            }

            func attach(to window: NSWindow?) {
                guard let window, window !== self.window else { return }
                detach()
                self.window = window
                let center = NotificationCenter.default
                let names: [Notification.Name] = [
                    NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification,
                    NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                ]
                observers = names.map { name in
                    center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        MainActor.assumeIsolated { self?.sync() }
                    }
                }
                sync()
                #if DEBUG
                    debugHooks()
                #endif
            }

            func detach() {
                observers.forEach(NotificationCenter.default.removeObserver)
                observers = []
                window = nil
            }

            /// Reads the window's state and applies it; safe to call as often as the window changes.
            private func sync() {
                guard let window else { return }
                let fullScreen = window.styleMask.contains(.fullScreen)
                guard !debugFullScreen, isFullScreen.wrappedValue != fullScreen else { return }
                isFullScreen.wrappedValue = fullScreen
                Log.info(
                    "full screen changed", category: "fullscreen",
                    context: [
                        "fullScreen": "\(fullScreen)",
                        "titlebarHeight": "\(window.frame.height - window.contentLayoutRect.height)",
                    ])
            }

            #if DEBUG
                private var hooksArmed = false

                /// `HIKKI_DEBUG_ENTER_FULLSCREEN` enters full screen shortly after launch; `HIKKI_DEBUG_QUIT_AFTER=<s>`
                /// quits after that many seconds (own-instance checks of the full-screen chrome).
                private func debugHooks() {
                    guard !hooksArmed else { return }
                    hooksArmed = true
                    let env = ProcessInfo.processInfo.environment
                    if env["HIKKI_DEBUG_ENTER_FULLSCREEN"] != nil {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                            if let window = self?.window, !window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
                        }
                    }
                    if let seconds = env["HIKKI_DEBUG_QUIT_AFTER"].flatMap(Double.init) {
                        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { NSApp.terminate(nil) }
                    }
                }
            #endif
        }
    }
#endif
