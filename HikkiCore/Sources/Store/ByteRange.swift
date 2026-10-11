import Foundation

/// HTTP byte ranges for the editor's asset scheme: media elements request ranges to play and seek.
public enum ByteRange {
    /// The requested range (`bytes=a-b`, `bytes=a-`, `bytes=-n`; only the first of several), clamped to the
    /// file; the whole file when absent or unusable.
    public static func parse(_ header: String?, size: Int) -> Range<Int> {
        let whole = 0..<size
        guard let header, header.hasPrefix("bytes="), size > 0 else { return whole }
        let spec = header.dropFirst("bytes=".count).split(separator: ",").first ?? ""
        let parts = spec.split(separator: "-", omittingEmptySubsequences: false)
            .map { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2 else { return whole }
        switch (parts[0], parts[1]) {
        case let (start?, end?) where start <= end && start < size: return start..<min(end + 1, size)
        case let (start?, nil) where start < size: return start..<size
        case let (nil, suffix?) where suffix > 0: return max(0, size - suffix)..<size
        default: return whole
        }
    }
}
