import SwiftUI

/// Where the trial stands, as the unlock sheet and Settings show it.
public enum UnlockStatus: Equatable, Sendable {
    case trial(daysLeft: Int)
    case expired
    case unlocked
}

/// The unlock (one in-app purchase for iPhone, iPad and Mac): where the trial stands, what the purchase is and what
/// happens without it, Unlock with the store's price, Restore Purchases. Plain values and closures — the app's
/// `Purchases` drives it.
public struct UnlockSheet: View {
    let status: UnlockStatus
    /// The store's localized price; nil while it loads or when the store can't be reached (Unlock is then disabled).
    let price: String?
    let isPurchasing: Bool
    let onUnlock: () -> Void
    let onRestore: () -> Void
    let onClose: () -> Void
    @Environment(\.colorTone) private var tone

    public init(
        status: UnlockStatus, price: String?, isPurchasing: Bool = false, onUnlock: @escaping () -> Void,
        onRestore: @escaping () -> Void, onClose: @escaping () -> Void
    ) {
        self.status = status
        self.price = price
        self.isPurchasing = isPurchasing
        self.onUnlock = onUnlock
        self.onRestore = onRestore
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s5) {
            HStack(alignment: .top) {
                IconView(status == .unlocked ? .check : .sparkle, size: TextSize.x2l.rawValue)
                    .foregroundStyle(tone.fill)
                    .frame(width: Size.touchTarget, height: Size.touchTarget)
                    .background(tone.selectionFill, in: .rect(cornerRadius: Radius.lg))
                Spacer()
                Button(action: onClose) {
                    IconView(.x, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
                }
                .buttonStyle(HikkiButtonStyle(.ghost))
                .accessibilityLabel(Text("app:common.close"))
                .accessibilityIdentifier("unlock-close")
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(title).font(.hk(.x2l, .semibold)).foregroundStyle(Theme.foreground)
                Text(statusLine).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
                    .accessibilityIdentifier("unlock-status")
            }
            VStack(alignment: .leading, spacing: Spacing.s3) {
                point(.laptop, "app:unlock.point.devices")
                point(.check, "app:unlock.point.once")
                point(.export, "app:unlock.point.yours")
            }
            if status != .unlocked {
                VStack(spacing: Spacing.s2) {
                    Button(action: onUnlock) {
                        if isPurchasing {
                            ProgressView().controlSize(.small)
                        } else if let price {
                            Text("app:unlock.buy \(price)")
                        } else {
                            Text("app:unlock.unavailable")
                        }
                    }
                    .buttonStyle(HikkiButtonStyle(.primary, fullWidth: true))
                    .disabled(price == nil || isPurchasing)
                    .accessibilityIdentifier("unlock-buy")
                    Button("app:unlock.restore", action: onRestore)
                        .buttonStyle(HikkiButtonStyle(.ghost, fullWidth: true))
                        .disabled(isPurchasing)
                        .accessibilityIdentifier("unlock-restore")
                }
            }
        }
        .padding(Spacing.s6)
        .frame(maxWidth: Size.unlockSheet)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unlock-sheet")
    }

    private var title: LocalizedStringKey {
        status == .unlocked ? "app:unlock.titleUnlocked" : "app:unlock.title"
    }

    private var statusLine: LocalizedStringKey {
        switch status {
        case .trial(let days): "app:unlock.trialLeft \(days.formatted())"
        case .expired: "app:unlock.expired"
        case .unlocked: "app:unlock.unlocked"
        }
    }

    private func point(_ icon: Icon, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            IconView(icon, size: TextSize.sm.rawValue).foregroundStyle(tone.fill)
            Text(text).font(.hk(.sm)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The trial is over: a quiet glass bar over the page's foot — the pages are read only — with Unlock.
public struct ReadOnlyBar: View {
    let onUnlock: () -> Void
    @Environment(\.colorTone) private var tone

    public init(onUnlock: @escaping () -> Void) {
        self.onUnlock = onUnlock
    }

    public var body: some View {
        HStack(spacing: Spacing.s3) {
            IconView(.lockSimple, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
            Text("app:unlock.readOnly").font(.hk(.sm)).foregroundStyle(Theme.foreground)
            Button("app:unlock.short", action: onUnlock)
                .buttonStyle(HikkiButtonStyle(.primary))
                .accessibilityIdentifier("read-only-unlock")
        }
        .padding(.leading, Spacing.s4)
        .padding(.trailing, Spacing.s1_5)
        .padding(.vertical, Spacing.s1_5)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("read-only-bar")
    }
}

#Preview("Trial") {
    UnlockSheet(status: .trial(daysLeft: 9), price: "$19.99", onUnlock: {}, onRestore: {}, onClose: {})
}

#Preview("Expired") {
    UnlockSheet(status: .expired, price: "$19.99", onUnlock: {}, onRestore: {}, onClose: {})
}

#Preview("Unlocked") {
    UnlockSheet(status: .unlocked, price: nil, onUnlock: {}, onRestore: {}, onClose: {})
}

#Preview("Read-only bar") {
    ReadOnlyBar {}.padding()
}
