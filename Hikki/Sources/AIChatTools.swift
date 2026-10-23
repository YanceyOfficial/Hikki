import Foundation
import HikkiAI
import HikkiCore
import HikkiUI

/// Ask AI's file tools as the chat keeps and draws them: a tool's output read into its `ChatToolCall`, and the call
/// as HikkiUI's card.
extension ChatToolCall {
    /// What the tool gave back, read into the record (texts capped as kept).
    mutating func record(_ output: AIToolOutput) {
        guard !output.isError else {
            status = .failed
            message = String(output.text.prefix(500))
            return
        }
        status = .done
        let fields = (try? JSONSerialization.jsonObject(with: Data(output.text.utf8))) as? [String: Any] ?? [:]
        if let path = fields["path"] as? String { self.path = path }
        switch WorkspaceFiles.Tool(rawValue: name) {
        case .listDirectory:
            let entries = fields["entries"] as? [[String: Any]] ?? []
            count = entries.count
            results = entries.prefix(Self.maxResults).compactMap { entry in
                (entry["path"] as? String).map { entry["type"] as? String == "folder" ? $0 + "/" : $0 }
            }
        case .readFile:
            text = Self.capped(fields["content"] as? String)
            count = fields["totalLines"] as? Int
            bytes = fields["size"] as? Int
        case .findFiles:
            let found = fields["results"] as? [String] ?? []
            count = found.count
            results = Array(found.prefix(Self.maxResults))
        case .grep:
            count = fields["matches"] as? Int
            var lines: [String] = []
            for file in fields["results"] as? [[String: Any]] ?? [] {
                let path = file["path"] as? String ?? ""
                for match in file["matches"] as? [[String: Any]] ?? [] {
                    lines.append("\(path):\(match["line"] as? Int ?? 0)  \(match["text"] as? String ?? "")")
                }
            }
            results = Array(lines.prefix(Self.maxResults))
        case .writeFile:
            bytes = fields["bytes"] as? Int
            created = fields["created"] as? Bool
            appended = fields["appended"] as? Bool
        case .editFile:
            replacements = fields["replacements"] as? Int
        case nil:
            break
        }
    }

    /// The call as its card shows it.
    var card: ToolCallCardItem {
        let tool = WorkspaceFiles.Tool(rawValue: name)
        let kind: ToolCallCardItem.Kind =
            switch tool {
            case .listDirectory: .list
            case .readFile: .read
            case .findFiles: .find
            case .grep: .search
            case .writeFile: .write
            case .editFile, nil: .edit
            }
        let state: ToolCallCardItem.State =
            switch status {
            case .running: .running
            case .waiting: .waiting
            case .done: .done
            case .failed: .failed(message ?? String(localized: "app:ai.tools.failed"))
            case .declined: .declined
            case .stopped: .stopped
            }
        var item = ToolCallCardItem(id: id, kind: kind, path: path, pattern: pattern, state: state, summary: summary(kind))
        switch kind {
        case .read:
            item.lines = LineCount.lines(text ?? "").map { LineDiff.clip($0, to: LineDiff.maxLineLength) }
        case .list, .find, .search:
            item.lines = results ?? []
        case .write:
            // Replacing a file shows what changes; a new file (or an addition) shows its text.
            if let before, appended != true, let text {
                Self.diff(before, text, into: &item)
            } else {
                item.lines = LineCount.lines(text ?? "").map { LineDiff.clip($0, to: LineDiff.maxLineLength) }
            }
        case .edit:
            Self.diff(before ?? "", after ?? "", into: &item)
        }
        return item
    }

    private func summary(_ kind: ToolCallCardItem.Kind) -> String? {
        switch kind {
        case .read: count.map { String(localized: "app:ai.tools.lines \(String($0))") }
        case .list: count.map { String(localized: "app:ai.tools.items \(String($0))") }
        case .find: count.map { String(localized: "app:ai.tools.files \(String($0))") }
        case .search: count.map { String(localized: "app:ai.tools.matches \(String($0))") }
        case .write:
            created == true
                ? String(localized: "app:ai.tools.created")
                : appended == true ? String(localized: "app:ai.tools.appended") : String(localized: "app:ai.tools.replaced")
        case .edit: nil
        }
    }

    private static func diff(_ old: String, _ new: String, into item: inout ToolCallCardItem) {
        let result = LineDiff.diff(old: old, new: new)
        item.added = result.added
        item.removed = result.removed
        switch result {
        case .tooLarge:
            item.diff = []
            item.summary = String(localized: "app:ai.tools.tooLarge")
        case .lines(let items, _, _):
            item.diff = items.map { entry in
                switch entry {
                case .gap(let count): ToolCallCardItem.DiffLine(.context, "", gap: count)
                case .row(let row):
                    ToolCallCardItem.DiffLine(
                        row.kind == .added ? .added : row.kind == .removed ? .removed : .context, row.text)
                }
            }
        }
    }
}
