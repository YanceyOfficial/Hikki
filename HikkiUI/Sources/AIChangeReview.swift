import SwiftUI

/// Ask AI's changes to the page, under the answer that proposed them: how many are reviewed, Approve all, a card per
/// pending change (a tap shows it in the page, where ↵ / ⌫ decide; ✓ / ✕ decide here) and, once looked at, the change
/// flies into a stack of reviewed cards — the newest on top, the earlier ones peeking above it, smaller; a tap spreads
/// the stack out. Plain values in, closures out.
public struct AIChangeReview: View {
    public enum Kind: String, Sendable, CaseIterable {
        case rewrite, insert, move, delete
    }

    public enum Status: Sendable, Equatable {
        case pending, approved, skipped, edited, stale

        var isReviewed: Bool { self != .pending }
    }

    public struct Item: Identifiable, Equatable, Sendable {
        public var id: String
        public var kind: Kind
        public var title: String
        public var why: String?
        public var state: Status
        /// The block as it reads after the review — the AI's new words marked `.added`, removed ones `.removed` — or,
        /// skipped, what was proposed (unmarked).
        public var runs: [VersionDiffView.Run]

        public init(id: String, kind: Kind, title: String, why: String? = nil, state: Status, runs: [VersionDiffView.Run] = []) {
            self.id = id
            self.kind = kind
            self.title = title
            self.why = why
            self.state = state
            self.runs = runs
        }
    }

    let items: [Item]
    /// Reviewed items in the order they were reviewed (oldest first); the stack draws the last on top.
    let reviewed: [Item]
    let activeID: String?
    let onFocus: (String) -> Void
    let onApprove: (String) -> Void
    let onSkip: (String) -> Void
    let onApproveAll: () -> Void
    @State private var spread = false
    @Namespace private var cards
    @Environment(\.colorTone) private var tone

    /// `items` in the answer's order; `reviewed` the reviewed ones in the order they were reviewed.
    public init(
        items: [Item], reviewed: [Item], activeID: String?, onFocus: @escaping (String) -> Void,
        onApprove: @escaping (String) -> Void, onSkip: @escaping (String) -> Void, onApproveAll: @escaping () -> Void
    ) {
        self.items = items
        self.reviewed = reviewed
        self.activeID = activeID
        self.onFocus = onFocus
        self.onApprove = onApprove
        self.onSkip = onSkip
        self.onApproveAll = onApproveAll
    }

    private var pending: [Item] { items.filter { !$0.state.isReviewed } }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            header
            ForEach(pending) { item in
                card(item)
                    .matchedGeometryEffect(id: item.id, in: cards)
                    .transition(.opacity)
            }
            if !reviewed.isEmpty { stack }
        }
        .animation(Motion.easeOut(), value: items)
        .animation(Motion.easeOut(), value: spread)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.s1_5) {
            HStack(spacing: Spacing.s2) {
                Text("app:ai.changes.progress \(String(items.count - pending.count)) \(String(items.count))")
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                    .monospacedDigit()
                Spacer(minLength: Spacing.s2)
                if !pending.isEmpty {
                    Button("app:ai.changes.approveAll", action: onApproveAll)
                        .buttonStyle(.borderless)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(tone.ink)
                        .accessibilityIdentifier("ai-changes-approve-all")
                }
            }
            GeometryReader { proxy in
                Capsule().fill(Theme.muted)
                    .overlay(alignment: .leading) {
                        Capsule().fill(tone.fill)
                            .frame(width: proxy.size.width * CGFloat(items.count - pending.count) / CGFloat(max(items.count, 1)))
                    }
            }
            .frame(height: Spacing.s1)
        }
    }

    private func card(_ item: Item) -> some View {
        let active = item.id == activeID
        return HStack(alignment: .top, spacing: Spacing.s2_5) {
            IconView(item.kind.icon, size: TextSize.sm.rawValue)
                .foregroundStyle(item.kind == .delete ? Theme.inkRed : Theme.inkGreen)
                .padding(.top, Spacing.px)
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(verbatim: item.title.isEmpty ? String(localized: item.kind.label) : item.title)
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(2)
                Text(item.kind.label).font(.hk(.xs)).foregroundStyle(Theme.subtleForeground)
                if let why = item.why {
                    Text(verbatim: why).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Spacing.s0_5) {
                verdict(.x, label: "app:ai.changes.skip") { onSkip(item.id) }
                verdict(.check, label: "app:ai.changes.approve") { onApprove(item.id) }
            }
        }
        .padding(Spacing.s3)
        .background(Theme.card, in: .rect(cornerRadius: Radius.xl))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.xl)
                .strokeBorder(active ? tone.fill : Theme.border, lineWidth: active ? Spacing.s0_5 : Spacing.px)
        }
        .contentShape(.rect(cornerRadius: Radius.xl))
        .onTapGesture { onFocus(item.id) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("ai-change-card")
    }

    private func verdict(_ icon: Icon, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            IconView(icon, size: TextSize.sm.rawValue)
                .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.mutedForeground)
        .help(Text(label))
        .accessibilityLabel(Text(label))
    }

    // MARK: - The reviewed stack

    /// Cards behind the top one that still peek out.
    private static let peeking = 3

    private var stack: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack {
                Text("app:ai.changes.reviewed \(String(reviewed.count))")
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer()
                if reviewed.count > 1 {
                    Button(spread ? "app:ai.changes.collapse" : "app:ai.changes.showAll") { spread.toggle() }
                        .buttonStyle(.borderless)
                        .font(.hk(.xs, .medium))
                        .foregroundStyle(Theme.mutedForeground)
                        .accessibilityIdentifier("ai-changes-stack-toggle")
                }
            }
            if spread {
                VStack(spacing: Spacing.s2) {
                    ForEach(reviewed.reversed()) { item in
                        reviewedCard(item).matchedGeometryEffect(id: item.id, in: cards)
                            .onTapGesture { if item.state != .stale { onFocus(item.id) } }
                    }
                }
            } else {
                ZStack(alignment: .bottom) {
                    ForEach(Array(reviewed.enumerated()), id: \.element.id) { index, item in
                        let depth = reviewed.count - 1 - index
                        reviewedCard(item)
                            .matchedGeometryEffect(id: item.id, in: cards)
                            .scaleEffect(1 - CGFloat(depth) * 0.06, anchor: .top)
                            .offset(y: -CGFloat(depth) * Spacing.s2_5)
                            .opacity(depth < Self.peeking ? 1 : 0)
                            .zIndex(Double(index))
                    }
                }
                // Room for the cards peeking above the top one.
                .padding(.top, CGFloat(min(reviewed.count - 1, Self.peeking - 1)) * Spacing.s2_5)
                .contentShape(.rect)
                .onTapGesture { if reviewed.count > 1 { spread = true } }
            }
        }
        .accessibilityIdentifier("ai-changes-stack")
    }

    private func reviewedCard(_ item: Item) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if !item.runs.isEmpty {
                Text(quote(item))
                    .font(.hk(.sm))
                    .foregroundStyle(item.state == .skipped ? Theme.mutedForeground : Theme.foreground)
                    .lineLimit(spread ? nil : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(verbatim: item.title.isEmpty ? String(localized: item.kind.label) : item.title)
                    .font(.hk(.xs, .semibold))
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                HStack(spacing: Spacing.s0) {
                    Text(item.state.label)
                    Text(verbatim: " · ")
                    Text(item.kind.label)
                }
                .font(.hk(.xs))
                .foregroundStyle(Theme.subtleForeground)
            }
        }
        .padding(Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: Radius.x2l))
        .overlay { RoundedRectangle(cornerRadius: Radius.x2l).strokeBorder(Theme.border, lineWidth: Spacing.px) }
        .opacity(item.state == .stale ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ai-change-reviewed")
    }

    private func quote(_ item: Item) -> AttributedString {
        var result = AttributedString()
        for run in item.runs {
            var piece = AttributedString(run.text)
            if item.state != .skipped {
                switch run.change {
                case .same: break
                case .added: piece.backgroundColor = Theme.washGreen
                case .removed:
                    piece.strikethroughStyle = .single
                    piece.foregroundColor = Theme.inkRed
                }
            }
            result += piece
        }
        return result
    }
}

