import HikkiCore
import SwiftUI

/// The app's `NSUserActivity` types (also under `NSUserActivityTypes` in the Info.plist).
enum HikkiActivity {
    /// What is on screen, as the scene's current activity: iOS titles a screenshot after its `title` (the share
    /// sheet's header, the file's name when it is AirDropped).
    static let viewing = "app.yancey.hikki.viewing"
}

/// The scene's titled screens, shared through the environment by `publishesScreenTitle()`.
@MainActor @Observable
final class ScreenTitleRegistry {
    private(set) var stack = ScreenTitleStack()

    func show(_ id: UUID, depth: Int, title: String) { stack.show(id, depth: depth, title: title) }
    func hide(_ id: UUID) { stack.hide(id) }
}

extension EnvironmentValues {
    /// How many titled screens this view is nested in.
    @Entry var screenTitleDepth: Int = 0
}

extension View {
    /// Names what this view shows, for the system: a screenshot taken while it is the frontmost titled screen is
    /// titled after it (a sheet over it wins while it is up). Needs `publishesScreenTitle()` above it.
    func screenTitle(_ title: String) -> some View {
        modifier(ScreenTitleModifier(title: title))
    }

    /// The scene's one `.userActivity`: the frontmost `screenTitle(_:)` as the current activity's title. Screens
    /// register here instead of publishing activities of their own, so which one is current never depends on how
    /// SwiftUI picks between several.
    func publishesScreenTitle() -> some View {
        modifier(ScreenTitlePublisher())
    }
}

private struct ScreenTitleModifier: ViewModifier {
    let title: String
    @Environment(ScreenTitleRegistry.self) private var registry: ScreenTitleRegistry?
    @Environment(\.screenTitleDepth) private var depth
    @State private var id = UUID()
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .environment(\.screenTitleDepth, depth + 1)
            .onAppear {
                isShown = true
                registry?.show(id, depth: depth + 1, title: title)
            }
            // Only while shown: a screen covered by another is still there, and must not come back in front.
            .onChange(of: title) { if isShown { registry?.show(id, depth: depth + 1, title: title) } }
            .onDisappear {
                isShown = false
                registry?.hide(id)
            }
    }
}

private struct ScreenTitlePublisher: ViewModifier {
    @State private var registry = ScreenTitleRegistry()

    func body(content: Content) -> some View {
        // Read in the body, so the activity follows the frontmost title.
        let title = registry.stack.front
        content
            .environment(registry)
            .userActivity(HikkiActivity.viewing, isActive: title != nil) { activity in
                activity.title = title
                activity.isEligibleForHandoff = false
                activity.isEligibleForSearch = false
                #if os(iOS)
                    activity.isEligibleForPrediction = false
                #endif
            }
    }
}
