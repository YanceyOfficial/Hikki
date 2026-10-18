import Foundation

/// Words in a text, counted the way the editor counts them (`wordCount` in `apps/editor/src/core/extract.ts`): every CJK
/// character (Han, Hiragana, Katakana, Hangul) is one word, other scripts count runs of letters and digits — with an
/// apostrophe inside a word ("it's") still one.
public enum WordCount {
    private static let cjkPattern = #"[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]"#
    private static let wordPattern = #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#

    public static func count(_ text: String) -> Int {
        guard !text.isEmpty,
            let cjk = try? NSRegularExpression(pattern: cjkPattern),
            let word = try? NSRegularExpression(pattern: wordPattern)
        else { return 0 }
        let whole = NSRange(text.startIndex..., in: text)
        let cjkCount = cjk.numberOfMatches(in: text, range: whole)
        let rest = cjk.stringByReplacingMatches(in: text, range: whole, withTemplate: " ")
        return cjkCount + word.numberOfMatches(in: rest, range: NSRange(rest.startIndex..., in: rest))
    }

    /// A page's count: its title and its text, as the editor saves it.
    public static func count(title: String, text: String) -> Int {
        count("\(title)\n\(text)")
    }
}
