import Foundation
import HighlightSwift

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// What a stretch of code is, named after the `syntax-*` design tokens (Xcode's Default Light/Dark) — the app colours
/// each with `Theme.syntax…`, as the editor's code blocks do from the same tokens.
public enum CodeToken: Int, CaseIterable, Sendable {
    case comment = 1
    case string, number, keyword, preprocessor, url, attribute, declaration, definition, type, function
}

/// A code block's colouring: which character ranges of `code` are which token. Still good for a longer text that
/// starts with `code` (a block that is still streaming), so a block keeps its colours while more of it arrives.
public struct CodeHighlight: Equatable, Sendable {
    public struct Span: Equatable, Sendable {
        /// Character offsets into the code.
        public let range: Range<Int>
        public let token: CodeToken
    }

    public let code: String
    public let spans: [Span]

    public func applies(to text: String) -> Bool { text.hasPrefix(code) }
}

/// Colours code through highlight.js (HighlightSwift runs it in JavaScriptCore) — the tokenizer behind the editor's
/// lowlight, so a block in the chat reads as one in a page. The approach is exodus-ios's (`CodeHighlighting.swift`):
/// one shared instance, results kept by (code, language). HighlightSwift hands back HTML-imported colours, so each
/// token's CSS colour is a sentinel grey that is read back as the token; the colours themselves stay the app's.
public actor CodeHighlighter {
    public static let shared = CodeHighlighter()

    /// Past this the block is drawn plain: a pasted log is not worth the JavaScript round-trip.
    public static let maximumLength = 20_000

    private let highlight = Highlight()
    private var cache: [Key: CodeHighlight] = [:]
    private var order: [Key] = []
    private let capacity = 100

    private struct Key: Hashable {
        let code: String
        let language: String?
    }

    /// The colouring, or nil when the code is too long, empty, the language unknown to highlight.js (or plain text),
    /// nothing in it is coloured, or JavaScript failed — the caller then draws the plain code.
    public func highlight(_ code: String, language: String?) async -> CodeHighlight? {
        let language = language?.lowercased()
        guard code.count <= Self.maximumLength, !code.allSatisfy(\.isWhitespace),
            !["text", "plaintext", "plain", "txt"].contains(language ?? "")
        else { return nil }
        let key = Key(code: code, language: language)
        if let hit = cache[key] { return hit }
        guard Self.resourcesFound else { return nil }
        let colours = HighlightColors.custom(css: Self.css)
        let result: AttributedString
        do {
            if let language {
                result = try await highlight.attributedText(code, language: language, colors: colours)
            } else {
                result = try await highlight.attributedText(code, colors: colours)
            }
        } catch {
            return nil
        }
        guard let spans = Self.spans(result, code: code), !spans.isEmpty else { return nil }
        let value = CodeHighlight(code: code, spans: spans)
        remember(key, value)
        return value
    }

    /// Whether HighlightSwift's resource bundle (highlight.js) is where its accessor looks — the accessor stops the
    /// process when it isn't, so code is drawn plain instead. The same places, in the same order, as the accessor
    /// Tuist generates for a static framework with resources (`Bundle.module`).
    static let resourcesFound: Bool = {
        let name = "HighlightSwift_HighlightSwift.bundle"
        var candidates = [
            Bundle.main.resourceURL, Bundle(for: BundleMarker.self).resourceURL, Bundle.main.bundleURL,
        ]
        if let override = ProcessInfo.processInfo.environment["PACKAGE_RESOURCE_BUNDLE_PATH"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        return candidates.contains { $0.flatMap { Bundle(url: $0.appendingPathComponent(name)) } != nil }
    }()

    private final class BundleMarker {}

    /// The tokens' ranges in `code`. HighlightSwift trims the text it imports, so the result is the code without
    /// its leading and trailing white space; anything else means the import changed the text, and nothing is used.
    static func spans(_ result: AttributedString, code: String) -> [CodeHighlight.Span]? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard String(result.characters) == trimmed else { return nil }
        let lead = code.prefix { $0.isWhitespace }.count
        var spans: [CodeHighlight.Span] = []
        var offset = lead
        for run in result.runs {
            let count = result[run.range].characters.count
            if let token = token(of: run) {
                let range = offset..<(offset + count)
                if let last = spans.last, last.token == token, last.range.upperBound == range.lowerBound {
                    spans[spans.count - 1] = .init(range: last.range.lowerBound..<range.upperBound, token: token)
                } else {
                    spans.append(.init(range: range, token: token))
                }
            }
            offset += count
        }
        return spans
    }

    /// The token a run's sentinel colour stands for (the nearest grey within a small tolerance: the import may
    /// convert colour spaces).
    private static func token(of run: AttributedString.Runs.Run) -> CodeToken? {
        #if canImport(UIKit)
            guard let colour = run.uiKit.foregroundColor else { return nil }
            var white: CGFloat = 0
            var alpha: CGFloat = 0
            var red: CGFloat = 0
            var green: CGFloat = 0
            var blue: CGFloat = 0
            if colour.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                white = (red + green + blue) / 3
            } else if !colour.getWhite(&white, alpha: &alpha) {
                return nil
            }
        #elseif canImport(AppKit)
            guard let colour = run.appKit.foregroundColor?.usingColorSpace(.sRGB) else { return nil }
            let white = (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3
        #endif
        let level = Double(white) * 255 / Double(step)
        let index = Int(level.rounded())
        guard abs(level - Double(index)) < 0.4 else { return nil }
        return CodeToken(rawValue: index)
    }

    /// Grey levels apart enough to survive a colour-space conversion.
    private static let step = 20

    private static func grey(_ token: CodeToken?) -> String {
        let level = (token?.rawValue ?? 0) * step
        return "rgb(\(level),\(level),\(level))"
    }

    /// highlight.js classes → tokens, as `editor/src/style.css` maps them for the page's code blocks.
    static let css: String = {
        let rules: [(String, CodeToken?)] = [
            (".hljs", nil),
            (".hljs-comment,.hljs-quote", .comment),
            (".hljs-doctag,.hljs-keyword,.hljs-literal,.hljs-selector-tag,.hljs-tag .hljs-name", .keyword),
            (".hljs-string,.hljs-regexp,.hljs-template-tag,.hljs-char.escape_", .string),
            (".hljs-number,.hljs-symbol,.hljs-bullet", .number),
            (".hljs-meta,.hljs-meta .hljs-keyword", .preprocessor),
            (".hljs-link", .url),
            (".hljs-attr,.hljs-attribute,.hljs-selector-attr,.hljs-selector-pseudo", .attribute),
            (".hljs-title.class_,.hljs-title.class_.inherited__", .declaration),
            (".hljs-title,.hljs-title.function_,.hljs-section,.hljs-selector-id,.hljs-selector-class", .definition),
            (".hljs-type,.hljs-built_in", .type),
            (".hljs-property,.hljs-function .hljs-params .hljs-type", .function),
        ]
        return rules.map { "\($0.0){color:\(grey($0.1))}" }.joined(separator: "\n")
    }()

    private func remember(_ key: Key, _ value: CodeHighlight) {
        if cache[key] == nil {
            order.append(key)
            if order.count > capacity {
                cache[order.removeFirst()] = nil
            }
        }
        cache[key] = value
    }
}
