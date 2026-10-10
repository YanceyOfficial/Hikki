import SwiftUI

/// Onboarding until a workspace exists, then the app.
struct RootView: View {
    var initialPageID: String?
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.workspace == nil {
            OnboardingView()
        } else {
            ContentView(initialPageID: initialPageID)
        }
    }
}
