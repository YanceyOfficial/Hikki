#if os(iOS)
    import HikkiCore
    import HikkiUI
    import PDFKit
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers
    import VisionKit

    /// A file a phone's picker handed over, copied to a temporary file of its own name; `EditorController.insertMedia`
    /// moves it into the workspace's assets.
    struct PickedMedia: Transferable {
        let url: URL

        static var transferRepresentation: some TransferRepresentation {
            FileRepresentation(importedContentType: .image) { try PickedMedia(copying: $0.file) }
            FileRepresentation(importedContentType: .movie) { try PickedMedia(copying: $0.file) }
        }

        init(url: URL) {
            self.url = url
        }

        /// A copy under a fresh folder, keeping the name (the block shows it): the original goes away with the picker.
        init(copying source: URL) throws {
            url = try Self.temporaryURL(named: source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: url)
        }

        init(data: Data, named name: String) throws {
            url = try Self.temporaryURL(named: name)
            try data.write(to: url, options: .atomic)
        }

        private static func temporaryURL(named name: String) throws -> URL {
            let folder = FileManager.default.temporaryDirectory.appending(path: "hikki-pick-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder.appending(path: name.isEmpty ? "file" : name)
        }
    }

    /// The keyboard bar's photo / file sheet (Notion's, `MediaSourceSheet`): each source opens its own picker over it —
    /// the photo library, the camera, Files, the document scanner — and what comes back goes to `onPicked`, which
    /// closes the sheet. Failures to read a pick reach the user as toasts.
    struct MediaPickerSheet: View {
        let onPicked: ([PickedMedia]) -> Void
        @State private var library = false
        @State private var libraryItems: [PhotosPickerItem] = []
        @State private var camera = false
        @State private var files = false
        @State private var scanner = false

        private var available: Set<MediaSource> {
            var sources: Set<MediaSource> = [.library, .files]
            if UIImagePickerController.isSourceTypeAvailable(.camera) { sources.insert(.camera) }
            if VNDocumentCameraViewController.isSupported { sources.insert(.scan) }
            return sources
        }

        var body: some View {
            MediaSourceSheet(available: available) { source in
                switch source {
                case .camera: camera = true
                case .library: library = true
                case .files: files = true
                case .scan: scanner = true
                }
            }
            .photosPicker(
                isPresented: $library, selection: $libraryItems, maxSelectionCount: 10, matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .compatible
            )
            .onChange(of: libraryItems) { _, items in
                guard !items.isEmpty else { return }
                libraryItems = []
                Task { await loadLibrary(items) }
            }
            .fileImporter(isPresented: $files, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                pickFiles(result)
            }
            .fullScreenCover(isPresented: $camera) {
                CameraPicker { image in
                    camera = false
                    guard let image else { return }
                    pick { [try PickedMedia(data: image.jpegData(compressionQuality: 0.85) ?? Data(), named: Self.photoName())] }
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $scanner) {
                DocumentScanner { scan in
                    scanner = false
                    guard let scan else { return }
                    pick { [try Self.pdf(of: scan)] }
                }
                .ignoresSafeArea()
            }
        }

        private func loadLibrary(_ items: [PhotosPickerItem]) async {
            var picked: [PickedMedia] = []
            for item in items {
                do {
                    if let media = try await item.loadTransferable(type: PickedMedia.self) { picked.append(media) }
                } catch {
                    Toasts.report(.uploadFailed, error, category: "media", context: ["source": "library"])
                }
            }
            if !picked.isEmpty { onPicked(picked) }
        }

        private func pickFiles(_ result: Result<[URL], any Error>) {
            pick {
                try result.get().map { url in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    return try PickedMedia(copying: url)
                }
            }
        }

        private func pick(_ read: () throws -> [PickedMedia]) {
            do {
                let picked = try read()
                if !picked.isEmpty { onPicked(picked) }
            } catch {
                Toasts.report(.uploadFailed, error, category: "media")
            }
        }

        /// "IMG_20261020_174012.jpg", as a camera names a picture.
        private static func photoName() -> String { "IMG_\(stamp()).jpg" }

        private static func stamp() -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            return formatter.string(from: .now)
        }

        /// A scan's pages as one PDF, named by the scan's title.
        private static func pdf(of scan: VNDocumentCameraScan) throws -> PickedMedia {
            let document = PDFDocument()
            for index in 0..<scan.pageCount {
                if let page = PDFPage(image: scan.imageOfPage(at: index)) { document.insert(page, at: document.pageCount) }
            }
            guard let data = document.dataRepresentation() else { throw CocoaError(.fileWriteUnknown) }
            // The scanner's own title ("Scan", in the system's language), else when it was made.
            let title = scan.title.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "-")
            return try PickedMedia(data: data, named: "\(title.isEmpty ? stamp() : title).pdf")
        }
    }

    /// The system camera, for one picture (nil: cancelled).
    private struct CameraPicker: UIViewControllerRepresentable {
        let onDone: (UIImage?) -> Void

        func makeUIViewController(context: Context) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

        final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
            let onDone: (UIImage?) -> Void

            init(onDone: @escaping (UIImage?) -> Void) {
                self.onDone = onDone
            }

            func imagePickerController(
                _ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
            ) {
                onDone(info[.originalImage] as? UIImage)
            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                onDone(nil)
            }
        }
    }

    /// VisionKit's document scanner (nil: cancelled or failed — a failure is reported).
    private struct DocumentScanner: UIViewControllerRepresentable {
        let onDone: (VNDocumentCameraScan?) -> Void

        func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
            let scanner = VNDocumentCameraViewController()
            scanner.delegate = context.coordinator
            return scanner
        }

        func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

        func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

        final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
            let onDone: (VNDocumentCameraScan?) -> Void

            init(onDone: @escaping (VNDocumentCameraScan?) -> Void) {
                self.onDone = onDone
            }

            func documentCameraViewController(
                _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
            ) {
                onDone(scan)
            }

            func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
                onDone(nil)
            }

            func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: any Error) {
                Toasts.report(.uploadFailed, error, category: "media", context: ["source": "scan"])
                onDone(nil)
            }
        }
    }
#endif
