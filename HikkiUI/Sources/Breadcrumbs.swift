import SwiftUI

public struct Crumb: Identifiable, Equatable {
    public var id: String
    public var title: String
    public var icon: String?

    public init(id: String, title: String, icon: String?) {
        self.id = id
        self.title = title
        self.icon = icon
    }
}

/// "👋 Parent / 📄 Child" — every crumb but the last navigates; long paths collapse the middle.
public struct Breadcrumbs: View {
    private let crumbs: [Crumb]
    private let onSelect: (String) -> Void

    public init(_ crumbs: [Crumb], onSelect: @escaping (String) -> Void) {
        self.crumbs = crumbs
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: Spacing.s0) {
            ForEach(Array(visible.enumerated()), id: \.offset) { index, entry in
                if index > 0 {
                    Text("/").font(.hk(.md)).foregroundStyle(Theme.mutedForeground).padding(.horizontal, Spacing.s0_5)
                }
                switch entry {
                case .ellipsis:
                    Text("…").font(.hk(.md)).foregroundStyle(Theme.mutedForeground).padding(.horizontal, Spacing.s1)
                case .crumb(let crumb, let isLast):
                    Button {
                        if !isLast { onSelect(crumb.id) }
                    } label: {
                        HStack(spacing: Spacing.s1) {
                            if crumb.icon != nil { PageIcon(crumb.icon, size: 13) }
                            Text(crumb.title.isEmpty ? String(localized: "Untitled") : crumb.title)
                                .font(.hk(.md, isLast ? .medium : .regular))
                                .foregroundStyle(isLast ? Theme.foreground : Theme.subtleForeground)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, Spacing.s1_5)
                        .padding(.vertical, Spacing.s1)
                        .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlightStyle())
                    .allowsHitTesting(!isLast)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("breadcrumbs")
    }

    private enum Entry {
        case crumb(Crumb, isLast: Bool)
        case ellipsis
    }

    private var visible: [Entry] {
        let entries = crumbs.enumerated().map { Entry.crumb($1, isLast: $0 == crumbs.count - 1) }
        guard entries.count > 3 else { return entries }
        return [entries[0], .ellipsis] + entries.suffix(2)
    }
}

/// Flat icon button for bars (no glass capsule), with hover highlight.
public struct BarIconButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let tint: Color?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.hk(.base))
                .foregroundStyle(tint ?? Theme.subtleForeground)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle())
        .help(Text(title))
    }
}
