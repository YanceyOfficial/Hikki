import SwiftUI

/// One toast (Sonner's look): an icon for its kind, the message, a small reference under it ("HK-2001 · K3F9QX" for an
/// error, so a report can name it), an optional action and a close button, on a popover surface.
public struct ToastView: View {
    public enum Kind: Sendable {
        case success, info, warning, error
    }

    let kind: Kind
    let message: String
    let reference: String?
    let actionTitle: LocalizedStringKey?
    let action: (() -> Void)?
    let close: () -> Void

    public init(
        kind: Kind, message: String, reference: String? = nil, actionTitle: LocalizedStringKey? = nil,
        action: (() -> Void)? = nil, close: @escaping () -> Void
    ) {
        self.kind = kind
        self.message = message
        self.reference = reference
        self.actionTitle = actionTitle
        self.action = action
        self.close = close
    }

    public var body: some View {
        HStack(alignment: .top, spacing: Spacing.s2_5) {
            IconView(icon, size: TextSize.base.rawValue)
                .foregroundStyle(tint)
                .padding(.top, Spacing.px)
            VStack(alignment: .leading, spacing: Spacing.s0_5) {
                Text(message)
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(Theme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                if let reference {
                    Text(verbatim: reference)
                        .font(.hk(.xs).monospacedDigit())
                        .foregroundStyle(Theme.mutedForeground)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.plain)
                    .font(.hk(.xs, .medium))
                    .foregroundStyle(Theme.foreground)
                    .padding(.horizontal, Spacing.s2)
                    .padding(.vertical, Spacing.s1)
                    .background(Theme.accent, in: .rect(cornerRadius: Radius.md))
                    .accessibilityIdentifier("toast-action")
            }
            Button(action: close) {
                IconView(.x, size: TextSize.xs.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                    .contentShape(.rect)
            }
            .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.full))
            .accessibilityLabel(Text("app:toast.close"))
            .accessibilityIdentifier("toast-close")
        }
        .padding(.leading, Spacing.s3_5)
        .padding(.trailing, Spacing.s2)
        .padding(.vertical, Spacing.s3)
        .frame(maxWidth: Size.toastWidth)
        .background(Theme.popover, in: .rect(cornerRadius: Radius.xl))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)  // design-lint: allow — the popover shadow's recipe
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("toast")
    }

    private var icon: Icon {
        switch kind {
        case .success: .checkCircleFill
        case .info: .info
        case .warning: .warningCircle
        case .error: .xCircle
        }
    }

    private var tint: Color {
        switch kind {
        case .success: Theme.inkGreen
        case .info: Theme.mutedForeground
        case .warning: Theme.inkYellow
        case .error: Theme.destructive
        }
    }
}

/// The toasts of a window, newest at the bottom, each entering from below and leaving with the shared motion.
public struct ToastStack<Item: Identifiable, Row: View>: View {
    let items: [Item]
    let row: (Item) -> Row

    public init(_ items: [Item], @ViewBuilder row: @escaping (Item) -> Row) {
        self.items = items
        self.row = row
    }

    public var body: some View {
        VStack(spacing: Spacing.s2) {
            ForEach(items) { item in
                row(item)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.easeOut(), value: items.map(\.id))
    }
}

#Preview {
    VStack(spacing: Spacing.s3) {
        ToastView(kind: .success, message: "Link copied", close: {})
        ToastView(kind: .info, message: "3 pages imported", close: {})
        ToastView(
            kind: .warning, message: "Couldn't sync with the workspace folder.", reference: "HK-2102 · K3F9QX",
            actionTitle: "Retry", action: {}, close: {})
        ToastView(
            kind: .error, message: "Couldn't save the page.", reference: "HK-2001 · W7RM2D", actionTitle: "Copy details",
            action: {}, close: {})
    }
    .padding(Spacing.s6)
    .background(Theme.background)
}
