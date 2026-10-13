import Foundation

/// What the web view does with a navigation it is asked about.
public enum NavigationDecision: Equatable, Sendable {
    /// Load it where it was asked for.
    case load
    /// Hand the URL to the system (a link the user clicked).
    case openOutside
    case cancel
}

/// Decides which navigations the editor's web view may perform. Only the bundled editor loads as the page, and only
/// as the page: an embed's frame may show an https page or a sandboxed snippet (`about:srcdoc`), never the editor
/// itself — a frame on the editor's own scheme would be same-origin with the page around it and could reach its
/// DOM, scripts and bridge. Anything else a clicked link asked for goes to the system; the rest is dropped.
public enum EditorNavigationPolicy {
    /// `isMainFrame` is nil when the navigation has no target frame yet (a new window).
    public static func decide(url: URL?, isMainFrame: Bool?, isLinkClick: Bool, editorScheme: String) -> NavigationDecision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if scheme == editorScheme.lowercased() {
            return url.host == "app" && isMainFrame == true ? .load : .cancel
        }
        if isMainFrame == false, scheme == "https" || scheme == "about" {
            return .load
        }
        return isLinkClick ? .openOutside : .cancel
    }
}
