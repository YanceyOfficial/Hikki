import SwiftUI

/// Icon-only toolbar button with an "on" state (formatting bars, inspectors).
/// The title is kept as the accessibility label and tooltip.
public struct ToolbarIconButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let isActive: Bool
    private let action: () -> Void

    public init(_ title: LocalizedStringKey, systemImage: String, isActive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isActive = isActive
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 40, height: 36)
                .foregroundStyle(isActive ? Color.accentColor : .primary)
                .background(isActive ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(Text(title))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

#Preview {
    HStack {
        ToolbarIconButton("Bold", systemImage: "bold", isActive: true) {}
        ToolbarIconButton("Italic", systemImage: "italic") {}
    }
    .padding()
}
