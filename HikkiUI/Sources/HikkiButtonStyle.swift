import SwiftUI

/// Native buttons in the shadcn `base-vega` look (same tokens as the web's Button): `Radius.md`,
/// primary / outline / ghost variants, full-width option for forms.
public struct HikkiButtonStyle: ButtonStyle {
    public enum Variant: Sendable { case primary, outline, ghost }

    private let variant: Variant
    private let fullWidth: Bool
    private let capsule: Bool

    /// `capsule`: round ends, for a button inside a capsule (a glass bar) where a rounded square looks out of place.
    public init(_ variant: Variant = .primary, fullWidth: Bool = false, capsule: Bool = false) {
        self.variant = variant
        self.fullWidth = fullWidth
        self.capsule = capsule
    }

    public func makeBody(configuration: Configuration) -> some View {
        StyledButton(configuration: configuration, variant: variant, fullWidth: fullWidth, capsule: capsule)
    }

    private struct StyledButton: View {
        let configuration: Configuration
        let variant: Variant
        let fullWidth: Bool
        let capsule: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false
        @Environment(\.colorTone) private var tone

        var body: some View {
            configuration.label
                .font(.hk(.sm, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, Spacing.s4)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .frame(height: Size.iconButton + Spacing.s2)
                .background(background, in: shape)
                .overlay {
                    if variant == .outline {
                        if capsule {
                            Capsule().strokeBorder(Theme.border)
                        } else {
                            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border)
                        }
                    }
                }
                .opacity(isEnabled ? 1 : 0.5)
                .scaleEffect(configuration.isPressed ? 0.98 : 1)
                .animation(.snappy(duration: 0.12), value: configuration.isPressed)
                .contentShape(shape)
                .onHover { hovering = $0 }
        }

        private var shape: AnyShape {
            capsule ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: Radius.md))
        }

        private var foreground: Color {
            variant == .primary ? tone.onFill : Theme.foreground
        }

        private var background: Color {
            switch variant {
            case .primary: tone.fill.opacity(configuration.isPressed || hovering ? 0.85 : 1)
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
