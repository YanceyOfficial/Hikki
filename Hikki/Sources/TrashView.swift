import HikkiCore
import HikkiUI
import SwiftUI

struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""
    @State private var confirmEmpty = false
    @State private var pendingDelete: PageSummary?

    var body: some View {
        List {
            if filtered.isEmpty {
                ContentUnavailableView(
                    filter.isEmpty ? "Trash is empty" : "No matches", systemImage: "trash",
                    description: Text("Pages you delete show up here.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(filtered) { page in
                HStack(spacing: Spacing.s2) {
                    PageIcon(page.icon)
                    VStack(alignment: .leading, spacing: Spacing.s0_5) {
                        Text(page.title.isEmpty ? String(localized: "Untitled") : page.title)
                            .font(.hk(.base, .medium))
                            .foregroundStyle(Theme.foreground)
                        if let deletedAt = page.deletedAt {
                            Text("Deleted \(deletedAt, format: .relative(presentation: .named))")
                                .font(.hk(.sm))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    Spacer()
                    Button("Restore", systemImage: "arrow.uturn.backward") { model.restore(id: page.id) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Restore")
                    Button("Delete Permanently", systemImage: "trash", role: .destructive) { pendingDelete = page }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Delete permanently")
                }
                .padding(.vertical, Spacing.s0_5)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { pendingDelete = page }
                    Button("Restore") { model.restore(id: page.id) }.tint(Theme.primary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $filter, prompt: "Filter by page title")
        .navigationTitle("Trash")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Empty Trash", role: .destructive) { confirmEmpty = true }
                    .disabled(model.trash.isEmpty)
            }
        }
        .confirmationDialog("Permanently delete every page in the trash?", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("Empty Trash", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("This can't be undone.")
        }
        .confirmationDialog(
            "Permanently delete “\(pendingDelete?.title ?? "")”?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Permanently", role: .destructive) {
                if let page = pendingDelete { model.deletePermanently(id: page.id) }
            }
        } message: {
            Text("The page and the pages inside it will be gone for good.")
        }
    }

    private var filtered: [PageSummary] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.trash : model.trash.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }
}
