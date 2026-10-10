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
                ContentUnavailableView {
                    IconLabel(filter.isEmpty ? "app:trash.isEmpty" : "app:trash.noMatches", icon: .trash)
                } description: {
                    Text("app:trash.emptyHint")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(filtered) { page in
                HStack(spacing: Spacing.s2) {
                    PageIcon(page.icon)
                    VStack(alignment: .leading, spacing: Spacing.s0_5) {
                        Text(page.title.isEmpty ? String(localized: "app:page.untitled") : page.title)
                            .font(.hk(.sm, .medium))
                            .foregroundStyle(Theme.foreground)
                        if let deletedAt = page.deletedAt {
                            Text("app:trash.deletedAt \(deletedAt, format: .relative(presentation: .named))")
                                .font(.hk(.xs))
                                .foregroundStyle(Theme.mutedForeground)
                        }
                    }
                    Spacer()
                    Button {
                        model.restore(id: page.id)
                    } label: {
                        IconLabel("app:trash.restore", icon: .arrowCounterClockwise)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("app:trash.restore")
                    Button(role: .destructive) {
                        pendingDelete = page
                    } label: {
                        IconLabel("app:trash.deletePermanently", icon: .trash)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("app:trash.deletePermanently")
                }
                .padding(.vertical, Spacing.s0_5)
                .swipeActions(edge: .trailing) {
                    Button("app:common.delete", role: .destructive) { pendingDelete = page }
                    Button("app:trash.restore") { model.restore(id: page.id) }.tint(Theme.primary)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .searchable(text: $filter, prompt: "app:trash.filterPrompt")
        .navigationTitle("app:nav.trash")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("app:trash.empty", role: .destructive) { confirmEmpty = true }
                    .disabled(model.trash.isEmpty)
            }
        }
        .confirmationDialog("app:trash.confirmEmpty", isPresented: $confirmEmpty, titleVisibility: .visible) {
            Button("app:trash.empty", role: .destructive) { model.emptyTrash() }
        } message: {
            Text("app:trash.cannotUndo")
        }
        .confirmationDialog(
            "app:trash.confirmDeleteOne \(pendingDelete?.title ?? "")",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("app:trash.deletePermanently", role: .destructive) {
                if let page = pendingDelete { model.deletePermanently(id: page.id) }
            }
        } message: {
            Text("app:trash.deleteOneHint")
        }
    }

    private var filtered: [PageSummary] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? model.trash : model.trash.filter { $0.title.localizedCaseInsensitiveContains(q) }
    }
}
