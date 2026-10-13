import HikkiUI
import SwiftUI

extension View {
    /// Photos' top scrim in full screen (macOS): the auto-hidden title bar and toolbar slide down over the
    /// content there, so a gradient from the column's colour to clear sits at the top of each column — the
    /// traffic lights and toolbar buttons stay readable, and the top rows fade under them instead of
    /// colliding. Nothing is drawn in a normal window, or on iOS.
    func fullScreenScrim(_ color: Color) -> some View {
        #if os(macOS)
            modifier(FullScreenScrim(color: color))
        #else
            self
        #endif
    }
}

#if os(macOS)
    import AppKit

    /// `HIKKI_DEBUG_SCRIM` forces the scrim on (screenshots).
    private let debugScrim = ProcessInfo.processInfo.environment["HIKKI_DEBUG_SCRIM"] != nil

    struct FullScreenScrim: ViewModifier {
        let color: Color
        @State private var isFullScreen = debugScrim

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .top) {
                    if isFullScreen {
                        LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: Size.fullscreenScrim)
                            .allowsHitTesting(false)
                            .ignoresSafeArea(edges: .top)
                            .transition(.opacity)
                    }
                }
                .background(FullScreenObserver(isFullScreen: $isFullScreen))
                .animation(Motion.easeOut(), value: isFullScreen)
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
                if debugScrim { return }
                if isFullScreen.wrappedValue != value { isFullScreen.wrappedValue = value }
            }
        }
    }
#endif
