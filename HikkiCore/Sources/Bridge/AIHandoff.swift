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
