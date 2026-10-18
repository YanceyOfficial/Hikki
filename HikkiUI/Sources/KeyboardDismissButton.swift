import SwiftUI

/// Round glass "hide keyboard" button. In a multi-line editor Return inserts a newline, so without it
/// the only way out of the keyboard is a gesture people don't find. With a panel in the keyboard's place
/// (`showsKeyboard`), it brings the keyboard back instead.
public struct KeyboardDismissButton: View {
    private let showsKeyboard: Bool
    private let action: () -> Void

    public init(showsKeyboard: Bool = false, action: @escaping () -> Void) {
        self.showsKeyboard = showsKeyboard
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel(
                showsKeyboard ? "app:keyboard.show" : "app:keyboard.hide", icon: showsKeyboard ? .keyboardFill : .keyboard,
                size: TextSize.base.rawValue
            )
            .labelStyle(.iconOnly)
            // The keyboard glyph is wider than the formatting icons; at full scale its circle would dominate the bar.
            .imageScale(.small)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier(showsKeyboard ? "show-keyboard" : "hide-keyboard")
    }
}

#Preview {
    KeyboardDismissButton {}
        .padding()
}
