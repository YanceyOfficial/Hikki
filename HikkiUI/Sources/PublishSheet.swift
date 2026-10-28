import SwiftUI

/// "Publish a read-only link?" (page ⋯ → Publish Link…): what the link does and what it doesn't, before anything
/// goes up — anyone with it reads the page; it is stored encrypted with the key in the link alone; it shows the page
/// as it is now until Update; comments, history and chats stay private. Publish puts the link on the clipboard.
public struct PublishSheet: View {
    let title: String
    let isPublishing: Bool
    let onPublish: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorTone) private var tone

    public init(title: String, isPublishing: Bool, onPublish: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.title = title
        self.isPublishing = isPublishing
        self.onPublish = onPublish
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s4) {
            HStack(spacing: Spacing.s2) {
                IconView(.globe, size: TextSize.lg.rawValue).foregroundStyle(tone.fill)
                Text("app:publish.title").font(.hk(.lg, .semibold))
            }
            Text(verbatim: title)  // the page's title
                .font(.hk(.base, .medium))
                .lineLimit(2)
                .foregroundStyle(Theme.mutedForeground)
            VStack(alignment: .leading, spacing: Spacing.s3) {
                Point(icon: .globe, text: "app:publish.point.anyone")
                Point(icon: .lockSimple, text: "app:publish.point.encrypted")
                Point(icon: .clockCounterClockwise, text: "app:publish.point.snapshot")
                Point(icon: .chatTeardropText, text: "app:publish.point.private")
            }
            HStack(spacing: Spacing.s2) {
                Button("app:common.cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("publish-cancel")
                Spacer(minLength: Spacing.s2)
                if isPublishing {
                    ProgressView().controlSize(.small)
                    Text("app:publish.publishing").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
                } else {
                    Button("app:publish.confirm", action: onPublish)
                        .buttonStyle(.borderedProminent)
                        .tint(tone.fill)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("publish-confirm")
                }
            }
        }
        .padding(Spacing.s6)
        #if os(macOS)
            .frame(width: Size.unlockSheet)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("publish-sheet")
    }

    private struct Point: View {
        let icon: Icon
        let text: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.s3) {
                IconView(icon, size: TextSize.base.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: Spacing.s5)
                    .padding(.top, Spacing.s0_5)
                Text(text).font(.hk(.sm)).foregroundStyle(Theme.foreground).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    PublishSheet(title: "Trip to Kyoto", isPublishing: false, onPublish: {}, onCancel: {})
}

#Preview("Publishing") {
    PublishSheet(title: "Trip to Kyoto", isPublishing: true, onPublish: {}, onCancel: {})
}
