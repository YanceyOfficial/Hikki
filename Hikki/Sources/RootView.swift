import HikkiCore
import HikkiUI
import SwiftUI

/// Onboarding until a workspace exists, then the app.
struct RootView: View {
    var initialPageID: String?
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    /// One tone for now (Kurenai); the palettes stay in the tokens for later.
    private let tone = ColorTone.standard

    var body: some View {
        Group {
            if model.workspace == nil {
                OnboardingView()
            } else {
                ContentView(initialPageID: initialPageID)
            }
        }
        #if os(iOS)
            .modifier(VerticalBarReader())
            // Folding or unfolding an iPhone Duo moves the window to the other screen: which way it may turn changes.
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: { _ in
                for scene in UIApplication.shared.connectedScenes {
                    (scene as? UIWindowScene)?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        #endif
        // Settings → Theme, app-wide (see AppearancePreference.apply); the editor follows its window.
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, new in new.apply() }
        // Settings → Appearance → Color tone: components read it from the environment; system controls via tint.
        .environment(\.colorTone, tone)
        .tint(tone.fill)
    }
}

#if os(iOS)
    /// The edge of the system's vertical bar (an iPhone Duo: the strip beside the camera, where the status bar and the
    /// navigation bar's buttons go), or nil where there is none — iOS 27.1's `toolbarVerticalEdge`, read once here
    /// so views don't each need the availability check. Where it is, the iPhone's own floating bar and top bar hand
    /// their buttons to it (`PhoneHome`, `PageScreen`).
    private struct VerticalBarReader: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 27.1, *) {
                content.modifier(Reading())
            } else {
                content
            }
        }

        @available(iOS 27.1, *)
        private struct Reading: ViewModifier {
            @Environment(\.toolbarVerticalEdge) private var edge

            func body(content: Content) -> some View {
                content.environment(\.verticalBarEdge, edge)
            }
        }
    }

    extension EnvironmentValues {
        /// See `VerticalBarReader`.
        @Entry var verticalBarEdge: HorizontalEdge?
    }

    /// A sheet covers the system's vertical bar (an iPhone Duo's strip beside the camera), yet it is handed the
    /// window's inset on that side, so its content stopped short of its edge. Inside a sheet that inset goes.
    private struct SheetOverVerticalBar: ViewModifier {
        @Environment(\.verticalBarEdge) private var edge

        func body(content: Content) -> some View {
            content.ignoresSafeArea(.container, edges: edge == .leading ? .leading : edge == .trailing ? .trailing : [])
        }
    }
#endif

extension View {
    /// A sheet's content, laid out to the sheet's own edges where a vertical bar would otherwise inset it (iOS).
    func sheetOverVerticalBar() -> some View {
        #if os(iOS)
            modifier(SheetOverVerticalBar())
        #else
            self
        #endif
    }
}
