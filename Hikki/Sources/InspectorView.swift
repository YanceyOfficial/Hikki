import HikkiCore
import HikkiUI
import SwiftUI

/// What the side panel shows, each opened by its own toolbar button: the page's outline or AI (comments later).
enum InspectorMode: String, CaseIterable, Identifiable {
    case outline, ai

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .outline: "app:inspector.outline"
        case .ai: "app:inspector.ai"
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

/// The trailing panel: a quiet header naming what it shows, then the open page's outline — a table of contents that
/// stays put and follows the reading, unlike the page's hover rail — or AI.
struct InspectorView: View {
    let navigator: Navigator
    let editor: EditorController

    var body: some View {
        VStack(spacing: Spacing.s0) {
            Text(navigator.inspectorMode.title)
                .font(.hk(.sm, .medium))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.s4)
                .frame(height: Size.pageBar)
                .accessibilityIdentifier("inspector-header")
            Group {
                switch navigator.inspectorMode {
                case .outline: OutlinePane(navigator: navigator, editor: editor)
                case .ai: AIPane()
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

/// The open page's headings, indented by level, along a rail: the section being read is marked on it (the page's
/// scroll-spy, `EditorController.activeHeading`) and kept in view; one jumps to its block.
private struct OutlinePane: View {
    let navigator: Navigator
    let editor: EditorController

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
                                    isActive: heading.id != nil && heading.id == active
                                ) {
                                    if let id = heading.id { editor.scrollToHeading(id) }
                                }
                                .id(index)
                                .accessibilityIdentifier("outline-\(heading.text)")
                            }
                        }
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s2)
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

/// One heading of the outline: a segment of the rail at its leading edge (the colour tone when it is the section
/// being read), the text indented by depth — top-level headings in full colour, deeper ones quieter.
private struct OutlineRow: View {
    let text: String
    let depth: Int
    let isActive: Bool
    let action: () -> Void
    @Environment(\.colorTone) private var colorTone

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.s0) {
                Capsule()
                    .fill(isActive ? colorTone.fill : Theme.border)
                    .frame(width: isActive ? 2 : 1)
                    .frame(width: Spacing.s2, alignment: .center)
                Text(text)
                    .font(.hk(.sm, isActive ? .medium : .regular))
                    .foregroundStyle(isActive || depth == 0 ? Theme.foreground : Theme.subtleForeground)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, Spacing.s2 + CGFloat(depth) * Spacing.s3)
                    .padding(.trailing, Spacing.s2)
                    .padding(.vertical, Spacing.s1_5)
            }
            .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
        .animation(Motion.easeOut(), value: isActive)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }
}

/// AI for the open page (the next feature): for now it says what will be here.
private struct AIPane: View {
    var body: some View {
        VStack(spacing: Spacing.s3) {
            AIGlyph(size: TextSize.x2l.rawValue)
            Text("app:inspector.ai.soon")
                .font(.hk(.md))
                .foregroundStyle(Theme.mutedForeground)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Spacing.s6)
    }
}
