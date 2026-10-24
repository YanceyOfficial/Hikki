import HikkiCore
import SwiftUI

/// The keys each shortcut uses now: the registry's (design/shortcuts.json) unless the user rebound it in Settings →
/// Shortcuts. Stored as JSON in UserDefaults; the native menus read it through `Shortcut.keyboardShortcut` (observed,
/// so they follow a change) and every editor gets it through `window.hikki.setShortcuts`.
@Observable
final class ShortcutStore {
    static let shared = ShortcutStore()
    /// No dot in the key: a dotted `@AppStorage` key read from the menus loops them (CLAUDE.md, menu bar extra).
    static let storageKey = "shortcutOverrides"

    private(set) var overrides: ShortcutOverrides
    @ObservationIgnored private let defaults: UserDefaults

    static let registry: [String: KeyCombo] = Dictionary(
        uniqueKeysWithValues: Shortcut.allCases.map { ($0.rawValue, $0.defaultCombo) })

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        overrides = ShortcutOverrides(data: defaults.data(forKey: Self.storageKey)).sanitized(defaults: Self.registry)
    }

    /// Reads the overrides again: another device's arrived (`SyncedSettings`), and the menus and editors follow.
    func reload() {
        overrides = ShortcutOverrides(data: defaults.data(forKey: Self.storageKey)).sanitized(defaults: Self.registry)
    }

    func combo(_ shortcut: Shortcut) -> KeyCombo {
        overrides.combo(shortcut.rawValue, default: shortcut.defaultCombo)
    }

    func isCustom(_ shortcut: Shortcut) -> Bool {
        overrides.combos[shortcut.rawValue] != nil
    }

    /// Why `combo` can't be `shortcut`'s keys (needs a modifier, reserved, another shortcut's), or nil.
    func problem(_ combo: KeyCombo, for shortcut: Shortcut) -> KeyCombo.Problem? {
        overrides.problem(binding: combo, to: shortcut.rawValue, defaults: Self.registry)
    }

    /// Rebinds `shortcut`; refused (false) when `problem` says so.
    @discardableResult
    func set(_ combo: KeyCombo, for shortcut: Shortcut) -> Bool {
        guard problem(combo, for: shortcut) == nil else { return false }
        overrides.set(combo, for: shortcut.rawValue, default: shortcut.defaultCombo)
        save()
        Log.info("shortcut rebound", category: "shortcuts", context: ["id": shortcut.rawValue])
        return true
    }

    func reset(_ shortcut: Shortcut) {
        overrides.reset(shortcut.rawValue)
        save()
    }

    func resetAll() {
        overrides = ShortcutOverrides()
        save()
    }

    /// What the editor needs: the rebound shortcuts only, in the registry's terms (`{ key, modifiers }`).
    static func editorPayload(_ overrides: ShortcutOverrides) -> [String: [String: Any]] {
        overrides.combos.mapValues { combo in
            ["key": combo.key, "modifiers": combo.modifiers.sorted().map(\.rawValue)]
        }
    }

    private func save() {
        if overrides.combos.isEmpty {
            defaults.removeObject(forKey: Self.storageKey)
        } else {
            defaults.set(overrides.data, forKey: Self.storageKey)
        }
    }
}

extension Shortcut {
    /// The keys in use (the user's, or the registry's).
    var combo: KeyCombo { ShortcutStore.shared.combo(self) }
    var keyboardShortcut: KeyboardShortcut { combo.keyboardShortcut }
    /// "⌘N", "⇧⌘↓" — for menus that can't bind the key (the editor's shortcuts) and for help text.
    var display: String { combo.display }
}

extension Shortcut.Group {
    var title: LocalizedStringKey {
        switch self {
        case .general: "app:shortcuts.group.general"
        case .navigation: "app:shortcuts.group.navigation"
        case .find: "app:shortcuts.group.find"
        case .format: "app:shortcuts.group.format"
        case .blocks: "app:shortcuts.group.blocks"
        }
    }
}

extension KeyCombo {
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    var keyEquivalent: KeyEquivalent {
        switch key {
        case "arrowUp": .upArrow
        case "arrowDown": .downArrow
        case "arrowLeft": .leftArrow
        case "arrowRight": .rightArrow
        case "tab": .tab
        case "return": .return
        case "escape": .escape
        case "delete": .delete
        default: KeyEquivalent(Character(key))
        }
    }

    var eventModifiers: EventModifiers {
        var out: EventModifiers = []
        if modifiers.contains(.command) { out.insert(.command) }
        if modifiers.contains(.shift) { out.insert(.shift) }
        if modifiers.contains(.option) { out.insert(.option) }
        if modifiers.contains(.control) { out.insert(.control) }
        return out
    }

    /// A pressed key as a combo (Settings → Shortcuts records with it), or nil for a key we can't name.
    init?(keyEquivalent: KeyEquivalent, modifiers: EventModifiers) {
        let named: [Character: String] = [
            KeyEquivalent.upArrow.character: "arrowUp", KeyEquivalent.downArrow.character: "arrowDown",
            KeyEquivalent.leftArrow.character: "arrowLeft", KeyEquivalent.rightArrow.character: "arrowRight",
            KeyEquivalent.tab.character: "tab", KeyEquivalent.return.character: "return",
            KeyEquivalent.escape.character: "escape", KeyEquivalent.delete.character: "delete",
        ]
        let character = keyEquivalent.character
        let key = named[character] ?? String(character).lowercased()
        guard !key.isEmpty else { return nil }
        var mods: Set<Modifier> = []
        if modifiers.contains(.command) { mods.insert(.command) }
        if modifiers.contains(.shift) { mods.insert(.shift) }
        if modifiers.contains(.option) { mods.insert(.option) }
        if modifiers.contains(.control) { mods.insert(.control) }
        self.init(key, mods)
    }
}
