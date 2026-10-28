import HikkiCore
import HikkiUI
import SwiftUI

/// Publishing a page (page ⋯ → Publish…; ISSUE-224): the page as the editor exports it (HTML, its attachments) put in
/// the container's public database by `PagePublisher` — sealed for people with the link, or listed in Hikki Shared
/// with its tags (`PublishOptions`) — the link kept in the workspace folder (`PublishedLinks`), the site's readers at
/// `/p/<record>#<key>` and `/shared/<record>`. Publishing asks first (the `PublishSheet`: how, the tags, a check that
/// the page holds nothing private) and ends on the `PublishedSheet` (the link, Copy, Open in Browser); Update Page goes
/// up at once and shows it again; Unpublish asks and takes the record down.
extension AppModel {
    /// Where published pages are read.
    static let publishSite = URL(string: "https://hikki.yancey.app")!

    func publishedLink(of pageID: String) -> PublishedLink? {
        publishedLinks?.link(of: pageID)
    }

    /// Publishes the page — or updates its record when it has one — as it is now; `options` changes how it is shared
    /// (nil keeps the link's own). Returns the link, nil after a failure (a toast).
    func publishLink(for pageID: String, options: PublishOptions?, editor: EditorController) async -> PublishedLink? {
        guard let links = publishedLinks, Purchases.shared.allowsWriting() else { return nil }
        publishingPages.insert(pageID)
        defer { publishingPages.remove(pageID) }
        let existing = links.link(of: pageID)
        let options = (options ?? existing?.options ?? .linkOnly).normalized
        do {
            await editor.flush(reason: "publish")
            guard let record = try store.document(id: pageID) else { return nil }
            let html = try await editor.exportText(record, format: .html)
            let (relinked, names) = PageExport.relinkAssets(in: html)
            // The cover goes along when a reader can draw it: a gradient, an Unsplash or other https picture, or an
            // uploaded one sent with the attachments.
            let cover = PublishedCover.from(PageCover(record.cover))
            var attached = names
            if let name = cover?.asset, !attached.contains(name) { attached.append(name) }
            let files = attached.compactMap { name in assets.file(named: name).map { (name: name, file: $0) } }
            // An uploaded cover whose file is gone stays behind.
            let sentCover = cover.flatMap { item in
                item.asset.map { name in files.contains { $0.name == name } } ?? true ? item.cover : nil
            }
            let payload = PublishedPayload(
                title: record.title, icon: record.icon, html: relinked,
                assets: files.map {
                    .init(name: $0.name, type: PublishedContent.mediaType(forExtension: URL(filePath: $0.name).pathExtension))
                },
                publishedAt: .now, cover: sentCover)
            let link = try await publisher.publish(
                payload: payload, assets: files, existing: existing, options: options, plainText: record.plainText,
                published: links.count())
            try links.save(link, for: pageID)
            return link
        } catch let error as PagePublisher.PublishError {
            switch error {
            case .tooLarge: Toasts.report(.publishTooLarge, error, category: "publish")
            case .tooMany: Toasts.report(.publishTooMany, error, category: "publish")
            case .notSignedIn: Toasts.report(.publishNotSignedIn, error, category: "publish")
            }
        } catch {
            Toasts.report(.publishFailed, error, category: "publish")
        }
        return nil
    }

    /// The page's link on the clipboard.
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

    /// A preset tag's name (`PublishTags.all`).
    static func publishTagTitle(_ id: String) -> String {
        switch id {
        case "study": String(localized: "app:publish.tag.study")
        case "language": String(localized: "app:publish.tag.language")
        case "work": String(localized: "app:publish.tag.work")
        case "tech": String(localized: "app:publish.tag.tech")
        case "design": String(localized: "app:publish.tag.design")
        case "writing": String(localized: "app:publish.tag.writing")
        case "reading": String(localized: "app:publish.tag.reading")
        case "travel": String(localized: "app:publish.tag.travel")
        case "food": String(localized: "app:publish.tag.food")
        case "health": String(localized: "app:publish.tag.health")
        case "life": String(localized: "app:publish.tag.life")
        case "templates": String(localized: "app:publish.tag.templates")
        default: id
        }
    }
}

/// What the publish sheet remembers between pages (and devices — a synced setting): the name shown as the author.
enum PublishPreferences {
    static let authorKey = "publish.author"
}

/// The page menus' publish entries: Publish… for a page that isn't published; for one that is, Published → Show
/// Link…, Copy Link, Update Page, Sharing Settings…, Unpublish. The requests go through the navigator; ContentView's
/// `PublishHost` answers them.
struct PublishMenuItems: View {
    @Environment(AppModel.self) private var model
    let page: PageSummary
    let navigator: Navigator

    var body: some View {
        if model.publishedLink(of: page.id) != nil {
            Menu {
                Button {
                    navigator.publishRequest = .showLink(page.id)
                } label: {
                    IconLabel("app:publish.show", icon: .globe)
                }
                Button {
                    model.copyPublishedLink(of: page.id)
                } label: {
                    IconLabel("app:publish.copy", icon: .link)
                }
                Button {
                    navigator.publishRequest = .update(page.id)
                } label: {
                    IconLabel("app:publish.update", icon: .arrowsClockwise)
                }
                .disabled(model.publishingPages.contains(page.id))
                Button {
                    navigator.publishRequest = .settings(page.id)
                } label: {
                    IconLabel("app:publish.settings", icon: .tag)
                }
                Button(role: .destructive) {
                    navigator.publishRequest = .unpublish(page.id)
                } label: {
                    IconLabel("app:publish.unpublish", icon: .linkBreak)
                }
            } label: {
                IconLabel("app:publish.menu", icon: .globe)
            }
            .accessibilityIdentifier("published-link")
        } else {
            Button {
                navigator.publishRequest = .settings(page.id)
            } label: {
                IconLabel("app:publish.action", icon: .globe)
            }
            .accessibilityIdentifier("publish-link")
        }
    }
}

