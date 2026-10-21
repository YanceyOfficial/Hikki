#if os(iOS)
    import HikkiCore
    import HikkiUI
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers

    /// The iPhone's cover sheet (HikkiUI's `CoverSheet`) for the page that asked for it (`coverSheet`): picks go back
    /// to the page as its own (`EditorController.applyCover`), uploads move into the workspace's assets first, and an
    /// Unsplash photo is searched and reported through the editor's backend (`UnsplashClient`). Upload's pickers are
    /// presented from here, over the sheet, which closes once the picture is in.
    struct CoverSheetHost: View {
        let request: EditorController.CoverRequest
        let editor: EditorController
        @Environment(\.dismiss) private var dismiss
        @State private var library = false
        @State private var libraryItem: PhotosPickerItem?
        @State private var camera = false
        @State private var files = false
        /// The photos shown, by id, for what a pick needs beyond the cell (the full-size address, the download ping).
        @State private var photos = PhotoShelf()

        private var uploadSources: Set<MediaSource> {
            var sources: Set<MediaSource> = [.library, .files]
            if UIImagePickerController.isSourceTypeAvailable(.camera) { sources.insert(.camera) }
            return sources
        }

        var body: some View {
            CoverSheet(
                current: request.cover, startsInPicker: request.mode == .picker, uploadSources: uploadSources,
                search: request.bff.map { base in
                    let client = UnsplashClient(base: base)
                    let shelf = photos
                    return { query in await Self.search(client, query, into: shelf) }
                },
                onSelect: { cover in apply(cover) },
                onPickPhoto: pick,
                onUpload: { source in
                    switch source {
                    case .library: library = true
                    case .camera: camera = true
                    case .files: files = true
                    case .scan: break
                    }
                },
                onRemove: { apply(nil) }
            )
            .photosPicker(isPresented: $library, selection: $libraryItem, matching: .images, preferredItemEncoding: .compatible)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task { await upload(from: item) }
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.image]) { result in
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    upload(try PickedMedia(copying: url))
                } catch {
                    Toasts.report(.uploadFailed, error, category: "covers", context: ["source": "files"])
                }
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in
                    camera = false
                    guard let image, let data = image.jpegData(compressionQuality: 0.85) else { return }
                    do {
                        upload(try PickedMedia(data: data, named: MediaPickerSheet.photoName()))
                    } catch {
                        Toasts.report(.uploadFailed, error, category: "covers", context: ["source": "camera"])
                    }
                }
                .ignoresSafeArea()
            }
        }

        private func apply(_ cover: String?) {
            let docId = request.docId
            Task { await editor.applyCover(cover, docId: docId) }
        }

        /// An Unsplash photo: its regular size becomes the cover, and the pick counts as a download for its
        /// photographer (Unsplash's guideline).
        private func pick(_ cell: CoverPhoto) {
            guard let photo = photos[cell.id], let base = request.bff else { return }
            apply(photo.regular.absoluteString)
            Task { await UnsplashClient(base: base).trackDownload(photo) }
        }

        private func upload(from item: PhotosPickerItem) async {
            do {
                guard let media = try await item.loadTransferable(type: PickedMedia.self) else { return }
                upload(media)
            } catch {
                Toasts.report(.uploadFailed, error, category: "covers", context: ["source": "library"])
            }
        }

        private func upload(_ media: PickedMedia) {
            let docId = request.docId
            dismiss()
            Task { await editor.uploadCover(media, docId: docId) }
        }

        private static func search(_ client: UnsplashClient, _ query: String, into shelf: PhotoShelf) async
            -> CoverSearchResult
        {
            do {
                let found = try await client.search(query)
                shelf.keep(found)
                return .photos(found.map(cell))
            } catch let failure as UnsplashClient.Failure {
                Log.warn("unsplash search failed", category: "covers", context: ["code": failure.code.rawValue])
                return .failed(busy: failure.code == .rateLimited)
            } catch {
                if !(error is CancellationError) {
                    Log.warn("unsplash search failed", category: "covers", context: ["error": "\(error)"])
                }
                return .failed(busy: false)
            }
        }

        private static func cell(_ photo: UnsplashPhoto) -> CoverPhoto {
            CoverPhoto(
                id: photo.id, thumb: photo.thumb, color: photo.color.flatMap(color(hex:)), alt: photo.alt,
                author: photo.author, authorURL: photo.authorUrl)
        }

        /// A photo's average colour, "#rrggbb" as Unsplash gives it (nil for anything else).
        private static func color(hex: String) -> Color? {
            guard hex.count == 7, hex.hasPrefix("#"), let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
            return Color(
                .sRGB, red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                blue: Double(value & 0xFF) / 255)
        }
    }

    /// The photos a search found, kept by id for the pick (searches run off the main actor).
    @MainActor private final class PhotoShelf {
        private var byId: [String: UnsplashPhoto] = [:]

        func keep(_ photos: [UnsplashPhoto]) {
            for photo in photos { byId[photo.id] = photo }
        }

        subscript(id: String) -> UnsplashPhoto? { byId[id] }
    }
#endif
