import SwiftUI

/// Pull to refresh (iOS) on the screens that list pages, for a workspace in iCloud: what this device has waiting
/// goes up and what other devices saved comes down now, rather than at the next push or activation. A workspace on
/// this device only has nothing to pull. Set once on a screen; every vertical scroll view in it takes it.
private struct SyncRefreshable: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        #if os(iOS)
            if model.syncsWithCloud {
                content.refreshable { await model.refreshFromCloud() }
            } else {
                content
            }
        #else
            content
        #endif
    }
}

extension View {
    func syncRefreshable() -> some View { modifier(SyncRefreshable()) }
}
