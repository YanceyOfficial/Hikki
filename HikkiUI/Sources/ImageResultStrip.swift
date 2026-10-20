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
    /// Fetches a thumbnail's bytes. The addresses come from a model's reply or a synced file, so the caller fetches
    /// them under its own rules (public hosts only) rather than the strip loading any URL it is given.
    let load: @Sendable (URL) async throws -> Data

    public init(
        items: [ImageResultItem], onAdd: ((ImageResultItem) -> Void)? = nil, onOpen: @escaping (ImageResultItem) -> Void,
        onCopy: @escaping (ImageResultItem) -> Void, load: @escaping @Sendable (URL) async throws -> Data
    ) {
        self.load = load
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
                        ImageResultThumbnail(item: item, load: load)
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
    let load: @Sendable (URL) async throws -> Data
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                image.resizable().scaledToFill().transition(.opacity)
            } else if failed {
                IconView(.image, size: TextSize.lg.rawValue).foregroundStyle(Theme.mutedForeground)
            }
        }
        .task(id: item.thumbnail) {
            do {
                let data = try await load(item.thumbnail)
                guard let picture = Self.image(data) else { throw CocoaError(.fileReadCorruptFile) }
                withAnimation(Motion.easeOut()) { image = picture }
            } catch {
                if !Task.isCancelled { failed = true }
            }
        }
        .frame(width: Size.aiPicture, height: Size.aiPicture)
        .background(Theme.muted)
        .clipShape(.rect(cornerRadius: Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border))
        .help(Text(verbatim: item.caption ?? ""))
    }

    private static func image(_ data: Data) -> Image? {
        #if os(iOS)
            UIImage(data: data).map(Image.init(uiImage:))
        #else
            NSImage(data: data).map(Image.init(nsImage:))
        #endif
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
        onAdd: { _ in }, onOpen: { _ in }, onCopy: { _ in },
        load: { try await URLSession.shared.data(from: $0).0 }
    )
    .padding()
}
