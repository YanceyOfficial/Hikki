import SwiftUI

/// A picture a web search found, as the strip shows it.
public struct ImageResultItem: Identifiable, Hashable, Sendable {
    public var id: String
    public var thumbnail: URL
    public var caption: String?
    /// The page the picture is on (its host is shown, and Open opens it).
    public var source: URL?

    public init(id: String, thumbnail: URL, caption: String? = nil, source: URL? = nil) {
        self.id = id
        self.thumbnail = thumbnail
        self.caption = caption
        self.source = source
    }
}

/// The pictures an AI answer's web search found: square thumbnails in a row that scrolls sideways. Each opens a menu —
/// Add to page (when there is one), Open the page it is on, Copy its link. A thumbnail loads like the editor's network
/// images: a muted square, the picture fading in, an icon if it fails.
public struct ImageResultStrip: View {
    let items: [ImageResultItem]
    let onAdd: ((ImageResultItem) -> Void)?
    let onOpen: (ImageResultItem) -> Void
    let onCopy: (ImageResultItem) -> Void

    public init(
        items: [ImageResultItem], onAdd: ((ImageResultItem) -> Void)? = nil, onOpen: @escaping (ImageResultItem) -> Void,
        onCopy: @escaping (ImageResultItem) -> Void
    ) {
        self.items = items
        self.onAdd = onAdd
        self.onOpen = onOpen
        self.onCopy = onCopy
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(items) { item in
                    Menu {
                        if let onAdd {
                            Button {
                                onAdd(item)
                            } label: {
                                IconLabel("app:ai.pictureAdd", icon: .plus)
                            }
                        }
                        if item.source != nil {
                            Button {
                                onOpen(item)
                            } label: {
                                IconLabel("app:ai.pictureOpen", icon: .globe)
                            }
                        }
                        Button {
                            onCopy(item)
                        } label: {
                            IconLabel("app:ai.pictureCopy", icon: .link)
                        }
                    } label: {
                        ImageResultThumbnail(item: item)
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .accessibilityLabel(Text(verbatim: item.caption ?? item.source?.host() ?? ""))
                    .accessibilityIdentifier("ai-picture")
                }
            }
        }
        .scrollClipDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-pictures")
    }
}

private struct ImageResultThumbnail: View {
    let item: ImageResultItem

    var body: some View {
        AsyncImage(url: item.thumbnail, transaction: Transaction(animation: Motion.easeOut())) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                IconView(.image, size: TextSize.lg.rawValue).foregroundStyle(Theme.mutedForeground)
            default:
                Color.clear
            }
        }
        .frame(width: Size.aiPicture, height: Size.aiPicture)
        .background(Theme.muted)
        .clipShape(.rect(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border))
        .help(Text(verbatim: item.caption ?? ""))
    }
}

#Preview {
    ImageResultStrip(
        items: [
            ImageResultItem(
                id: "1", thumbnail: URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=200")!,
                caption: "Kiyomizu-dera in autumn", source: URL(string: "https://example.com/kyoto")),
            ImageResultItem(id: "2", thumbnail: URL(string: "https://invalid.example/missing.jpg")!),
        ],
        onAdd: { _ in }, onOpen: { _ in }, onCopy: { _ in }
    )
    .padding()
}
