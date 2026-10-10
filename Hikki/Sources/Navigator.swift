import HikkiCore
import Observation
import SwiftUI

enum Route: Hashable {
    case home
    case trash
    case page(String)

    var pageID: String? {
        if case .page(let id) = self { id } else { nil }
    }
}

/// Per-window navigation state (each window/tab has its own route, expansion and search sheet).
@Observable
final class Navigator {
    /// nil at launch: iPhone shows the sidebar first (like Notion mobile); wider layouts show Home for nil.
    var route: Route?
    var isSearching = false
    var expanded: Set<String> = []
    @ObservationIgnored private(set) weak var model: AppModel?

    func attach(_ model: AppModel) {
        self.model = model
    }

    func open(_ id: String) {
        guard let model else { return }
        // Reveal the page in the sidebar.
        for ancestor in model.tree.path(to: id).dropLast() { expanded.insert(ancestor.id) }
        route = .page(id)
    }

    func newPage(parentId: String? = nil) {
        guard let id = model?.createPage(parentId: parentId) else { return }
        if let parentId { expanded.insert(parentId) }
        route = .page(id)
    }
}

extension FocusedValues {
    @Entry var editor: EditorController?
    @Entry var navigator: Navigator?
}
