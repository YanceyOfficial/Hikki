import SwiftUI

/// The keyboard bar's end button: puts the keyboard away — or, while a panel is in the keyboard's place
/// (`showsKeyboard`), closes the panel and brings the keyboard back. Drawn as the bar's other tools are, inside its
/// glass capsule.
public struct KeyboardDismissButton: View {
    private let showsKeyboard: Bool
    private let action: () -> Void

    public init(showsKeyboard: Bool = false, action: @escaping () -> Void) {
        self.showsKeyboard = showsKeyboard
        self.action = action
    }

    public var body: some View {
        ToolbarIconButton(
            showsKeyboard ? "app:keyboard.show" : "app:keyboard.hide", symbol: showsKeyboard ? .x : .keyboard,
            action: action
        )
        .accessibilityIdentifier(showsKeyboard ? "show-keyboard" : "hide-keyboard")
    }
}

#Preview {
    HStack {
        KeyboardDismissButton {}
        KeyboardDismissButton(showsKeyboard: true) {}
    }
    .padding()
}
