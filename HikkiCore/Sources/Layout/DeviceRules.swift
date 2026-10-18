import CoreGraphics

/// Every rule that makes Hikki behave differently on one device than another, in one place. `#if os(...)` in the code
/// only separates the Mac from iOS (compile time); everything below is decided at run time, from the screen or the
/// window, never from the device's name or idiom (Apple's "Preparing your app for iPhone Duo").
///
/// | Device                          | Orientation | Layout (by window width) | Split view      | Vertical bar |
/// |---------------------------------|-------------|--------------------------|-----------------|--------------|
/// | iPhone                          | portrait    | iPhone (compact)         | no              | —            |
/// | iPhone Duo, folded              | portrait    | iPhone (compact)         | no              | yes          |
/// | iPhone Duo, unfolded            | landscape   | iPad (regular)           | if ≥ 800 pt     | yes          |
/// | iPad (mini to 13")              | landscape   | iPad (regular)           | if ≥ 800 pt     | —            |
/// | Mac                             | any         | iPad (regular)           | yes             | —            |
///
/// Where the system has a vertical bar (iOS 27.1's `toolbarVerticalEdge`, read once in `RootView`): the iPhone's
/// floating bar and top bar hand their buttons to it, the page runs under it, top bars keep `topEdgeClearance` from the
/// screen's top edge, and it hides while one of the page's bottom sheets is open. The web editor's own touch rules are
/// in `apps/editor/src/lib/device.ts`.
public enum DeviceRules {
    // MARK: Orientation

    public enum Orientation: Equatable, Sendable { case portrait, landscape }

    /// The shorter side, in points, from which a screen is tablet-sized (phones top out near 440; an unfolded Duo is
    /// 669, iPad mini 744).
    public static let tabletShortSide: CGFloat = 600

    /// Which way the window may turn on this screen: a phone-sized one upright, a tablet-sized one on its side.
    public static func orientation(screen: CGSize) -> Orientation {
        min(screen.width, screen.height) >= tabletShortSide ? .landscape : .portrait
    }

    // MARK: Split view

    /// The window width, in points, two pages side by side need.
    public static let splitMinimumWidth: CGFloat = 800

    public static func allowsSplit(windowWidth: CGFloat) -> Bool {
        windowWidth >= splitMinimumWidth
    }

    // MARK: Vertical bar (an iPhone Duo)

    /// How far top bars keep from the screen's top edge where the safe area doesn't (the Duo's status bar sits beside
    /// the camera, so its top inset is a few points and a button there is in the system's swipe-down zone).
    public static let topEdgeClearance: CGFloat = 24

    /// Whether the system's bars step aside while a bottom sheet of the page's is open: only where they would sit over
    /// the sheet (a vertical bar beside it); elsewhere they stay.
    public static func sheetHidesBars(hasVerticalBar: Bool) -> Bool { hasVerticalBar }
}
