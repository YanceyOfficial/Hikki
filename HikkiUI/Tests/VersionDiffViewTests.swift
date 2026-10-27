import Foundation
import SwiftUI
import Testing

@testable import HikkiUI

struct VersionDiffViewTests {
    @Test func aTableRowSplitsIntoItsCellsWithTheirMarks() {
        // A row as `TextBlock` flattens it: cells joined by " | ", here with one word marked as added.
        var row = AttributedString("文型 | 示例 ")
        var added = AttributedString("new")
        added.backgroundColor = Theme.washGreen
        row += added
        let cells = VersionDiffView.splitCells(row)
        #expect(cells.map { String($0.characters) } == ["文型", "示例 new"])
        #expect(cells[1].runs.map(\.backgroundColor).contains(Theme.washGreen))
        #expect(cells[0].runs.allSatisfy { $0.backgroundColor == nil })
    }

    @Test func aRowWithoutSeparatorsIsOneCell() {
        #expect(VersionDiffView.splitCells(AttributedString("alone")).count == 1)
        #expect(VersionDiffView.splitCells(AttributedString("a | ")).map { String($0.characters) } == ["a", ""])
    }
}
