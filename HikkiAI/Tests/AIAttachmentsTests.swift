import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HikkiAI

struct AIAttachmentsTests {
    /// A solid picture of the given size, encoded as `type`.
    private func picture(width: Int, height: Int, alpha: Bool, type: UTType) throws -> Data {
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.3, alpha: alpha ? 0.5 : 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func size(_ data: Data) -> (Int, Int) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return (0, 0) }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0, props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    @Test func aLargePhotoIsScaledDownAsJPEG() throws {
        let part = try AIAttachments.part(try picture(width: 4000, height: 3000, alpha: false, type: .png), type: .png, name: "a.png")
        guard case .image(let data, let mime) = part else { return #expect(Bool(false)) }
        #expect(mime == "image/jpeg")
        #expect(size(data) == (1568, 1176))
    }

    @Test func transparencyStaysPNGAndSmallPicturesKeepTheirSize() throws {
        let part = try AIAttachments.part(try picture(width: 200, height: 100, alpha: true, type: .png), type: .png, name: "a.png")
        guard case .image(let data, let mime) = part else { return #expect(Bool(false)) }
        #expect(mime == "image/png")
        #expect(size(data) == (200, 100))
    }

    @Test func pdfsGoAsDocumentsAndOtherFilesAreRefused() throws {
        let pdf = Data("%PDF-1.4\n".utf8)
        #expect(
            try AIAttachments.part(pdf, type: .pdf, name: "notes.pdf") == .document(pdf, mimeType: "application/pdf", name: "notes.pdf"))
        #expect(throws: AIAttachments.Failure.unsupported) { try AIAttachments.part(Data(), type: .zip, name: "a.zip") }
        #expect(throws: AIAttachments.Failure.unreadable) { try AIAttachments.part(Data("no".utf8), type: .png, name: "a.png") }
    }

    @Test func bothProvidersCarryAPDF() throws {
        let message = AIMessage(
            role: .user, parts: [.text("Summarize"), .document(Data("%PDF".utf8), mimeType: "application/pdf", name: "a.pdf")])
        let request = AIRequest(model: AIModelCatalog.sonnet, instructions: "", messages: [message])
        let anthropic =
            try JSONSerialization.jsonObject(with: try RequestBuilders.anthropic(request, apiKey: "k").httpBody!) as! [String: Any]
        let parts = ((anthropic["messages"] as! [[String: Any]])[0]["content"] as! [[String: Any]])
        #expect(parts[1]["type"] as? String == "document")
        let openAI = try JSONSerialization.jsonObject(with: try RequestBuilders.openAI(request, apiKey: "k").httpBody!) as! [String: Any]
        let input = ((openAI["input"] as! [[String: Any]])[0]["content"] as! [[String: Any]])
        #expect(input[1]["type"] as? String == "input_file" && input[1]["filename"] as? String == "a.pdf")
    }
}

/// ISSUE-197: ⌘V in the AI composer with a picture copied typed the file's name; what the pasteboard holds now decides.
struct AIPasteTests {
    @Test func aCopiedPictureFileIsAttachedNotItsName() {
        // Finder: the file's URL, its name as text, its icon as a picture.
        let shot = URL(fileURLWithPath: "/Users/me/Desktop/Screenshot 2026-10-24 at 15.00.17.png")
        #expect(AIPaste.decide(fileURLs: [shot], hasText: true, types: [.fileURL, .icns, .utf8PlainText]) == .files([shot]))
        let pdf = URL(fileURLWithPath: "/tmp/notes.pdf")
        #expect(AIPaste.decide(fileURLs: [pdf], hasText: true, types: [.fileURL]) == .files([pdf]))
    }

    @Test func onlyThePicturesAndPDFsAmongCopiedFilesAreAttached() {
        let photo = URL(fileURLWithPath: "/tmp/photo.heic")
        let text = URL(fileURLWithPath: "/tmp/readme.txt")
        #expect(AIPaste.decide(fileURLs: [text, photo], hasText: true, types: [.fileURL]) == .files([photo]))
        // Nothing attachable (a text file, a folder): the names paste as text, not Finder's icon as a picture.
        #expect(AIPaste.decide(fileURLs: [text], hasText: true, types: [.fileURL, .tiff, .utf8PlainText]) == .text)
        #expect(AIPaste.decide(fileURLs: [URL(fileURLWithPath: "/tmp/folder")], hasText: true, types: [.fileURL]) == .text)
    }

    @Test func pictureDataIsAttachedWhenThereIsNoText() {
        // A screenshot copied to the clipboard, a picture copied in Preview.
        #expect(AIPaste.decide(fileURLs: [], hasText: false, types: [.png, .tiff]) == .data(.png))
        #expect(AIPaste.decide(fileURLs: [], hasText: false, types: [.tiff]) == .data(.tiff))
        #expect(AIPaste.decide(fileURLs: [], hasText: false, types: [.pdf]) == .data(.pdf))
    }

    @Test func textPastesAsText() {
        #expect(AIPaste.decide(fileURLs: [], hasText: true, types: [.utf8PlainText]) == .text)
        // Copied text often comes with a picture of itself (Pages, Word, browsers): still text.
        #expect(AIPaste.decide(fileURLs: [], hasText: true, types: [.rtf, .pdf, .tiff, .utf8PlainText]) == .text)
        #expect(AIPaste.decide(fileURLs: [], hasText: false, types: []) == .text)
    }
}
