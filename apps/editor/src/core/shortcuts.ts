import { SHORTCUTS as REGISTRY, type Shortcut, type ShortcutId } from '../generated/shortcuts'

export type { Shortcut, ShortcutId }

/** The registry's keys (design/shortcuts.json), before the user's. Tiptap keymaps are built from these. */
export const DEFAULT_SHORTCUTS: Readonly<Record<ShortcutId, Shortcut>> = REGISTRY

/** The keys in use: the registry's, with the user's rebindings (Settings → Shortcuts) laid over them. */
export const SHORTCUTS: Record<ShortcutId, Shortcut> = { ...REGISTRY }

/** A rebinding as the native side sends it, in the registry's terms. */
export type ShortcutOverride = { key: string; modifiers: string[] }

/** Registry key names → DOM key names and glyphs (scripts/gen-shortcuts.mjs has the same table). */
const NAMED: Record<string, { dom: string; glyph: string }> = {
  arrowUp: { dom: 'ArrowUp', glyph: '↑' },
  arrowDown: { dom: 'ArrowDown', glyph: '↓' },
  arrowLeft: { dom: 'ArrowLeft', glyph: '←' },
  arrowRight: { dom: 'ArrowRight', glyph: '→' },
  tab: { dom: 'Tab', glyph: '⇥' },
  return: { dom: 'Enter', glyph: '↩' },
  escape: { dom: 'Escape', glyph: '⎋' },
  delete: { dom: 'Backspace', glyph: '⌫' }
}

/**
 * `window.hikki.setShortcuts`: replaces every rebinding at once (an id missing from `overrides` goes back to its
 * default). Unknown ids and keys are ignored. Matching (`matchesShortcut`) and labels (`shortcutLabel`) follow at once;
 * the keymaps that still listen on a default are overruled by `ShortcutOverrides` (extensions/shortcuts.ts).
 */
export function applyShortcutOverrides(overrides: Record<string, ShortcutOverride>): void {
  for (const id of Object.keys(REGISTRY) as ShortcutId[]) {
    const override = overrides[id]
    const named = override ? NAMED[override.key] : undefined
    if (!override || (!named && override.key.length !== 1)) {
      SHORTCUTS[id] = REGISTRY[id]
      continue
    }
    const has = (m: string) => override.modifiers.includes(m)
    const key = named ? named.dom : override.key.toLowerCase()
    const glyphs =
      (has('control') ? '⌃' : '') + (has('option') ? '⌥' : '') + (has('shift') ? '⇧' : '')
    SHORTCUTS[id] = {
      key,
      command: has('command'),
      shift: has('shift'),
      option: has('option'),
      control: has('control'),
      bound: REGISTRY[id].bound,
      display: glyphs + (has('command') ? '⌘' : '') + (named ? named.glyph : key.toUpperCase())
    }
  }
}

/** Whether the user moved this shortcut off its default keys. */
export const isRebound = (id: ShortcutId): boolean => SHORTCUTS[id] !== REGISTRY[id]

/** DOM `KeyboardEvent.code` for the punctuation we bind (letters and digits follow a pattern). */
const CODES: Record<string, string> = {
  ',': 'Comma',
  '.': 'Period',
  '[': 'BracketLeft',
  ']': 'BracketRight',
  '/': 'Slash',
  ';': 'Semicolon',
  "'": 'Quote',
  '\\': 'Backslash',
  '-': 'Minus',
  '=': 'Equal',
  '`': 'Backquote'
}

/** The physical key a shortcut's key sits on (`event.code`); DOM key names (ArrowUp, Tab…) double as codes. */
export function codeFor(key: string): string {
  if (/^[a-z]$/u.test(key)) return `Key${key.toUpperCase()}`
  if (/^[0-9]$/u.test(key)) return `Digit${key}`
  return CODES[key] ?? key
}

/**
 * Whether a keydown is these keys. Compared by physical key, not `event.key`: with ⌥ held, macOS reports "ƒ" for F
 * and "¡" for 1. "command" accepts Ctrl too (the editor in a browser on another platform).
 */
export function matchesKeys(event: KeyboardEvent, s: Shortcut): boolean {
  if (event.isComposing || event.code !== codeFor(s.key)) return false
  const command = event.metaKey || (event.ctrlKey && !s.control)
  return (
    command === s.command &&
    event.shiftKey === s.shift &&
    event.altKey === s.option &&
    (!s.control || event.ctrlKey)
  )
}

/** Whether a keydown is this shortcut, on the keys in use. */
export const matchesShortcut = (event: KeyboardEvent, id: ShortcutId): boolean =>
  matchesKeys(event, SHORTCUTS[id])

/** The shortcut a keydown is now, if any. */
export function shortcutFor(event: KeyboardEvent): ShortcutId | undefined {
  return (Object.keys(SHORTCUTS) as ShortcutId[]).find((id) => matchesShortcut(event, id))
}

/** The label menus show ("⌘B", "⇧⌘↓"), on the keys in use. */
export const shortcutLabel = (id: ShortcutId): string => SHORTCUTS[id].display

/**
 * The registry's keys as a Tiptap/ProseMirror keymap key ("Mod-Alt-5", "Mod-Shift-ArrowDown"). Keymaps are built
 * once, so they always hold the default; a rebinding is applied in front of them (`ShortcutOverrides`).
 */
export function tiptapShortcut(id: ShortcutId): string {
  const s = DEFAULT_SHORTCUTS[id]
  const parts = []
  if (s.command) parts.push('Mod')
  if (s.control) parts.push('Control')
  if (s.option) parts.push('Alt')
  if (s.shift) parts.push('Shift')
  parts.push(s.key)
  return parts.join('-')
}
