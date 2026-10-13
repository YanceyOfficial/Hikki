import HikkiUI
import SwiftUI

extension View {
    /// Photos' full screen (macOS): the auto-hidden title bar and toolbar slide down over the content, and
    /// there they get the system's translucent toolbar band — a blurred, dimmed strip across both columns —
    /// so the traffic lights and buttons read over whatever is under them (the sidebar's search field, the
    /// page's top rows), and nothing moves. In a window the toolbar stays transparent, as everywhere else.
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
                .toolbarBackgroundVisibility(isFullScreen ? .visible : .automatic, for: .windowToolbar)
                .background(FullScreenObserver(isFullScreen: $isFullScreen))
        }
    }

    /// Reports whether the hosting window is in full screen (now, and as it enters or leaves).
    private struct FullScreenObserver: NSViewRepresentable {
        @Binding var isFullScreen: Bool

        func makeCoordinator() -> Coordinator { Coordinator(isFullScreen: $isFullScreen) }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            // The window is known only once the view is in it.
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        }

        static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
            coordinator.detach()
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
