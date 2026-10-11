import SwiftUI

/// A tappable option card (radio-group style): icon, title, description, check when selected.
public struct SelectableCard: View {
    private let title: LocalizedStringKey
    private let detail: LocalizedStringKey
    private let icon: Icon
    private let isSelected: Bool
    private let action: () -> Void
    @State private var hovering = false
    @Environment(\.colorTone) private var tone

    public init(_ title: LocalizedStringKey, detail: LocalizedStringKey, icon: Icon, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Spacing.s3) {
                IconView(icon, size: Size.iconButton - Spacing.s2)
                    .foregroundStyle(isSelected ? tone.fill : Theme.subtleForeground)
                    .padding(.top, Spacing.px)
                VStack(alignment: .leading, spacing: Spacing.s1) {
                    Text(title).font(.hk(.sm, .semibold)).foregroundStyle(Theme.foreground)
                    Text(detail)
                        .font(.hk(.md))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Spacing.s2)
                IconView(.checkCircleFill, size: TextSize.lg.rawValue)
                    .foregroundStyle(tone.fill)
                    .opacity(isSelected ? 1 : 0)
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Theme.selection : hovering ? Theme.accent : Theme.card, in: .rect(cornerRadius: Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.lg)
                    .strokeBorder(isSelected ? tone.fill : Theme.border, lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(.rect(cornerRadius: Radius.lg))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    VStack {
        SelectableCard("iCloud Drive", detail: "Syncs across your devices.", icon: .cloud, isSelected: true) {}
        SelectableCard("This device only", detail: "Stays on this device.", icon: .laptop, isSelected: false) {}
    }
    .padding()
    .frame(width: 420)
}
