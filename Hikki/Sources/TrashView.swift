import HikkiCore
import HikkiUI
import SwiftUI

/// Trash, laid out like Home: a title with the count and Empty Trash, then a table of the trashed pages — when each was
/// deleted, when it goes for good (Settings → Keep deleted pages), Restore and Delete on each row. iPhone keeps a list
/// with swipe actions, iPad too.
struct TrashView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmEmpty = false
    @State private var pendingDelete: PageSummary?
    @State private var selection: Set<PageSummary.ID> = []

    /// The table on the Mac; iPhone and iPad keep the list (a button inside an iPad table cell selected the row
    /// instead of firing).
    private var compact: Bool {
        #if os(iOS)
            true
        #else
            false
        #endif
    }

    var body: some View {
        screen.screenTitle(String(localized: "app:nav.trash"))
    }

    @ViewBuilder private var screen: some View {
        VStack(alignment: .leading, spacing: Spacing.s0) {
            header
                .padding(.horizontal, Spacing.s6)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s3)
            if model.trash.isEmpty {
                ContentUnavailableView {
                    IconLabel("app:trash.isEmpty", icon: .trash)
                } description: {
                    Text("app:trash.emptyHint")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compact {
                list
            } else {
                table
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // One surface with the table under the title (Music's): the table's own background, not the page's darker one.
        .background(Theme.listSurface)
        .navigationTitle("app:nav.trash")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text("app:trash.title").font(.hk(.x2l, .bold)).foregroundStyle(Theme.foreground)
            Text(model.trash.count, format: .number).font(.hk(.md)).foregroundStyle(Theme.mutedForeground)
            Spacer()
            Button("app:trash.empty", role: .destructive) { confirmEmpty = true }
                .disabled(model.trash.isEmpty)
                .accessibilityIdentifier("trash-empty")
        }
    }

    private func title(_ page: PageSummary) -> String {
        page.title.isEmpty ? String(localized: "app:page.untitled") : page.title
    }

    @ViewBuilder private func purgeLabel(_ page: PageSummary) -> some View {
        if let deletedAt = page.deletedAt, let purge = TrashPreferences.purgeDate(for: deletedAt) {
            Text(purge, format: .relative(presentation: .named))
        } else {
            Text("app:trash.never")
        }
    }

    private func actions(_ page: PageSummary) -> some View {
        HStack(spacing: Spacing.s1) {
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
    }

    private var table: some View {
        Table(model.trash, selection: $selection) {
            TableColumn("app:trash.column.name") { page in
                HStack(spacing: Spacing.s2) {
                    PageIcon(page.icon, size: 16)
                    Text(title(page)).lineLimit(1)
                }
            }
            .width(min: 200, ideal: 320)  // design-lint: allow (table column widths)
            TableColumn("app:trash.column.deleted") { page in
                if let deletedAt = page.deletedAt {
                    Text(deletedAt, format: .relative(presentation: .named)).foregroundStyle(Theme.subtleForeground)
                }
            }
            .width(min: 100, ideal: 140)  // design-lint: allow (table column widths)
            TableColumn("app:trash.column.purge") { page in
                purgeLabel(page).foregroundStyle(Theme.subtleForeground)
            }
            .width(min: 100, ideal: 140)  // design-lint: allow (table column widths)
            TableColumn("") { page in
                actions(page)
            }
            .width(min: 60, ideal: 70)  // design-lint: allow (table column widths)
        }
        .contextMenu(forSelectionType: PageSummary.ID.self) { ids in
            if ids.count == 1, let id = ids.first, let page = model.trash.first(where: { $0.id == id }) {
                Button("app:trash.restore") { model.restore(id: page.id) }
                Button("app:trash.deletePermanently", role: .destructive) { pendingDelete = page }
            }
        }
        // Its rows on the screen's own surface, so the title above and the table read as one.
        .scrollContentBackground(.hidden)
        .accessibilityIdentifier("trash-table")
    }

    private var list: some View {
        List(model.trash) { page in
            HStack(spacing: Spacing.s2) {
                PageIcon(page.icon)
                VStack(alignment: .leading, spacing: Spacing.s0_5) {
                    Text(title(page)).font(.hk(.sm, .medium)).foregroundStyle(Theme.foreground)
                    if let deletedAt = page.deletedAt {
                        Text("app:trash.deletedAt \(deletedAt, format: .relative(presentation: .named))")
                            .font(.hk(.xs))
                            .foregroundStyle(Theme.mutedForeground)
                    }
                }
                Spacer()
                actions(page)
            }
            .padding(.vertical, Spacing.s0_5)
            .swipeActions(edge: .trailing) {
                Button("app:common.delete", role: .destructive) { pendingDelete = page }
                Button("app:trash.restore") { model.restore(id: page.id) }
            }
        }
        .listStyle(.plain)
    }
}
