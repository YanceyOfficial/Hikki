import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Files attached to a question, made ready for a model: pictures scaled down to what models read (and to the
/// providers' size limits) and re-encoded as JPEG or PNG; PDFs as they are, within a size limit. Sent as base64.
public enum AIAttachments {
    /// Longest side of a picture sent (Anthropic reads up to about 1568 px; more only costs).
    public static let maxImageSide = 1568
    public static let maxDocumentBytes = 20 * 1024 * 1024
    /// Most attachments on one question.
    public static let maxCount = 6

    public enum Failure: Error, Equatable {
        case unsupported
        case unreadable
        case tooLarge
    }

    /// The part for a file's data, by its type (a file extension or MIME type's UTType).
    public static func part(_ data: Data, type: UTType, name: String) throws -> AIMessage.Part {
        if type.conforms(to: .pdf) {
            guard data.count <= maxDocumentBytes else { throw Failure.tooLarge }
            return .document(data, mimeType: "application/pdf", name: name)
        }
        guard type.conforms(to: .image) else { throw Failure.unsupported }
        return try image(data)
    }

    /// A picture scaled so its longest side is at most `maxImageSide`: PNG when it has transparency, JPEG otherwise.
    public static func image(_ data: Data) throws -> AIMessage.Part {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw Failure.unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxImageSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw Failure.unreadable
        }
        let alpha = image.alphaInfo
        let transparent = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        let type = transparent ? UTType.png : UTType.jpeg
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return .image(output as Data, mimeType: transparent ? "image/png" : "image/jpeg")
    }
}
