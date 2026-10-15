import Foundation

/// A model's answer as styled text (the Ask AI chat). The answer is untrusted: inline Markdown only, and a link stays
/// a link only when it goes to a web page — `hikki://`, `tel:`, other apps' schemes and the like become plain text,
/// so tapping an answer can't open a page, place a call or drive another app.
public enum AIMarkdown {
    public static func attributed(_ text: String) -> AttributedString {
        var styled =
            (try? AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)))
            ?? AttributedString(text)
        for run in styled.runs {
            guard let link = run.link else { continue }
            if !isWebLink(link) { styled[run.range].link = nil }
        }
        return styled
    }

    static func isWebLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return false }
        return url.host() != nil
    }
}
