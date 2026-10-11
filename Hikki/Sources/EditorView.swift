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

    #if os(iOS)
        func makeUIView(context: Context) -> HikkiWebView { controller.webView }
        func updateUIView(_ view: HikkiWebView, context: Context) {
            // Set explicitly: WKWebView's scroll view didn't inset for the toolbar on its own (the cover's
            // buttons sat under the glass at rest).
            let scroll = view.scrollView
            guard scroll.contentInset.top != topInset else { return }
            scroll.contentInsetAdjustmentBehavior = .never
            scroll.contentInset.top = topInset
            scroll.verticalScrollIndicatorInsets.top = topInset
            if scroll.contentOffset.y <= 0 { scroll.contentOffset.y = -topInset }
        }
    #else
        func makeNSView(context: Context) -> HikkiWebView { controller.webView }
        func updateNSView(_ view: HikkiWebView, context: Context) {
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
    #endif
}
