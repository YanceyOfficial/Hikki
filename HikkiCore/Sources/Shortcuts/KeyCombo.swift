import Foundation

/// A key with its modifiers, in the registry's terms (design/shortcuts.json): a lower-case character or a named key
/// (`arrowUp`, `tab`…). The native menus and the editor both bind it; Settings → Shortcuts records new ones.
public struct KeyCombo: Codable, Hashable, Sendable {
    /// In display order (⌃⌥⇧⌘), as macOS menus show them.
    public enum Modifier: String, Codable, CaseIterable, Sendable, Comparable {
        case control, option, shift, command

        public var glyph: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }

        public static func < (a: Modifier, b: Modifier) -> Bool {
            allCases.firstIndex(of: a)! < allCases.firstIndex(of: b)!
        }
    }

    public var key: String
    public var modifiers: Set<Modifier>

    public init(_ key: String, _ modifiers: Set<Modifier>) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    /// Named keys and their glyphs (the generator's table).
    public static let namedKeys: [String: String] = [
        "arrowUp": "↑", "arrowDown": "↓", "arrowLeft": "←", "arrowRight": "→",
        "tab": "⇥", "return": "↩", "escape": "⎋", "delete": "⌫",
    ]

    /// Characters the editor matches by physical key (`codeFor` in apps/editor/src/core/shortcuts.ts): letters, digits and
    /// this punctuation. Anything else (a dead key, an IME character) can't be bound on both sides.
    public static let bindableCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789,.[]/;'\\-=`".map(String.init))

    /// "⇧⌘↓", "⌥⌘1".
    public var display: String {
        modifiers.sorted().map(\.glyph).joined() + (Self.namedKeys[key] ?? key.uppercased())
    }

    public enum Problem: Equatable, Sendable {
        /// Plain keys and ⇧ alone would fire while typing.
        case needsModifier
        /// A key the editor can't match (see `bindableCharacters`).
        case unsupportedKey
        /// The system's or every app's (⌘Q, ⌘C, ⌘Z…).
        case reserved
        /// Another shortcut has it (its id).
        case taken(String)
    }

    /// Combos that stay with the system or the Edit menu whatever the user picks.
    public static let reserved: Set<KeyCombo> = [
        KeyCombo("q", [.command]), KeyCombo("h", [.command]), KeyCombo("h", [.command, .option]),
        KeyCombo("m", [.command]), KeyCombo("c", [.command]), KeyCombo("v", [.command]),
        KeyCombo("x", [.command]), KeyCombo("z", [.command]), KeyCombo("z", [.command, .shift]),
        KeyCombo("a", [.command]), KeyCombo("`", [.command]), KeyCombo("tab", [.command]),
        KeyCombo("v", [.command, .shift, .option]),
    ]

    /// What's wrong with binding this at all (not counting other shortcuts).
    public var problem: Problem? {
        if modifiers.isDisjoint(with: [.command, .control, .option]) { return .needsModifier }
        if Self.namedKeys[key] == nil && !Self.bindableCharacters.contains(key) { return .unsupportedKey }
        if Self.reserved.contains(self) { return .reserved }
        return nil
    }
}

/// The user's rebindings, by shortcut id; everything else keeps its default. Stored as JSON in UserDefaults.
public struct ShortcutOverrides: Codable, Equatable, Sendable {
    public private(set) var combos: [String: KeyCombo]

    public init(_ combos: [String: KeyCombo] = [:]) {
        self.combos = combos
    }

    public init(data: Data?) {
        self.init((data.flatMap { try? JSONDecoder().decode([String: KeyCombo].self, from: $0) }) ?? [:])
    }

    public var data: Data { (try? JSONEncoder().encode(combos)) ?? Data() }

    public func combo(_ id: String, default fallback: KeyCombo) -> KeyCombo {
        combos[id] ?? fallback
    }

    /// Binds `combo` to `id`; picking the default again just drops the override.
    public mutating func set(_ combo: KeyCombo, for id: String, default fallback: KeyCombo) {
        combos[id] = combo == fallback ? nil : combo
    }

    public mutating func reset(_ id: String) {
        combos[id] = nil
    }

    /// The shortcut other than `id` that `combo` is bound to now, given every shortcut's default.
    public func owner(of combo: KeyCombo, defaults: [String: KeyCombo], except id: String) -> String? {
        defaults.keys.sorted().first { other in
            other != id && self.combo(other, default: defaults[other]!) == combo
        }
    }

    /// Why `combo` can't go to `id`, or nil when it can.
    public func problem(binding combo: KeyCombo, to id: String, defaults: [String: KeyCombo]) -> KeyCombo.Problem? {
        if let problem = combo.problem { return problem }
        if let owner = owner(of: combo, defaults: defaults, except: id) { return .taken(owner) }
        return nil
    }

    /// Overrides that still make sense (a stored one may name a shortcut that's gone, or collide after an update):
    /// unknown ids and unbindable combos go, then — while two shortcuts share keys — the later (by id) override goes,
    /// until every shortcut has keys of its own (the defaults alone always do).
    public func sanitized(defaults: [String: KeyCombo]) -> ShortcutOverrides {
        var out = ShortcutOverrides(combos.filter { defaults[$0.key] != nil && $0.value.problem == nil })
        while let id = out.combos.keys.sorted().last(where: { id in
            out.owner(of: out.combos[id]!, defaults: defaults, except: id) != nil
        }) {
            out.combos[id] = nil
        }
        return out
    }
}
