import HikkiCore
import HikkiUI
import SwiftUI

/// A page's read-only link (page ⋯ → Publish Link…; ISSUE-224): the page as the editor exports it (HTML, its
/// attachments) sealed and put in the container's public database by `PagePublisher`, the link kept in the
/// workspace folder (`PublishedLinks`), the site's reader at `/p/<record>#<key>`. A first publish asks (the
/// `PublishSheet`: what anyone with the link can do); an update goes up at once; Unpublish asks and takes the record
/// down.
extension AppModel {
    /// Where published pages are read.
    static let publishSite = URL(string: "https://hikki.yancey.app")!

    func publishedLink(of pageID: String) -> PublishedLink? {
        publishedLinks?.link(of: pageID)
    }

    /// Publishes the page — or updates its link when it has one — with the page as it is now, and puts the link on
    /// the clipboard. Failures are toasts.
    func publishLink(for pageID: String, editor: EditorController) async {
        guard let links = publishedLinks, Purchases.shared.allowsWriting() else { return }
        publishingPages.insert(pageID)
        defer { publishingPages.remove(pageID) }
        let existing = links.link(of: pageID)
        do {
            await editor.flush(reason: "publish")
            guard let record = try store.document(id: pageID) else { return }
            let html = try await editor.exportText(record, format: .html)
            let (relinked, names) = PageExport.relinkAssets(in: html)
            let files = names.compactMap { name in assets.file(named: name).map { (name: name, file: $0) } }
            let payload = PublishedPayload(
                title: record.title, icon: record.icon, html: relinked,
                assets: files.map {
                    .init(name: $0.name, type: PublishedContent.mediaType(forExtension: URL(filePath: $0.name).pathExtension))
                },
                publishedAt: .now)
            let link = try await publisher.publish(payload: payload, assets: files, existing: existing, published: links.count())
            try links.save(link, for: pageID)
            Clipboard.copy(link.url(site: Self.publishSite).absoluteString)
            Toasts.shared.show(.success, String(localized: existing == nil ? "app:publish.copied" : "app:publish.updated"))
        } catch let error as PagePublisher.PublishError {
            switch error {
            case .tooLarge: Toasts.report(.publishTooLarge, error, category: "publish")
            case .tooMany: Toasts.report(.publishTooMany, error, category: "publish")
            case .notSignedIn: Toasts.report(.publishNotSignedIn, error, category: "publish")
            }
        } catch {
            Toasts.report(.publishFailed, error, category: "publish")
        }
    }

    /// The page's link on the clipboard again.
    func copyPublishedLink(of pageID: String) {
        guard let link = publishedLink(of: pageID) else { return }
        Clipboard.copy(link.url(site: Self.publishSite).absoluteString)
        Toasts.shared.show(.success, String(localized: "app:publish.copied"))
    }

    /// Takes the page's record down; the link stops working for everyone.
    func unpublish(_ pageID: String) async {
        guard let links = publishedLinks, let link = links.link(of: pageID) else { return }
        do {
            try await publisher.unpublish(link)
            try links.remove(for: pageID)
            Toasts.shared.show(.info, String(localized: "app:publish.unpublished"))
        } catch {
            Toasts.report(.unpublishFailed, error, category: "publish")
        }
    }
}

/// The page menus' publish entries: Publish Link… for a page without one; Published Link → Copy Link, Update Link,
/// Unpublish for one that has it. The requests go through the navigator; ContentView's `PublishHost` answers them.
struct PublishMenuItems: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        if model.publishedLink(of: page.id) != nil {
            Menu {
                Button {
                    model.copyPublishedLink(of: page.id)
                } label: {
                    IconLabel("app:publish.copy", icon: .link)
                }
                Button {
                    navigator.publishRequestID = page.id
                } label: {
                    IconLabel("app:publish.update", icon: .arrowsClockwise)
                }
                .disabled(model.publishingPages.contains(page.id))
                Button(role: .destructive) {
                    navigator.unpublishRequestID = page.id
                } label: {
                    IconLabel("app:publish.unpublish", icon: .linkBreak)
                }
            } label: {
                IconLabel("app:publish.menu", icon: .globe)
            }
            .accessibilityIdentifier("published-link")
        } else {
            Button {
                navigator.publishRequestID = page.id
            } label: {
                IconLabel("app:publish.action", icon: .globe)
            }
            .accessibilityIdentifier("publish-link")
        }
    }
}

/// Answers the menus' requests: a first publish shows the `PublishSheet` and publishes on its word; an update of a
/// published page goes up at once; Unpublish asks in an alert. Hosted by ContentView with the window's editor.
struct PublishHost: ViewModifier {
    @Environment(AppModel.self) private var model
    let navigator: Navigator
    let editor: EditorController

    /// The first publish's sheet: a request for a page without a link.
    private var asksFirst: Bool {
        guard let id = navigator.publishRequestID else { return false }
        return model.publishedLink(of: id) == nil
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: navigator.publishRequestID) { _, id in
                // Already published: the update needs no second confirmation.
                guard let id, model.publishedLink(of: id) != nil else { return }
                navigator.publishRequestID = nil
                Task { await model.publishLink(for: id, editor: editor) }
            }
            .sheet(isPresented: Binding(get: { asksFirst }, set: { if !$0 { navigator.publishRequestID = nil } })) {
                if let id = navigator.publishRequestID, let page = model.tree.page(id) {
                    PublishSheet(
                        title: page.displayTitle, isPublishing: model.publishingPages.contains(id),
                        onPublish: {
                            Task {
                                await model.publishLink(for: id, editor: editor)
                                navigator.publishRequestID = nil
                            }
                        },
                        onCancel: { navigator.publishRequestID = nil }
                    )
                    #if os(iOS)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                    #endif
                }
            }
            .alert(
                "app:publish.unpublish.title",
                isPresented: Binding(get: { navigator.unpublishRequestID != nil }, set: { if !$0 { navigator.unpublishRequestID = nil } })
            ) {
                Button("app:publish.unpublish", role: .destructive) {
                    guard let id = navigator.unpublishRequestID else { return }
                    Task { await model.unpublish(id) }
                }
                .accessibilityIdentifier("confirm-unpublish")
                Button("app:common.cancel", role: .cancel) {}
            } message: {
                Text("app:publish.unpublish.message")
            }
    }
}
