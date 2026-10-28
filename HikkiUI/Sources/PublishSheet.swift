import SwiftUI

/// "Publish this page" (page ⋯ → Publish…, and Sharing Settings… for a published one): how it is shared — only with
/// people who have the link (stored encrypted, the key in the link alone) or listed in Hikki Shared, the website's
/// public list (stored readable, found by its tags and words) — its tags (a listed page is filed under them), the name
/// shown as its author, what goes with it and what stays private, and a check that the page holds nothing private.
/// Publish is open once that check is made and a listed page has a tag.
public struct PublishSheet: View {
    public struct Tag: Identifiable, Equatable {
        public var id: String
        public var title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    let title: String
    let tags: [Tag]
    let maxTags: Int
    /// Changing a published page's settings: the confirmation reads Save.
    let isUpdate: Bool
    let isPublishing: Bool
    @Binding var listed: Bool
    @Binding var chosenTags: Set<String>
    @Binding var author: String
    @Binding var checked: Bool
    let onPublish: () -> Void
    let onCancel: () -> Void
    @Environment(\.colorTone) private var tone

    public init(
        title: String, tags: [Tag], maxTags: Int, isUpdate: Bool = false, isPublishing: Bool, listed: Binding<Bool>,
        chosenTags: Binding<Set<String>>, author: Binding<String>, checked: Binding<Bool>, onPublish: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.tags = tags
        self.maxTags = maxTags
        self.isUpdate = isUpdate
        self.isPublishing = isPublishing
        _listed = listed
        _chosenTags = chosenTags
        _author = author
        _checked = checked
        self.onPublish = onPublish
        self.onCancel = onCancel
    }

    private var canPublish: Bool { checked && (!listed || !chosenTags.isEmpty) && !isPublishing }

