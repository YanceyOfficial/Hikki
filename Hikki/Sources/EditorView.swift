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
        func makeUIView(context: Context) -> HikkiWebView { controller.webView }
        func updateUIView(_ view: HikkiWebView, context: Context) {
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
    #endif
}
