import SwiftUI

/// What a publish ends on (and the page ⋯ → Published → Show Link…): the page is published — its link in a field with
/// Copy, how it is shared (listed in Hikki Community, or only with the link), its tags and author, that the link shows the
/// page as published until it is updated — then Open in Browser and Done.
public struct PublishedSheet: View {
    let link: String
    let listed: Bool
    let tags: [String]
    let author: String
    let updated: Bool
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onDone: () -> Void
    @State private var copied = false
    @Environment(\.colorTone) private var tone

    public init(
        link: String, listed: Bool, tags: [String], author: String = "", updated: Bool = false, onCopy: @escaping () -> Void,
        onOpen: @escaping () -> Void, onDone: @escaping () -> Void
    ) {
        self.link = link
        self.listed = listed
        self.tags = tags
        self.author = author
        self.updated = updated
        self.onCopy = onCopy
        self.onOpen = onOpen
        self.onDone = onDone
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s5) {
            HStack(spacing: Spacing.s3) {
                IconView(.checkCircleFill, size: TextSize.xl.rawValue).foregroundStyle(tone.fill)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(updated ? "app:published.updated" : "app:published.title").font(.hk(.lg, .semibold))
                    Text(listed ? "app:published.listed" : "app:published.link")
                        .font(.hk(.sm))
                        .foregroundStyle(Theme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Spacing.s2) {
                Text(verbatim: link)  // the link itself
                    .font(.hk(.sm))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("published-link-text")
                Button {
                    onCopy()
                    withAnimation(Motion.easeOut()) { copied = true }
                } label: {
                    IconLabel(copied ? "app:published.copied" : "app:published.copy", icon: copied ? .check : .copy)
                        .font(.hk(.sm, .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(tone.fill)
                .accessibilityIdentifier("published-copy")
            }
            .padding(.leading, Spacing.s3)
            .padding(.trailing, Spacing.s1_5)
            .padding(.vertical, Spacing.s1_5)
            .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
            if !tags.isEmpty {
                HStack(spacing: Spacing.s1_5) {
                    IconView(.tag, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
                    Text(verbatim: tags.joined(separator: " · "))  // the tags' names, already localized
                        .font(.hk(.sm))
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            if !author.isEmpty {
                Text("app:published.author \(author)")
                    .font(.hk(.sm))
                    .foregroundStyle(Theme.mutedForeground)
            }
            Text("app:published.snapshot")
                .font(.hk(.xs))
                .foregroundStyle(Theme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Spacing.s2) {
                Button(action: onOpen) {
                    IconLabel("app:published.open", icon: .arrowSquareOut)
                }
                .accessibilityIdentifier("published-open")
                Spacer(minLength: Spacing.s2)
                Button("app:published.done", action: onDone)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("published-done")
            }
        }
        .padding(Spacing.s6)
        #if os(macOS)
            .frame(width: Size.unlockSheet)
        #endif
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("published-sheet")
    }
}

#Preview("Listed") {
    PublishedSheet(
        link: "https://hikki.yancey.app/community/2164cc13-79da-4b22-8cc0-bb706bc33c12", listed: true, tags: ["Study", "Languages"],
        author: "Yancey",
        onCopy: {}, onOpen: {}, onDone: {})
}

#Preview("Link") {
    PublishedSheet(
        link: "https://hikki.yancey.app/p/2164cc13-79da-4b22-8cc0-bb706bc33c12#2EYCRiuvEg8cI2ZnUMkxlbgiY7ciOMm5Y7zlfyizv5E",
        listed: false, tags: [], updated: true, onCopy: {}, onOpen: {}, onDone: {})
}
