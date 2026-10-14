import Foundation
import PDFKit
import Vision

/// Text inside attached files, for the index: a PDF's text through PDFKit, an image's through Vision's text
/// recognition — on device, no network. Omnisearch's Text Extractor, built into the OS.
public enum AttachmentText {
    /// What can be read.
    public enum Kind: Sendable, Equatable {
        case pdf, image
    }

    /// How many characters of a file's text are kept.
    public static let maxCharacters = 200_000
    /// How many PDF pages are read.
    static let maxPDFPages = 300

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "tif", "tiff", "bmp"]

    /// nil for a file no text is read from (video, audio, archives…).
    public static func kind(ofExtension raw: String) -> Kind? {
        let ext = raw.lowercased()
        if ext == "pdf" { return .pdf }
        return imageExtensions.contains(ext) ? .image : nil
    }

    /// The file's text, "" when it holds none (a scanned PDF without a text layer, an image without words), nil
    /// when the file can't be read at all.
    public static func extract(from url: URL, kind: Kind) async -> String? {
        switch kind {
        case .pdf: pdfText(url)
        case .image: await imageText(url)
        }
    }

    static func pdfText(_ url: URL) -> String? {
        guard let document = PDFDocument(url: url) else { return nil }
        var text = ""
        for index in 0..<min(document.pageCount, maxPDFPages) {
            guard let page = document.page(at: index)?.string else { continue }
            text += page
            text += "\n"
            if text.count >= maxCharacters { break }
        }
        return clean(text)
    }

    static func imageText(_ url: URL) async -> String? {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        do {
            let observations = try await request.perform(on: url)
            let lines = observations.compactMap { $0.topCandidates(1).first?.string }
            return clean(lines.joined(separator: "\n"))
        } catch {
            return nil
        }
    }

    /// Whitespace runs collapsed, lines kept, cut at `maxCharacters`.
    static func clean(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { line in
            line.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let joined = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.count > maxCharacters ? String(joined.prefix(maxCharacters)) : joined
    }
}
