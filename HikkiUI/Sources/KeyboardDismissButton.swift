import SwiftUI

/// Round glass "hide keyboard" button. In a multi-line editor Return inserts a newline, so without it
/// the only way out of the keyboard is a gesture people don't find.
public struct KeyboardDismissButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconLabel("Hide Keyboard", icon: .keyboard, size: TextSize.base.rawValue)
                .labelStyle(.iconOnly)
                // The keyboard glyph is wider than the formatting icons; at full scale its circle would dominate the bar.
                .imageScale(.small)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("hide-keyboard")
    }
}

#Preview {
    KeyboardDismissButton {}
        .padding()
}
