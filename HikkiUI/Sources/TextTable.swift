import SwiftUI

/// A table of styled text in read-only content (a Markdown table in the AI chat's answers): a header row on a quiet
/// fill, rows divided by hairlines, each column aligned as given, inside a rounded outline. A cell wraps at
/// `maxCellWidth`; a table wider than its place scrolls sideways (with a fade on the trailing edge). After exodus-ios's
/// `MarkdownTableView` (Sources/MarkdownKit).
public struct TextTable: View {
    private let header: [AttributedString]
    private let rows: [[AttributedString]]
    private let alignments: [HorizontalAlignment]
    private let maxCellWidth: CGFloat

    /// `alignments` one per column (missing ones lead); rows may be shorter than the header (empty cells).
    public init(
        header: [AttributedString], rows: [[AttributedString]], alignments: [HorizontalAlignment] = [],
        maxCellWidth: CGFloat = Size.tableCellMax
    ) {
        self.header = header
        self.rows = rows
        self.alignments = alignments
        self.maxCellWidth = maxCellWidth
    }

    private var columns: Int { max(header.count, rows.map(\.count).max() ?? 0) }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: Spacing.s0, verticalSpacing: Spacing.s0) {
                GridRow {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(header[safe: column], column: column, isHeader: true)
                    }
                }
                ForEach(rows.indices, id: \.self) { index in
                    Divider().overlay(Theme.tableBorder)
                    GridRow {
                        ForEach(0..<columns, id: \.self) { column in
                            cell(rows[index][safe: column], column: column, isHeader: false)
                        }
                    }
                }
            }
            .fixedSize()
            .overlay { shape.strokeBorder(Theme.tableBorder, lineWidth: 1) }
            .clipShape(shape)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .trailingScrollFade()
    }

    private func cell(_ content: AttributedString?, column: Int, isHeader: Bool) -> some View {
        let alignment = alignments[safe: column] ?? .leading
        return WidthCap(maxWidth: maxCellWidth) {
            Text(content ?? AttributedString())
                .font(.hk(.sm, isHeader ? .semibold : .regular))
                .multilineTextAlignment(Self.textAlignment(alignment))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Spacing.s2_5)
        .padding(.vertical, Spacing.s1_5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: alignment, vertical: .top))
        .background(isHeader ? Theme.muted : .clear)
        .gridColumnAlignment(alignment)
    }

    private static func textAlignment(_ alignment: HorizontalAlignment) -> TextAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

/// A cell's width is its natural width capped at `maxWidth`, whatever the grid proposes: inside the sideways scroll
/// view a cell wraps at the cap and is never squeezed to fit the screen.
private struct WidthCap: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let subview = subviews.first else { return .zero }
        let width = min(subview.sizeThatFits(.unspecified).width, maxWidth)
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

extension Array {
    fileprivate subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    TextTable(
        header: ["Model", "Context", "Notes"],
        rows: [
            ["Small", "128k", "Fast; good for short edits and quick answers to simple questions about a page"],
            ["Large", "1M", try! AttributedString(markdown: "**Best** for long pages")],
            ["Tiny"],
        ],
        alignments: [.leading, .trailing, .leading]
    )
    .padding(Spacing.s6)
    .frame(width: 420)
}
