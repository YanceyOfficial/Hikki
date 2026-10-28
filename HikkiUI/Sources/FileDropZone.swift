import SwiftUI

/// A place to drop files (Settings → Import & Export): a dashed card with an icon, a line and a hint, lit in the tone
/// while a drag is over it (`isTargeted`); a tap opens the picker instead (`action`). The drop itself is the caller's
/// `.onDrop` on it.
public struct FileDropZone: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: Icon
    let isTargeted: Bool
    let action: () -> Void
    @Environment(\.colorTone) private var tone

    public init(title: LocalizedStringKey, detail: LocalizedStringKey, icon: Icon, isTargeted: Bool, action: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.icon = icon
        self.isTargeted = isTargeted
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.s2) {
                IconView(icon, size: TextSize.lg.rawValue).foregroundStyle(isTargeted ? tone.ink : Theme.mutedForeground)
                Text(title).font(.hk(.base, .medium)).foregroundStyle(Theme.foreground)
                Text(detail).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.s6)
            .padding(.horizontal, Spacing.s4)
            .background(isTargeted ? tone.selectionFill : Theme.muted, in: .rect(cornerRadius: Radius.xl))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.xl)
                    .strokeBorder(
                        isTargeted ? tone.fill : Theme.border,
                        style: StrokeStyle(lineWidth: Spacing.px, dash: [Spacing.s1_5, Spacing.s1]))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(Motion.easeOut(), value: isTargeted)
        .accessibilityIdentifier("drop-zone")
    }
}

#Preview {
    VStack(spacing: Spacing.s4) {
        FileDropZone(
            title: "Drop files or folders here", detail: "Markdown, HTML, text, Hikki JSON, or a Notion export (.zip)",
            icon: .trayArrowDown, isTargeted: false
        ) {}
        FileDropZone(title: "Drop files or folders here", detail: "Release to import", icon: .trayArrowDown, isTargeted: true) {}
    }
    .padding()
}
