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
