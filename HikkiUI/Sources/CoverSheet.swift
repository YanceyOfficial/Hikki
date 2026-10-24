import SwiftUI

/// A photo the cover sheet's Unsplash tab shows: its thumbnail, average colour (shown while it loads) and photographer.
public nonisolated struct CoverPhoto: Identifiable, Equatable, Sendable {
    public var id: String
    public var thumb: URL
    public var color: Color?
    public var alt: String?
    public var author: String
    /// The photographer's page (utm-tagged, Unsplash's attribution rule).
    public var authorURL: URL

    public init(id: String, thumb: URL, color: Color? = nil, alt: String? = nil, author: String, authorURL: URL) {
        self.id = id
        self.thumb = thumb
        self.color = color
        self.alt = alt
        self.author = author
        self.authorURL = authorURL
    }
}

/// What a search for cover photos came back with.
public nonisolated enum CoverSearchResult: Equatable, Sendable {
    case photos([CoverPhoto])
    /// It failed; `busy`: Unsplash's hourly limit, try later.
    case failed(busy: Bool)
}

/// A phone's cover sheet (Notion's): its actions — Change cover, Remove cover — or straight away the picker when the
/// page has none. The picker has four tabs: Gallery (the built-in gradients), Upload (the photo library, the camera,
/// Files), Link (an https picture) and Unsplash (a search, each photo credited to its photographer). Plain values in,
/// picks out; the app writes them, presents the upload pickers and closes the sheet once an upload is in.
public struct CoverSheet: View {
    let current: String?
    let startsInPicker: Bool
    let uploadSources: Set<MediaSource>
    /// Searches Unsplash (an empty query: a random batch); nil where this build has no backend for it.
    let search: (@Sendable (String) async -> CoverSearchResult)?
    let onSelect: (String) -> Void
    let onPickPhoto: (CoverPhoto) -> Void
    let onUpload: (MediaSource) -> Void
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        current: String?, startsInPicker: Bool, uploadSources: Set<MediaSource> = [.library, .camera, .files],
        search: (@Sendable (String) async -> CoverSearchResult)?, onSelect: @escaping (String) -> Void,
        onPickPhoto: @escaping (CoverPhoto) -> Void, onUpload: @escaping (MediaSource) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.current = current
        self.startsInPicker = startsInPicker
        self.uploadSources = uploadSources
        self.search = search
        self.onSelect = onSelect
        self.onPickPhoto = onPickPhoto
        self.onUpload = onUpload
        self.onRemove = onRemove
    }

    public var body: some View {
        NavigationStack {
            if startsInPicker {
                picker
            } else {
                List {
                    Section {
                        NavigationLink {
                            picker
                        } label: {
                            IconLabel("app:cover.change", icon: .image)
                        }
                        .accessibilityIdentifier("cover-sheet-change")
                        Button(role: .destructive) {
                            remove()
                        } label: {
                            IconLabel("app:cover.removeCover", icon: .trash).foregroundStyle(Theme.destructive)
                        }
                        .accessibilityIdentifier("cover-sheet-remove")
                    }
                }
                #if os(iOS)
                    .listStyle(.insetGrouped)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .navigationTitle(Text("app:cover.title"))
            }
        }
        .accessibilityIdentifier("cover-sheet")
    }

    private var picker: some View {
        CoverPicker(
            current: current, uploadSources: uploadSources, search: search,
            onSelect: { cover in
                dismiss()
                onSelect(cover)
            },
            onPickPhoto: { photo in
                dismiss()
                onPickPhoto(photo)
            },
            onUpload: onUpload, onRemove: remove)
    }

    private func remove() {
        dismiss()
        onRemove()
    }
}

/// The picker's tabs.
private enum CoverTab: String, CaseIterable, Identifiable {
    case gallery, upload, link, unsplash

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .gallery: "app:cover.gallery"
        case .upload: "app:cover.upload"
        case .link: "app:cover.link"
        case .unsplash: "app:cover.unsplash"
        }
    }
}

private struct CoverPicker: View {
    let current: String?
    let uploadSources: Set<MediaSource>
    let search: (@Sendable (String) async -> CoverSearchResult)?
    let onSelect: (String) -> Void
    let onPickPhoto: (CoverPhoto) -> Void
    let onUpload: (MediaSource) -> Void
    let onRemove: () -> Void
    @State private var tab = CoverTab.gallery