    public var body: some View {
        #if os(macOS)
            VStack(alignment: .leading, spacing: Spacing.s5) {
                content
                actions
            }
            .padding(Spacing.s6)
            .frame(width: Size.unlockSheet)
            .modifier(SheetIdentity())
        #else
            // A phone's sheet scrolls its choices; Cancel and Publish stay at its foot.
            ScrollView {
                content
                    .padding(.horizontal, Spacing.s6)
                    .padding(.top, Spacing.s8)
                    .padding(.bottom, Spacing.s4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .safeAreaInset(edge: .bottom, spacing: Spacing.s0) {
                actions
                    .padding(.horizontal, Spacing.s6)
                    .padding(.vertical, Spacing.s4)
                    .background(Theme.background)
                    .overlay(alignment: .top) { Divider() }
            }
            .modifier(SheetIdentity())
        #endif
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Spacing.s5) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(isUpdate ? "app:publish.settings.title" : "app:publish.title").font(.hk(.lg, .semibold))
                Text(verbatim: title)  // the page's title
                    .font(.hk(.sm))
                    .lineLimit(1)
                    .foregroundStyle(Theme.mutedForeground)
            }
            VStack(spacing: Spacing.s2) {
                Choice(
                    icon: .link, title: "app:publish.mode.link", detail: "app:publish.mode.link.detail", isSelected: !listed
                ) { listed = false }
                .accessibilityIdentifier("publish-mode-link")
                Choice(
                    icon: .globe, title: "app:publish.mode.listed", detail: "app:publish.mode.listed.detail", isSelected: listed
                ) { listed = true }
                .accessibilityIdentifier("publish-mode-listed")
            }
            VStack(alignment: .leading, spacing: Spacing.s2) {
                HStack {
                    Text(listed ? "app:publish.tags" : "app:publish.tags.optional").font(.hk(.sm, .medium))
                    Spacer()
                    Text("app:publish.tags.limit \(maxTags.formatted())").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                }
                FlowRow {
                    ForEach(tags) { tag in
                        let isOn = chosenTags.contains(tag.id)
                        FilterChip(LocalizedStringKey(tag.title), isSelected: isOn, look: .filled) {
                            if isOn {
                                chosenTags.remove(tag.id)
                            } else if chosenTags.count < maxTags {
                                chosenTags.insert(tag.id)
                            }
                        }
                        .opacity(!isOn && chosenTags.count >= maxTags ? 0.5 : 1)
                        .accessibilityIdentifier("publish-tag-\(tag.id)")
                    }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.s1_5) {
                Text("app:publish.author").font(.hk(.sm, .medium))
                TextField("app:publish.author.placeholder", text: $author)
                    .textFieldStyle(.roundedBorder)
                    .font(.hk(.sm))
                    .accessibilityIdentifier("publish-author")
                Text("app:publish.author.detail").font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // What the choice above doesn't already say: a listed page is anyone's to read; either way the link
            // shows the page as it is now, and its conversations stay private.
            VStack(alignment: .leading, spacing: Spacing.s2_5) {
                if listed { Point(icon: .globe, text: "app:publish.point.readable") }
                Point(icon: .clockCounterClockwise, text: "app:publish.point.snapshot")
                Point(icon: .chatTeardropText, text: "app:publish.point.private")
            }
            CheckRow(isOn: $checked, text: "app:publish.check")
                .accessibilityIdentifier("publish-check")
        }
        .animation(Motion.easeOut(), value: listed)
    }

    private var actions: some View {
        HStack(spacing: Spacing.s2) {
            Button("app:common.cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("publish-cancel")
            Spacer(minLength: Spacing.s2)
            if isPublishing {
                ProgressView().controlSize(.small)
                Text("app:publish.publishing").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
            } else {
                Button(isUpdate ? "app:publish.save" : "app:publish.confirm", action: onPublish)
                    .buttonStyle(.borderedProminent)
                    .tint(tone.fill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canPublish)
                    .accessibilityIdentifier("publish-confirm")
            }
        }
    }

    private struct SheetIdentity: ViewModifier {
        func body(content: Content) -> some View {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("publish-sheet")
        }
    }

    /// The privacy check: a box and its whole sentence, wrapping — a switch cut the sentence to one line.
    private struct CheckRow: View {
        @Binding var isOn: Bool
        let text: LocalizedStringKey
        @Environment(\.colorTone) private var tone

        var body: some View {
            Button {
                isOn.toggle()
            } label: {
                HStack(alignment: .top, spacing: Spacing.s3) {
                    IconView(isOn ? .checkCircleFill : .circle, size: TextSize.base.rawValue)
                        .foregroundStyle(isOn ? tone.fill : Theme.mutedForeground)
                        .frame(width: Spacing.s5)
                    Text(text).font(.hk(.sm)).foregroundStyle(Theme.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.s3)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
                .contentShape(.rect(cornerRadius: Radius.md))
            }
            .buttonStyle(.pressable)
            .accessibilityAddTraits(isOn ? .isSelected : [])
        }
    }

    /// One way to share: a card with its glyph, name and what it means, the chosen one outlined in the tone.
    private struct Choice: View {
        let icon: Icon
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let isSelected: Bool
        let action: () -> Void
        @Environment(\.colorTone) private var tone

        var body: some View {
            Button(action: action) {
                HStack(alignment: .top, spacing: Spacing.s3) {
                    IconView(icon, size: TextSize.base.rawValue)
                        .foregroundStyle(isSelected ? tone.fill : Theme.mutedForeground)
                        .frame(width: Spacing.s5)
                        .padding(.top, Spacing.s0_5)
                    VStack(alignment: .leading, spacing: Spacing.s0_5) {
                        Text(title).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground)
                        Text(detail).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    IconView(isSelected ? .checkCircleFill : .circle, size: TextSize.base.rawValue)
                        .foregroundStyle(isSelected ? tone.fill : Theme.border)
                }
                .padding(Spacing.s3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? tone.selectionFill : .clear, in: .rect(cornerRadius: Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md).strokeBorder(isSelected ? tone.fill : Theme.border)
                )
                .contentShape(.rect(cornerRadius: Radius.md))
            }
            .buttonStyle(.pressable)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    private struct Point: View {
        let icon: Icon
        let text: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.s3) {
                IconView(icon, size: TextSize.sm.rawValue)
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(width: Spacing.s5)
                    .padding(.top, Spacing.s0_5)
                Text(text).font(.hk(.sm)).foregroundStyle(Theme.mutedForeground).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PublishSheetPreview: View {
    var listed: Bool
    @State private var isListed = false
    @State private var tags: Set<String> = ["study"]
    @State private var checked = false
    @State private var author = "Yancey"

    var body: some View {
        PublishSheet(
            title: "Trip to Kyoto",
            tags: ["study", "language", "work", "tech", "design", "writing", "reading", "travel"].map {
                .init(id: $0, title: $0.capitalized)
            }, maxTags: 3, isPublishing: false, listed: $isListed, chosenTags: $tags, author: $author, checked: $checked, onPublish: {},
            onCancel: {}
        )
        .onAppear { isListed = listed }
    }
}

#Preview("Link") { PublishSheetPreview(listed: false) }
#Preview("Listed") { PublishSheetPreview(listed: true) }
