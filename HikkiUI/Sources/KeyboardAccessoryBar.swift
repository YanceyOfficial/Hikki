import SwiftUI

/// Bar for above the software keyboard: scrolling tools on the leading side, a hide-keyboard button pinned
/// trailing so it is always reachable however many tools there are.
public struct KeyboardAccessoryBar<Tools: View>: View {
    public static var height: CGFloat { Size.keyboardBar }

    private let onDismiss: () -> Void
    private let tools: Tools

    public init(onDismiss: @escaping () -> Void, @ViewBuilder tools: () -> Tools) {
        self.onDismiss = onDismiss
        self.tools = tools()
    }

    public var body: some View {
        HStack(spacing: Spacing.s0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s0_5) { tools }
                    .padding(.horizontal, Spacing.s2)
            }
            // Fades tools out under the pinned button instead of cutting them off.
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading,
                    endPoint: .trailing)
            )
            KeyboardDismissButton(action: onDismiss)
                .padding(.trailing, Spacing.s2)
        }
        .frame(height: Self.height)
        .background(.bar)
    }
}

#Preview {
    VStack {
        Spacer()
        KeyboardAccessoryBar(onDismiss: {}) {
            let icons: [Icon] = [.textB, .textItalic, .textStrikethrough, .listBullets, .listNumbers, .listChecks, .quotes, .codeBlock]
            ForEach(icons, id: \.self) { icon in
                ToolbarIconButton(LocalizedStringKey(icon.rawValue), symbol: icon, isActive: icon == .textB) {}
            }
        }
    }
}
