import CoreGraphics
import CoreText
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import HikkiSearch

struct AttachmentTextTests {
    private func temporaryFile(_ ext: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "hikki-attachment-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: "file.\(ext)")
    }

    /// Draws `text` with Core Text into `context` inside `box`.
    private func draw(_ text: String, size: CGFloat, in context: CGContext, box: CGRect) {
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: box.insetBy(dx: 24, dy: 24), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        CTFrameDraw(frame, context)
    }

    @Test func readsThePagesOfAPDF() async throws {
        let url = try temporaryFile("pdf")
        var box = CGRect(x: 0, y: 0, width: 400, height: 300)
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        for page in ["The roadmap is due Friday.", "Second   page\ttext"] {
            context.beginPDFPage(nil)
            draw(page, size: 20, in: context, box: box)
            context.endPDFPage()
        }
        context.closePDF()
        try (data as Data).write(to: url)

        #expect(AttachmentText.kind(ofExtension: "PDF") == .pdf)
        let text = try #require(await AttachmentText.extract(from: url, kind: .pdf))
        #expect(text.contains("roadmap is due Friday"))
        #expect(text.contains("Second page text"))
    }

    @Test func recognizesTextInAnImage() async throws {
        let url = try temporaryFile("png")
        let width = 800
        let height = 240
        let context = try #require(
            CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
        draw("HELLO SEARCH", size: 96, in: context, box: CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))

        #expect(AttachmentText.kind(ofExtension: "png") == .image)
        let text = try #require(await AttachmentText.extract(from: url, kind: .image))
        #expect(text.uppercased().contains("HELLO"))
    }

    @Test func readsNothingFromOtherFilesAndCleansWhitespace() {
        #expect(AttachmentText.kind(ofExtension: "mp4") == nil)
        #expect(AttachmentText.kind(ofExtension: "zip") == nil)
        #expect(AttachmentText.clean("  a   b \n\n\n c\t d  \n") == "a b\nc d")
        #expect(AttachmentText.clean(String(repeating: "x", count: AttachmentText.maxCharacters + 5)).count == AttachmentText.maxCharacters)
    }
}
