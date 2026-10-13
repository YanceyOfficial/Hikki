import { SHORTCUTS, type ShortcutId } from '../generated/shortcuts'

export { SHORTCUTS, type ShortcutId }

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
 * Whether a keydown is this shortcut. Compared by physical key, not `event.key`: with ⌥ held, macOS reports
 * "ƒ" for F and "¡" for 1. "command" accepts Ctrl too (the editor in a browser on another platform).
 */
export function matchesShortcut(event: KeyboardEvent, id: ShortcutId): boolean {
  const s = SHORTCUTS[id]
  if (event.isComposing || event.code !== codeFor(s.key)) return false
  const command = event.metaKey || (event.ctrlKey && !s.control)
  return (
    command === s.command &&
    event.shiftKey === s.shift &&
    event.altKey === s.option &&
    (!s.control || event.ctrlKey)
  )
}

/** The label menus show ("⌘B", "⇧⌘↓"). */
export const shortcutLabel = (id: ShortcutId): string => SHORTCUTS[id].display

/** The same shortcut as a Tiptap/ProseMirror keymap key ("Mod-Alt-5", "Mod-Shift-ArrowDown"). */
export function tiptapShortcut(id: ShortcutId): string {
  const s = SHORTCUTS[id]
  const parts = []
  if (s.command) parts.push('Mod')
  if (s.control) parts.push('Control')
  if (s.option) parts.push('Alt')
  if (s.shift) parts.push('Shift')
  parts.push(s.key.length === 1 ? s.key : s.key)
  return parts.join('-')
}
