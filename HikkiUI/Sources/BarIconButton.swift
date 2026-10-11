import SwiftUI

public struct BarIconButton: View {
    private let title: LocalizedStringKey
    private let symbol: Icon
    private let tint: Color?
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, symbol: Icon, tint: Color? = nil, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel(title, icon: symbol, size: TextSize.base.rawValue)
                .labelStyle(.iconOnly)
                .foregroundStyle(tint ?? Theme.subtleForeground)
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(HoverHighlightStyle())
        .help(Text(title))
    }
}
