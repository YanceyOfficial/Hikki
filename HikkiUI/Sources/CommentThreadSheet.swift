import SwiftUI

/// One comment as the thread sheet shows it.
public struct CommentThreadComment: Identifiable, Equatable, Sendable {
    public var id: String
    /// Who wrote it (nil: this device's user, "You").
    public var author: String?
    /// The device it was written on, when that was another one ("on Mac").
    public var device: String?
    public var createdAt: Date
    public var edited: Bool
    /// The words for display (page mentions read "@Title").
    public var text: String
    /// The words as stored, what Edit starts from.
    public var body: String

    public init(
        id: String, author: String?, device: String? = nil, createdAt: Date, edited: Bool = false, text: String,
        body: String? = nil
    ) {
        self.id = id
        self.author = author
        self.device = device
        self.createdAt = createdAt
        self.edited = edited
        self.text = text
        self.body = body ?? text
    }
}

/// What the thread sheet asks for.
public enum CommentThreadAction: Equatable, Sendable {
    case reply(String)
    case resolve
    /// A reply alone; the first comment deletes the whole discussion.
    case delete(commentId: String, wholeThread: Bool)
    case edit(commentId: String, body: String)
    case copyLink
}

/// A phone's open comment thread, Notion's: a sheet with the passage it is on, its comments — each with its actions
/// always at hand (⋯: Edit in place, Copy link to discussion, Delete) — resolve ✓ at the top, and the reply field at
/// its foot. Plain values in, actions out; the app writes them and hands the thread back changed.
public struct CommentThreadSheet: View {
    let quote: String
    let comments: [CommentThreadComment]
    let onAction: (CommentThreadAction) -> Void
    let onClose: () -> Void
    @State private var reply = ""
    @State private var editing: String?
    @State private var draft = ""
    @FocusState private var replying: Bool
    @FocusState private var editingFocus: Bool

    public init(
        quote: String, comments: [CommentThreadComment], onAction: @escaping (CommentThreadAction) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.quote = quote
        self.comments = comments
        self.onAction = onAction
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            HStack(spacing: Spacing.s2) {
                Text("app:comments.discussion").font(.hk(.base, .semibold)).foregroundStyle(Theme.foreground)
                Spacer(minLength: Spacing.s0)
                Button {
                    onAction(.resolve)
                } label: {
                    IconLabel("app:comments.resolve", icon: .check, size: TextSize.base.rawValue)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.mutedForeground)
                        .frame(width: Size.iconButton, height: Size.iconButton)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("comment-sheet-resolve")
                ComposerCloseButton(action: onClose)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s4)
            .padding(.bottom, Spacing.s2)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s4) {
                    if !quote.isEmpty {
                        // The passage's own words.
                        Text(verbatim: quote)
                            .font(.hk(.sm))
                            .foregroundStyle(Theme.subtleForeground)
                            .lineLimit(3)
                            .padding(.leading, Spacing.s2_5)
                            .overlay(alignment: .leading) { Capsule().fill(Theme.inkYellow).frame(width: Spacing.s0_5) }
                    }
                    ForEach(Array(comments.enumerated()), id: \.element.id) { index, comment in
                        row(comment, first: index == 0)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s2)
            }
            .scrollBounceBehavior(.basedOnSize)
            ComposerSendField(
                placeholder: "app:comments.replyPlaceholder", text: $reply, focused: $replying,
                identifier: "comment-sheet-field", sendIdentifier: "comment-sheet-send"
            ) { text in
                onAction(.reply(text))
                reply = ""
            }
            .padding(Spacing.s3)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.x2l))
            .padding(.horizontal, Spacing.s2)
            .padding(.bottom, Spacing.s2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment-sheet")
    }

    private func row(_ comment: CommentThreadComment, first: Bool) -> some View {
        HStack(alignment: .top, spacing: Spacing.s2_5) {
            CommentAvatar(name: comment.author)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s1_5) {
                    // The author's own name.
                    Text(verbatim: comment.author ?? String(localized: "app:comments.you"))
                        .font(.hk(.sm, .semibold))
                        .foregroundStyle(Theme.foreground)
                    Text(comment.createdAt, format: .relative(presentation: .named))
                        .font(.hk(.xs))
                        .foregroundStyle(Theme.mutedForeground)
                    if comment.edited {
                        Text("app:comments.edited").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                    }
                    Spacer(minLength: Spacing.s0)
                    actions(comment, first: first)
                }
                if editing == comment.id {
                    editor(comment)
                } else {
                    // The comment, as written.
                    Text(verbatim: comment.text)
                        .font(.hk(.base))
                        .foregroundStyle(Theme.foreground)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let device = comment.device {
                    Text("app:comments.onDevice \(device)").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comment-sheet-comment")
    }

    private func actions(_ comment: CommentThreadComment, first: Bool) -> some View {
        Menu {
            Button {
                draft = comment.body
                editing = comment.id
                editingFocus = true
            } label: {
                IconLabel("app:comments.edit", icon: .pencilSimple)
            }
            Button {
                onAction(.copyLink)
            } label: {
                IconLabel("app:comments.copyLink", icon: .link)
            }
            Button(role: .destructive) {
                onAction(.delete(commentId: comment.id, wholeThread: first))
            } label: {
                IconLabel(first ? "app:comments.deleteThread" : "app:common.delete", icon: .trash)
            }
        } label: {
            IconLabel("app:comments.more", icon: .dotsThree, size: TextSize.base.rawValue)
                .labelStyle(.iconOnly)
                .foregroundStyle(Theme.mutedForeground)
                .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityIdentifier("comment-sheet-more")
    }

    private func editor(_ comment: CommentThreadComment) -> some View {
        VStack(alignment: .trailing, spacing: Spacing.s2) {
            TextField("app:comments.replyPlaceholder", text: $draft, axis: .vertical)
                .font(.hk(.base))
                .focused($editingFocus)
                .padding(Spacing.s2)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
                .accessibilityIdentifier("comment-sheet-edit-field")
            HStack(spacing: Spacing.s2) {
                Button("app:common.cancel") { editing = nil }
                    .buttonStyle(.glass)
                Button("app:comments.save") {
                    let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty, body != comment.body { onAction(.edit(commentId: comment.id, body: body)) }
                    editing = nil
                }
                .buttonStyle(.glassProminent)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("comment-sheet-save")
            }
        }
    }
}

/// The author's initial in a circle (the page's comment cards draw the same).
private struct CommentAvatar: View {
    let name: String?
    @Environment(\.colorTone) private var tone

    var body: some View {
        // An initial, not words.
        Text(verbatim: String((name ?? String(localized: "app:comments.you")).prefix(1)).uppercased())
            .font(.hk(.xs, .semibold))
            .foregroundStyle(Theme.primaryForeground)
            .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
            .background(tone.fill, in: .circle)
    }
}

#Preview {
    VStack {
        Spacer()
        CommentThreadSheet(
            quote: "Peak is mid-November",
            comments: [
                CommentThreadComment(id: "1", author: nil, createdAt: .now.addingTimeInterval(-3600), text: "Is this still right?"),
                CommentThreadComment(
                    id: "2", author: "Yancey", device: "Mac", createdAt: .now.addingTimeInterval(-600), edited: true,
                    text: "Yes — checked @Kyoto trip"),
            ],
            onAction: { _ in }, onClose: {}
        )
        .frame(height: 420)
    }
}
