import SwiftUI

#if os(macOS)
    import AppKit
#endif

/// A shortcut's keys as a key cap that records new ones: click it, press the keys (Escape cancels). Plain values in,
/// the pressed key out — the caller decides whether it's allowed. A reset button shows once it differs from the default.
public struct ShortcutRecorder: View {
    private let display: String
    private let isCustom: Bool
    private let identifier: String
    private let onRecord: (KeyEquivalent, EventModifiers) -> Void
    private let onReset: () -> Void
    @Binding private var recording: Bool
    #if os(macOS)
        @State private var monitor: Any?
        @State private var held = ""
    #endif

    public init(
        display: String, isCustom: Bool, recording: Binding<Bool>, identifier: String,
        onRecord: @escaping (KeyEquivalent, EventModifiers) -> Void, onReset: @escaping () -> Void
    ) {
        self.display = display
        self.isCustom = isCustom
        self._recording = recording
        self.identifier = identifier
        self.onRecord = onRecord
        self.onReset = onReset
    }

    public var body: some View {
        HStack(spacing: Spacing.s1) {
            if isCustom && !recording {
                Button(action: onReset) {
                    IconLabel("app:shortcuts.reset", icon: .arrowCounterClockwise, size: TextSize.sm.rawValue)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.subtleForeground)
                        .frame(width: Size.iconButtonSm, height: Size.iconButtonSm)
                        .contentShape(.rect)
                }
                .buttonStyle(HoverHighlightStyle())
                .help(Text("app:shortcuts.reset"))
                .accessibilityIdentifier("\(identifier)-reset")
            }
            Button {
                recording.toggle()
            } label: {
                cap
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
            .accessibilityValue(Text(recording ? "" : display))
        }
        #if os(macOS)
            .onChange(of: recording) { _, on in on ? startMonitor() : stopMonitor() }
            .onDisappear { stopMonitor() }
        #else
            // A first responder reads the keys while recording (SwiftUI focus doesn't move onto a button).
            .background {
                if recording {
                    KeyCapture { key, modifiers in
                        record(key, modifiers)
                    } onResign: {
                        recording = false
                    }
                    .frame(width: 0, height: 0)
                }
            }
        #endif
    }

    private var cap: some View {
        Group {
            if recording {
                #if os(macOS)
                    Text(held.isEmpty ? String(localized: "app:shortcuts.recording") : held)
                #else
                    Text("app:shortcuts.recording")
                #endif
            } else {
                Text(verbatim: display)
            }
        }
        .font(.hk(.sm, .medium))
        .monospacedDigit()
        .foregroundStyle(recording ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.foreground))
        .padding(.horizontal, Spacing.s2)
        .frame(minWidth: Size.shortcutCap, minHeight: Size.iconButtonSm)
        .background(Theme.muted, in: .rect(cornerRadius: Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(recording ? AnyShapeStyle(.tint) : AnyShapeStyle(Theme.border), lineWidth: 1)
        }
        .contentShape(.rect)
        .animation(Motion.easeOut(), value: recording)
    }

    private func record(_ key: KeyEquivalent, _ modifiers: EventModifiers) {
        recording = false
        // Escape on its own cancels.
        if key == .escape && modifiers.isEmpty { return }
        onRecord(key, modifiers)
    }

    #if os(macOS)
        /// Keys go to us before the menus while recording (⌘N must not make a page).
        private func startMonitor() {
            stopMonitor()
            held = ""
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
                let modifiers = Self.modifiers(event.modifierFlags)
                if event.type == .flagsChanged {
                    held = Self.glyphs(modifiers)
                    return event
                }
                if let key = Self.key(event) { record(key, modifiers) }
                return nil
            }
        }

        private func stopMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            held = ""
        }

        /// The physical key (ANSI positions, as the editor matches `event.code`), whatever the layout makes of it.
        private static func key(_ event: NSEvent) -> KeyEquivalent? {
            switch event.keyCode {
            case 126: .upArrow
            case 125: .downArrow
            case 123: .leftArrow
            case 124: .rightArrow
            case 48: .tab
            case 36, 76: .return
            case 53: .escape
            case 51: .delete
            default: ansi[event.keyCode].map { KeyEquivalent($0) }
            }
        }

        private static let ansi: [UInt16: Character] = [
            0: "a", 11: "b", 8: "c", 2: "d", 14: "e", 3: "f", 5: "g", 4: "h", 34: "i", 38: "j", 40: "k", 37: "l",
            46: "m", 45: "n", 31: "o", 35: "p", 12: "q", 15: "r", 1: "s", 17: "t", 32: "u", 9: "v", 13: "w", 7: "x",
            16: "y", 6: "z", 29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9",
            27: "-", 24: "=", 33: "[", 30: "]", 42: "\\", 41: ";", 39: "'", 50: "`", 43: ",", 47: ".", 44: "/",
        ]

        private static func modifiers(_ flags: NSEvent.ModifierFlags) -> EventModifiers {
            var out: EventModifiers = []
            if flags.contains(.command) { out.insert(.command) }
            if flags.contains(.shift) { out.insert(.shift) }
            if flags.contains(.option) { out.insert(.option) }
            if flags.contains(.control) { out.insert(.control) }
            return out
        }

        private static func glyphs(_ modifiers: EventModifiers) -> String {
            (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
                + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
        }
    #endif
}

