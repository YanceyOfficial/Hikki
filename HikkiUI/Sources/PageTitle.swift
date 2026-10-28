import SwiftUI

/// A page's title as it is shown: the title, or "Untitled" for an empty one — the one place that fallback is written
/// (the app's `PageSummary.displayTitle` reads it; HikkiUI's rows take a `String` and call it themselves).
public enum PageTitle {
    /// Pure string work, so callers off the main thread (the reminders' parse queue) may use it too.
    public nonisolated static func display(_ title: String) -> String {
        title.isEmpty ? String(localized: "app:page.untitled") : title
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.s2) {
        Text(verbatim: PageTitle.display("Trip to Kyoto"))
        Text(verbatim: PageTitle.display(""))
    }
    .padding()
}
