import SwiftUI
import WebKit

#if os(iOS)
    typealias PlatformViewRepresentable = UIViewRepresentable
#else
    typealias PlatformViewRepresentable = NSViewRepresentable
#endif

/// Hosts the controller's single web view; SwiftUI may recreate this wrapper freely.
struct EditorView: PlatformViewRepresentable {
    let controller: EditorController
    /// Height of the toolbar the page scrolls under: the content starts below it and passes beneath the
    /// Liquid Glass when scrolled (Photos).
    var topInset: CGFloat = 0
    /// Height of a native bar floating over the page's foot (iPhone): bottom sheets in the page stay clear of it.
    var bottomInset: CGFloat = 0

    #if os(iOS)
        /// A container of its own, the web view put back into it on every update: SwiftUI may build this wrapper
        /// again (a side of the window rebuilt as it splits), and an older wrapper going away took the window's one
        /// web view out of the newer one with it — a blank page (seen under XCUITest on iPad).
        func makeUIView(context: Context) -> UIView { UIView() }
        func updateUIView(_ host: UIView, context: Context) {
            let view = controller.webView!
            if view.superview !== host {
                view.frame = host.bounds
                view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                host.addSubview(view)
            }
            // The page runs to the top of the screen and makes the toolbar's room itself (`bleed`): a cover fills
            // it behind the status bar and the glass buttons (immersive), a page without one starts below them.
            controller.setInsets(top: topInset, bottom: bottomInset, bleed: true)
            let scroll = view.scrollView
            scroll.contentInsetAdjustmentBehavior = .never
            guard scroll.contentInset.top != 0 else { return }
            scroll.contentInset.top = 0
            scroll.verticalScrollIndicatorInsets.top = topInset
        }
    #else
        func makeNSView(context: Context) -> HikkiWebView { controller.webView }
        func updateNSView(_ view: HikkiWebView, context: Context) {
            // The obscured inset alone: WebKit already lays fixed-position content (the find panel) out
            // below it, so telling the page the height as well pushed the panel down twice.
            if view.obscuredContentInsets.top != topInset {
                view.obscuredContentInsets = NSEdgeInsets(top: topInset, left: 0, bottom: 0, right: 0)
            }
        }
    #endif
}

final class HikkiWebView: WKWebView {
    #if os(iOS)
        /// Shown above the software keyboard instead of WebKit's default ⌃⌄ Done bar.
        var keyboardToolbar: UIView?
        /// A panel of the bar's in the keyboard's place (nil: the keyboard).
        var keyboardPanel: UIView?
        /// The bar's state (its panels, what the page reports for them).
        var keyboardBar: KeyboardBar?
        /// Something of its own covers the page (a drawing's editor): the keyboard comes without our bar, whose tools
        /// act on the page under it.
        var hidesKeyboardBar = false {
            didSet {
                guard hidesKeyboardBar != oldValue else { return }
                if hidesKeyboardBar { keyboardBar?.closePanel() }
                reloadKeyboardViews()
            }
        }
        /// Placed in a window (the page may already be up by then, and told nothing of its screen).
        var onMoveToWindow: (() -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { onMoveToWindow?() }
        }
    #endif
}
