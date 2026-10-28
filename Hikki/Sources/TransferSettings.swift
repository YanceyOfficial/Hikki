import HikkiCore
import HikkiUI
import SwiftUI
import UniformTypeIdentifiers

/// Settings → Import & Export (its own page, Notion's Import): a drop zone, the sources — Markdown / HTML / text,
/// a Hikki export (JSON), a Notion export (.zip) — the whole workspace out to a folder, and the job's progress and
/// summary (`BulkTransfer`, which runs on when Settings closes). Files dropped on the zone (Mac, iPad) import like
/// chosen ones; on iPhone the zone is a button for the picker.
struct TransferPage: View {
    @Environment(AppModel.self) private var model
    @AppStorage(TransferPreferences.formatKey) private var format = WorkspaceExport.Format.markdown
    @State private var picking: Picking?
    @State private var targeted = false

    /// What the picker is opened for.
    private enum Picking: Identifiable {
        case documents, hikki, notion, exportFolder

        var id: Self { self }

        var types: [UTType] {
            switch self {
            case .documents: [UTType("net.daringfireball.markdown"), .html, .plainText, .folder].compactMap { $0 }
            case .hikki: [.json, .folder]
            case .notion: [.zip]
            case .exportFolder: [.folder]
            }
        }

        var allowsMany: Bool { self != .exportFolder }
    }

    private var transfer: BulkTransfer { model.bulkTransfer }

