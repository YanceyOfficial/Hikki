import CoreGraphics

/// Where the in-app split view (two panes side by side) is offered: a window wide enough for two pages and the
/// toolbar, on any device — an 11-inch iPad upright, any iPad on its side, an unfolded iPhone Duo, the Mac. Decided by
/// the window's own width, not the device (Apple's "Preparing your app for iPhone Duo": no idiom or screen checks), so
/// a narrow Stage Manager window or iPad mini upright doesn't split.
public enum SplitPolicy {
    /// The window width, in points, two pages need (iPad mini upright is 744; an 11-inch iPad upright 820 and up).
    public static let minimumWidth: CGFloat = 800

    public static func allowed(windowWidth: CGFloat) -> Bool {
        windowWidth >= minimumWidth
    }
}
