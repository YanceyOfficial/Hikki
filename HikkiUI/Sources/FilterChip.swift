import SwiftUI

/// A small capsule that narrows a list (⌘K's All / Titles / Text / Files), Notion's filter pills. Two looks:
/// `.subtle` (Mac/iPad) — outlined at rest, a grey fill when chosen, like shadcn's toggle; `.filled` (iPhone) —
/// a grey fill at rest, the foreground colour when chosen. Plain values in; the caller keeps the choice.
public struct FilterChip: View {
    public enum Look: Sendable {
        case subtle, filled
    }

    private let title: LocalizedStringKey
    private let isSelected: Bool
    private let look: Look
    private let action: () -> Void
    @State private var hovering = false

    public init(_ title: LocalizedStringKey, isSelected: Bool, look: Look = .subtle, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.look = look
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.hk(look == .filled ? .sm : .xs, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, look == .filled ? Spacing.s3_5 : Spacing.s2_5)
                .frame(height: look == .filled ? Size.iconButton + Spacing.s1 : Size.iconButtonSm + Spacing.s0_5)
                .background(background, in: .capsule)
                .overlay {
                    if look == .subtle && !isSelected { Capsule().strokeBorder(Theme.border) }
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.easeOut(), value: isSelected)
        .animation(Motion.easeOut(), value: hovering)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        switch look {
        case .subtle: isSelected ? Theme.foreground : Theme.mutedForeground
        case .filled: isSelected ? Theme.background : Theme.foreground
        }
    }

    private var background: Color {
        switch look {
        case .subtle: isSelected ? Theme.accentStrong : hovering ? Theme.accent : .clear
        case .filled: isSelected ? Theme.foreground : Theme.muted
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Spacing.s4) {
        HStack(spacing: Spacing.s1_5) {
            FilterChip("All", isSelected: true) {}
            FilterChip("Titles", isSelected: false) {}
            FilterChip("Text", isSelected: false) {}
            FilterChip("Files", isSelected: false) {}
        }
        HStack(spacing: Spacing.s2) {
            FilterChip("All", isSelected: true, look: .filled) {}
            FilterChip("Titles", isSelected: false, look: .filled) {}
            FilterChip("Files", isSelected: false, look: .filled) {}
        }
    }
    .padding()
}
