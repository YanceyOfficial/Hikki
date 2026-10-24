import SwiftUI

/// The press everything pressable shares — 97 % with `Motion.easeOut(Motion.popOut)`, the web's `Button` / `Toggle`
/// press — for a button style's label (`HikkiButtonStyle`, the chat's send button) or a whole card or tile.
public struct PressEffect: ViewModifier {
    private let pressed: Bool

    public init(pressed: Bool) {
        self.pressed = pressed
    }

    public func body(content: Content) -> some View {
        content
            .scaleEffect(pressed ? 0.97 : 1)
            .animation(Motion.easeOut(Motion.popOut), value: pressed)
    }
}

extension View {
    /// `.pressEffect(configuration.isPressed)` inside a `ButtonStyle`.
    public func pressEffect(_ pressed: Bool) -> some View { modifier(PressEffect(pressed: pressed)) }
}

/// A button that is only its label and the press — cards, tiles and rows that draw themselves.
public struct PressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label.pressEffect(configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// `.buttonStyle(.pressable)`
    public static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

#Preview {
    VStack(spacing: Spacing.s3) {
        Button {
        } label: {
            Text(verbatim: "A tile")
                .padding(Spacing.s4)
                .frame(maxWidth: .infinity)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.pressable)
        Button("Continue") {}.buttonStyle(.hikki())
    }
    .padding()
}
