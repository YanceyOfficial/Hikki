#if os(iOS)
    import HikkiCore
    import HikkiUI
    import ObjectiveC
    import SwiftUI
    import WebKit

    /// Editor formatting bar shown above the iPhone/iPad software keyboard.
    struct KeyboardToolbar: View {
        /// Weak: the bar lives in the controller's own web view, so a strong reference kept the editor (and its web
        /// process) alive after its window closed.
        weak var controller: EditorController?

        static let commands: [EditorCommand] = [
            .heading1, .heading2, .bold, .italic, .strike, .code,
            .bulletList, .orderedList, .taskList, .blockquote, .codeBlock, .undo, .redo,
        ]

        var body: some View {
            KeyboardAccessoryBar(onDismiss: dismiss) {
                ForEach(Self.commands) { command in
                    ToolbarIconButton(
                        LocalizedStringKey(command.title),
                        symbol: command.icon,
                        isActive: controller?.activeFormats.contains(command.rawValue) == true
                    ) {
                        controller?.exec(command)
                    }
                }
            }
        }

        private func dismiss() {
            controller?.dismissKeyboard()
        }
    }

    extension HikkiWebView {
        /// WebKit's first responder is the private WKContentView, not the WKWebView, so overriding
        /// `inputAccessoryView` on the web view has no effect. We give that one content view instance a
        /// runtime subclass whose `inputAccessoryView` returns our bar. No private API is called.
        func installKeyboardToolbar(controller: EditorController) {
            let host = UIHostingController(rootView: KeyboardToolbar(controller: controller))
            host.sizingOptions = .intrinsicContentSize
            host.view.backgroundColor = .clear
            host.view.frame = CGRect(x: 0, y: 0, width: 320, height: KeyboardAccessoryBar<EmptyView>.height)
            host.view.autoresizingMask = [.flexibleWidth]
            keyboardToolbar = host.view

            guard let content = scrollView.subviews.first(where: { NSStringFromClass(type(of: $0)).hasPrefix("WKContent") }) else {
                Log.warn("keyboard toolbar: WKContentView not found", category: "ui")
                return
            }
            guard let subclass = Self.accessorySubclass(of: type(of: content)) else {
                Log.warn("keyboard toolbar: could not create subclass", category: "ui")
                return
            }
            object_setClass(content, subclass)
        }

        private static func accessorySubclass(of base: AnyClass) -> AnyClass? {
            let name = "Hikki_\(NSStringFromClass(base))"
            if let existing = NSClassFromString(name) { return existing }
            guard let subclass = objc_allocateClassPair(base, name, 0) else { return nil }
            let getter: @convention(block) (UIView) -> UIView? = { view in
                var ancestor = view.superview
                while let current = ancestor, !(current is HikkiWebView) { ancestor = current.superview }
                return (ancestor as? HikkiWebView)?.keyboardToolbar
            }
            class_addMethod(subclass, #selector(getter: UIResponder.inputAccessoryView), imp_implementationWithBlock(getter), "@@:")
            objc_registerClassPair(subclass)
            return subclass
        }
    }
#endif
