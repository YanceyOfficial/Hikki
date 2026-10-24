import SwiftUI

/// A picture an AI answer makes, as its tile shows it.
public struct PictureTileItem: Identifiable {
    public enum State: Equatable {
        /// Not started yet (another one is being made first).
        case waiting
        /// Being made: `image` is the rough version so far, if one came.
        case forming
        case done
        /// Not made: why, in the user's words (stopped, refused, offline…).
        case failed(String)
    }

    public var id: String
    public var state: State
    public var image: Image?
    /// Width over height (3:2, 1, 2:3).
    public var aspect: CGFloat
    /// What it was asked to show (its tooltip and spoken name).
    public var description: String
    /// Already put into the page.
    public var added: Bool

    public init(
        id: String, state: State, image: Image? = nil, aspect: CGFloat, description: String, added: Bool = false
    ) {
        self.id = id
        self.state = state
        self.image = image
        self.aspect = aspect
        self.description = description
        self.added = added
    }
}

/// The pictures an AI answer makes, in a grid under it (one fills the width): each forms in place — a muted tile, then
/// the rough versions blurred and sharpening — and once made opens a menu: Add to page (Replace in page when it
/// changes a picture there), Use as cover, Try again. A failed one says why, with Try again. Add all puts every made
/// one in that isn't yet.
public struct PictureTiles: View {
    let items: [PictureTileItem]
    /// The pictures change one in the page: adding replaces it.
    let replacing: Bool
    let onAdd: ((String) -> Void)?
    let onCover: ((String) -> Void)?
    let onRetry: (String) -> Void
    let onAddAll: (() -> Void)?

    public init(
        items: [PictureTileItem], replacing: Bool = false, onAdd: ((String) -> Void)?, onCover: ((String) -> Void)?,
        onRetry: @escaping (String) -> Void, onAddAll: (() -> Void)? = nil
    ) {
        self.items = items
        self.replacing = replacing
        self.onAdd = onAdd
        self.onCover = onCover
        self.onRetry = onRetry
        self.onAddAll = onAddAll
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Spacing.s2, alignment: .top), count: items.count == 1 ? 1 : 2)
    }

    /// Made and not yet in the page: what Add all would add.
    private var addable: Int { items.filter { $0.state == .done && !$0.added }.count }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: Spacing.s2) {
                ForEach(items) { item in tile(item) }
            }
            if let onAddAll, !replacing, addable > 1 {
                Button(action: onAddAll) {
                    IconLabel("app:ai.pictures.addAll", icon: .plus)
                        .font(.hk(.sm))
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s1_5)
                        .background(Theme.muted, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("ai-pictures-add-all")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-made-pictures")
        .animation(Motion.easeOut(), value: items.map(\.state))
    }

    @ViewBuilder
    private func tile(_ item: PictureTileItem) -> some View {
        switch item.state {
        case .done:
            Menu {
                if let onAdd {
                    Button {
                        onAdd(item.id)
                    } label: {
                        IconLabel(replacing ? "app:ai.pictures.replace" : "app:ai.pictureAdd", icon: .plus)
                    }
                }
                if let onCover, !replacing {
                    Button {
                        onCover(item.id)
                    } label: {
                        IconLabel("app:ai.pictures.cover", icon: .image)
                    }
                }
                Button {
                    onRetry(item.id)
                } label: {
                    IconLabel("app:ai.pictures.retry", icon: .arrowsClockwise)
                }
            } label: {
                PictureTileFace(item: item)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel(Text(verbatim: item.description))
            .accessibilityIdentifier("ai-made-picture")
        case .failed(let reason):
            PictureTileFace(item: item)
                .overlay {
                    VStack(spacing: Spacing.s2) {
                        IconView(.warningCircle, size: TextSize.lg.rawValue).foregroundStyle(Theme.destructive)
                        Text(verbatim: reason)
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                        Button {
                            onRetry(item.id)
                        } label: {
                            IconLabel("app:ai.pictures.retry", icon: .arrowsClockwise).font(.hk(.xs))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(ColorTone.standard.ink)
                    }
                    .padding(Spacing.s3)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ai-made-picture-failed")
        case .waiting, .forming:
            PictureTileFace(item: item)
                .accessibilityLabel(Text("app:ai.pictures.making"))
                .accessibilityIdentifier("ai-made-picture-making")
        }
    }
}

/// A tile's face: the picture at its shape, the rough version blurred while it forms, a spinner until one comes.
private struct PictureTileFace: View {
    let item: PictureTileItem

    var body: some View {
        Theme.muted
            .aspectRatio(item.aspect, contentMode: .fit)
            .overlay {
                if case .failed = item.state {
                    EmptyView()
                } else if let image = item.image {
                    image.resizable().scaledToFill()
                        .blur(radius: item.state == .done ? 0 : Spacing.s3)
                        .transition(.opacity)
                }
            }
            .overlay {
                if item.state == .waiting || item.state == .forming { ProgressView().controlSize(.small) }
            }
            .overlay(alignment: .topLeading) {
                if item.added {
                    IconLabel("app:ai.pictures.added", icon: .check)
                        .font(.hk(.xs))
                        .foregroundStyle(.white)
                        .padding(.horizontal, Spacing.s2)
                        .padding(.vertical, Spacing.s0_5)
                        .background(.black.opacity(0.55), in: .capsule)  // design-lint: allow — a badge over any picture
                        .padding(Spacing.s1_5)
                }
            }
            .clipShape(.rect(cornerRadius: Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(Theme.border))
            .animation(Motion.easeOut(), value: item.state)
            .help(Text(verbatim: item.description))
    }
}

#Preview {
    PictureTiles(
        items: [
            PictureTileItem(id: "1", state: .done, aspect: 1.5, description: "Torii", added: true),
            PictureTileItem(id: "2", state: .forming, aspect: 1.5, description: "Bamboo"),
            PictureTileItem(id: "3", state: .waiting, aspect: 1.5, description: "Pagoda"),
            PictureTileItem(id: "4", state: .failed("OpenAI declined to make this picture."), aspect: 1.5, description: "x"),
        ],
        onAdd: { _ in }, onCover: { _ in }, onRetry: { _ in }, onAddAll: {}
    )
    .frame(width: 300)
    .padding()
}
