import SwiftUI

/// One of AI's presets as the page names them (Improve writing, Translate…), sent back by id.
public struct AIComposerPreset: Identifiable, Equatable, Sendable {
    public var id: String
    public var label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}

/// The phone's Ask AI field over the keyboard (Notion AI's composer): a Liquid Glass card naming the words it will
/// work on, a field for the user's own instruction, and the presets as chips. It takes the keyboard when it appears.
public struct KeyboardAIComposer: View {
    let quote: String
    let presets: [AIComposerPreset]
    let onSend: (String) -> Void
    let onPreset: (String) -> Void
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorTone) private var tone

    public init(
        quote: String, presets: [AIComposerPreset], onSend: @escaping (String) -> Void, onPreset: @escaping (String) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.quote = quote
        self.presets = presets
        self.onSend = onSend
        self.onPreset = onPreset
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                IconView(.sparkle, size: TextSize.base.rawValue).foregroundStyle(tone.fill)
                ComposerQuote(quote: quote)
                Spacer(minLength: Spacing.s0)
                ComposerCloseButton(action: onClose)
            }
            ComposerSendField(
                placeholder: "app:keyboard.aiPlaceholder", text: $text, focused: $focused, identifier: "keyboard-ai-field",
                onSend: onSend)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s1_5) {
                    ForEach(presets) { preset in
                        Button {
                            onPreset(preset.id)
                        } label: {
                            Text(verbatim: preset.label)
                                .font(.hk(.sm, .medium))
                                .padding(.horizontal, Spacing.s3)
                                .frame(height: Size.iconButton)
                                .overlay { Capsule().strokeBorder(Theme.border, lineWidth: Spacing.px) }
                                .contentShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("keyboard-ai-\(preset.id)")
                    }
                }
            }
        }
        .padding(Spacing.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard-ai-composer")
    }
}

/// The phone's comment field over the keyboard (Notion's): the words or block it comments on, the field, send. The
/// thread starts only when it is sent, so closing it leaves nothing behind.
public struct KeyboardCommentComposer: View {
    let quote: String
    let onSend: (String) -> Void
    let onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    public init(quote: String, onSend: @escaping (String) -> Void, onClose: @escaping () -> Void) {
        self.quote = quote
        self.onSend = onSend
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                IconView(.chatTeardropText, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                ComposerQuote(quote: quote)
                Spacer(minLength: Spacing.s0)
                ComposerCloseButton(action: onClose)
            }
            ComposerSendField(
                placeholder: "app:keyboard.commentPlaceholder", text: $text, focused: $focused,
                identifier: "keyboard-comment-field", onSend: onSend)
        }
        .padding(Spacing.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard-comment-composer")
    }
}

/// The phone's link field over the keyboard: the words it links, the address, Apply — and Remove when there is one.
public struct KeyboardLinkComposer: View {
    let quote: String
    let href: String?
    let onApply: (String) -> Void
    let onRemove: () -> Void
    let onClose: () -> Void
    @State private var text: String
    @FocusState private var focused: Bool
    @Environment(\.colorTone) private var tone

    public init(
        quote: String, href: String?, onApply: @escaping (String) -> Void, onRemove: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.quote = quote
        self.href = href
        self.onApply = onApply
        self.onRemove = onRemove
        self.onClose = onClose
        _text = State(initialValue: href ?? "")
    }

    private var address: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            HStack(spacing: Spacing.s2) {
                IconView(.link, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                ComposerQuote(quote: quote)
                Spacer(minLength: Spacing.s0)
                ComposerCloseButton(action: onClose)
            }
            TextField("app:keyboard.linkPlaceholder", text: $text)
                .font(.hk(.base))
                .focused($focused)
                #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { if !address.isEmpty { onApply(address) } }
                .accessibilityIdentifier("keyboard-link-field")
            HStack(spacing: Spacing.s2) {
                if href != nil {
                    Button("app:keyboard.removeLink", role: .destructive, action: onRemove)
                        .buttonStyle(.glass)
                }
                Spacer(minLength: Spacing.s0)
                Button("app:keyboard.applyLink") { onApply(address) }
                    .buttonStyle(.glassProminent)
                    .tint(tone.fill)
                    .disabled(address.isEmpty)
            }
        }
        .padding(Spacing.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("keyboard-link-composer")
    }
}

/// A composer's field and its send button (Return sends too); nothing goes out while it is blank.
private struct ComposerSendField: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let identifier: String
    let onSend: (String) -> Void
    @Environment(\.colorTone) private var tone

    private var message: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        HStack(spacing: Spacing.s2) {
            TextField(placeholder, text: $text)
                .font(.hk(.base))
                .focused(focused)
                .submitLabel(.send)
                .onSubmit { if !message.isEmpty { onSend(message) } }
                .accessibilityIdentifier(identifier)
            Button {
                onSend(message)
            } label: {
                IconLabel("app:ai.send", icon: .arrowUp, size: TextSize.base.rawValue)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.primaryForeground)
                    .frame(width: Size.iconButton, height: Size.iconButton)
                    .background(message.isEmpty ? Theme.mutedForeground : tone.fill, in: .circle)
            }
            .buttonStyle(.plain)
            .disabled(message.isEmpty)
            .accessibilityIdentifier("keyboard-composer-send")
        }
    }
}

/// The words a composer works on, as a chip (Notion's).
private struct ComposerQuote: View {
    let quote: String

    var body: some View {
        if !quote.isEmpty {
            Text(verbatim: quote)
                .font(.hk(.sm))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, Spacing.s2)
                .padding(.vertical, Spacing.s1)
                .background(Theme.muted, in: .capsule)
        }
    }
}

private struct ComposerCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconLabel("app:common.close", icon: .x, size: TextSize.sm.rawValue)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: Size.iconButton, height: Size.iconButton)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("keyboard-composer-close")
    }
}

#Preview("AI") {
    VStack {
        Spacer()
        KeyboardAIComposer(
            quote: "用于表达「看起来好像…」",
            presets: [.init(id: "improve", label: "Improve writing"), .init(id: "fix", label: "Fix spelling & grammar")],
            onSend: { _ in }, onPreset: { _ in }, onClose: {})
    }
}

#Preview("Comment") {
    VStack {
        Spacer()
        KeyboardCommentComposer(quote: "Line number 3 of the page", onSend: { _ in }, onClose: {})
    }
}

#Preview("Link") {
    VStack {
        Spacer()
        KeyboardLinkComposer(quote: "Hikki", href: "https://hikki.yancey.app", onApply: { _ in }, onRemove: {}, onClose: {})
    }
}
