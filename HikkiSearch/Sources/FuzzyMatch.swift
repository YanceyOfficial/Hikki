/// fzf-style subsequence scoring for short strings (page titles in the quick switcher).
/// Every query character must appear in order; consecutive runs and word starts score higher.
public enum FuzzyMatch {
    /// nil when `query` is not a subsequence of `candidate`. Higher is better.
    public static func score(_ query: String, in candidate: String) -> Int? {
        let q = Array(query.lowercased().filter { !$0.isWhitespace })
        let c = Array(candidate.lowercased())
        guard !q.isEmpty else { return 0 }
        guard q.count <= c.count else { return nil }

        var score = 0
        var qi = 0
        var previousMatch: Int?
        for (ci, char) in c.enumerated() where qi < q.count && char == q[qi] {
            score += 1
            if let previous = previousMatch, previous == ci - 1 { score += 5 }  // consecutive run
            if ci == 0 || !c[ci - 1].isLetter && !c[ci - 1].isNumber { score += 3 }  // word start
            if ci == 0 { score += 2 }
            previousMatch = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        // Prefer tighter, shorter candidates.
        return score * 10 - (c.count - q.count)
    }
}
