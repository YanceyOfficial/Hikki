import PDFKit
import SwiftUI

/// A PDF, natively (PDFKit, what Preview shows): pages scrolling in a column, zoom and fit, the page number, find in the
/// document, a strip of page thumbnails, and an unlock prompt for a password-protected file. Purely presentational —
/// it reads the file at `url`; "open outside" is the caller's.
public struct PDFViewer: View {
    private let url: URL
    private let onOpenExternally: (() -> Void)?
    @State private var model = PDFViewerModel()

    public init(url: URL, onOpenExternally: (() -> Void)? = nil) {
        self.url = url
        self.onOpenExternally = onOpenExternally
    }

    public var body: some View {
        VStack(spacing: Spacing.s0) {
            if model.document == nil {
                message("app:pdf.unreadable")
            } else if model.isLocked {
                unlock
            } else {
                HStack(spacing: Spacing.s0) {
                    if model.showsThumbnails {
                        PDFThumbnails(model: model)
                            .frame(width: Size.pdfThumbnails)
                        Divider()
                    }
                    PDFKitView(model: model)
                }
                Divider()
                bar
            }
        }
        .background(Theme.background)
        .task(id: url) { model.open(url) }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        VStack(spacing: Spacing.s3) {
            IconView(.fileText, size: TextSize.x3l.rawValue).foregroundStyle(Theme.mutedForeground)
            Text(text).font(.hk(.md)).foregroundStyle(Theme.subtleForeground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Notion's "This PDF is locked · Unlock Document": the password, checked by PDFKit, never stored.
    private var unlock: some View {
        VStack(spacing: Spacing.s3) {
            IconView(.lockSimple, size: TextSize.x3l.rawValue).foregroundStyle(Theme.mutedForeground)
            Text("app:pdf.locked").font(.hk(.md, .medium)).foregroundStyle(Theme.foreground)
            HStack(spacing: Spacing.s2) {
                SecureField("app:pdf.password", text: $model.password)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: Size.pdfPassword)
                    .onSubmit { model.unlock() }
                    .accessibilityIdentifier("pdf-password")
                Button("app:pdf.unlock") { model.unlock() }
                    .accessibilityIdentifier("pdf-unlock")
            }
            if model.wrongPassword {
                Text("app:pdf.wrongPassword").font(.hk(.xs)).foregroundStyle(Theme.destructive)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The bottom bar: thumbnails, find, page number, zoom, open outside.
    private var bar: some View {
        HStack(spacing: Spacing.s2) {
            barButton("app:pdf.thumbnails", icon: .sidebarSimple, active: model.showsThumbnails) {
                model.showsThumbnails.toggle()
            }
            HStack(spacing: Spacing.s1) {
                IconView(.magnifyingGlass, size: TextSize.sm.rawValue).foregroundStyle(Theme.mutedForeground)
                TextField("app:pdf.find", text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.hk(.sm))
                    .frame(width: Size.pdfFind)
                    .onSubmit { model.findNext() }
                    .accessibilityIdentifier("pdf-find")
                if !model.query.isEmpty {
                    Text(verbatim: model.matchLabel).font(.hk(.xs)).foregroundStyle(Theme.mutedForeground).monospacedDigit()
                }
            }
            .padding(.horizontal, Spacing.s2)
            .frame(height: Size.iconButton)
            .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
            Spacer(minLength: Spacing.s2)
            Text("app:pdf.page \(model.pageNumber.formatted()) \(model.pageCount.formatted())")
                .font(.hk(.sm))
                .foregroundStyle(Theme.subtleForeground)
                .monospacedDigit()
                .accessibilityIdentifier("pdf-page")
            Spacer(minLength: Spacing.s2)
            barButton("app:pdf.zoomOut", icon: .minus) { model.zoom(by: 1 / 1.25) }
            Button("app:pdf.fit") { model.fit() }
                .buttonStyle(HoverHighlightStyle(cornerRadius: Radius.md))
                .font(.hk(.sm))
            barButton("app:pdf.zoomIn", icon: .plus) { model.zoom(by: 1.25) }
            if let onOpenExternally {
                barButton("app:pdf.openOutside", icon: .export, action: onOpenExternally)
            }
        }
        .padding(.horizontal, Spacing.s3)
        .frame(height: Size.pageBar)
    }

    private func barButton(_ title: LocalizedStringKey, icon: Icon, active: Bool = false, action: @escaping () -> Void)
        -> some View
    {
        ToolbarIconButton(title, symbol: icon, isActive: active, action: action)
    }
}

/// The viewer's state, shared by the SwiftUI chrome and the PDFKit view.
@Observable
final class PDFViewerModel {
    private(set) var document: PDFDocument?
    private(set) var isLocked = false
    var password = ""
    private(set) var wrongPassword = false
    var showsThumbnails = false
    var query = "" {
        didSet {
            if query != oldValue {
                matches = []
                matchIndex = -1
            }
        }
    }
    private(set) var pageNumber = 1
    private(set) var pageCount = 0
    private var matches: [PDFSelection] = []
    private var matchIndex = -1
    @ObservationIgnored weak var view: PDFView?

    var matchLabel: String {
        matches.isEmpty ? (matchIndex == -2 ? "0" : "") : "\(matchIndex + 1)/\(matches.count)"
    }

    func open(_ url: URL) {
        document = PDFDocument(url: url)
        isLocked = document?.isLocked ?? false
        pageCount = document?.pageCount ?? 0
        pageNumber = 1
        view?.document = isLocked ? nil : document
    }

    func unlock() {
        guard let document else { return }
        if document.unlock(withPassword: password) {
            isLocked = false
            wrongPassword = false
            password = ""
            pageCount = document.pageCount
            view?.document = document
        } else {
            wrongPassword = true
        }
    }

    func attach(_ view: PDFView) {
        self.view = view
        if !isLocked { view.document = document }
    }

    func pageChanged() {
        guard let view, let page = view.currentPage, let document = view.document else { return }
        pageNumber = document.index(for: page) + 1
    }

    func zoom(by factor: CGFloat) {
        guard let view else { return }
        view.autoScales = false
        view.scaleFactor = min(max(view.scaleFactor * factor, view.minScaleFactor), view.maxScaleFactor)
    }

    func fit() {
        view?.autoScales = true
    }

    func go(to page: Int) {
        guard let document, let target = document.page(at: page) else { return }
        view?.go(to: target)
    }

    func findNext() {
        guard let document, !query.isEmpty else { return }
        if matches.isEmpty {
            matches = document.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            matchIndex = matches.isEmpty ? -2 : -1
        }
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + 1) % matches.count
        let match = matches[matchIndex]
        view?.setCurrentSelection(match, animate: true)
        view?.go(to: match)
    }
}

#if os(macOS)
    private struct PDFKitView: NSViewRepresentable {
        let model: PDFViewerModel

        func makeNSView(context: Context) -> PDFView {
            let view = PDFView()
            configure(view, coordinator: context.coordinator)
            return view
        }

        func updateNSView(_ view: PDFView, context: Context) {}

        func makeCoordinator() -> PageObserver { PageObserver(model: model) }
    }
#else
    private struct PDFKitView: UIViewRepresentable {
        let model: PDFViewerModel

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            configure(view, coordinator: context.coordinator)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}

        func makeCoordinator() -> PageObserver { PageObserver(model: model) }
    }
#endif

private func configure(_ view: PDFView, coordinator: PageObserver) {
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    view.autoScales = true
    #if os(macOS)
        view.backgroundColor = .clear
    #else
        view.backgroundColor = .clear
        view.usePageViewController(false)
    #endif
    coordinator.model.attach(view)
    NotificationCenter.default.addObserver(
        coordinator, selector: #selector(PageObserver.pageChanged), name: .PDFViewPageChanged, object: view)
}

/// Tells the model which page shows.
private final class PageObserver: NSObject {
    let model: PDFViewerModel

    init(model: PDFViewerModel) {
        self.model = model
    }

    @objc func pageChanged() {
        model.pageChanged()
    }
}

/// The thumbnail strip: one small page per row, the current one outlined; a click goes there.
private struct PDFThumbnails: View {
    let model: PDFViewerModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Spacing.s3) {
                    ForEach(0..<model.pageCount, id: \.self) { index in
                        Button {
                            model.go(to: index)
                        } label: {
                            VStack(spacing: Spacing.s1) {
                                PDFPageThumbnail(document: model.document, index: index)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: Radius.sm)
                                            .stroke(index + 1 == model.pageNumber ? Theme.ring : Theme.border, lineWidth: 1)
                                    }
                                Text(verbatim: "\(index + 1)").font(.hk(.x2s)).foregroundStyle(Theme.mutedForeground)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(index)
                    }
                }
                .padding(Spacing.s3)
            }
            .onChange(of: model.pageNumber) { _, page in proxy.scrollTo(page - 1, anchor: .center) }
        }
        .background(Theme.sidebar)
    }
}

private struct PDFPageThumbnail: View {
    let document: PDFDocument?
    let index: Int

    var body: some View {
        let width = Size.pdfThumbnails - Spacing.s6
        if let page = document?.page(at: index) {
            let bounds = page.bounds(for: .cropBox)
            let height = bounds.width > 0 ? width * bounds.height / bounds.width : width
            #if os(macOS)
                Image(nsImage: page.thumbnail(of: CGSize(width: width * 2, height: height * 2), for: .cropBox))
                    .resizable()
                    .frame(width: width, height: height)
            #else
                Image(uiImage: page.thumbnail(of: CGSize(width: width * 2, height: height * 2), for: .cropBox))
                    .resizable()
                    .frame(width: width, height: height)
            #endif
        }
    }
}

#Preview {
    PDFViewer(url: URL(filePath: "/System/Library/Desktop Pictures/.thumbnails/none.pdf"))
        .frame(width: 700, height: 500)
}
