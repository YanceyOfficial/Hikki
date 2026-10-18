#if os(iOS)
    import GameController
    import HikkiCore
    import HikkiUI
    import ObjectiveC
    import SwiftUI
    import WebKit

    /// The bar over the software keyboard (Notion's): one row of tools — with a caret, + · AI · @ · to-do · photo ·
    /// comment · Aa · link · indent · outdent · undo; with a selection, Aa · B · I · U · S · colour · AI · link ·
    /// comment. Tools that need no typing (+, Aa, colour) put their panel where the keyboard was, at its height
    /// (the web view's input view), and the end button brings the keyboard back; tools that need typing (AI, link)
    /// keep the keyboard and dock their field above the bar (the page's `touchOpen`).
    @MainActor @Observable
    final class KeyboardBar {
        enum Panel { case blocks, format }

        @ObservationIgnored weak var controller: EditorController?
        @ObservationIgnored weak var webView: HikkiWebView?
        private(set) var panel: Panel?
        private(set) var blocks: [KeyboardBlockSection] = []
        private(set) var turnInto: [KeyboardBlockItem] = []
        private(set) var state = EditorController.TouchState()
        /// The keyboard's height (without the bar) when it was last up: a panel takes the same, so the page stays put.
        @ObservationIgnored var keyboardHeight: CGFloat = 291
        /// With a hardware keyboard the system keeps the keyboard's area off screen, a panel in it too: the panel is a
        /// sheet of that height instead.
        @ObservationIgnored private weak var sheet: UIViewController?
        @ObservationIgnored private var observers: [NSObjectProtocol] = []

        init(controller: EditorController) {
            self.controller = controller
            let center = NotificationCenter.default
            observers.append(
                center.addObserver(forName: UIResponder.keyboardWillChangeFrameNotification, object: nil, queue: .main) {
                    [weak self] note in
                    let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
                    MainActor.assumeIsolated { self?.noteKeyboard(frame) }
                })
            observers.append(
                center.addObserver(forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main) {
                    [weak self] _ in
                    MainActor.assumeIsolated {
                        // The keyboard went away altogether (or the page lost the caret): no panel stays behind.
                        // (A panel shown as a sheet takes the focus by design.)
                        guard let self, self.panel != nil, self.sheet == nil else { return }
                        self.panel = nil
                        self.webView?.keyboardPanel = nil
                    }
                })
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        private func noteKeyboard(_ frame: CGRect?) {
            guard panel == nil, let frame, frame.height > KeyboardAccessoryBar<EmptyView>.height * 2 else { return }
            keyboardHeight = frame.height - KeyboardAccessoryBar<EmptyView>.height
        }

        func toggle(_ kind: Panel) {
            if panel == kind { closePanel() } else { Task { await open(kind) } }
        }

        func open(_ kind: Panel) async {
            guard let controller, let webView else { return }
            switch kind {
            case .blocks:
                blocks = await controller.touchBlockMenu()
            case .format:
                turnInto = await controller.touchTurnIntoMenu()
                await refresh()
            }
            let host = UIHostingController(rootView: KeyboardPanelView(bar: self))
            panel = kind
            if GCKeyboard.coalesced != nil, sheet == nil, let presenter = webView.window?.rootViewController?.topmostPresented {
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

        /// AI or link: the keyboard stays and the page docks the field above the bar.
        func openField(_ kind: String) {
            closePanel()
            Task { await controller?.touchOpen(kind) }
        }

        func insertBlock(_ id: String) {
            closePanel()
            Task { await controller?.touchInsertBlock(id) }
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
                    divider
                    tool("app:keyboard.askAI", .sparkle) { bar.openField("ai") }
                    tool("app:format.link", .link) { bar.openField("link") }
                    tool("app:keyboard.comment", .chatTeardropText) { bar.run("comment") }
                } else {
                    tool("app:keyboard.addBlock", .plus, isActive: bar.panel == .blocks) { bar.toggle(.blocks) }
                    tool("app:keyboard.askAI", .sparkle) { bar.openField("ai") }
                    tool("app:keyboard.mention", .at) { bar.run("mention") }
                    divider
                    tool("app:format.todoList", .checkSquare, isActive: on("taskList")) { bar.run("todo") }
                    tool("app:keyboard.photo", .image) { bar.insertBlock("image") }
                    tool("app:keyboard.comment", .chatTeardropText) { bar.run("comment") }
                    divider
                    tool("app:keyboard.format", .textAa, isActive: bar.panel == .format) { bar.toggle(.format) }
                    tool("app:format.link", .link) { bar.openField("link") }
                    tool("app:keyboard.indent", .textIndent) { bar.run("indent") }
                    tool("app:keyboard.outdent", .textOutdent) { bar.run("outdent") }
                    tool("app:format.undo", .arrowUUpLeft) { bar.run("undo") }
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

        private var divider: some View {
            Rectangle().fill(Theme.border).frame(width: Spacing.px, height: Spacing.s5).padding(.horizontal, Spacing.s1)
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
                case .format:
                    KeyboardFormatPanel(
                        marks: Set(bar.state.marks.compactMap(KeyboardFormatPanel.Mark.init(rawValue:))), turnInto: bar.turnInto,
                        block: bar.state.block, textColor: bar.state.textColor, backgroundColor: bar.state.backgroundColor,
                        onMark: { mark in mark == .link ? bar.openField("link") : bar.run(mark.rawValue) },
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

            guard let content = contentView else {
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
            contentView?.reloadInputViews()
        }

        private var contentView: UIView? {
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
            let accessory: @convention(block) (UIView) -> UIView? = { webView($0)?.keyboardToolbar }
            let input: @convention(block) (UIView) -> UIView? = { webView($0)?.keyboardPanel }
            class_addMethod(subclass, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(accessory), "@@:")
            class_addMethod(subclass, #selector(getter: UIResponder.inputView), imp_implementationWithBlock(input), "@@:")
            objc_registerClassPair(subclass)
            return subclass
        }
    }
#endif
