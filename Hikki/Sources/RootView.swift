import SwiftUI

/// Onboarding until a workspace exists, then the app.
struct RootView: View {
    var initialPageID: String?
    @Environment(AppModel.self) private var model
    @AppStorage(AppearancePreference.storageKey) private var appearance = AppearancePreference.system

    var body: some View {
        Group {
            if model.workspace == nil {
                OnboardingView()
            } else {
                ContentView(initialPageID: initialPageID)
            }
        }
        // Settings → Theme; the editor's web view follows the window's appearance.
        .preferredColorScheme(appearance.colorScheme)
    }
}
