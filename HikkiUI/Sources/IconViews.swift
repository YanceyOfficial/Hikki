import SwiftUI

/// An `Icon` at a fixed square size, tinted by the surrounding foreground style.
public struct IconView: View {
    private let icon: Icon
    private let size: CGFloat

    public init(_ icon: Icon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        icon.image
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// `Label` with an `Icon` — the replacement for `Label(_:systemImage:)` (menus, buttons). In menus the
/// system sizes the symbol itself (`glyph`).
public struct IconLabel: View {
    private let title: LocalizedStringKey
    private let icon: Icon
    private let size: CGFloat

    public init(_ title: LocalizedStringKey, icon: Icon, size: CGFloat = 16) {
        self.title = title
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Label {
            Text(title)
        } icon: {
            if icon.systemName != nil {
                icon.glyph
            } else {
                icon.image.aspectRatio(contentMode: .fit).frame(width: size, height: size)
            }
        }
    }
}
