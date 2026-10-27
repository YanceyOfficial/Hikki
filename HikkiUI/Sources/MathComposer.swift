import SwiftUI

/// The phone's formula editor (the page's panel, natively): a Liquid Glass card over the keyboard, like the link
/// composer — the LaTeX source in a monospaced field that takes the keyboard as the card appears, while the page above
/// shows the result as it is typed (`onChange`), so the card needs no preview of its own. Cancel puts the formula
/// back, Done keeps what was typed, Remove Formula takes an existing one out; an emptied formula is removed by Done
/// as well. A sheet was tried first: with the keyboard up it grew to the whole screen and hid the page's preview.
public struct MathComposer: View {
    /// The card's title: an inline formula or an equation block.
    public enum Kind: Sendable {
        case inline, block
    }

    @State private var latex: String
    let kind: Kind
    /// Whether the formula was there before (Remove Formula is offered); a formula just inserted has no text yet.
    let existing: Bool
    let onChange: (String) -> Void
    let onDone: (String) -> Void
    let onCancel: () -> Void
    let onRemove: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorTone) private var tone

    public init(
        latex: String, kind: Kind, onChange: @escaping (String) -> Void, onDone: @escaping (String) -> Void,
        onCancel: @escaping () -> Void, onRemove: @escaping () -> Void
    ) {
        _latex = State(initialValue: latex)
        self.kind = kind
        self.existing = !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        self.onChange = onChange
        self.onDone = onDone
        self.onCancel = onCancel
        self.onRemove = onRemove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                IconView(kind == .inline ? .function : .sigma, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                Text(kind == .inline ? "app:math.inline" : "app:math.block")
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(Theme.mutedForeground)
                Spacer(minLength: Spacing.s0)
                Button("app:math.cancel", action: onCancel)
                    .font(.hk(.sm))
                    .tint(tone.fill)
                    .accessibilityIdentifier("math-composer-cancel")
            }
            TextField("app:math.placeholder", text: $latex, axis: .vertical)
                .lineLimit(1...6)
                .font(.hk(.base, design: .monospaced))
                .focused($focused)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.asciiCapable)
                #endif
                .accessibilityIdentifier("math-composer-field")
            Text("app:math.hint").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
            HStack(spacing: Spacing.s2) {
                if existing {
                    Button("app:math.remove", role: .destructive, action: onRemove)
                        .buttonStyle(.glass)
                        .accessibilityIdentifier("math-composer-remove")
                }
                Spacer(minLength: Spacing.s0)
                Button("app:math.done") { onDone(latex) }
                    .buttonStyle(.glassProminent)
                    .tint(tone.fill)
                    .accessibilityIdentifier("math-composer-done")
            }
        }
        .padding(Spacing.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .onChange(of: latex) { onChange(latex) }
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("math-composer")
    }
}

#Preview("Inline") {
    VStack {
        Spacer()
        MathComposer(latex: "\\frac{a}{b}", kind: .inline, onChange: { _ in }, onDone: { _ in }, onCancel: {}, onRemove: {})
    }
}

#Preview("New equation") {
    VStack {
        Spacer()
        MathComposer(latex: "", kind: .block, onChange: { _ in }, onDone: { _ in }, onCancel: {}, onRemove: {})
    }
}
