import SwiftUI

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Design tokens live in design/tokens.json; colors are generated into Generated/DesignTokens.swift
/// (shadcn/ui semantic names: `Theme.background`, `Theme.mutedForeground`, `Theme.sidebarAccent`…).
///
/// `nonisolated`: UIKit/AppKit resolve dynamic colors on SwiftUI's async render thread. With the
/// module's default MainActor isolation the provider closures trapped there (EXC_BREAKPOINT in
/// `_swift_task_checkIsolatedSwift`, seen on iPad).
public nonisolated enum Theme {
    /// What a system table or list draws behind its rows (Home's and Trash's tables): screens built around one use it
    /// whole, so their header and the rows read as one surface.
    public static var listSurface: Color {
        #if os(macOS)
            Color(nsColor: .controlBackgroundColor)
        #else
            Color(uiColor: .systemBackground)
        #endif
    }

    static func dynamic(light: UInt32, lightAlpha: Double, dark: UInt32, darkAlpha: Double) -> Color {
        #if os(iOS)
            Color(
                UIColor { @Sendable traits in
                    traits.userInterfaceStyle == .dark ? UIColor(hex: dark, alpha: darkAlpha) : UIColor(hex: light, alpha: lightAlpha)
                })
        #else
            Color(
                NSColor(name: nil) { @Sendable appearance in
                    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                        ? NSColor(hex: dark, alpha: darkAlpha) : NSColor(hex: light, alpha: lightAlpha)
                })
        #endif
    }
}

extension Font {
    /// Token-sized system font: `.font(.hk(.xs, .medium))`. On iOS the size follows the system text size (Dynamic
    /// Type, as the Body style scales — 1× at the default size); the Mac has one size.
    public static func hk(_ size: TextSize, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: TextSize.scaled(size.rawValue), weight: weight, design: design)  // design-lint: allow
    }
}

extension TextSize {
    /// A token size as the system text size scales it (iOS: Body's metrics; the Mac: as is).
    public static func scaled(_ points: CGFloat) -> CGFloat {
        #if os(iOS)
            UIFontMetrics(forTextStyle: .body).scaledValue(for: points)
        #else
            points
        #endif
    }

    /// The factor the system text size puts on text (1 at the default size): what the page takes for its own words.
    public static var scale: CGFloat { scaled(TextSize.lg.rawValue) / TextSize.lg.rawValue }
}

#if os(iOS)
    nonisolated extension UIColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(
                red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
        }
    }
#else
    nonisolated extension NSColor {
        convenience init(hex: UInt32, alpha: Double) {
            self.init(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
        }
    }
#endif
