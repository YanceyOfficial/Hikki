import CoreGraphics

/// Which layout an iPhone gets. A regular width alone made a phone use the iPad layout (sidebar, tabs in the
/// toolbar), which doesn't fit a phone's hand or its screen: an unfolded iPhone Duo held upright, or a large iPhone
/// on its side. A phone keeps the iPad layout only unfolded and on its side — wider than tall with a regular height,
/// an iPad mini's shape; everything else is the iPhone's own layout (Home, the drawer, the floating bar).
public enum PhoneLayout {
    /// Whether the window's regular width should read as compact (the iPhone layout).
    public static func forcesCompact(
        isPhone: Bool, horizontalRegular: Bool, verticalRegular: Bool, size: CGSize
    ) -> Bool {
        guard isPhone, horizontalRegular else { return false }
        let tabletShaped = verticalRegular && size.width > size.height
        return !tabletShaped
    }
}

/// Where the in-app split view (two panes side by side) is offered: the Mac and the larger iPads. A small iPad
/// (iPad mini) or a phone — an unfolded iPhone Duo included — has no room for two pages and the toolbar.
public enum SplitPolicy {
    /// The shorter side of the screen, in points, a device needs (iPad mini: 744; the 11-inch iPads: 820 and up).
    public static let minimumShortSide: CGFloat = 800

    public static func allowed(isPad: Bool, screenShortSide: CGFloat) -> Bool {
        isPad && screenShortSide >= minimumShortSide
    }
}
