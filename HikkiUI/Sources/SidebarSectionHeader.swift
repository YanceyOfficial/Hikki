import SwiftUI

/// Small grey section label ("Favorites", "Private").
public struct SidebarSectionHeader: View {
    private let title: LocalizedStringKey

    public init(_ title: LocalizedStringKey) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.mutedText)
            .textCase(nil)
    }
}
