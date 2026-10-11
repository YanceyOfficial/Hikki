import HikkiUI
import SwiftUI

/// Onboarding until a workspace exists, then the app.
struct RootView: View {
    var initialPageID: String?
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system
    @AppStorage(ColorTone.storageKey) private var tone = ColorTone.standard

    var body: some View {
        Group {
            if model.workspace == nil {
                OnboardingView()
            } else {
                ContentView(initialPageID: initialPageID)
            }
        }
        // Settings → Theme, app-wide (see AppearancePreference.apply); the editor follows its window.
        .onAppear { appearance.apply() }
        .onChange(of: appearance) { _, new in new.apply() }
        // Settings → Appearance → Color tone: components read it from the environment; system controls via tint.
        .environment(\.colorTone, tone)
        .tint(tone.fill)
    }
}