    var body: some View {
        Section {
            if let progress = transfer.progress {
                TaskProgressRow(
                    label(progress), done: progress.done, total: progress.total, cancelTitle: "app:common.cancel",
                    onCancel: transfer.cancel)
            } else {
                FileDropZone(
                    title: "app:settings.transfer.drop", detail: "app:settings.transfer.drop.detail", icon: .trayArrowDown,
                    isTargeted: targeted
                ) {
                    picking = .documents
                }
                .onDrop(of: SidebarFileDrop.types + [.zip], isTargeted: $targeted) { providers in drop(providers) }
                .listRowInsets(EdgeInsets(top: Spacing.s2, leading: Spacing.s2, bottom: Spacing.s2, trailing: Spacing.s2))
                .listRowBackground(Color.clear)
                SourceRow(
                    icon: .fileText, title: "app:settings.transfer.source.documents",
                    detail: "app:settings.transfer.source.documents.detail", identifier: "settings-import"
                ) {
                    picking = .documents
                }
                SourceRow(
                    icon: .files, title: "app:settings.transfer.source.hikki", detail: "app:settings.transfer.source.hikki.detail",
                    identifier: "settings-import-hikki"
                ) {
                    picking = .hikki
                }
                SourceRow(
                    icon: .fileZip, title: "app:settings.transfer.source.notion",
                    detail: "app:settings.transfer.source.notion.detail", identifier: "settings-import-notion"
                ) {
                    picking = .notion
                }
            }
            if let summary = transfer.summary, summary.kind == .importing {
                SummaryRow(summary: summary, onDismiss: transfer.dismissSummary)
            }
        } header: {
            Text("app:settings.transfer.import")
        } footer: {
            Text("app:settings.transfer.import.detail")
        }
        Section {
            LabeledContent("app:settings.transfer.export") {
                HStack(spacing: Spacing.s2) {
                    Picker(selection: $format) {
                        ForEach(WorkspaceExport.Format.allCases) { Text(Self.title(of: $0)).tag($0) }
                    } label: {
                        Text("app:settings.transfer.format")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityIdentifier("settings-export-format")
                    Button("app:settings.transfer.exportButton") { picking = .exportFolder }
                        .disabled(transfer.isRunning)
                        .accessibilityIdentifier("settings-export")
                }
            }
            if let summary = transfer.summary, summary.kind == .exporting {
                SummaryRow(summary: summary, onDismiss: transfer.dismissSummary)
            }
        } header: {
            Text("app:settings.transfer.exportSection")
        } footer: {
            Text("app:settings.transfer.export.detail")
        }
        .fileImporter(
            isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } }),
            allowedContentTypes: picking?.types ?? [], allowsMultipleSelection: picking?.allowsMany ?? false
        ) { result in
            let mode = picking
            picking = nil
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            switch mode {
            case .exportFolder: transfer.startExport(format, to: urls[0], model: model)
            case .documents, .hikki, .notion: start(urls)
            case nil: break
            }
        }
    }

    private func start(_ urls: [URL]) {
        guard Purchases.shared.allowsWriting() else { return }
        transfer.startImport(urls, model: model)
    }

    /// Files dropped on the zone (file URLs on the Mac, typed documents on iPad): read, then imported like chosen ones.
    private func drop(_ providers: [NSItemProvider]) -> Bool {
        let zips = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.zip.identifier) }
        let files = SidebarFileDrop.importable(providers)
        guard !files.isEmpty || !zips.isEmpty else { return false }
        Task {
            let urls = await SidebarFileDrop.load(files + zips.filter { provider in !files.contains { $0 === provider } })
            Log.info("files dropped on import", category: "import", context: ["items": "\(providers.count)", "files": "\(urls.count)"])
            guard !urls.isEmpty else { return }
            start(urls)
        }
        return true
    }

    private func label(_ progress: BulkTransfer.Progress) -> Text {
        guard progress.total > 0 else { return Text("app:settings.transfer.preparing") }
        let done = progress.done.formatted()
        let total = progress.total.formatted()
        return progress.kind == .importing
            ? Text("app:settings.transfer.importing \(done) \(total)") : Text("app:settings.transfer.exporting \(done) \(total)")
    }

    private static func title(of format: WorkspaceExport.Format) -> LocalizedStringKey {
        switch format {
        case .markdown: "app:export.markdown"
        case .html: "app:export.html"
        case .json: "app:export.json"
        }
    }

    /// One way in: what it takes, a line about it, Choose….
    private struct SourceRow: View {
        let icon: Icon
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
        let identifier: String
        let action: () -> Void

        var body: some View {
            LabeledContent {
                Button("app:settings.transfer.choose", action: action)
                    .accessibilityIdentifier(identifier)
            } label: {
                HStack(alignment: .top, spacing: Spacing.s3) {
                    IconView(icon, size: TextSize.lg.rawValue).foregroundStyle(Theme.mutedForeground).padding(.top, Spacing.s0_5)
                    VStack(alignment: .leading, spacing: Spacing.s0_5) {
                        Text(title)
                        Text(detail).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground)
                    }
                }
            }
        }
    }

    /// How the last job ended: pages imported / exported, what was left out and why, where the export went.
    private struct SummaryRow: View {
        let summary: BulkTransfer.Summary
        let onDismiss: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(headline)
                    .font(.hk(.sm, .medium))
                    .foregroundStyle(summary.failed ? Theme.destructive : Theme.foreground)
                    .accessibilityIdentifier("settings-transfer-result")
                if !summary.skipped.isEmpty {
                    DisclosureGroup {
                        ForEach(Array(summary.skipped.enumerated()), id: \.offset) { _, item in
                            LabeledContent {
                                Text(Self.reason(item.reason))
                            } label: {
                                Text(verbatim: item.name)  // a file's name or a page's title, as-is
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .font(.hk(.xs))
                        }
                    } label: {
                        Text("app:settings.transfer.skipped \(summary.skipped.count.formatted())")
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                HStack(spacing: Spacing.s2) {
                    #if os(macOS)
                        if let folder = summary.destination, !summary.failed {
                            Button("app:settings.transfer.reveal") { NSWorkspace.shared.activateFileViewerSelecting([folder]) }
                        }
                    #endif
                    Button("app:settings.transfer.clear", action: onDismiss)
                        .accessibilityIdentifier("settings-transfer-clear")
                }
            }
            .padding(.vertical, Spacing.s1)
        }

        private var headline: LocalizedStringKey {
            let count = summary.count.formatted()
            switch (summary.kind, summary.failed, summary.cancelled) {
            case (.exporting, true, _): return "app:settings.transfer.exportFailed"
            case (.importing, _, true): return "app:settings.transfer.importCancelled \(count)"
            case (.exporting, _, true): return "app:settings.transfer.exportCancelled \(count)"
            case (.importing, _, false): return "app:settings.transfer.imported \(count)"
            case (.exporting, _, false): return "app:settings.transfer.exported \(count)"
            }
        }

        private static func reason(_ reason: WorkspaceImport.Reason) -> LocalizedStringKey {
            switch reason {
            case .unsupported: "app:settings.transfer.reason.unsupported"
            case .tooLarge: "app:settings.transfer.reason.tooLarge"
            case .notAPage: "app:settings.transfer.reason.notAPage"
            case .newerFormat: "app:settings.transfer.reason.newerFormat"
            case .inTrash: "app:settings.transfer.reason.inTrash"
            case .failed: "app:settings.transfer.reason.failed"
            case .symbolicLink: "app:settings.transfer.reason.symbolicLink"
            case .badArchive: "app:settings.transfer.reason.badArchive"
            }
        }
    }
}
