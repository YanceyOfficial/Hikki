import SwiftUI

/// Small grey section label ("app:sidebar.favorites", "app:sidebar.private").
public struct SidebarSectionHeader: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.hk(.xs, .medium))
            .foregroundStyle(Theme.mutedForeground)
            .textCase(nil)
    }
}