    var body: some View {
        VStack(spacing: Spacing.s0) {
            Picker(selection: $tab) {
                ForEach(CoverTab.allCases) { item in Text(item.title).tag(item) }
            } label: {
                Text("app:cover.title")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.s4)
            .padding(.vertical, Spacing.s2)
            .accessibilityIdentifier("cover-tabs")
            switch tab {
            case .gallery: CoverGallery(current: current, onSelect: onSelect)
            case .upload: CoverUploadPane(sources: uploadSources, onUpload: onUpload)
            case .link: CoverLinkPane(onSelect: onSelect)
            case .unsplash: CoverUnsplashPane(search: search, onPick: onPickPhoto)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .navigationTitle(Text("app:cover.title"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if current != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button(role: .destructive, action: onRemove) {
                        Text("app:cover.remove")
                    }
                    .accessibilityIdentifier("cover-remove")
                }
            }
        }
    }
}

/// The built-in gradients, the page's own ringed.
private struct CoverGallery: View {
    let current: String?
    let onSelect: (String) -> Void
    @Environment(\.colorTone) private var tone

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.coverSwatch), spacing: Spacing.s3)], spacing: Spacing.s3) {
                ForEach(CoverGradient.allCases) { gradient in
                    let selected = current == gradient.cover
                    Button {
                        onSelect(gradient.cover)
                    } label: {
                        RoundedRectangle(cornerRadius: Radius.md)
                            .fill(gradient.gradient)
                            .frame(height: Size.coverSwatchHeight)
                            .overlay { RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Theme.border, lineWidth: Spacing.px) }
                            .padding(Spacing.s0_5)
                            .overlay {
                                if selected {
                                    RoundedRectangle(cornerRadius: Radius.lg).strokeBorder(tone.fill, lineWidth: Spacing.s0_5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(gradient.label))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("cover-gradient-\(gradient.rawValue)")
                }
            }
            .padding(Spacing.s4)
        }
    }
}

extension CoverGradient {
    /// Its name, for VoiceOver.
    var label: LocalizedStringKey {
        switch self {
        case .dusk: "app:cover.gradient.dusk"
        case .ocean: "app:cover.gradient.ocean"
        case .meadow: "app:cover.gradient.meadow"
        case .peach: "app:cover.gradient.peach"
        case .lavender: "app:cover.gradient.lavender"
        case .sand: "app:cover.gradient.sand"
        case .night: "app:cover.gradient.night"
        case .ember: "app:cover.gradient.ember"
        case .forest: "app:cover.gradient.forest"
        case .slate: "app:cover.gradient.slate"
        }
    }
}

/// Where an uploaded cover comes from: the app presents that picker.
private struct CoverUploadPane: View {
    let sources: Set<MediaSource>
    let onUpload: (MediaSource) -> Void

    var body: some View {
        List {
            Section {
                ForEach([MediaSource.library, .camera, .files].filter(sources.contains), id: \.self) { source in
                    Button {
                        onUpload(source)
                    } label: {
                        IconLabel(source.title, icon: source.icon).foregroundStyle(Theme.foreground)
                    }
                    .accessibilityIdentifier("cover-upload-\(source.rawValue)")
                }
            } footer: {
                Text("app:cover.uploadHint")
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
    }
}

/// A picture on the web, by its https link.
private struct CoverLinkPane: View {
    let onSelect: (String) -> Void
    @State private var link = ""

    private var url: String? {
        let value = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: value), parsed.scheme == "https", parsed.host() != nil else { return nil }
        return value
    }

    var body: some View {
        List {
            Section {
                TextField(text: $link) { Text("app:cover.linkPlaceholder") }
                    #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit { if let url { onSelect(url) } }
                    .accessibilityIdentifier("cover-link-field")
            } footer: {
                Text("app:cover.linkHint")
            }
            Section {
                Button {
                    if let url { onSelect(url) }
                } label: {
                    Text("app:cover.linkSubmit").frame(maxWidth: .infinity)
                }
                .disabled(url == nil)
                .accessibilityIdentifier("cover-link-submit")
            }
        }
        #if os(iOS)
            .listStyle(.insetGrouped)
        #endif
    }
}

/// Unsplash: a search (a random batch while it is empty), photos in two columns, each credited.
private struct CoverUnsplashPane: View {
    let search: (@Sendable (String) async -> CoverSearchResult)?
    let onPick: (CoverPhoto) -> Void
    @State private var query = ""
    /// The answer and the query it is for: while a newer one is on its way the grid shows placeholders.
    @State private var result: (query: String, result: CoverSearchResult)?

