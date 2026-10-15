import HikkiCore
import HikkiUI
import SwiftUI

/// Settings → About → Logs: the newest log entries on this device (all, warnings and up, or errors), filtered by
/// text — to look something up on the device itself, an iPhone especially, without exporting first.
struct LogsView: View {
    enum Level: String, CaseIterable, Identifiable {
        case all, warnings, errors
        var id: String { rawValue }

        func admits(_ level: LogLevel) -> Bool {
            switch self {
            case .all: true
            case .warnings: level == .warn || level == .error
            case .errors: level == .error
            }
        }
    }

    @State private var entries: [LogEntry] = []
    @State private var level = Level.warnings
    @State private var filter = ""

    var body: some View {
        List {
            Picker("app:logs.level", selection: $level) {
                Text("app:logs.filter.all").tag(Level.all)
                Text("app:logs.filter.warnings").tag(Level.warnings)
                Text("app:logs.filter.errors").tag(Level.errors)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("logs-level")
            if shown.isEmpty {
                Text("app:logs.empty").font(.hk(.sm)).foregroundStyle(Theme.mutedForeground)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { _, entry in
                LogRow(entry: entry)
            }
        }
        .searchable(text: $filter, prompt: Text("app:logs.search"))
        .navigationTitle(Text("app:diagnostics.logs"))
        .task { entries = await Task.detached { Log.recent(limit: 1000) }.value }
        .refreshable { entries = await Task.detached { Log.recent(limit: 1000) }.value }
    }

    private var shown: [LogEntry] {
        let text = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { entry in
            guard level.admits(entry.level) else { return false }
            guard !text.isEmpty else { return true }
            let context = entry.context?.map { "\($0.key)=\($0.value)" }.joined(separator: " ") ?? ""
            return "\(entry.category) \(entry.message) \(context)".lowercased().contains(text)
        }
    }
}

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s0_5) {
            HStack(spacing: Spacing.s1_5) {
                Text(verbatim: entry.level.rawValue.uppercased())
                    .font(.hk(.x2s, .semibold))
                    .foregroundStyle(tint)
                Text(verbatim: entry.category).font(.hk(.xs, .medium)).foregroundStyle(Theme.subtleForeground)
                Spacer(minLength: Spacing.s2)
                Text(entry.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.hk(.xs).monospacedDigit())
                    .foregroundStyle(Theme.mutedForeground)
            }
            Text(verbatim: entry.message).font(.hk(.sm)).foregroundStyle(Theme.foreground)
            if let context = entry.context, !context.isEmpty {
                Text(verbatim: context.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "  "))
                    .font(.hk(.xs).monospaced())
                    .foregroundStyle(Theme.mutedForeground)
                    .lineLimit(4)
            }
        }
        .textSelection(.enabled)
        .padding(.vertical, Spacing.s0_5)
    }

    private var tint: Color {
        switch entry.level {
        case .error: Theme.destructive
        case .warn: Theme.inkYellow
        case .info: Theme.inkBlue
        case .debug: Theme.mutedForeground
        }
    }
}

/// The diagnostics bundle as something to share: built (zipped) only when it is actually shared.
struct DiagnosticsFile: Transferable {
    let logs: [URL]
    let reports: [URL]
    let app: AppInfo
    let facts: [String: String]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { file in
            do {
                return SentTransferredFile(
                    try DiagnosticsBundle.make(logs: file.logs, reports: file.reports, app: file.app, facts: file.facts))
            } catch {
                Toasts.report(.diagnosticsExportFailed, error, category: "diagnostics")
                throw error
            }
        }
    }
}
