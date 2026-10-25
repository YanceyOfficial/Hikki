import SwiftUI

/// One page the picker offers (the app builds them from `PageTree.moveChoices`): plain values.
public struct MovePickerItem: Identifiable, Equatable, Sendable {
    public let id: String
    /// Empty: untitled.
    public let title: String
    public let icon: String?
    public let depth: Int
    public let hasChildren: Bool
    public let isExpanded: Bool
    /// Where the page is now: shown with a check, not pickable.
    public let isCurrent: Bool
    /// Search results: the pages above it ("Work / Projects"); empty in the tree.
    public let path: String

    public init(
        id: String, title: String, icon: String?, depth: Int = 0, hasChildren: Bool = false, isExpanded: Bool = false,
        isCurrent: Bool = false, path: String = ""
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.depth = depth
        self.hasChildren = hasChildren
        self.isExpanded = isExpanded
        self.isCurrent = isCurrent
        self.path = path
    }
}

/// Move to (Notion's "Move page to…"): a search field on top; without a query the top-level pages as "Suggested",
/// each with a disclosure that opens its children in place; with one, the matching pages with their path. The
/// workspace sits at the foot — picking it moves the page to the top level. ↑ ↓ move the highlight (→ ← open and
/// close a page while the field is empty), Return picks, Escape cancels. `onPick(nil)` is the top level.
public struct MovePagePicker<Badge: View>: View {
    @Binding private var query: String
    private let items: [MovePickerItem]
    private let workspaceName: String
    private let isAtTopLevel: Bool
    private let focusesField: Bool
    private let isComposing: () -> Bool
    private let badge: Badge
    private let onToggle: (String) -> Void
    private let onPick: (String?) -> Void
    private let onCancel: () -> Void
    @State private var selected: Entry?
    @FocusState private var fieldFocused: Bool

    /// `badge`: the workspace's own badge, drawn on the top-level row. `isComposing`: an input method holds marked
    /// text, so the arrows, Return and Escape are its own.
    public init(
        query: Binding<String>, items: [MovePickerItem], workspaceName: String, isAtTopLevel: Bool,
        focusesField: Bool = true, isComposing: @escaping () -> Bool = { false }, @ViewBuilder badge: () -> Badge,
        onToggle: @escaping (String) -> Void, onPick: @escaping (String?) -> Void, onCancel: @escaping () -> Void
    ) {
        _query = query
        self.items = items
        self.workspaceName = workspaceName
        self.isAtTopLevel = isAtTopLevel
        self.focusesField = focusesField
        self.isComposing = isComposing
        self.badge = badge()
        self.onToggle = onToggle
        self.onPick = onPick
        self.onCancel = onCancel
    }

    private enum Entry: Hashable {
        case page(String)
        case topLevel
    }

    private var searching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Keyboard order: the rows, then the workspace at the foot.
    private var entries: [Entry] { items.map { .page($0.id) } + [.topLevel] }

    private func isEnabled(_ entry: Entry) -> Bool {
        switch entry {
        case .page(let id): !(items.first(where: { $0.id == id })?.isCurrent ?? true)
        case .topLevel: !isAtTopLevel
        }
    }

