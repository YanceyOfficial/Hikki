import SwiftUI
#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Shared color tokens. Mirrors the CSS variables in editor/src/style.css so native chrome and the
/// web editor read as one surface. Neutral warm greys (Notion-like) with a single blue accent.
public enum Theme {
    public static let background = dynamic(light: 0xFFFFFF, dark: 0x191919)
    public static let sidebar = dynamic(light: 0xF8F8F7, dark: 0x202020)
    public static let elevated = dynamic(light: 0xFFFFFF, dark: 0x252525)
    public static let text = dynamic(light: 0x37352F, dark: 0xFFFFFF, darkAlpha: 0.81)
    public static let secondaryText = dynamic(light: 0x37352F, lightAlpha: 0.65, dark: 0xFFFFFF, darkAlpha: 0.6)
    public static let mutedText = dynamic(light: 0x37352F, lightAlpha: 0.45, dark: 0xFFFFFF, darkAlpha: 0.443)
    public static let hover = dynamic(light: 0x37352F, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.055)
    public static let selected = dynamic(light: 0x37352F, lightAlpha: 0.08, dark: 0xFFFFFF, darkAlpha: 0.08)
    public static let border = dynamic(light: 0x37352F, lightAlpha: 0.09, dark: 0xFFFFFF, darkAlpha: 0.094)
    public static let accent = Color(red: 0x23 / 255, green: 0x83 / 255, blue: 0xE2 / 255)
    public static let danger = dynamic(light: 0xE03E3E, dark: 0xFF7369)

    public enum Metrics {
        public static let sidebarMinWidth: CGFloat = 240
        public static let sidebarIdealWidth: CGFloat = 264
        public static let sidebarMaxWidth: CGFloat = 400
        public static let rowHeight: CGFloat = 30
        public static let cornerRadius: CGFloat = 6
    }

    static func dynamic(light: UInt32, lightAlpha: Double = 1, dark: UInt32, darkAlpha: Double = 1) -> Color {
        #if os(iOS)
            Color(UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
            })
        #else
            Color(NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
            })
        #endif
    }
}

#if os(iOS)
    extension UIColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }
#else
    extension NSColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }
#endif
