import Foundation
import Testing

@testable import HikkiCore

struct KeyComboTests {
    private let defaults: [String: KeyCombo] = [
        "bold": KeyCombo("b", [.command]),
        "italic": KeyCombo("i", [.command]),
        "moveDown": KeyCombo("arrowDown", [.command, .shift]),
    ]

    @Test func displaysModifiersInMenuOrder() {
        #expect(KeyCombo("arrowDown", [.command, .shift]).display == "⇧⌘↓")
        #expect(KeyCombo("1", [.command, .option]).display == "⌥⌘1")
        #expect(KeyCombo("tab", [.shift, .control]).display == "⌃⇧⇥")
        #expect(KeyCombo("B", [.command]).key == "b")
    }

    @Test func refusesKeysThatCantBeShortcuts() {
        #expect(KeyCombo("b", []).problem == .needsModifier)
        #expect(KeyCombo("b", [.shift]).problem == .needsModifier)
        #expect(KeyCombo("é", [.command]).problem == .unsupportedKey)
        #expect(KeyCombo("q", [.command]).problem == .reserved)
        #expect(KeyCombo("z", [.command, .shift]).problem == .reserved)
        #expect(KeyCombo("b", [.control]).problem == nil)
        #expect(KeyCombo("\\", [.command]).problem == nil)
    }

    @Test func aComboAnotherShortcutUsesIsTaken() {
        var overrides = ShortcutOverrides()
        #expect(overrides.problem(binding: KeyCombo("i", [.command]), to: "bold", defaults: defaults) == .taken("italic"))
        // Its own default is never "taken".
        #expect(overrides.problem(binding: KeyCombo("b", [.command]), to: "bold", defaults: defaults) == nil)
        // Once italic moves away, its old keys are free.
        overrides.set(KeyCombo("i", [.command, .shift]), for: "italic", default: defaults["italic"]!)
        #expect(overrides.problem(binding: KeyCombo("i", [.command]), to: "bold", defaults: defaults) == nil)
        #expect(
            overrides.problem(binding: KeyCombo("i", [.command, .shift]), to: "bold", defaults: defaults)
                == .taken("italic"))
    }

    @Test func pickingTheDefaultAgainDropsTheOverride() {
        var overrides = ShortcutOverrides()
        overrides.set(KeyCombo("j", [.command]), for: "bold", default: defaults["bold"]!)
        #expect(overrides.combos["bold"] == KeyCombo("j", [.command]))
        overrides.set(KeyCombo("b", [.command]), for: "bold", default: defaults["bold"]!)
        #expect(overrides.combos.isEmpty)
    }

    @Test func roundTripsThroughData() {
        var overrides = ShortcutOverrides()
        overrides.set(KeyCombo("arrowUp", [.option, .command]), for: "moveDown", default: defaults["moveDown"]!)
        #expect(ShortcutOverrides(data: overrides.data) == overrides)
        #expect(ShortcutOverrides(data: Data("garbage".utf8)) == ShortcutOverrides())
        #expect(ShortcutOverrides(data: nil) == ShortcutOverrides())
    }

    @Test func sanitizingDropsStaleAndClashingOverrides() {
        let stored = ShortcutOverrides([
            "gone": KeyCombo("j", [.command]),  // no such shortcut any more
            "bold": KeyCombo("i", [.command]),  // italic's default, italic not moved
            "moveDown": KeyCombo("x", [.command]),  // reserved
        ])
        #expect(stored.sanitized(defaults: defaults) == ShortcutOverrides())

        // A swap is fine: each takes the other's default.
        let swapped = ShortcutOverrides(["bold": KeyCombo("i", [.command]), "italic": KeyCombo("b", [.command])])
        #expect(swapped.sanitized(defaults: defaults) == swapped)

        // Two overrides on the same keys: the later id gives way, and its default comes back.
        let twice = ShortcutOverrides(["bold": KeyCombo("k", [.command]), "italic": KeyCombo("k", [.command])])
        #expect(twice.sanitized(defaults: defaults) == ShortcutOverrides(["bold": KeyCombo("k", [.command])]))
    }
}
