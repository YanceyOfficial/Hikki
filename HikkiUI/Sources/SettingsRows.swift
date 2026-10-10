import SwiftUI

/// Notion-style settings building blocks: a titled section with a hairline, rows of title + detail +
/// trailing control, and the left column's navigation item.

/// A settings group: small title, hairline, then its rows.
public struct SettingsSection<Content: View>: View {
    private let title: LocalizedStringKey
    private let content: Content

    public init(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            Text(title)
                .font(.hk(.base, .semibold))
                .foregroundStyle(Theme.foreground)
                .padding(.bottom, Spacing.s3)
            Theme.border.frame(height: 1)
            VStack(alignment: .leading, spacing: Spacing.s5) { content }
                .padding(.top, Spacing.s5)
        }
    }
}

/// One setting: what it is (and a one-line explanation) on the left, its control on the right.
public struct SettingsRow<Trailing: View>: View {
    private let title: LocalizedStringKey
    private let detail: LocalizedStringKey?
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, detail: LocalizedStringKey? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.trailing = trailing()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: Spacing.s6) {
                labels
                Spacer(minLength: Spacing.s4)
                trailing
            }
            // Narrow (iPhone): the control goes under the text.
            VStack(alignment: .leading, spacing: Spacing.s2) {
                labels
                trailing
            }
        }
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Text(title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground)
            if let detail {
                Text(detail).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// An item in the settings window's left column.
public struct SettingsNavItem: View {
    private let title: LocalizedStringKey
    private let icon: Icon
    private let isSelected: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, icon: Icon, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                IconView(icon, size: Size.sidebarIcon).foregroundStyle(Theme.sidebarForeground)
                Text(title).font(.hk(.sm, isSelected ? .medium : .regular)).foregroundStyle(Theme.foreground)
                Spacer(minLength: 0)
            }
            .frame(height: Size.row)
            .contentShape(.rect)
            .sidebarItemBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("Settings rows") {
    VStack(alignment: .leading, spacing: Spacing.s8) {
        SettingsSection("Appearance") {
            SettingsRow("Theme", detail: "Choose a theme for this device") {
                Picker("Theme", selection: .constant(0)) {
                    Text("System").tag(0)
                    Text("Dark").tag(1)
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingsRow("Version") { Text(verbatim: "1.0 (1)").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground) }
        }
        VStack(spacing: Spacing.s0_5) {
            SettingsNavItem("Preferences", icon: .slidersHorizontal, isSelected: true) {}
            SettingsNavItem("About", icon: .info, isSelected: false) {}
        }
        .frame(width: 220)
    }
    .padding(Spacing.s8)
    .frame(width: 640)
    .background(Theme.background)
}
