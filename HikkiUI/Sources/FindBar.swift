import SwiftUI

/// The find bar's switches: the Replace row, and how the term is read.
public struct FindBarOptions: Equatable, Sendable {
    public var replace: Bool
    public var caseSensitive: Bool
    public var wholeWord: Bool
    public var regex: Bool

    public init(replace: Bool = false, caseSensitive: Bool = false, wholeWord: Bool = false, regex: Bool = false) {
        self.replace = replace
        self.caseSensitive = caseSensitive
        self.wholeWord = wholeWord
        self.regex = regex
    }
}

/// What the page found: how many matches, and which one is stepped to (0-based; nil without matches).
public struct FindBarStatus: Equatable, Sendable {
    public var count: Int
    public var current: Int?

    public init(count: Int = 0, current: Int? = nil) {
        self.count = count
        self.current = current
    }
}

/// The phone's find bar (Safari's, natively over the page and its keyboard): the term in a field that takes the
/// keyboard as it appears, "1 / 3", ‹ ›, the options (Replace, Match Case, Whole Word, Regular Expression) and Done;
/// with Replace, a second row — the replacement, Replace, Replace All. The typing is the bar's; the page's counts
/// come back as `status`. `canReplace` is false on a locked page, where Replace stays out of the options.
public struct FindBar: View {
    @Binding var term: String
    @Binding var replaceTerm: String
    @Binding var options: FindBarOptions
    let status: FindBarStatus
    let canReplace: Bool
    let onStep: (Int) -> Void
    let onReplace: (_ all: Bool) -> Void
    let onClose: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.colorTone) private var tone

    public init(
        term: Binding<String>, replaceTerm: Binding<String>, options: Binding<FindBarOptions>, status: FindBarStatus,
        canReplace: Bool, onStep: @escaping (Int) -> Void, onReplace: @escaping (_ all: Bool) -> Void,
        onClose: @escaping () -> Void
    ) {
        _term = term
        _replaceTerm = replaceTerm
        _options = options
        self.status = status
        self.canReplace = canReplace
        self.onStep = onStep
        self.onReplace = onReplace
        self.onClose = onClose
    }

    private var showsReplace: Bool { options.replace && canReplace }

    public var body: some View {
        VStack(spacing: Spacing.s2) {
            HStack(spacing: Spacing.s1) {
                FindField(
                    placeholder: "app:find.short", text: $term, identifier: "find-bar-field", focused: $focused,
                    onSubmit: { onStep(1) }
                ) {
                    countLabel
                }
                .submitLabel(.search)
                ToolbarIconButton("app:find.previous", symbol: .caretLeft, style: .quiet) { onStep(-1) }
                    .disabled(status.count == 0)
                    .accessibilityIdentifier("find-bar-previous")
                ToolbarIconButton("app:find.next", symbol: .caretRight, style: .quiet) { onStep(1) }
                    .disabled(status.count == 0)
                    .accessibilityIdentifier("find-bar-next")
                optionsMenu
                Button("app:find.done", action: onClose)
                    .font(.hk(.base, .semibold))
                    .tint(tone.fill)
                    .accessibilityIdentifier("find-bar-done")
            }
            if showsReplace {
                HStack(spacing: Spacing.s2) {
                    FindField(
                        placeholder: "app:find.replacePlaceholder", text: $replaceTerm, identifier: "find-bar-replace-field",
                        focused: nil, onSubmit: { onReplace(false) }
                    ) {
                        EmptyView()
                    }
                    Button("app:find.replaceOne") { onReplace(false) }
                        .buttonStyle(.glass)
                        .disabled(status.count == 0)
                        .accessibilityIdentifier("find-bar-replace")
                    Button("app:find.replaceAll") { onReplace(true) }
                        .buttonStyle(.glass)
                        .disabled(status.count == 0)
                        .accessibilityIdentifier("find-bar-replace-all")
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(Spacing.s3)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s2)
        .animation(Motion.easeOut(), value: showsReplace)
        .onAppear { focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("find-bar")
    }

    /// "1 / 3" beside the term; "No matches" once there is a term and nothing for it; nothing before typing.
    @ViewBuilder private var countLabel: some View {
        if !term.isEmpty {
            Group {
                if let current = status.current, status.count > 0 {
                    Text(verbatim: "\(current + 1) / \(status.count)")
                } else {
                    Text("app:find.none")
                }
            }
            .font(.hk(.xs))
            .foregroundStyle(Theme.mutedForeground)
            .monospacedDigit()
            .accessibilityIdentifier("find-bar-count")
        }
    }

    private var optionsMenu: some View {
        Menu {
            if canReplace {
                Toggle("app:find.showReplace", isOn: $options.replace)
            }
            Toggle("app:find.matchCase", isOn: $options.caseSensitive)
            Toggle("app:find.wholeWord", isOn: $options.wholeWord)
            Toggle("app:find.regex", isOn: $options.regex)
        } label: {
            IconLabel("app:find.options", icon: .slidersHorizontal, size: TextSize.lg.rawValue)
                .labelStyle(.iconOnly)
                .frame(width: Size.touchTarget, height: Size.touchTarget)
                .foregroundStyle(
                    options.caseSensitive || options.wholeWord || options.regex || showsReplace ? tone.ink : Theme.subtleForeground
                )
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("find-bar-options")
    }
}

/// A field of the bar: a quiet fill, an `accessory` after the text (the count), a clear button once there is text.
private struct FindField<Accessory: View>: View {
    let placeholder: LocalizedStringKey
    @Binding var text: String
    let identifier: String
    let focused: FocusState<Bool>.Binding?
    let onSubmit: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: Spacing.s1_5) {
            field
                .font(.hk(.base))
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                .onSubmit(onSubmit)
                .accessibilityIdentifier(identifier)
            accessory()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    IconLabel("app:find.clear", icon: .xCircle, size: TextSize.base.rawValue)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.iconButton, height: Size.iconButton)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(identifier)-clear")
            }
        }
        .padding(.leading, Spacing.s3)
        .padding(.trailing, Spacing.s1)
        .frame(height: Size.toolbarButtonHeight)
        .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
    }

    @ViewBuilder private var field: some View {
        if let focused {
            TextField(placeholder, text: $text).focused(focused)
        } else {
            TextField(placeholder, text: $text)
        }
    }
}

#Preview("Find") {
    @Previewable @State var term = "apple"
    @Previewable @State var replaceTerm = ""
    @Previewable @State var options = FindBarOptions()
    VStack {
        Spacer()
        FindBar(
            term: $term, replaceTerm: $replaceTerm, options: $options, status: FindBarStatus(count: 3, current: 0),
            canReplace: true, onStep: { _ in }, onReplace: { _ in }, onClose: {})
    }
}

#Preview("Replace") {
    @Previewable @State var term = "apple"
    @Previewable @State var replaceTerm = "pear"
    @Previewable @State var options = FindBarOptions(replace: true, caseSensitive: true)
    VStack {
        Spacer()
        FindBar(
            term: $term, replaceTerm: $replaceTerm, options: $options, status: FindBarStatus(count: 0, current: nil),
            canReplace: true, onStep: { _ in }, onReplace: { _ in }, onClose: {})
    }
}
