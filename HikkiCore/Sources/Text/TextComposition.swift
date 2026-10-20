#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Whether the focused text field is mid-composition — an input method (Japanese, Chinese…) holding marked text
/// whose candidates the arrow keys, Return and Escape belong to. Lists that move with the arrow keys (⌘K search, the
/// @ page list) leave the keys alone meanwhile.
public enum TextComposition {
    #if canImport(AppKit)
        /// `responder`: the focused field's editor (a SwiftUI text field's first responder is its NSTextView).
        public static func isComposing(_ responder: Any?) -> Bool {
            (responder as? NSTextInputClient)?.hasMarkedText() ?? false
        }

        @MainActor public static var isActive: Bool { isComposing(NSApp.keyWindow?.firstResponder) }
    #elseif canImport(UIKit)
        @MainActor public static func isComposing(_ responder: Any?) -> Bool {
            (responder as? UITextInput)?.markedTextRange != nil
        }

        @MainActor public static var isActive: Bool {
            FirstResponder.current = nil
            UIApplication.shared.sendAction(#selector(UIResponder.hk_noteFirstResponder), to: nil, from: nil, for: nil)
            defer { FirstResponder.current = nil }
            return isComposing(FirstResponder.current)
        }
    #endif
}

#if canImport(UIKit) && !canImport(AppKit)
    @MainActor private enum FirstResponder {
        static weak var current: UIResponder?
    }

    extension UIResponder {
        /// Sent to nil: the first responder answers (the usual way to find it on iOS).
        @MainActor @objc fileprivate func hk_noteFirstResponder() { FirstResponder.current = self }
    }
#endif
