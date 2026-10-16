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
            .modifier(PhonePosture())
            .modifier(VerticalBarReader())
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
    /// An iPhone in a regular-width posture (an unfolded iPhone Duo upright, a large iPhone on its side) reads as
    /// compact, so it keeps the iPhone's own layout; unfolded on its side it gets the iPad's (`PhoneLayout`). Measured
    /// with a GeometryReader so the first frame already has the right layout (no flip after launch).
    private struct PhonePosture: ViewModifier {
        @Environment(\.horizontalSizeClass) private var horizontal
        @Environment(\.verticalSizeClass) private var vertical

        func body(content: Content) -> some View {
            GeometryReader { proxy in
                let compact = PhoneLayout.forcesCompact(
                    isPhone: UIDevice.current.userInterfaceIdiom == .phone, horizontalRegular: horizontal == .regular,
                    verticalRegular: vertical == .regular, size: proxy.size)
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .environment(\.horizontalSizeClass, compact ? .compact : horizontal)
            }
        }
    }

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
#endif
