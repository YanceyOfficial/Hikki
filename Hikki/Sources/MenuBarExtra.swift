import HikkiCore
import SwiftUI

#if os(macOS)
    import AppKit

    /// Settings → General → Menu bar. Kept in UserDefaults by hand, observed as a plain object: an `@AppStorage`
    /// binding handed to `MenuBarExtra(isInserted:)` made SwiftUI rebuild the main menu and every scene without
    /// end (the window stayed blank, the main thread at 100 %) whenever the app was launched by Launch Services.
    @Observable
    @MainActor
    final class MenuBarPreferences {
        static let showKey = "menuBar.show"
        static let shared = MenuBarPreferences()

        var show: Bool {
            didSet { UserDefaults.standard.set(show, forKey: Self.showKey) }
        }

        private init() {
            show = UserDefaults.standard.object(forKey: Self.showKey) as? Bool ?? true
        }
    }

    /// What the menu bar menu asked the main window to do.
    struct MenuBarRequest: Equatable, Identifiable {
        enum Kind { case newPage, search }
        let id = UUID()
        let kind: Kind
    }

    /// The menu bar menu has no focused window, so it can't reach a `Navigator`: it posts a request here and the
    /// key window's ContentView performs it (`menuBarRequests(navigator:)`).
    @Observable
    final class MenuBarRequests {
        static let shared = MenuBarRequests()
        var pending: MenuBarRequest?
    }

    /// The status item: Hikki's glyph (a template image, design/icon/hi-star/menubar.svg) and a short menu that
    /// works while another app is in front. Optional — Settings → General → Menu bar.
    struct MenuBarScene: Scene {
        @Bindable private var preferences = MenuBarPreferences.shared

        var body: some Scene {
            MenuBarExtra(isInserted: $preferences.show) {
                MenuBarMenu()
            } label: {
                Image("MenuBarIcon")
            }
        }
    }

    private struct MenuBarMenu: View {
        @Environment(\.openSettings) private var openSettings

        var body: some View {
            Button("app:menubar.open") { MainWindows.showMain() }
            Button("app:page.new") { request(.newPage) }
            Button("app:menu.search") { request(.search) }
            Divider()
            Button("app:settings.open") {
                NSApp.activate()
                openSettings()
            }
            Divider()
            Button("app:menubar.quit") { NSApp.terminate(nil) }
        }

        /// Bring the main window forward first so it is the key window when the request lands.
        private func request(_ kind: MenuBarRequest.Kind) {
            MainWindows.showMain()
            MenuBarRequests.shared.pending = MenuBarRequest(kind: kind)
        }
    }

    extension View {
        /// Performs menu bar requests in this window when it is the key one.
        func menuBarRequests(navigator: Navigator) -> some View {
            modifier(MenuBarRequestHandler(navigator: navigator))
        }
    }

    private struct MenuBarRequestHandler: ViewModifier {
        let navigator: Navigator
        @State private var window: NSWindow?

        func body(content: Content) -> some View {
            content
                .background(WindowReader(window: $window))
                .onChange(of: MenuBarRequests.shared.pending?.id) { _, _ in
                    guard let request = MenuBarRequests.shared.pending, let window, window.isKeyWindow else { return }
                    MenuBarRequests.shared.pending = nil
                    switch request.kind {
                    case .newPage: navigator.newPage()
                    case .search: navigator.isSearching = true
                    }
                }
        }
    }

    /// Captures the hosting NSWindow (SwiftUI has no window environment on macOS).
    private struct WindowReader: NSViewRepresentable {
        @Binding var window: NSWindow?

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            DispatchQueue.main.async { window = view.window }
            return view
        }

        func updateNSView(_ view: NSView, context: Context) {
            DispatchQueue.main.async { if window !== view.window { window = view.window } }
        }
    }
#else
    extension View {
        func menuBarRequests(navigator: Navigator) -> some View { self }
    }
#endif
