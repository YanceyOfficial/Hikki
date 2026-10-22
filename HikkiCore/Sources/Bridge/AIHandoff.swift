import Foundation

/// A request AI on the selection judged too big for an edit or a short answer (`aiHandoff`): the user's words and the
/// passage they were about, continued in the chat about the page — the instruction sent as the turn's question, the
/// passage as its selected context. Page text: never logged.
public struct AIHandoff: Equatable, Sendable {
    public var docId: String
    public var instruction: String
    public var selection: String

    public init(docId: String, instruction: String, selection: String) {
        self.docId = docId
        self.instruction = instruction
        self.selection = selection
    }

    /// Where the chat comes up for a handoff.
    public enum Placement: Equatable, Sendable {
        /// The panel beside the page it came from, in AI mode (opened if closed, switched from the outline or comments) —
        /// in a split window, the panel of the side it came from.
        case inspector
        /// Ask AI as a sheet: on iPhone (a compact window), which has no panel beside the page.
        case sheet
    }

    /// `wide`: the Mac / iPad layout (a regular width), where the panel sits beside the page.
    public static func placement(wide: Bool) -> Placement {
        wide ? .inspector : .sheet
    }
}

/// The page asking for pictures ("/" AI pictures, a selection's Pictures…, an image's Edit with AI): the chat opens
/// where a handoff's does, set up for pictures — they go into the page at `blockId`, after it (in place of it when it
/// is still an empty line) or, for a picture being changed, in place of it (`replace`), and the composer waits for
/// the user's words.
public struct PicturesHandoff: Equatable, Sendable {
    public var docId: String
    public var blockId: String?
    public var replace: Bool
    /// The selected passage the pictures are of ("" for none).
    public var selection: String
    /// The picture being changed: its address in the page (a workspace asset).
    public var source: String?

    public init(docId: String, blockId: String?, replace: Bool = false, selection: String = "", source: String? = nil) {
        self.docId = docId
        self.blockId = blockId
        self.replace = replace
        self.selection = selection
        self.source = source
    }
}
