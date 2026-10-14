import SwiftUI

/// Where a drag can land: a rounded area with a dotted border, an optional icon and label. At rest it is a quiet
/// invitation ("Drag a page here"); with `isTargeted` (something is over it) it takes the colour tone. Plain values in;
/// the caller does the dropping.
public struct DropTargetArea: View {
    private let title: LocalizedStringKey?
    private let icon: Icon?
    private let isTargeted: Bool
    @Environment(\.colorTone) private var colorTone

    public init(_ title: LocalizedStringKey? = nil, icon: Icon? = nil, isTargeted: Bool) {
        self.title = title
        self.icon = icon
        self.isTargeted = isTargeted
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: Radius.lg)
            .fill(isTargeted ? colorTone.selectionFill.opacity(0.6) : .clear)
            .strokeBorder(
                isTargeted ? colorTone.fill.opacity(0.7) : Theme.border,
                style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.1, 6])
            )
            .overlay {
                if title != nil || icon != nil {
                    VStack(spacing: Spacing.s1_5) {
                        if let icon { IconView(icon, size: TextSize.lg.rawValue) }
                        if let title { Text(title).font(.hk(.sm, .medium)).multilineTextAlignment(.center) }
                    }
                    .foregroundStyle(isTargeted ? colorTone.fill : Theme.mutedForeground)
                    .padding(Spacing.s3)
                }
            }
            .animation(Motion.easeOut(), value: isTargeted)
    }
}

#Preview {
    VStack(spacing: Spacing.s4) {
        DropTargetArea("Drag a page or a tab here", icon: .trayArrowDown, isTargeted: false).frame(height: 96)
        DropTargetArea("Show here", isTargeted: true).frame(height: 96)
    }
    .padding()
    .frame(width: 360)
}
