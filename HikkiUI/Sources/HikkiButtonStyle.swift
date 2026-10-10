import SwiftUI

/// Native buttons in the shadcn `base-vega` look (same tokens as the web's Button): `Radius.md`,
/// primary / outline / ghost variants, full-width option for forms.
public struct HikkiButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case primary, outline, ghost }

    private let variant: Variant
    private let fullWidth: Bool

    public init(_ variant: Variant = .primary, fullWidth: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, variant: variant, fullWidth: fullWidth)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let variant: Variant
        let fullWidth: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.hk(.sm, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, Spacing.s4)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: Size.iconButton + Spacing.s2)
                .background(background, in: .rect(cornerRadius: Radius.md))
                .overlay {
                    if variant == .outline {
                        RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border)
                    }
                }
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .contentShape(.rect(cornerRadius: Radius.md))
                .onHover { hovering = $0 }
        }

        private var foreground: Color {
            variant == .primary ? Theme.primaryForeground : Theme.foreground
        }

        private var background: Color {
            switch variant {
            case .primary: Theme.primary.opacity(configuration.isPressed || hovering ? 0.85 : 1)
            case .outline: hovering ? Theme.accent : Theme.background
            case .ghost: hovering ? Theme.accent : .clear
            }
        }
    }
}

extension ButtonStyle where Self == HikkiButtonStyle {
    /// `.buttonStyle(.hikki(.outline, fullWidth: true))`
    public static func hikki(_ variant: HikkiButtonStyle.Variant = .primary, fullWidth: Bool = false) -> HikkiButtonStyle {
        HikkiButtonStyle(variant, fullWidth: fullWidth)
    }
}

#Preview {
    VStack(spacing: Spacing.s3) {
        Button("Continue") {}.buttonStyle(.hikki())
        Button("Choose folder") {}.buttonStyle(.hikki(.outline))
        Button("Skip") {}.buttonStyle(.hikki(.ghost))
    }
    .padding()
}
