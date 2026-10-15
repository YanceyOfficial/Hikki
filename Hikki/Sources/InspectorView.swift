import HikkiCore
import HikkiUI
import SwiftUI

/// What the side panel shows, each opened by its own toolbar button (which, marked, names it): the outline, comments, AI.
enum InspectorMode: String, CaseIterable, Identifiable {
    case outline, comments, ai

    var id: String { rawValue }
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
    let chat: AIChat
    @AppStorage(InspectorPreferences.widthKey) private var width = Double(Size.inspectorIdeal)
    @State private var dragStart: Double?

    var body: some View {
        InspectorView(navigator: navigator, editor: editor, chat: chat)
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

/// The trailing panel: a quiet header naming what it shows, then the open page's outline — a table of contents that
/// stays put and follows the reading, unlike the page's hover rail — comments (to come), or a chat with AI about the
/// page.
struct InspectorView: View {
    let navigator: Navigator
    let editor: EditorController
    let chat: AIChat

    var body: some View {
        VStack(spacing: Spacing.s0) {
            // No title: the toolbar's marked button already says what the panel shows, and the content already
            // starts below the toolbar. A slim row only for the AI chat's New chat, once there is one.
            if navigator.inspectorMode == .ai && !chat.messages.isEmpty {
                HStack(spacing: Spacing.s1) {
                    Spacer(minLength: Spacing.s2)
                    AIChatActions(chat: chat).labelStyle(.iconOnly).buttonStyle(.borderless)
                }
                .padding(.horizontal, Spacing.s3)
                .frame(height: Size.iconButton)
            } else {
                Color.clear.frame(height: Spacing.s2)
            }
            Group {
                switch navigator.inspectorMode {
                case .outline: OutlinePane(navigator: navigator, editor: editor)
                case .comments: CommentsPane(pageID: navigator.route.pageID, editor: editor)
                case .ai:
                    // About the page beside it (cleared from the composer to ask without it).
                    AIChatView(chat: chat)
                        .onAppear { chat.show(page: navigator.route.pageID) }
                        .onChange(of: navigator.route.pageID) { _, id in chat.show(page: id) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // Full height: the panel's background runs up under the toolbar (its content starts below it).
        .background(Theme.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("inspector-\(navigator.inspectorMode.rawValue)")
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

/// The open page's headings, indented by level: the section being read (the page's scroll-spy,
/// `EditorController.activeHeading`) sits on a background that glides from row to row as the reading moves, and is kept
/// in view; one jumps to its block.
private struct OutlinePane: View {
    let navigator: Navigator
    let editor: EditorController
    @Namespace private var highlight

    var body: some View {
        if let pageID = navigator.route.pageID {
            if let info = editor.pageInfo, info.docId == pageID, !info.headings.isEmpty {
                let minLevel = info.headings.map(\.level).min() ?? 1
                let active = editor.activeHeading.flatMap { $0.docId == pageID ? $0.id : nil }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Spacing.s0) {
                            ForEach(Array(info.headings.enumerated()), id: \.offset) { index, heading in
                                OutlineRow(
                                    text: heading.text, depth: heading.level - minLevel,
                                    isActive: heading.id != nil && heading.id == active, highlight: highlight
                                ) {
                                    if let id = heading.id { editor.scrollToHeading(id) }
                                }
                                .id(index)
                                .accessibilityIdentifier("outline-\(heading.text)")
                            }
                        }
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
                        .animation(Motion.easeOut(), value: active)
                    }
                    .onChange(of: active) { _, id in
                        guard let index = info.headings.firstIndex(where: { $0.id == id && id != nil }) else { return }
                        withAnimation(Motion.easeOut()) { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                EmptyPane(text: "app:inspector.noHeadings")
            }
        } else {
            EmptyPane(text: "app:inspector.noPage")
        }
    }
}

/// One heading of the outline, indented by depth — top-level headings in full colour, deeper ones quieter. The section
/// being read carries the outline's one background (matched geometry: it glides to the next active row); nothing else
/// about the row changes.
private struct OutlineRow: View {
    let text: String
    let depth: Int
    let isActive: Bool
    let highlight: Namespace.ID
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The text never changes with the reading (a weight or colour change animated along with the background
            // flickered as it moved): only the background marks the section.
            Text(text)
                .font(.hk(.sm))
                .foregroundStyle(depth == 0 ? Theme.foreground : Theme.subtleForeground)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Spacing.s2 + CGFloat(depth) * Spacing.s3)
                .padding(.trailing, Spacing.s2)
                .padding(.vertical, Spacing.s1_5)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(Theme.accent)
                            .matchedGeometryEffect(id: "active", in: highlight)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// AI for the open page (the next feature): for now it says what will be here.
/// Every thread on the page, open or resolved (Notion's comments panel): what each is about, its first comment and
/// replies; picking one opens it in the page, its passage in view. Threads change when the page writes them (here or in
/// the other editor), when this panel reopens one, and when the app comes back (other devices).
private struct CommentsPane: View {
    @Environment(AppModel.self) private var model
    let pageID: String?
    let editor: EditorController
    @State private var threads: [CommentThread] = []
    @State private var showResolved = false

    private var shown: [CommentThread] {
        threads.filter { ($0.resolvedAt != nil) == showResolved }.sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s1_5) {
                filter("app:comments.filter.open \(threads.filter { $0.resolvedAt == nil }.count.formatted())", resolved: false)
                filter("app:comments.filter.resolved \(threads.filter { $0.resolvedAt != nil }.count.formatted())", resolved: true)
            }
            .padding(.horizontal, Spacing.s3)
            if shown.isEmpty {
                Text(showResolved ? "app:comments.noneResolved" : "app:comments.empty")
                    .font(.hk(.md))
                    .foregroundStyle(Theme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Spacing.s6)
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.s2) {
                        ForEach(shown) { thread in
                            ThreadRow(thread: thread) {
                                editor.openComment(thread.id)
                            } reopen: {
                                guard let pageID else { return }
                                do {
                                    try model.comments?.setResolved(false, pageId: pageID, threadId: thread.id)
                                } catch {
                                    Toasts.report(.commentFailed, error, category: "comments", context: ["docId": pageID])
                                }
                                NotificationCenter.default.post(name: .pageCommentsChanged, object: nil, userInfo: ["id": pageID])
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.s3)
                    .padding(.bottom, Spacing.s4)
                }
            }
        }
        .task(id: pageID) { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .pageCommentsChanged)) { note in
            let id = note.userInfo?["id"] as? String
            if id == nil || id == pageID { reload() }
        }
        .accessibilityIdentifier("comments-pane")
    }

    private func reload() {
        threads = pageID.flatMap { try? model.comments?.threads(of: $0) } ?? []
    }

    private func filter(_ title: LocalizedStringKey, resolved: Bool) -> some View {
        Button {
            showResolved = resolved
        } label: {
            Text(title)
                .font(.hk(.md))
                .foregroundStyle(showResolved == resolved ? Theme.background : Theme.subtleForeground)
                .padding(.horizontal, Spacing.s3)
                .frame(height: Size.iconButton)
                .background(showResolved == resolved ? Theme.foreground : Theme.muted, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// A thread in the panel: the passage (a warm bar), who wrote the first comment and when, the comment, its replies.
private struct ThreadRow: View {
    let thread: CommentThread
    let open: () -> Void
    let reopen: () -> Void

    var body: some View {
        let first = thread.comments.first
        Button(action: open) {
            VStack(alignment: .leading, spacing: Spacing.s1_5) {
                if !thread.quote.isEmpty {
                    // The passage's own words.
                    Text(verbatim: thread.quote)
                        .font(.hk(.md))
                        .foregroundStyle(Theme.subtleForeground)
                        .lineLimit(2)
                        .padding(.leading, Spacing.s2_5)
                        .overlay(alignment: .leading) { Capsule().fill(Theme.inkYellow).frame(width: Spacing.s0_5) }
                }
                if let first {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                        // The author's own name.
                        Text(verbatim: first.author ?? String(localized: "app:comments.you")).font(.hk(.md, .semibold))
                        Text(first.createdAt, format: .relative(presentation: .named))
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    // The comment, as written.
                    Text(verbatim: first.plainBody).font(.hk(.sm)).foregroundStyle(Theme.foreground).lineLimit(4)
                }
                HStack {
                    if thread.comments.count > 1 {
                        Text("app:comments.replies \((thread.comments.count - 1).formatted())")
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: 0)
                    if thread.resolvedAt != nil {
                        Button("app:comments.reopen", action: reopen)
                            .font(.hk(.xs))
                            .buttonStyle(.borderless)
                    }
                }
            }
            .padding(Spacing.s3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.muted.opacity(0.5), in: .rect(cornerRadius: Radius.xl))
            .contentShape(.rect(cornerRadius: Radius.xl))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("comment-row")
    }
}
