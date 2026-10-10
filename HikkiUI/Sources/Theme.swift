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
    /// Token-sized system font: `.font(.hk(.xs, .medium))`.
    public static func hk(_ size: TextSize, _ weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size.rawValue, weight: weight, design: design)  // design-lint: allow
    }
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
