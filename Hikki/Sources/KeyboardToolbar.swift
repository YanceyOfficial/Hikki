#if os(iOS)
    import HikkiCore
    import HikkiUI
    import ObjectiveC
    import SwiftUI
    import UniformTypeIdentifiers
    import WebKit

    /// The bar over the software keyboard (Notion's): one glass capsule of tools — with a caret, AI · + · Aa · file ·
    /// photo · turn into · undo · emoji · comment, then (scrolled) @ · delete · indent · outdent · move up · move down ·
    /// ⋯; with a selection, Aa · B · I · U · S · colour · AI · link · comment · ⋯. Tools that need no typing (+, Aa,
    /// turn into, colour) put their panel where the keyboard was, at its height (the web view's input view), and the
    /// end button brings the keyboard back; AI and link open a native field over the keyboard (`composer`, drawn by
    /// the page screen), ⋯ the block's actions as a sheet (`blockActions`).
    @MainActor @Observable
    final class KeyboardBar {
        enum Panel { case blocks, format, turnInto }

        /// The native field over the keyboard for AI or a link, on the words `touchPrepare` selected — or a comment,
        /// on the selection or the caret's block (`commentScope`).
        struct Composer: Identifiable, Equatable {
            enum Kind { case ai, link, comment }
            let id = UUID()
            var kind: Kind
            var quote: String
            var href: String?
            var presets: [AIComposerPreset]
            var commentScope = "selection"
        }

        @ObservationIgnored weak var controller: EditorController?
        @ObservationIgnored weak var webView: HikkiWebView?
        private(set) var panel: Panel?
        private(set) var blocks: [KeyboardBlockSection] = []
        private(set) var turnInto: [KeyboardBlockItem] = []
        private(set) var state = EditorController.TouchState()
        private(set) var composer: Composer?
        /// The ⋯ sheet's block (nil: closed); the page screen presents it.
        var blockActions: BlockActionsInfo?
        /// The photo / file sheet is open (`MediaPickerSheet`, presented by the page screen).
        var mediaSheet = false
        /// The keyboard's height (without the bar) when it was last up: a panel takes the same, so the page stays put.
        @ObservationIgnored var keyboardHeight: CGFloat = 291
        /// With a hardware keyboard the system keeps the keyboard's area off screen, a panel in it too: the panel is a
        /// sheet of that height instead.
        @ObservationIgnored private weak var sheet: UIViewController?
        @ObservationIgnored private var observers: [NSObjectProtocol] = []
        /// The next time the keyboard goes away, the page's selection stays (an AI edit under review on it).
        @ObservationIgnored private var keepSelectionOnHide = false

        init(controller: EditorController) {
            self.controller = controller
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.keyboardWentAway() }
                })
            // A keyboard back up (the page's, after a field) means no hide is still to come for the flag.
            observers.append(
                NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.composer == nil else { return }
                        self.keepSelectionOnHide = false
                    }
                })
        }

        /// The keyboard went away altogether — the bar's button, a swipe, a tap elsewhere — or only seemed to:
        /// swapping it for a panel or a native field may post a hide of its own, so this acts only once the page has
        /// let go of the caret. No panel stays behind (one shown as a sheet takes the focus by design), and no
        /// selection: WebKit would keep painting it, greyed out, with nothing to act on it (Notion's).
        private func keyboardWentAway() {
            guard webView?.editingContent?.isFirstResponder != true, sheet == nil else { return }
            if panel != nil {
                panel = nil
                webView?.keyboardPanel = nil
            }
            guard composer == nil, blockActions == nil, !mediaSheet else { return }
            if keepSelectionOnHide {
                keepSelectionOnHide = false
                return
            }
            controller?.collapseSelection()
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        /// The software keyboard's height under the bar, read from where the bar is now; nil when there is none (a
        /// hardware keyboard keeps only the bar up, at the screen's foot). The keyboard's frame notifications were
        /// tried first and misled on a phone (the panel then opened as a sheet hidden behind the keyboard); neither
        /// is `GCKeyboard` an answer — a keyboard attached doesn't mean the software one is hidden.
        private func keyboardUnderBar() -> CGFloat? {
            guard let bar = webView?.keyboardToolbar, let window = bar.window else { return nil }
            let screen = window.screen
            let below = screen.bounds.maxY - bar.convert(bar.bounds, to: screen.coordinateSpace).maxY
            return below > KeyboardAccessoryBar<EmptyView>.height * 2 ? below : nil
        }

        func toggle(_ kind: Panel) {
            if panel == kind { closePanel() } else { Task { await open(kind) } }
        }

        func open(_ kind: Panel) async {
            guard let controller, let webView else { return }
            switch kind {
            case .blocks:
                blocks = await controller.touchBlockMenu()
            case .format, .turnInto:
                turnInto = await controller.touchTurnIntoMenu()
                await refresh()
            }
            let host = UIHostingController(rootView: KeyboardPanelView(bar: self))
            // Measured before the panel takes the keyboard's place (then the bar sits on the panel).
            let software = panel == nil ? keyboardUnderBar() : keyboardHeight
            if let software { keyboardHeight = software }
            panel = kind
            if software == nil, sheet == nil, let presenter = webView.window?.rootViewController?.topmostPresented {
                host.sheetPresentationController?.detents = [.custom { [height = keyboardHeight] _ in height }]
                host.sheetPresentationController?.prefersGrabberVisible = true
                host.presentationController?.delegate = sheetDelegate
                sheet = host
                presenter.present(host, animated: true)
                return
            }
            guard sheet == nil else { return }
            host.view.frame = CGRect(x: 0, y: 0, width: webView.bounds.width, height: keyboardHeight)
            host.view.autoresizingMask = [.flexibleWidth]
            webView.keyboardPanel = host.view
            webView.reloadKeyboardViews()
        }

        @ObservationIgnored private lazy var sheetDelegate = SheetDelegate { [weak self] in self?.panel = nil }

        /// Back to typing, the caret where it was.
        func closePanel() {
            guard panel != nil else { return }
            panel = nil
            if let sheet {
                sheet.dismiss(animated: true)
                self.sheet = nil
                return
            }
            webView?.keyboardPanel = nil
            webView?.reloadKeyboardViews()
        }

        /// The keyboard (or panel) goes away altogether.
        func dismiss() {
            closePanel()
            controller?.dismissKeyboard()
        }

        func refresh() async {
            if let state = await controller?.touchState() { self.state = state }
        }

        // MARK: Tools

        func run(_ tool: String) {
            Task {
                await controller?.touchRun(tool)
                await refresh()
            }
        }

        /// AI or link: a native field over the keyboard, on the selection (or the word at the caret, which the page
        /// selects). It takes the keyboard; the page keeps painting its selection meanwhile.
        func openField(_ kind: Composer.Kind) {
            closePanel()
            keepSelectionOnHide = false
            Task {
                guard let target = await controller?.touchPrepare() else { return }
                webView?.dismissEditMenu()
                composer = Composer(kind: kind, quote: target.quote, href: target.href, presets: target.presets)
            }
        }

        /// Comment: a native field over the keyboard on the selection, or else (and from the ⋯ sheet) the caret's
        /// block. The page's own comment sheet stays shut: its field taking focus scrolled the page away.
        func openComment(block: Bool = false) {
            closePanel()
            keepSelectionOnHide = false
            let scope = block ? "block" : "selection"
            Task {
                guard let quote = await controller?.touchCommentQuote(scope) else { return }
                webView?.dismissEditMenu()
                composer = Composer(kind: .comment, quote: quote, href: nil, presets: [], commentScope: scope)
            }
        }

        func sendComment(_ body: String) {
            guard let scope = composer?.commentScope else { return }
            composer = nil
            Task { await controller?.touchComment(scope: scope, body: body) }
        }

        /// ✕ on a field: back to the page's keyboard, its selection as it was (the field's keyboard going down first
        /// leaves the selection be).
        func closeComposer() {
            composer = nil
            keepSelectionOnHide = true
            controller?.focusBody()
        }

        /// The composer's request: a preset (its id) or the user's own words.
        func sendAI(preset: String? = nil, instruction: String? = nil) {
            composer = nil
            // The edit is shown on the selection: the keyboard going down with the field leaves it be.
            keepSelectionOnHide = true
            Task { await controller?.touchAI(id: preset ?? "custom", instruction: preset == nil ? instruction : nil) }
        }

        func setLink(_ href: String?) {
            composer = nil
            Task { await controller?.touchLink(href) }
        }

        /// ⋯: the block at the caret's actions, as a sheet over the page (the keyboard goes down).
        func openBlockActions() {
            closePanel()
            Task {
                guard let controller, let info = await controller.touchBlockInfo() else { return }
                let items = info.turnInto == nil ? [] : await controller.touchTurnIntoMenu()
                let link = await controller.touchBlockLink() != nil
                blockActions = BlockActionsInfo(
                    kind: info.kind, turnInto: info.turnInto, turnIntoItems: items, textColor: info.textColor,
                    backgroundColor: info.backgroundColor, colorable: info.colorable, copyLink: link, comment: info.comment,
                    askAI: info.ai, words: info.words, characters: info.characters,
                    moveTargets: info.movable ? controller.moveTargets() : [])
                webView?.endEditing(true)
            }
        }

        func runBlockAction(_ action: BlockAction) {
            Task {
                guard let controller else { return }
                switch action {
                case .copyLink:
                    guard let link = await controller.touchBlockLink() else { return }
                    Self.copyLink(href: link.href, label: link.label)
                    Toasts.shared.show(.success, String(localized: "app:blockActions.linkCopied"))
                case .askAI:
                    await controller.touchBlockAction("selectText")
                    openField(.ai)
                case .comment:
                    openComment(block: true)
                case .insertBelow, .duplicate, .delete:
                    await controller.touchBlockAction(action.rawValue)
                }
            }
        }

        /// A ready hyperlink (the block's text) plus the URL, as the page's own Copy link puts them: pasted into a
        /// page it lands as a link, anywhere else as the address.
        private static func copyLink(href: String, label: String) {
            let text = label.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let attribute = href.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;")
            var item: [String: Any] = [
                UTType.html.identifier: "<a href=\"\(attribute)\">\(text)</a>", UTType.utf8PlainText.identifier: href,
            ]
            if let url = URL(string: href) { item[UTType.url.identifier] = url }
            UIPasteboard.general.setItems([item])
        }

        func setBlockColor(_ kind: KeyboardFormatPanel.ColorKind, _ color: String?) {
            Task { await controller?.touchBlockColor(kind, color) }
        }

        /// A block from "+"; pictures, video, audio and files come through the photo / file sheet instead of the
        /// page's file input.
        func insertBlock(_ id: String) {
            if Self.mediaBlocks.contains(id) { return openMedia() }
            closePanel()
            Task { await controller?.touchInsertBlock(id) }
        }

        private static let mediaBlocks: Set<String> = ["image", "video", "audio", "file"]

        /// Photo and file: our own sheet of sources (camera, Photos, Files, scan); what is picked goes in at the caret.
        func openMedia() {
            closePanel()
            mediaSheet = true
            webView?.endEditing(true)
        }

        func insertMedia(_ picked: [PickedMedia]) {
            mediaSheet = false
            Task { await controller?.insertMedia(picked) }
        }

        func moveBlock(to target: String) {
            blockActions = nil
            Task { await controller?.touchMoveBlock(to: target) }
        }

        func turnInto(_ id: String) {
            Task {
                await controller?.touchTurnInto(id)
                await refresh()
            }
        }

        func setColor(_ kind: KeyboardFormatPanel.ColorKind, _ color: String?) {
            Task {
                await controller?.touchSetColor(kind, color)
                await refresh()
            }
        }
    }

    /// A panel's sheet swiped away: the bar's tool is no longer pressed.
    private final class SheetDelegate: NSObject, UIAdaptivePresentationControllerDelegate {
        let onDismiss: () -> Void
        init(onDismiss: @escaping () -> Void) { self.onDismiss = onDismiss }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onDismiss() }
    }

    extension UIViewController {
        /// The controller on top of everything this one presents.
        fileprivate var topmostPresented: UIViewController {
            presentedViewController?.topmostPresented ?? self
        }
    }

    /// The bar's row of tools (see `KeyboardBar`).
    struct KeyboardToolbar: View {
        let bar: KeyboardBar

        private var selecting: Bool { bar.controller?.selection != nil }
        private func on(_ format: String) -> Bool { bar.controller?.activeFormats.contains(format) == true }
        private func marked(_ mark: String) -> Bool { bar.state.marks.contains(mark) }

        var body: some View {
            KeyboardAccessoryBar(panelOpen: bar.panel != nil, onDismiss: { bar.panel == nil ? bar.dismiss() : bar.closePanel() }) {
                if selecting {
                    tool("app:keyboard.format", .textAa, isActive: bar.panel == .format) { bar.toggle(.format) }
                    tool("app:format.bold", .textB, isActive: marked("bold")) { bar.run("bold") }
                    tool("app:format.italic", .textItalic, isActive: marked("italic")) { bar.run("italic") }
                    tool("app:format.underline", .textUnderline, isActive: marked("underline")) { bar.run("underline") }
                    tool("app:format.strikethrough", .textStrikethrough, isActive: marked("strike")) { bar.run("strike") }
                    tool("app:keyboard.color", .textAUnderline) { bar.toggle(.format) }
                    tool("app:keyboard.askAI", .sparkle) { bar.openField(.ai) }
                    tool("app:format.link", .link) { bar.openField(.link) }
                    tool("app:keyboard.comment", .chatTeardropText) { bar.openComment() }
                    tool("app:keyboard.more", .dotsThree) { bar.openBlockActions() }
                } else {
                    // Notion's order: what a line becomes first, then the block's own moves after a scroll.
                    tool("app:keyboard.askAI", .sparkle) { bar.openField(.ai) }
                    tool("app:keyboard.addBlock", .plus, isActive: bar.panel == .blocks) { bar.toggle(.blocks) }
                    tool("app:keyboard.format", .textAa, isActive: bar.panel == .format) { bar.toggle(.format) }
                    tool("app:keyboard.file", .paperclip) { bar.openMedia() }
                    tool("app:keyboard.photo", .image) { bar.openMedia() }
                    tool("app:keyboard.turnInto", .arrowsClockwise, isActive: bar.panel == .turnInto) { bar.toggle(.turnInto) }
                    tool("app:format.undo", .arrowUUpLeft) { bar.run("undo") }
                    tool("app:keyboard.emoji", .smiley) { bar.run("emoji") }
                    tool("app:keyboard.comment", .chatTeardropText) { bar.openComment() }
                    tool("app:keyboard.mention", .at) { bar.run("mention") }
                    tool("app:keyboard.deleteBlock", .trash) { bar.run("delete") }
                    tool("app:keyboard.indent", .textIndent) { bar.run("indent") }
                    tool("app:keyboard.outdent", .textOutdent) { bar.run("outdent") }
                    tool("app:shortcut.moveBlockUp", .arrowUp) { bar.run("moveUp") }
                    tool("app:shortcut.moveBlockDown", .arrowDown) { bar.run("moveDown") }
                    tool("app:keyboard.more", .dotsThree) { bar.openBlockActions() }
                }
            }
            // A selection made or cleared: the marks the panel shows follow.
            .task(id: bar.controller?.selection) { await bar.refresh() }
        }

        private func tool(_ title: LocalizedStringKey, _ icon: Icon, isActive: Bool = false, action: @escaping () -> Void)
            -> some View
        {
            ToolbarIconButton(title, symbol: icon, isActive: isActive, action: action)
        }
    }

    /// The panel in the keyboard's place. A swipe down closes it, and the keyboard with it.
    struct KeyboardPanelView: View {
        let bar: KeyboardBar

        var body: some View {
            Group {
                switch bar.panel {
                case .blocks:
                    KeyboardBlockPanel(sections: bar.blocks, onPick: bar.insertBlock)
                case .turnInto:
                    KeyboardBlockPanel(
                        sections: [.init(id: "turnInto", title: String(localized: "app:keyboard.turnInto"), items: bar.turnInto)],
                        current: bar.state.block,
                        onPick: { id in
                            bar.turnInto(id)
                            bar.closePanel()
                        })
                case .format:
                    KeyboardFormatPanel(
                        marks: Set(bar.state.marks.compactMap(KeyboardFormatPanel.Mark.init(rawValue:))), turnInto: bar.turnInto,
                        block: bar.state.block, textColor: bar.state.textColor, backgroundColor: bar.state.backgroundColor,
                        onMark: { mark in mark == .link ? bar.openField(.link) : bar.run(mark.rawValue) },
                        onTurnInto: bar.turnInto(_:), onColor: bar.setColor)
                case nil:
                    Color.clear
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: Spacing.s6).onEnded { drag in
                    if drag.translation.height > Spacing.s16, abs(drag.translation.width) < drag.translation.height { bar.dismiss() }
                })
        }
    }

    extension HikkiWebView {
        /// WebKit's first responder is the private WKContentView, not the WKWebView, so overriding
        /// `inputAccessoryView` / `inputView` on the web view has no effect. We give that one content view instance a
        /// runtime subclass whose `inputAccessoryView` returns our bar and whose `inputView` returns the open panel (nil:
        /// the system keyboard). No private API is called.
        func installKeyboardToolbar(controller: EditorController) {
            let bar = KeyboardBar(controller: controller)
            bar.webView = self
            keyboardBar = bar
            let host = UIHostingController(rootView: KeyboardToolbar(bar: bar))
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: KeyboardAccessoryBar<EmptyView>.height)
            host.view.autoresizingMask = [.flexibleWidth]
            keyboardToolbar = host.view

            guard let content = editingContent else {
                Log.warn("keyboard toolbar: WKContentView not found", category: "ui")
                return
            }
            guard let subclass = Self.accessorySubclass(of: type(of: content)) else {
                Log.warn("keyboard toolbar: could not create subclass", category: "ui")
                return
            }
            object_setClass(content, subclass)
        }

        /// The keyboard swaps for the panel (or back), the caret staying put.
        func reloadKeyboardViews() {
            editingContent?.reloadInputViews()
        }

        /// WebKit's Cut / Copy / Paste menu goes away: a native field over the keyboard leaves it hanging over the page.
        func dismissEditMenu() {
            // WebKit hangs the interaction on one of its content view's subviews, not on the content view itself.
            func dismiss(in view: UIView) {
                for case let menu as UIEditMenuInteraction in view.interactions { menu.dismissMenu() }
                view.subviews.forEach(dismiss)
            }
            dismiss(in: self)
        }

        /// WebKit's content view: the first responder while the page is edited.
        var editingContent: UIView? {
            scrollView.subviews.first { NSStringFromClass(type(of: $0)).hasPrefix("WKContent") }
        }

        private static func accessorySubclass(of base: AnyClass) -> AnyClass? {
            let name = "Hikki_\(NSStringFromClass(base))"
            if let existing = NSClassFromString(name) { return existing }
            guard let subclass = objc_allocateClassPair(base, name, 0) else { return nil }
            let webView: (UIView) -> HikkiWebView? = { view in
                var ancestor = view.superview
                while let current = ancestor, !(current is HikkiWebView) { ancestor = current.superview }
                return ancestor as? HikkiWebView
            }
            let accessory: @convention(block) (UIView) -> UIView? = { view in
                guard let webView = webView(view), !webView.hidesKeyboardBar else { return nil }
                return webView.keyboardToolbar
            }
            let input: @convention(block) (UIView) -> UIView? = { webView($0)?.keyboardPanel }
            class_addMethod(subclass, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(accessory), "@@:")
            class_addMethod(subclass, #selector(getter: UIResponder.inputView), imp_implementationWithBlock(input), "@@:")
            objc_registerClassPair(subclass)
            return subclass
        }
    }
#endif
