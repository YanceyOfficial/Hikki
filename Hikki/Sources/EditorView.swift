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

    #if os(iOS)
        func makeUIView(context: Context) -> HikkiWebView { controller.webView }
        func updateUIView(_ view: HikkiWebView, context: Context) {}
    #else
        func makeNSView(context: Context) -> HikkiWebView { controller.webView }
        func updateNSView(_ view: HikkiWebView, context: Context) {}
    #endif
}

final class HikkiWebView: WKWebView {
    #if os(iOS)
        /// Shown above the software keyboard instead of WebKit's default ⌃⌄ Done bar.
        var keyboardToolbar: UIView?
    #endif
}