#if os(iOS)
    /// A zero-size first responder that hands each key press (physical key + modifiers) to `onKey`.
    private struct KeyCapture: UIViewRepresentable {
        let onKey: (KeyEquivalent, EventModifiers) -> Void
        let onResign: () -> Void

        func makeUIView(context: Context) -> CaptureView {
            let view = CaptureView()
            view.onKey = onKey
            view.onResign = onResign
            DispatchQueue.main.async { view.becomeFirstResponder() }
            return view
        }

        func updateUIView(_ view: CaptureView, context: Context) {
            view.onKey = onKey
            view.onResign = onResign
        }

        static func dismantleUIView(_ view: CaptureView, coordinator: ()) {
            view.onResign = nil
            _ = view.resignFirstResponder()
        }

        final class CaptureView: UIView {
            var onKey: ((KeyEquivalent, EventModifiers) -> Void)?
            var onResign: (() -> Void)?

            override var canBecomeFirstResponder: Bool { true }

            override func resignFirstResponder() -> Bool {
                let done = super.resignFirstResponder()
                onResign?()
                return done
            }

            /// Modifier keys held now: they arrive as presses of their own, and a synthesized key (UI tests, some
            /// hardware keyboards) may not carry them in its flags.
            private var held: UIKeyModifierFlags = []

            override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                var handled = false
                for press in presses {
                    guard let key = press.key else { continue }
                    if let flag = Self.modifier(key.keyCode) {
                        held.insert(flag)
                        handled = true
                    } else if let equivalent = Self.equivalent(key.keyCode) {
                        let flags = held.union(key.modifierFlags).union(event?.modifierFlags ?? [])
                        var modifiers: EventModifiers = []
                        if flags.contains(.command) { modifiers.insert(.command) }
                        if flags.contains(.shift) { modifiers.insert(.shift) }
                        if flags.contains(.alternate) { modifiers.insert(.option) }
                        if flags.contains(.control) { modifiers.insert(.control) }
                        onKey?(equivalent, modifiers)
                        handled = true
                    }
                }
                if !handled { super.pressesBegan(presses, with: event) }
            }

            override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
                for press in presses {
                    if let code = press.key?.keyCode, let flag = Self.modifier(code) { held.remove(flag) }
                }
                super.pressesEnded(presses, with: event)
            }

            private static func modifier(_ code: UIKeyboardHIDUsage) -> UIKeyModifierFlags? {
                switch code {
                case .keyboardLeftGUI, .keyboardRightGUI: .command
                case .keyboardLeftShift, .keyboardRightShift: .shift
                case .keyboardLeftAlt, .keyboardRightAlt: .alternate
                case .keyboardLeftControl, .keyboardRightControl: .control
                default: nil
                }
            }

            /// The physical key (HID usage), as the editor matches `event.code`.
            private static func equivalent(_ code: UIKeyboardHIDUsage) -> KeyEquivalent? {
                switch code {
                case .keyboardUpArrow: return .upArrow
                case .keyboardDownArrow: return .downArrow
                case .keyboardLeftArrow: return .leftArrow
                case .keyboardRightArrow: return .rightArrow
                case .keyboardTab: return .tab
                case .keyboardReturnOrEnter, .keypadEnter: return .return
                case .keyboardEscape: return .escape
                case .keyboardDeleteOrBackspace: return .delete
                default: break
                }
                let raw = code.rawValue
                if (4...29).contains(raw) { return KeyEquivalent(Character(UnicodeScalar(UInt8(97 + raw - 4)))) }
                if (30...38).contains(raw) { return KeyEquivalent(Character(String(raw - 29))) }
                let others: [Int: Character] = [
                    39: "0", 45: "-", 46: "=", 47: "[", 48: "]", 49: "\\", 51: ";", 52: "'", 53: "`", 54: ",", 55: ".",
                    56: "/",
                ]
                return others[raw].map { KeyEquivalent($0) }
            }
        }
    }
#endif

#Preview {
    @Previewable @State var recording = false
    @Previewable @State var display = "⌘B"
    VStack(alignment: .trailing, spacing: Spacing.s3) {
        ShortcutRecorder(
            display: display, isCustom: display != "⌘B", recording: $recording, identifier: "preview",
            onRecord: { key, _ in display = "⌘" + String(key.character).uppercased() },
            onReset: { display = "⌘B" })
        ShortcutRecorder(
            display: "⇧⌘↓", isCustom: true, recording: .constant(false), identifier: "preview-2",
            onRecord: { _, _ in }, onReset: {})
    }
    .padding()
}
