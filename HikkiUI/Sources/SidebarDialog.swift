import SwiftUI

/// One row of a `SidebarDialog`.
public struct SidebarDialogItem<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: LocalizedStringKey
    public let icon: Icon
    /// The row's accessibility identifier (UI tests).
    public let identifier: String

    public init(id: ID, title: LocalizedStringKey, icon: Icon, identifier: String) {
        self.id = id
        self.title = title
        self.icon = icon
        self.identifier = identifier
    }
}

/// Rows of a `SidebarDialog` under an optional heading.
public struct SidebarDialogSection<ID: Hashable>: Identifiable {
    public let id: Int
    public let title: LocalizedStringKey?
    public let items: [SidebarDialogItem<ID>]

    public init(id: Int, title: LocalizedStringKey?, items: [SidebarDialogItem<ID>]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

/// A large dialog with its pages listed on the left and the picked page on the right (Notion's settings): the rows
/// are icon + name, the open one on the sidebar's grey pill with its icon in the colour tone, as in the app's sidebar.
/// A close button (and Escape, through it) dismisses it. Plain values and closures: the caller keeps the selection.
public struct SidebarDialog<ID: Hashable, Content: View>: View {
    private let title: LocalizedStringKey
    private let sections: [SidebarDialogSection<ID>]
    @Binding private var selection: ID
    private let closeTitle: LocalizedStringKey
    private let closeIdentifier: String
    private let onClose: () -> Void
    private let content: (ID) -> Content

    public init(
        _ title: LocalizedStringKey, sections: [SidebarDialogSection<ID>], selection: Binding<ID>, closeTitle: LocalizedStringKey,
        closeIdentifier: String, onClose: @escaping () -> Void, @ViewBuilder content: @escaping (ID) -> Content
    ) {
        self.title = title
        self.sections = sections
        _selection = selection
        self.closeTitle = closeTitle
        self.closeIdentifier = closeIdentifier
        self.onClose = onClose
        self.content = content
    }

    public var body: some View {
        HStack(spacing: Spacing.s0) {
            sidebar
                .frame(width: Size.settingsSidebar)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.border).frame(width: Spacing.px)
            VStack(spacing: Spacing.s0) {
                header
                content(selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Theme.background)
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(title)
                    .font(.hk(.lg, .semibold))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.bottom, Spacing.s2)
                ForEach(sections) { section in
                    if let heading = section.title {
                        Text(heading)
                            .font(.hk(.xs, .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, Spacing.s2)
                            .padding(.top, Spacing.s3)
                            .padding(.bottom, Spacing.s1)
                    } else if section.id != sections.first?.id {
                        Spacer().frame(height: Spacing.s3)
                    }
                    ForEach(section.items) { item in
                        SidebarDialogRow(item: item, isSelected: item.id == selection) { selection = item.id }
                    }
                }
            }
            .padding(Spacing.s3)
            .padding(.top, Spacing.s2)
        }
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            if let item = sections.lazy.flatMap(\.items).first(where: { $0.id == selection }) {
                Text(item.title).font(.hk(.lg, .semibold)).foregroundStyle(Theme.foreground)
            }
            Spacer(minLength: Spacing.s0)
            Button(action: onClose) {
                IconLabel(closeTitle, icon: .x, size: TextSize.base.rawValue)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: Size.iconButton, height: Size.iconButton)
                    .contentShape(.rect)
            }
            .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
            // Escape closes the dialog.
            .keyboardShortcut(.cancelAction)
            .help(Text(closeTitle))
            .accessibilityIdentifier(closeIdentifier)
        }
        .padding(.horizontal, Spacing.s5)
        .padding(.vertical, Spacing.s3)
    }
}

private struct SidebarDialogRow<ID: Hashable>: View {
    let item: SidebarDialogItem<ID>
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorTone) private var tone
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s2) {
                IconView(item.icon, size: Size.sidebarIcon)
                    .foregroundStyle(isSelected ? tone.fill : Theme.subtleForeground)
                Text(item.title)
                    .font(.hk(.md, isSelected ? .medium : .regular))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
            }
            .padding(.horizontal, Spacing.s2)
            .frame(maxWidth: .infinity, minHeight: Size.row, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(isSelected ? Theme.sidebarAccent : hovering ? Theme.sidebarAccent.opacity(0.55) : .clear)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(), value: isSelected)
        .animation(Motion.easeOut(Motion.popOut), value: hovering)
        .accessibilityIdentifier(item.identifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    @Previewable @State var page = "general"
    SidebarDialog(
        "Settings",
        sections: [
            SidebarDialogSection(
                id: 0, title: "Workspace", items: [.init(id: "workspace", title: "Workspace", icon: .house, identifier: "w")]),
            .init(
                id: 1, title: "App",
                items: [
                    .init(id: "general", title: "General", icon: .gearSix, identifier: "g"),
                    .init(id: "ai", title: "AI", icon: .sparkle, identifier: "a"),
                ]),
            .init(id: 2, title: nil, items: [.init(id: "about", title: "About", icon: .info, identifier: "i")]),
        ],
        selection: $page, closeTitle: "Close", closeIdentifier: "close", onClose: {}
    ) { page in
        Form { Text(verbatim: page) }.formStyle(.grouped)
    }
    .frame(width: Size.settingsWidth, height: Size.settingsHeight)
}