/// Answers the menus' publish requests, hosted by ContentView with the window's editor: one sheet that starts as the
/// `PublishSheet` (a first publish, or the settings of a published page) and becomes the `PublishedSheet` once the page
/// is up — or opens on it for Show Link… and after Update Page — and an alert for Unpublish.
struct PublishHost: ViewModifier {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let navigator: Navigator
    let editor: EditorController

    /// The sheet, by page: the settings, or the published link (`updated`: an update of a published page).
    struct Flow: Identifiable {
        enum Step {
            case settings
            case published(updated: Bool)
        }
        var pageID: String
        var step: Step
        var id: String { pageID }
        var isSettings: Bool {
            if case .settings = step { return true }
            return false
        }
    }

    @State private var flow: Flow?
    @State private var unpublishID: String?

    func body(content: Content) -> some View {
        content
            .onChange(of: navigator.publishRequest) { _, request in
                guard let request else { return }
                navigator.publishRequest = nil
                handle(request)
            }
            .sheet(item: $flow) { flow in
                sheet(for: flow)
                    #if os(iOS)
                        .presentationDetents(flow.isSettings ? [.large] : [.medium])
                        .presentationDragIndicator(.visible)
                    #endif
            }
            .alert(
                "app:publish.unpublish.title",
                isPresented: Binding(get: { unpublishID != nil }, set: { if !$0 { unpublishID = nil } })
            ) {
                Button("app:publish.unpublish", role: .destructive) {
                    guard let id = unpublishID else { return }
                    Task { await model.unpublish(id) }
                }
                .accessibilityIdentifier("confirm-unpublish")
                Button("app:common.cancel", role: .cancel) {}
            } message: {
                Text("app:publish.unpublish.message")
            }
    }

    private func handle(_ request: PublishRequest) {
        switch request {
        case .settings(let id):
            flow = Flow(pageID: id, step: .settings)
        case .update(let id):
            Task {
                if await model.publishLink(for: id, options: nil, editor: editor) != nil {
                    flow = Flow(pageID: id, step: .published(updated: true))
                }
            }
        case .showLink(let id):
            guard model.publishedLink(of: id) != nil else { return }
            flow = Flow(pageID: id, step: .published(updated: false))
        case .unpublish(let id):
            unpublishID = id
        }
    }

    @ViewBuilder
    private func sheet(for flow: Flow) -> some View {
        switch flow.step {
        case .settings:
            PublishSettings(pageID: flow.pageID, editor: editor) { updated in
                self.flow = Flow(pageID: flow.pageID, step: .published(updated: updated))
            } onCancel: {
                self.flow = nil
            }
        case .published(let updated):
            if let link = model.publishedLink(of: flow.pageID) {
                let url = link.url(site: AppModel.publishSite)
                PublishedSheet(
                    link: url.absoluteString, listed: link.listed, tags: link.tags.map(AppModel.publishTagTitle),
                    author: link.author,
                    updated: updated,
                    onCopy: { Clipboard.copy(url.absoluteString) },
                    onOpen: { openURL(url) },
                    onDone: { self.flow = nil }
                )
            }
        }
    }
}

/// The publish sheet's choices, held by a view of its own: a sheet's content is built apart from the view that
/// presents it, so state kept there never redrew the sheet (taps on the choices, tags and the check did nothing).
private struct PublishSettings: View {
    @Environment(AppModel.self) private var model
    let pageID: String
    let editor: EditorController
    let onPublished: (_ updated: Bool) -> Void
    let onCancel: () -> Void
    @State private var listed = false
    @State private var chosenTags: Set<String> = []
    @State private var checked = false
    @State private var author = ""
    @State private var loaded = false
    @AppStorage(PublishPreferences.authorKey) private var savedAuthor = ""

    var body: some View {
        let published = model.publishedLink(of: pageID) != nil
        PublishSheet(
            title: model.tree.page(pageID)?.displayTitle ?? "",
            tags: PublishTags.all.map { .init(id: $0, title: AppModel.publishTagTitle($0)) },
            maxTags: PublishTags.maxPerPage, isUpdate: published, isPublishing: model.publishingPages.contains(pageID),
            listed: $listed, chosenTags: $chosenTags, author: $author, checked: $checked,
            onPublish: {
                let options = PublishOptions(listed: listed, tags: Array(chosenTags), author: author).normalized
                savedAuthor = options.author
                Task {
                    if await model.publishLink(for: pageID, options: options, editor: editor) != nil { onPublished(published) }
                }
            },
            onCancel: onCancel
        )
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let options = model.publishedLink(of: pageID)?.options ?? .linkOnly
            listed = options.listed
            chosenTags = Set(options.tags)
            author = options.author.isEmpty ? savedAuthor : options.author
        }
    }
}