    public var body: some View {
        VStack(spacing: Spacing.s0) {
            field
            Theme.border.frame(height: Spacing.px)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.px) {
                        Text(searching ? "app:move.results" : "app:move.suggested")
                            .font(.hk(.xs, .medium))
                            .foregroundStyle(Theme.mutedForeground)
                            .padding(.horizontal, Spacing.s2)
                            .padding(.top, Spacing.s2)
                            .padding(.bottom, Spacing.s1)
                        if items.isEmpty && searching {
                            Text("app:move.noResults")
                                .font(.hk(.sm))
                                .foregroundStyle(Theme.mutedForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.s6)
                        }
                        ForEach(items) { item in
                            row(item).id(Entry.page(item.id))
                        }
                    }
                    .padding(Spacing.s1_5)
                }
                .scrollIndicators(.automatic)
                .onChange(of: selected) { _, entry in
                    if let entry, entry != .topLevel { proxy.scrollTo(entry) }
                }
            }
            Theme.border.frame(height: Spacing.px)
            topLevelRow
                .padding(Spacing.s1_5)
        }
        #if os(macOS)
            .frame(width: Size.movePickerWidth, height: Size.movePickerHeight)
            .background(Theme.popover)
        #else
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
        #endif
        .onAppear {
            if focusesField { fieldFocused = true }
            keepSelection()
        }
        .onChange(of: items) { _, _ in keepSelection() }
        .onKeyPress(.downArrow) { isComposing() ? .ignored : move(1) }
        .onKeyPress(.upArrow) { isComposing() ? .ignored : move(-1) }
        // → opens the highlighted page's children, ← closes them — only while the field is empty (the caret's keys
        // otherwise).
        .onKeyPress(.rightArrow) { disclose(open: true) }
        .onKeyPress(.leftArrow) { disclose(open: false) }
        .onKeyPress(.escape) {
            guard !isComposing() else { return .ignored }
            onCancel()
            return .handled
        }
        .accessibilityIdentifier("move-picker")
    }

    private var field: some View {
        HStack(spacing: Spacing.s2_5) {
            IconView(.magnifyingGlass, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
            TextField("app:move.placeholder", text: $query)
                .textFieldStyle(.plain)
                .font(.hk(.base))
                .focused($fieldFocused)
                .onSubmit(pickSelected)
                .accessibilityIdentifier("move-search")
            #if os(iOS)
                Button("app:common.cancel", action: onCancel).foregroundStyle(Theme.subtleForeground)
            #else
                // A sheet on the Mac can't be clicked away: Escape or this — the search palette's close button.
                Button(action: onCancel) {
                    IconView(.x, size: TextSize.sm.rawValue)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.iconButton, height: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.full))
                .help("app:common.close")
                .accessibilityLabel("app:common.close")
            #endif
        }
        .padding(.horizontal, Spacing.s3_5)
        .padding(.vertical, Spacing.s3)
    }

    private func row(_ item: MovePickerItem) -> some View {
        let entry = Entry.page(item.id)
        return HStack(spacing: Spacing.s1_5) {
            if !searching { disclosure(item) }
            PageIcon(item.icon, size: Size.pageIcon)
            VStack(alignment: .leading, spacing: Spacing.s0) {
                Text(verbatim: PageTitle.display(item.title))
                    .font(.hk(.sm))
                    .foregroundStyle(item.isCurrent ? Theme.mutedForeground : Theme.foreground)
                    .lineLimit(1)
                if !item.path.isEmpty {
                    Text(verbatim: item.path).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                }
            }
            Spacer(minLength: Spacing.s2)
            if item.isCurrent {
                IconView(.check, size: TextSize.sm.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityLabel("app:move.current")
            }
        }
        .padding(.leading, CGFloat(item.depth) * Spacing.s5)
        .padding(.horizontal, Spacing.s1_5)
        .padding(.vertical, item.path.isEmpty ? Spacing.s0 : Spacing.s1)
        .frame(minHeight: Size.row)
        .background(selected == entry ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
        .onTapGesture { pick(entry) }
        .onHover { if $0 { selected = entry } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("move-target-\(item.id)")
    }

    /// The caret that opens a page's children in place; the same room, empty, where there are none.
    @ViewBuilder private func disclosure(_ item: MovePickerItem) -> some View {
        if item.hasChildren {
            Button {
                withAnimation(Motion.easeOut()) { onToggle(item.id) }
            } label: {
                IconView(.caretRight, size: TextSize.xs.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                    .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                    .contentShape(.rect)
            }
            .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.sm))
            .accessibilityLabel(Text(item.isExpanded ? "app:sidebar.collapse" : "app:sidebar.expand"))
        } else {
            Color.clear.frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
        }
    }

    private var topLevelRow: some View {
        HStack(spacing: Spacing.s2) {
            badge
            Text(verbatim: workspaceName)
                .font(.hk(.sm, .medium))
                .foregroundStyle(isAtTopLevel ? Theme.mutedForeground : Theme.foreground)
                .lineLimit(1)
            Spacer(minLength: Spacing.s2)
            if isAtTopLevel {
                IconView(.check, size: TextSize.sm.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .accessibilityLabel("app:move.current")
            } else {
                Text("app:page.moveToTopLevel").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
            }
        }
        .padding(.horizontal, Spacing.s2)
        .frame(minHeight: Size.row)
        .background(selected == .topLevel ? Theme.accentStrong : .clear, in: .rect(cornerRadius: Radius.md))
        .contentShape(.rect)
        .onTapGesture { pick(.topLevel) }
        .onHover { if $0 { selected = .topLevel } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("move-target-top")
    }


    /// The highlight stays on its row while it is still there, else goes to the first one that can be picked.
    private func keepSelection() {
        if let selected, entries.contains(selected), isEnabled(selected) { return }
        selected = entries.first(where: isEnabled)
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        let enabled = entries.filter(isEnabled)
        guard !enabled.isEmpty else { return .ignored }
        guard let selected, let index = enabled.firstIndex(of: selected) else {
            self.selected = delta > 0 ? enabled.first : enabled.last
            return .handled
        }
        self.selected = enabled[(index + delta + enabled.count) % enabled.count]
        return .handled
    }

    private func disclose(open: Bool) -> KeyPress.Result {
        guard !searching, !isComposing(), case .page(let id)? = selected,
            let item = items.first(where: { $0.id == id }), item.hasChildren, item.isExpanded != open
        else { return .ignored }
        withAnimation(Motion.easeOut()) { onToggle(id) }
        return .handled
    }

    private func pickSelected() {
        if let selected { pick(selected) }
    }

    private func pick(_ entry: Entry) {
        guard isEnabled(entry) else { return }
        switch entry {
        case .page(let id): onPick(id)
        case .topLevel: onPick(nil)
        }
    }
}

#Preview {
    @Previewable @State var query = ""
    @Previewable @State var expanded: Set<String> = ["work"]
    let tree: [MovePickerItem] = [
        .init(id: "work", title: "Work", icon: "💼", hasChildren: true, isExpanded: expanded.contains("work")),
        .init(id: "roadmap", title: "Roadmap", icon: nil, depth: 1, isCurrent: true),
        .init(id: "sync", title: "Weekly sync", icon: "🗓️", depth: 1),
        .init(id: "trip", title: "Trip to Kyoto", icon: "🗾", hasChildren: true, isExpanded: expanded.contains("trip")),
        .init(id: "reading", title: "", icon: nil),
    ]
    let found = tree.filter { $0.title.localizedStandardContains(query) }.map {
        MovePickerItem(id: $0.id, title: $0.title, icon: $0.icon, isCurrent: $0.isCurrent, path: $0.depth > 0 ? "Work" : "")
    }
    MovePagePicker(
        query: $query, items: query.isEmpty ? tree.filter { $0.depth == 0 || expanded.contains("work") } : found,
        workspaceName: "Yancey's Notes", isAtTopLevel: false, badge: { Text(verbatim: "📓") },
        onToggle: { id in
            if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
        },
        onPick: { _ in }, onCancel: {})
}
