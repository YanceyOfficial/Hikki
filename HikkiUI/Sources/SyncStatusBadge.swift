import SwiftUI

/// The page's quiet save indicator, Google Docs' and Notion's: a small chip in the corner of the editor saying where
/// the latest edit has got to — saving, saved on this device, on its way to iCloud, in it, waiting for a network, or
/// not syncing. Muted, with its words only while something just happened (`compact` leaves the glyph); the tooltip
/// says it in full (the time of the last save or sync). Trouble is drawn in the destructive colour. Plain values:
/// the app works the state out (`PageSyncState`) and words it.
public struct SyncStatusBadge: View {
    public enum Kind: Equatable, Sendable {
        case saving
        case saved
        case uploading
        case waiting
        case synced
        case trouble

        var icon: Icon {
            switch self {
            case .saving: .arrowsClockwise
            case .saved: .check
            case .uploading: .cloudArrowUp
            case .waiting: .cloudSlash
            case .synced: .cloudCheck
            case .trouble: .cloudWarning
            }
        }
    }

    private let kind: Kind
    private let title: String
    private let detail: String
    private let compact: Bool

    /// - Parameters:
    ///   - title: the chip's words ("Saving…", "Synced to iCloud").
    ///   - detail: the tooltip and VoiceOver's line ("Synced to iCloud at 14:03").
    ///   - compact: only the glyph (a while after the last change); trouble always keeps its words.
    public init(kind: Kind, title: String, detail: String, compact: Bool = false) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.compact = compact && kind != .trouble
    }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            IconView(kind.icon, size: TextSize.xs.rawValue)
            if !compact {
                Text(verbatim: title)
                    .font(.hk(.x2s))
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .foregroundStyle(kind == .trouble ? Theme.destructive : Theme.mutedForeground)
        .padding(.horizontal, compact ? Spacing.s1_5 : Spacing.s2)
        .padding(.vertical, Spacing.s1)
        .background(Theme.background, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border))
        .fixedSize()
        .toolTip(detail)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: detail))
        .accessibilityIdentifier("syncStatus")
        .animation(Motion.easeOut(), value: kind)
        .animation(Motion.easeOut(), value: compact)
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: Spacing.s3) {
        SyncStatusBadge(kind: .saving, title: "Saving…", detail: "Saving…")
        SyncStatusBadge(kind: .saved, title: "Saved", detail: "Saved on this device at 14:03")
        SyncStatusBadge(kind: .uploading, title: "Syncing…", detail: "Saved on this device, going up to iCloud")
        SyncStatusBadge(kind: .waiting, title: "Waiting to sync", detail: "Saved on this device; it goes up once online")
        SyncStatusBadge(kind: .synced, title: "Synced to iCloud", detail: "Synced to iCloud at 14:03")
        SyncStatusBadge(kind: .synced, title: "Synced to iCloud", detail: "Synced to iCloud at 14:03", compact: true)
        SyncStatusBadge(kind: .trouble, title: "Not syncing", detail: "Not signed in to iCloud")
    }
    .padding(Spacing.s6)
}
