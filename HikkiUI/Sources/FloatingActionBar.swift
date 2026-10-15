import SwiftUI

/// The phone's bottom bar (Notion's): Liquid Glass floating over the content — a round button, a wide capsule with
/// the AI mark and a prompt, and the main action as a round button in the colour tone.
public struct FloatingActionBar: View {
    public struct Action {
        let title: LocalizedStringKey
        let icon: Icon
        let identifier: String
        let perform: () -> Void

        public init(_ title: LocalizedStringKey, icon: Icon, identifier: String, perform: @escaping () -> Void) {
            self.title = title
            self.icon = icon
            self.identifier = identifier
            self.perform = perform
        }
    }

    private let leading: Action
    private let prompt: LocalizedStringKey
    private let promptIdentifier: String
    private let onPrompt: () -> Void
    private let trailing: Action
    @Environment(\.colorTone) private var tone

    public init(
        leading: Action, prompt: LocalizedStringKey, promptIdentifier: String, onPrompt: @escaping () -> Void,
        trailing: Action
    ) {
        self.leading = leading
        self.prompt = prompt
        self.promptIdentifier = promptIdentifier
        self.onPrompt = onPrompt
        self.trailing = trailing
    }

    public var body: some View {
        GlassEffectContainer(spacing: Spacing.s2_5) {
            HStack(spacing: Spacing.s2_5) {
                round(leading, tinted: false)
                Button(action: onPrompt) {
                    HStack(spacing: Spacing.s2_5) {
                        AIGlyph(size: TextSize.lg.rawValue)
                            .frame(width: Size.iconButton + Spacing.s2, height: Size.iconButton + Spacing.s2)
                            .background(Theme.muted, in: .circle)
                        Text(prompt).font(.hk(.base)).foregroundStyle(Theme.mutedForeground).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, Spacing.s2)
                    .frame(height: Size.floatingBar)
                    .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityIdentifier(promptIdentifier)
                round(trailing, tinted: true)
            }
        }
        .padding(.horizontal, Spacing.s4)
    }

    private func round(_ action: Action, tinted: Bool) -> some View {
        Button(action: action.perform) {
            IconView(action.icon, size: TextSize.xl.rawValue)
                .foregroundStyle(tinted ? tone.onFill : Theme.foreground)
                .frame(width: Size.floatingBar, height: Size.floatingBar)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(tinted ? .regular.tint(tone.fill).interactive() : .regular.interactive(), in: .circle)
        .accessibilityLabel(Text(action.title))
        .accessibilityIdentifier(action.identifier)
    }
}

#Preview {
    ZStack(alignment: .bottom) {
        LinearGradient(colors: [Theme.washGreen, Theme.washBlue], startPoint: .top, endPoint: .bottom)
        FloatingActionBar(
            leading: .init("Search", icon: .magnifyingGlass, identifier: "search") {}, prompt: "Ask AI",
            promptIdentifier: "ask", onPrompt: {},
            trailing: .init("New page", icon: .notePencil, identifier: "new") {}
        )
        .padding(.bottom, Spacing.s6)
    }
    .frame(width: 390, height: 300)
}
