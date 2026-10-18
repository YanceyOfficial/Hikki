import HikkiAI
import HikkiUI
import SwiftUI

/// An answer in the AI chat, drawn from its Markdown (`AIMarkdown`: only web links stay links): paragraphs, headings,
/// nested bulleted / numbered / task lists, quotes with a bar, code blocks with their language, a copy button and
/// highlighting (`CodeBlockView` over `CodeHighlighter`), tables (`TextTable`) and rules. While it streams the text is
/// parsed again as it grows — an unclosed fence is code to the end — and a growing code block keeps the colours it had
/// for the part already highlighted, so nothing flickers between plain and coloured.
struct AnswerText: View {
    let text: String
    var isStreaming = false

    var body: some View {
        AnswerBlocks(blocks: AIMarkdown.blocks(text), depth: 0, isStreaming: isStreaming)
            .textSelection(.enabled)
    }
}

private struct AnswerBlocks: View {
    let blocks: [AIMarkdown.Block]
    /// How deep in lists these blocks sit (bullets change with depth).
    let depth: Int
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s2_5) {
            ForEach(blocks.indices, id: \.self) { index in
                AnswerBlock(block: blocks[index], depth: depth, isStreaming: isStreaming)
            }
        }
    }
}

private struct AnswerBlock: View {
    let block: AIMarkdown.Block
    let depth: Int
    let isStreaming: Bool

    var body: some View {
        switch block {
        case .paragraph(let text):
            AnswerLine(text: text)
        case .heading(let level, let text):
            Text(AnswerLine.styled(text))
                .font(Self.headingFont(level))
                .foregroundStyle(level >= 5 ? Theme.subtleForeground : Theme.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? Spacing.s1_5 : Spacing.s0)
                .accessibilityAddTraits(.isHeader)
        case .list(let list):
            AnswerList(list: list, depth: depth, isStreaming: isStreaming)
        case .quote(let blocks):
            HStack(alignment: .top, spacing: Spacing.s3) {
                Capsule().fill(Theme.border).frame(width: Spacing.s0_5)
                AnswerBlocks(blocks: blocks, depth: depth, isStreaming: isStreaming)
                    .foregroundStyle(Theme.subtleForeground)
            }
            .fixedSize(horizontal: false, vertical: true)
        case .code(let language, let code):
            AnswerCode(code: code, language: language, isStreaming: isStreaming)
        case .table(let table):
            TextTable(
                header: table.header.map(AnswerLine.styled), rows: table.rows.map { $0.map(AnswerLine.styled) },
                alignments: table.alignments.map(Self.alignment))
        case .rule:
            Divider().padding(.vertical, Spacing.s1)
        }
    }

    private static func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .hk(.xl, .semibold)
        case 2: .hk(.lg, .semibold)
        case 3: .hk(.base, .semibold)
        default: .hk(.sm, .semibold)
        }
    }

    private static func alignment(_ alignment: AIMarkdown.Table.Alignment?) -> HorizontalAlignment {
        switch alignment {
        case .center: .center
        case .trailing: .trailing
        default: .leading
        }
    }
}

/// A paragraph: the body size, a little air between lines; inline code on a quiet fill.
private struct AnswerLine: View {
    let text: AttributedString

    var body: some View {
        Text(Self.styled(text)).font(.hk(.base)).lineSpacing(Spacing.s1).fixedSize(horizontal: false, vertical: true)
    }

    /// Text renders the parsed emphasis, strike and code itself; inline code also gets a fill so it reads as code.
    static func styled(_ text: AttributedString) -> AttributedString {
        var text = text
        for run in text.runs where run.inlinePresentationIntent?.contains(.code) == true {
            text[run.range].backgroundColor = Theme.muted
        }
        return text
    }
}

/// A list, its markers hanging: bullets that change with depth, numbers from the list's start, boxes for task items.
private struct AnswerList: View {
    let list: AIMarkdown.List
    let depth: Int
    let isStreaming: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s1_5) {
            ForEach(list.items.indices, id: \.self) { index in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
                    marker(list.items[index], number: list.start + index)
                    AnswerBlocks(blocks: list.items[index].blocks, depth: depth + 1, isStreaming: isStreaming)
                }
            }
        }
        .padding(.leading, Spacing.s1)
    }

    @ViewBuilder
    private func marker(_ item: AIMarkdown.List.Item, number: Int) -> some View {
        Group {
            switch item.checked {
            case true?:
                IconView(.checkSquare, size: TextSize.base.rawValue).foregroundStyle(.tint)
            case false?:
                IconView(.square, size: TextSize.base.rawValue).foregroundStyle(Theme.mutedForeground)
            case nil:
                // List markers, not copy.
                Text(verbatim: list.ordered ? "\(number)." : ["•", "◦", "▪"][min(depth, 2)])
                    .font(.hk(.base).monospacedDigit())
                    .foregroundStyle(Theme.mutedForeground)
            }
        }
        // One width for bullets, numbers and boxes, so item text lines up whatever its marker.
        .frame(minWidth: Spacing.s4, alignment: .trailing)
    }
}

/// A code block coloured off the main thread. While the answer streams the colouring waits for a pause (each token
/// would start highlight.js again) and the colours already found stay on the part they were found for.
private struct AnswerCode: View {
    let code: String
    let language: String?
    let isStreaming: Bool
    @State private var highlight: CodeHighlight?

    var body: some View {
        CodeBlockView(
            code: code, language: language,
            highlighted: highlight.flatMap { $0.applies(to: code) ? Self.coloured(code, $0) : nil },
            copyLabel: "app:ai.code.copy", copiedLabel: "app:ai.code.copied"
        )
        .task(id: Request(code: code, language: language)) {
            if isStreaming {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
            }
            let found = await CodeHighlighter.shared.highlight(code, language: language)
            guard !Task.isCancelled, found != nil || !(highlight?.applies(to: code) ?? false) else { return }
            highlight = found
        }
    }

    private struct Request: Equatable {
        let code: String
        let language: String?
    }

    /// The code with each token in its `syntax-*` colour; the rest takes the block's text colour.
    static func coloured(_ code: String, _ highlight: CodeHighlight) -> AttributedString {
        var text = AttributedString(code)
        var index = text.startIndex
        var offset = 0
        for span in highlight.spans {
            guard span.range.lowerBound >= offset,
                let start = text.characters.index(index, offsetBy: span.range.lowerBound - offset, limitedBy: text.endIndex),
                let end = text.characters.index(start, offsetBy: span.range.count, limitedBy: text.endIndex)
            else { break }
            text[start..<end].foregroundColor = colour(span.token)
            index = end
            offset = span.range.upperBound
        }
        return text
    }

    private static func colour(_ token: CodeToken) -> Color {
        switch token {
        case .comment: Theme.syntaxComment
        case .string: Theme.syntaxString
        case .number: Theme.syntaxNumber
        case .keyword: Theme.syntaxKeyword
        case .preprocessor: Theme.syntaxPreprocessor
        case .url: Theme.syntaxUrl
        case .attribute: Theme.syntaxAttribute
        case .declaration: Theme.syntaxDeclaration
        case .definition: Theme.syntaxDefinition
        case .type: Theme.syntaxType
        case .function: Theme.syntaxFunction
        }
    }
}
