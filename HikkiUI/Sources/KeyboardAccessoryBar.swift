import SwiftUI

/// Bar for above the software keyboard (Notion's): one Liquid Glass capsule floating just over the keyboard, its
/// tools scrolling inside it and the keyboard button pinned at its end, past a hairline, however many tools there
/// are. While a panel takes the keyboard's place (`panelOpen`), that button closes the panel and brings the keyboard
/// back.
public struct KeyboardAccessoryBar<Tools: View>: View {
    public static var height: CGFloat { Size.keyboardBar }

    private let panelOpen: Bool
    private let onDismiss: () -> Void
    private let tools: Tools

    public init(panelOpen: Bool = false, onDismiss: @escaping () -> Void, @ViewBuilder tools: () -> Tools) {
        self.panelOpen = panelOpen
        self.onDismiss = onDismiss
        self.tools = tools()
    }

    public var body: some View {
        HStack(spacing: Spacing.s0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s0) { tools }
                    .padding(.horizontal, Spacing.s1)
            }
            // Fades tools out under the pinned button instead of cutting them off.
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: 0.92), .init(color: .clear, location: 1)], startPoint: .leading,
                    endPoint: .trailing)
            )
            Rectangle().fill(Theme.border).frame(width: Spacing.px, height: Spacing.s6)
            KeyboardDismissButton(showsKeyboard: panelOpen, action: onDismiss)
                .padding(.horizontal, Spacing.s1)
        }
        .frame(height: Size.toolbarButtonHeight + Spacing.s2)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Spacing.s2)
        .padding(.bottom, Spacing.s1)
        .frame(height: Self.height, alignment: .top)
    }
}

#Preview {
    VStack {
        Spacer()
        KeyboardAccessoryBar(onDismiss: {}) {
            let icons: [Icon] = [.sparkle, .plus, .textAa, .paperclip, .image, .arrowsClockwise, .arrowUUpLeft, .smiley]
            ForEach(icons, id: \.self) { icon in
                ToolbarIconButton(LocalizedStringKey(icon.rawValue), symbol: icon, isActive: icon == .plus, style: .quiet) {}
            }
        }
    }
}
