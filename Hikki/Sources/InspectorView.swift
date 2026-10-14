import HikkiCore
import HikkiUI
import SwiftUI

/// What the inspector shows.
enum InspectorTab: String, CaseIterable, Identifiable {
    case outline, info, calendar

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .outline: "app:inspector.outline"
        case .info: "app:inspector.info"
        case .calendar: "app:inspector.calendar"
        }
    }

    var icon: Icon {
        switch self {
        case .outline: .listBullets
        case .info: .info
        case .calendar: .calendarDots
        }
    }
}

enum InspectorPreferences {
    static let visibleKey = "inspector.visible"
    static let tabKey = "inspector.tab"
    static let widthKey = "inspector.width"
}

/// The inspector beside the page on Mac and iPad, full height as Apple's are: a hairline, a handle on it to drag the
/// width (remembered), then the inspector. It lives inside the detail column, so opening it narrows the page rather
/// than the window growing; the window's title steps aside meanwhile (ContentView), as in Photos.
struct InspectorPanel: View {
    let navigator: Navigator
    let editor: EditorController
    @AppStorage(InspectorPreferences.widthKey) private var width = Double(Size.inspectorIdeal)
    @State private var dragStart: Double?

    var body: some View {
        InspectorView(navigator: navigator, editor: editor)
            .frame(width: CGFloat(width))
            .overlay(alignment: .leading) {
                // Apple's inspector: full height on the right, the hairline from the window's top edge.
                Theme.border.frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .ignoresSafeArea(edges: .top)
                    .overlay {
                        // A wider, invisible grip over the hairline.
                        Color.clear
                            .frame(width: Spacing.s2)
                            .contentShape(.rect)
                            #if os(macOS)
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                            #endif
                            .gesture(
                                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                                    .onChanged { drag in
                                        let start = dragStart ?? width
                                        dragStart = start
                                        width = min(
                                            Double(Size.inspectorMax),
                                            max(Double(Size.inspectorMin), start - drag.translation.width))
                                    }
                                    .onEnded { _ in dragStart = nil }
                            )
                    }
            }
    }
}

/// The trailing inspector (Xcode's): a segmented control of tabs on top, then the open page's outline — a table of
/// contents that stays put, unlike the page's hover rail — its facts and size, or a calendar of edits.
struct InspectorView: View {
    let navigator: Navigator
    let editor: EditorController

