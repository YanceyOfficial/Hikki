import SwiftUI

/// A miniature of how an AI edit is reviewed (Settings → AI), drawn with one real edit — "We was late" fixed to "We
/// were late" — so the two styles compare on the same change: `inline` — the change in the sentence; `diff` — the
/// sentence before and after on − / + rows. (What the model says beside an edit is always in a card under either.) The
/// sample stays English in every language: it shows a layout, not copy.
public struct ReviewStyleThumbnail: View {
    public enum Sketch: String, CaseIterable, Sendable {
        case inline, diff

        /// The style a stored value names; anything else — the retired `bubble` card among them — reads as `inline`.
        public init(stored: String?) {
            self = stored.flatMap(Sketch.init(rawValue:)) ?? .inline
        }
    }

    private let sketch: Sketch

    public init(_ sketch: Sketch) {
        self.sketch = sketch
    }

    private static let before = "was"
    private static let after = "were"
    private static let head = "We "
    private static let tail = " late to the meeting."

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1_5) {
            switch sketch {
            case .inline:
                Text(sentence(removed: true, added: true))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                HStack(spacing: Spacing.s1) {
                    Spacer(minLength: 0)
                    pill("Discard", filled: false)
                    pill("Accept", filled: true)
                }
            case .diff:
                VStack(alignment: .leading, spacing: Spacing.px) {
                    diffRow(sign: "−", text: sentence(removed: true, added: false, struck: false), wash: Theme.washRed)
                    diffRow(sign: "+", text: sentence(removed: false, added: true), wash: Theme.washGreen)
                }
                Spacer(minLength: 0)
            }
        }
        .font(.hk(.x2s))
        .foregroundStyle(Theme.foreground)
        .padding(Spacing.s2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background, in: .rect(cornerRadius: Radius.md))
        .accessibilityHidden(true)
    }

    /// The sentence with the old word (red, struck through) and/or the new one (green).
    private func sentence(removed: Bool, added: Bool, struck: Bool = true) -> AttributedString {
        var text = AttributedString(Self.head)
        if removed {
            var word = AttributedString(Self.before)
            word.foregroundColor = Theme.inkRed
            word.backgroundColor = Theme.washRed
            if struck { word.strikethroughStyle = .single }
            text += word
        }
        if removed && added { text += AttributedString(" ") }
        if added {
            var word = AttributedString(Self.after)
            word.foregroundColor = Theme.inkGreen
            word.backgroundColor = Theme.washGreen
            text += word
        }
        return text + AttributedString(Self.tail)
    }

    private func diffRow(sign: String, text: AttributedString, wash: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s1) {
            Text(verbatim: sign).foregroundStyle(Theme.mutedForeground)
            Text(text).lineLimit(1)
        }
        .padding(.horizontal, Spacing.s1)
        .padding(.vertical, Spacing.px)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash.opacity(0.6), in: .rect(cornerRadius: Radius.sm))
    }

    private func pill(_ label: String, filled: Bool) -> some View {
        Text(verbatim: label)
            .padding(.horizontal, Spacing.s1_5)
            .padding(.vertical, Spacing.px)
            .foregroundStyle(filled ? Theme.primaryForeground : Theme.foreground)
            .background(filled ? Theme.primary : Theme.muted, in: .capsule)
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
    }
    .padding()
    .frame(width: 320)
    .background(Theme.muted)
}
