import SwiftUI

/// Bar for above the software keyboard: scrolling tools on the leading side, a hide-keyboard button pinned
/// trailing so it is always reachable however many tools there are.
public struct KeyboardAccessoryBar<Tools: View>: View {
    public static var height: CGFloat { 48 }

    private let onDismiss: () -> Void
    private let tools: Tools

    public init(onDismiss: @escaping () -> Void, @ViewBuilder tools: () -> Tools) {
        self.onDismiss = onDismiss
        self.tools = tools()
    }

    public var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { tools }
                    .padding(.horizontal, 8)
            }
            // Fades tools out under the pinned button instead of cutting them off.
            .mask(
                LinearGradient(stops: [.init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing)
            )
            KeyboardDismissButton(action: onDismiss)
                .padding(.trailing, 8)
        }
        .frame(height: Self.height)
        .background(.bar)
    }
}

#Preview {
    VStack {
        Spacer()
        KeyboardAccessoryBar(onDismiss: {}) {
            ForEach(["bold", "italic", "strikethrough", "list.bullet", "list.number", "checklist", "text.quote", "curlybraces"], id: \.self) { icon in
                ToolbarIconButton(LocalizedStringKey(icon), systemImage: icon, isActive: icon == "bold") {}
            }
        }
    }
}
