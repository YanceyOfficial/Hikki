import SwiftUI

/// A miniature of how an AI edit is reviewed (Settings → AI): lines of "text" as bars, removals red, additions green.
/// `inline` — the changes in the page's lines; `diff` — − / + rows; `bubble` — the page untouched, a card beside it.
public struct ReviewStyleThumbnail: View {
    public enum Sketch: String, CaseIterable, Sendable {
        case inline, diff, bubble
    }

    private let sketch: Sketch

    public init(_ sketch: Sketch) {
        self.sketch = sketch
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            switch sketch {
            case .inline:
                line([.text(0.3), .del(0.18), .add(0.2), .text(0.2)])
                line([.text(0.55), .add(0.25)])
                line([.text(0.2), .del(0.15), .text(0.4)])
                line([.text(0.7)])
            case .diff:
                line([.text(0.85)])
                row(removed: true) { line([.text(0.3), .del(0.18), .text(0.32)]) }
                row(removed: false) { line([.text(0.3), .add(0.22), .text(0.32)]) }
                line([.text(0.6)])
            case .bubble:
                line([.selected(0.75)])
                line([.selected(0.5)])
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    line([.del(0.22), .text(0.08), .add(0.25)])
                    line([.del(0.15), .text(0.08), .add(0.3)])
                }
                .padding(Spacing.s1_5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.popover, in: .rect(cornerRadius: Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border))
                .shadow(color: Theme.border, radius: Spacing.s0_5, y: Spacing.px)
            }
        }
        .padding(Spacing.s2_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background, in: .rect(cornerRadius: Radius.md))
        .accessibilityHidden(true)
    }

    private enum Bar {
        case text(CGFloat)
        case del(CGFloat)
        case add(CGFloat)
        case selected(CGFloat)
    }

    /// A line of bars, each a fraction of the line's width.
    private func line(_ bars: [Bar]) -> some View {
        GeometryReader { proxy in
            HStack(spacing: Spacing.px) {
                ForEach(Array(bars.enumerated()), id: \.offset) { _, bar in
                    let (fraction, color) = style(bar)
                    Capsule().fill(color).frame(width: proxy.size.width * fraction)
                }
            }
        }
        .frame(height: Spacing.s1_5)
    }

    /// A diff row: its line on the removal or addition wash.
    private func row(removed: Bool, @ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.vertical, Spacing.px)
            .padding(.horizontal, Spacing.s0_5)
            .background(removed ? Theme.washRed : Theme.washGreen, in: .rect(cornerRadius: Radius.sm))
    }

    private func style(_ bar: Bar) -> (CGFloat, Color) {
        switch bar {
        case .text(let f): (f, Theme.mutedForeground.opacity(0.35))
        case .del(let f): (f, Theme.inkRed.opacity(0.7))
        case .add(let f): (f, Theme.inkGreen.opacity(0.8))
        case .selected(let f): (f, Theme.selection)
        }
    }
}

/// An option shown as a picture (a thumbnail over its title), check when selected — for a choice that is easier seen
/// than described.
public struct ThumbnailOption<Thumbnail: View>: View {
    private let title: LocalizedStringKey
    private let isSelected: Bool
    private let action: () -> Void
    private let thumbnail: Thumbnail
    @State private var hovering = false
    @Environment(\.colorTone) private var tone

    public init(
        _ title: LocalizedStringKey, isSelected: Bool, action: @escaping () -> Void,
        @ViewBuilder thumbnail: () -> Thumbnail
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.thumbnail = thumbnail()
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s2) {
                thumbnail
                    .frame(height: Size.thumbnail)
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.md)
                            .strokeBorder(isSelected ? tone.fill : Theme.border, lineWidth: isSelected ? 2 : 1)
                    )
                HStack(spacing: Spacing.s1) {
                    IconView(.checkCircleFill, size: TextSize.sm.rawValue)
                        .foregroundStyle(tone.fill)
                        .opacity(isSelected ? 1 : 0)
                    Text(title)
                        .font(.hk(.md, isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.foreground : Theme.mutedForeground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .padding(Spacing.s1_5)
            .background(hovering && !isSelected ? Theme.accent : .clear, in: .rect(cornerRadius: Radius.lg))
            .contentShape(.rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    HStack(spacing: Spacing.s3) {
        ThumbnailOption("Inline", isSelected: true, action: {}) { ReviewStyleThumbnail(.inline) }
        ThumbnailOption("Diff", isSelected: false, action: {}) { ReviewStyleThumbnail(.diff) }
        ThumbnailOption("Bubble", isSelected: false, action: {}) { ReviewStyleThumbnail(.bubble) }
    }
    .padding()
    .frame(width: 460)
    .background(Theme.muted)
}