    var body: some View {
        if let search {
            VStack(spacing: Spacing.s2) {
                HStack(spacing: Spacing.s2) {
                    IconView(.magnifyingGlass, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
                    TextField(text: $query) { Text("app:cover.unsplashSearch") }
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .accessibilityIdentifier("cover-unsplash-search")
                }
                .padding(.horizontal, Spacing.s3)
                .frame(height: Size.searchField)
                .background(Theme.muted, in: .rect(cornerRadius: Radius.lg))
                .padding(.horizontal, Spacing.s4)
                ScrollView { grid.padding(Spacing.s4) }
            }
            .task(id: query) {
                // Typing settles before a search goes out; a newer query cancels this one.
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let answer = await search(query)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.easeOut()) { result = (query, answer) }
            }
        } else {
            Text("app:cover.unsplashUnavailable")
                .font(.hk(.sm))
                .foregroundStyle(Theme.mutedForeground)
                .frame(maxWidth: .infinity)
                .padding(Spacing.s6)
        }
    }

    @ViewBuilder private var grid: some View {
        let columns = [GridItem(.adaptive(minimum: Size.coverPhoto), spacing: Spacing.s3, alignment: .top)]
        switch result?.query == query ? result?.result : nil {
        case .photos(let photos)?:
            LazyVGrid(columns: columns, spacing: Spacing.s3) {
                ForEach(photos) { photo in CoverPhotoCell(photo: photo, onPick: onPick) }
            }
        case .failed(let busy)?:
            Text(busy ? "app:cover.unsplashBusy" : "app:cover.unsplashFailed")
                .font(.hk(.sm))
                .foregroundStyle(Theme.destructive)
                .frame(maxWidth: .infinity)
        case nil:
            LazyVGrid(columns: columns, spacing: Spacing.s3) {
                ForEach(0..<6, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Spacing.s1_5) {
                        RoundedRectangle(cornerRadius: Radius.md).fill(Theme.muted).aspectRatio(16 / 10, contentMode: .fit)
                        RoundedRectangle(cornerRadius: Radius.sm).fill(Theme.muted).frame(height: Spacing.s3)
                    }
                }
            }
            .accessibilityIdentifier("cover-unsplash-loading")
        }
    }
}

/// One photo: the picture (its colour until it loads, fading in) and "Photo by <name> on Unsplash", both linked.
private struct CoverPhotoCell: View {
    let photo: CoverPhoto
    let onPick: (CoverPhoto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1) {
            Button {
                onPick(photo)
            } label: {
                Color.clear
                    .aspectRatio(16 / 10, contentMode: .fit)
                    .background(photo.color ?? Theme.muted)
                    .overlay {
                        AsyncImage(url: photo.thumb, transaction: Transaction(animation: Motion.easeOut())) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill().transition(.opacity)
                            } else if phase.error != nil {
                                IconView(.image, size: TextSize.lg.rawValue).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                    }
                    .clipShape(.rect(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: photo.alt ?? photo.author))
            .accessibilityIdentifier("cover-unsplash-photo")
            Text(credit)
                .font(.hk(.xs))
                .foregroundStyle(Theme.mutedForeground)
                .lineLimit(2)
        }
    }

    /// Unsplash's attribution: the photographer and Unsplash, each a link (utm-tagged).
    private var credit: AttributedString {
        let unsplash = "Unsplash"
        var text = AttributedString(String(localized: "app:cover.credit \(photo.author) \(unsplash)"))
        if let range = text.range(of: photo.author) {
            text[range].link = photo.authorURL
            text[range].underlineStyle = .single
        }
        if let range = text.range(of: unsplash, options: .backwards) {
            text[range].link = Self.unsplashHome
            text[range].underlineStyle = .single
        }
        return text
    }

    static let unsplashHome = URL(string: "https://unsplash.com/?utm_source=hikki&utm_medium=referral")!
}

#Preview("Actions") {
    CoverSheet(
        current: "gradient:ocean", startsInPicker: false, search: nil, onSelect: { _ in }, onPickPhoto: { _ in },
        onUpload: { _ in }, onRemove: {})
}

#Preview("Picker") {
    CoverSheet(
        current: "gradient:ocean", startsInPicker: true,
        search: { _ in
            .photos([
                CoverPhoto(
                    id: "1", thumb: URL(string: "https://images.unsplash.com/photo-1493976040374-85c8e12f0c0e?w=400")!,
                    color: .gray, author: "Sora Sagano", authorURL: URL(string: "https://unsplash.com/@sorasagano")!)
            ])
        },
        onSelect: { _ in }, onPickPhoto: { _ in }, onUpload: { _ in }, onRemove: {})
}