    var body: some View {
        @Bindable var navigator = navigator
        VStack(spacing: Spacing.s0) {
            // Xcode's inspector tabs: plain icons in a row, the chosen one in the tone.
            HStack(spacing: Spacing.s1) {
                ForEach(InspectorTab.allCases) { tab in
                    InspectorTabButton(tab: tab, isSelected: navigator.inspectorTab == tab) {
                        navigator.inspectorTab = tab
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s1_5)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("inspector-tabs")
            Divider()
            Group {
                switch navigator.inspectorTab {
                case .outline: OutlinePane(navigator: navigator, editor: editor)
                case .info: InfoPane(navigator: navigator, editor: editor)
                case .calendar: CalendarPane(navigator: navigator)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Full height: the panel's background runs up under the toolbar (its content starts below it).
        .background(Theme.background)
    }
}

/// One inspector tab: an icon, tinted when chosen, a soft hover; the title as tooltip and label.
private struct InspectorTabButton: View {
    let tab: InspectorTab
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        Button(action: action) {
            IconView(tab.icon, size: TextSize.base.rawValue)
                .foregroundStyle(isSelected ? colorTone.ink : Theme.subtleForeground)
                .frame(width: Size.iconButton + Spacing.s2, height: Size.iconButton)
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .help(tab.title)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("inspector-tab-\(tab.rawValue)")
    }
}

/// A line of quiet text in the middle of an empty pane.
private struct EmptyPane: View {
    let text: LocalizedStringKey

    var body: some View {
        Text(text)
            .font(.hk(.md))
            .foregroundStyle(Theme.mutedForeground)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Spacing.s6)
    }
}

/// The open page's headings, indented by level; one jumps to its block.
private struct OutlinePane: View {
    let navigator: Navigator
    let editor: EditorController

    var body: some View {
        if let pageID = navigator.route.pageID {
            if let info = editor.pageInfo, info.docId == pageID, !info.headings.isEmpty {
                let minLevel = info.headings.map(\.level).min() ?? 1
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.px) {
                        ForEach(Array(info.headings.enumerated()), id: \.offset) { _, heading in
                            Button {
                                if let id = heading.id { editor.scrollToHeading(id) }
                            } label: {
                                Text(heading.text)
                                    .font(.hk(.md, heading.level == minLevel ? .medium : .regular))
                                    .foregroundStyle(heading.level == minLevel ? Theme.foreground : Theme.subtleForeground)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, Spacing.s1_5)
                                    .padding(.horizontal, Spacing.s2)
                                    .padding(.leading, CGFloat(heading.level - minLevel) * Spacing.s3)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
                            .accessibilityIdentifier("outline-\(heading.text)")
                        }
                    }
                    .padding(Spacing.s2)
                }
            } else {
                EmptyPane(text: "app:inspector.noHeadings")
            }
        } else {
            EmptyPane(text: "app:inspector.noPage")
        }
    }
}

/// The page's facts (Xcode's file inspector): where it is, when, how big — live counts while it is open.
private struct InfoPane: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let editor: EditorController
    @State private var record: DocumentRecord?

    var body: some View {
        if let pageID = navigator.route.pageID, let page = model.tree.page(pageID) {
            let live = editor.pageInfo.flatMap { $0.docId == pageID ? $0 : nil }
            let path = model.tree.path(to: pageID).dropLast().map(Self.title)
            Form {
                Section {
                    LabeledContent("app:inspector.info.title") { Text(Self.title(page)).lineLimit(2) }
                    if !path.isEmpty {
                        LabeledContent("app:inspector.info.location") { Text(path.joined(separator: " › ")).lineLimit(2) }
                    }
                    LabeledContent("app:inspector.info.created") {
                        Text((record?.createdAt ?? page.updatedAt).formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("app:inspector.info.edited") {
                        Text(page.updatedAt, format: .relative(presentation: .named))
                    }
                }
                Section {
                    LabeledContent("app:inspector.info.words") {
                        Text(live?.words ?? record?.wordCount ?? 0, format: .number).accessibilityIdentifier("inspector-words")
                    }
                    if let live {
                        LabeledContent("app:inspector.info.characters") { Text(live.characters, format: .number) }
                        LabeledContent("app:inspector.info.headings") { Text(live.headings.count, format: .number) }
                    }
                    if let record, !record.assetReferences.isEmpty {
                        LabeledContent("app:inspector.info.attachments") { Text(record.assetReferences.count, format: .number) }
                    }
                }
                Section {
                    Toggle(
                        "app:inspector.info.favorite",
                        isOn: Binding(get: { page.isFavorite }, set: { model.setFavorite($0, id: pageID) }))
                    Toggle("app:inspector.info.locked", isOn: Binding(get: { page.isLocked }, set: { model.setLocked($0, id: pageID) }))
                }
            }
            .formStyle(.grouped)
            .task(id: "\(pageID)-\(page.updatedAt.timeIntervalSince1970)") {
                record = try? model.store.document(id: pageID)
            }
        } else {
            EmptyPane(text: "app:inspector.noPage")
        }
    }

    private static func title(_ page: PageSummary) -> String {
        page.title.isEmpty ? String(localized: "app:page.untitled") : page.title
    }
}

/// A month at a glance (days with edits dotted); a day lists the pages last edited on it.
private struct CalendarPane: View {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    @State private var day = Date.now
    @State private var month = Date.now

    var body: some View {
        let pages =
            model.tree.all
            .filter { Calendar.current.isDate($0.updatedAt, inSameDayAs: day) }
            .sorted { $0.updatedAt > $1.updatedAt }
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                MonthCalendar(
                    month: $month, selection: $day, marked: Set(model.tree.all.map { MonthCalendar.dayKey($0.updatedAt) }))
                Divider()
                Text(day, format: .dateTime.weekday(.wide).month().day())
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .padding(.horizontal, Spacing.s2)
                if pages.isEmpty {
                    Text("app:inspector.calendar.none")
                        .font(.hk(.md))
                        .foregroundStyle(Theme.mutedForeground)
                        .padding(.horizontal, Spacing.s2)
                } else {
                    VStack(spacing: Spacing.px) {
                        ForEach(pages) { page in
                            Button {
                                navigator.open(page.id)
                            } label: {
                                HStack(spacing: Spacing.s2) {
                                    PageIcon(page.icon, size: 16)
                                    Text(page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                                        .font(.hk(.md))
                                        .foregroundStyle(Theme.foreground)
                                        .lineLimit(1)
                                    Spacer(minLength: Spacing.s2)
                                    Text(page.updatedAt, format: .dateTime.hour().minute())
                                        .font(.hk(.xs))
                                        .foregroundStyle(Theme.mutedForeground)
                                }
                                .padding(.vertical, Spacing.s1_5)
                                .padding(.horizontal, Spacing.s2)
                                .contentShape(.rect)
                            }
                            .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
                        }
                    }
                }
            }
            .padding(Spacing.s3)
        }
    }
}
