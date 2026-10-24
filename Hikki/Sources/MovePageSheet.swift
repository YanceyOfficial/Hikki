import HikkiCore
import HikkiUI
import SwiftUI

/// Move to, from every page menu (Notion's "Move page to…"): HikkiUI's `MovePagePicker` over the page tree
/// (`PageTree.moveChoices`). It opens with the page's own place shown (its ancestors expanded). A pick moves the page
/// through the model as before — inside the picked page, at its end, or the workspace row for the top level.
/// ContentView presents it for `Navigator.movePageID`: a sheet the popover's size on the Mac, a form sheet on iPad,
/// a half-height sheet on iPhone.
struct MovePageSheet: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    /// The field takes the keyboard at once (Mac, iPad); on iPhone a software keyboard would cover half the list.
    var focusesField = true
    let dismiss: () -> Void
    @State private var query = ""
    @State private var expanded: Set<String> = []

    var body: some View {
        MovePagePicker(
            query: $query, items: items, workspaceName: model.workspace?.name ?? "Hikki",
            isAtTopLevel: model.tree.isTopLevel(pageID), focusesField: focusesField,
            isComposing: { TextComposition.isActive },
            badge: {
                WorkspaceBadge(initial: model.workspace?.initial ?? "H", icon: model.workspace?.icon, size: Size.iconButtonSm)
            },
            onToggle: { id in
                if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
            },
            onPick: { target in
                dismiss()
                if let target {
                    model.movePage(pageID, onto: target, zone: .inside)
                } else {
                    model.movePageToTopLevel(pageID)
                }
            },
            onCancel: dismiss
        )
        .onAppear {
            // Where the page is now: the pages above it open, so its current parent shows (with its check).
            expanded = Set(model.tree.path(to: pageID).dropLast().map(\.id))
        }
        // The page went away meanwhile (trashed on another device): nothing left to move.
        .onChange(of: model.tree.page(pageID) == nil) { _, gone in
            if gone { dismiss() }
        }
    }

    private var items: [MovePickerItem] {
        model.tree.moveChoices(for: pageID, query: query, expanded: expanded).map { choice in
            MovePickerItem(
                id: choice.id, title: choice.title, icon: choice.icon, depth: choice.depth, hasChildren: choice.hasChildren,
                isExpanded: choice.isExpanded, isCurrent: choice.isCurrentParent,
                path: choice.path.map { $0.isEmpty ? String(localized: "app:page.untitled") : $0 }.joined(separator: " / "))
        }
    }
}