extension AIChangeReview.Kind {
    var icon: Icon {
        switch self {
        case .rewrite: .pencilSimple
        case .insert: .plus
        case .move: .arrowBendUpRight
        case .delete: .trash
        }
    }

    var label: LocalizedStringResource {
        switch self {
        case .rewrite: "app:ai.changes.kind.rewrite"
        case .insert: "app:ai.changes.kind.insert"
        case .move: "app:ai.changes.kind.move"
        case .delete: "app:ai.changes.kind.delete"
        }
    }
}

extension AIChangeReview.Status {
    var label: LocalizedStringResource {
        switch self {
        case .pending: "app:ai.changes.status.pending"
        case .approved: "app:ai.changes.status.approved"
        case .skipped: "app:ai.changes.status.skipped"
        case .edited: "app:ai.changes.status.edited"
        case .stale: "app:ai.changes.status.stale"
        }
    }
}

#Preview("AI change review") {
    @Previewable @State var items: [AIChangeReview.Item] = [
        .init(
            id: "1", kind: .rewrite, title: "系动词不都是静态动词", why: "turn, become, get 表示变化，不是静态。", state: .pending,
            runs: [.init("系动词：联系主语和表语的动词", .same), .init("，可表状态或变化", .added), .init("。", .same)]),
        .init(
            id: "2", kind: .insert, title: "补一个判断方法小节", why: "没有说明如何区分五种句型。", state: .pending,
            runs: [.init("怎么判断：先找谓语动词，再看它后面需要什么。", .added)]),
        .init(id: "3", kind: .delete, title: "删掉重复的例句", state: .pending, runs: [.init("She is a teacher.", .removed)]),
        .init(
            id: "4", kind: .rewrite, title: "He know → He knows", why: "第三人称单数。", state: .pending,
            runs: [.init("He ", .same), .init("knows", .added), .init(" it drives me crazy.", .same)]),
    ]
    @Previewable @State var order: [String] = []
    let decide = { (id: String, state: AIChangeReview.Status) in
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = state
        order.append(id)
    }
    ScrollView {
        AIChangeReview(
            items: items, reviewed: order.compactMap { id in items.first { $0.id == id } }, activeID: "1",
            onFocus: { _ in }, onApprove: { decide($0, .approved) }, onSkip: { decide($0, .skipped) },
            onApproveAll: { items.filter { $0.state == .pending }.forEach { decide($0.id, .approved) } }
        )
        .padding()
    }
    .frame(width: 360, height: 640)
}
