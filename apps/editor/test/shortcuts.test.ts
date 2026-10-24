import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  applyShortcutOverrides,
  codeFor,
  isRebound,
  keyLabel,
  matchesShortcut,
  SHORTCUTS,
  shortcutLabel,
  tiptapShortcut
} from '../src/core/shortcuts'
import en from '../src/locales/en.json'
import zh from '../src/locales/zh-Hans.json'
import { doc } from './helpers'

const key = (init: KeyboardEventInit) => new KeyboardEvent('keydown', init)

describe('shortcut registry', () => {
  it('maps keys to physical codes', () => {
    expect(codeFor('f')).toBe('KeyF')
    expect(codeFor('5')).toBe('Digit5')
    expect(codeFor(',')).toBe('Comma')
    expect(codeFor('ArrowDown')).toBe('ArrowDown')
  })

  it('matches by physical key, so ⌥ changing the character does not matter', () => {
    expect(matchesShortcut(key({ metaKey: true, code: 'KeyF', key: 'f' }), 'find')).toBe(true)
    expect(
      matchesShortcut(key({ metaKey: true, altKey: true, code: 'KeyF', key: 'ƒ' }), 'findReplace')
    ).toBe(true)
    expect(
      matchesShortcut(key({ metaKey: true, altKey: true, code: 'KeyF', key: 'ƒ' }), 'find')
    ).toBe(false)
    expect(matchesShortcut(key({ ctrlKey: true, code: 'KeyF', key: 'f' }), 'find')).toBe(true)
    expect(matchesShortcut(key({ code: 'KeyF', key: 'f' }), 'find')).toBe(false)
    expect(
      matchesShortcut(
        key({ metaKey: true, shiftKey: true, code: 'ArrowDown', key: 'ArrowDown' }),
        'moveBlockDown'
      )
    ).toBe(true)
  })

  it('renders labels and Tiptap keymap keys from the same definitions', () => {
    expect(shortcutLabel('bold')).toBe('⌘B')
    expect(shortcutLabel('findPrevious')).toBe('⇧⌘G')
    expect(shortcutLabel('moveBlockDown')).toBe('⇧⌘↓')
    expect(shortcutLabel('heading1')).toBe('⌥⌘1')
    expect(tiptapShortcut('bulletedList')).toBe('Mod-Alt-5')
    expect(tiptapShortcut('moveBlockDown')).toBe('Mod-Shift-ArrowDown')
    expect(tiptapShortcut('strikethrough')).toBe('Mod-Shift-s')
  })

  it('has no two shortcuts on the same keys', () => {
    const combos = Object.values(SHORTCUTS).map(
      (s) => `${s.command}${s.shift}${s.option}${s.control}:${s.key}`
    )
    expect(new Set(combos).size).toBe(combos.length)
  })
})

describe('block shortcuts in the editor', () => {
  let host: HTMLElement
  let editor: Editor
  beforeEach(() => {
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, doc('shortcut me'))
    editor.commands.setTextSelection(3)
  })
  afterEach(() => {
    editor.destroy()
    host.remove()
  })

  it('⌥⌘5 makes a bulleted list, ⌥⌘0 plain text again, ⌥⌘9 a quote', () => {
    editor.commands.keyboardShortcut('Mod-Alt-5')
    expect(editor.getJSON().content?.[0].type).toBe('bulletList')
    editor.commands.keyboardShortcut('Mod-Alt-0')
    expect(editor.getJSON().content?.[0].type).toBe('paragraph')
    editor.commands.keyboardShortcut('Mod-Alt-9')
    expect(editor.getJSON().content?.[0].type).toBe('blockquote')
    expect(editor.getText()).toContain('shortcut me')
  })

  it('⌥⌘2 is a heading 2 once, not toggled twice by two bindings', () => {
    editor.commands.keyboardShortcut('Mod-Alt-2')
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
  })
})

describe('rebound shortcuts (Settings → Shortcuts)', () => {
  let host: HTMLElement
  let editor: Editor
  beforeEach(() => {
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, doc('shortcut me'))
    editor.commands.setTextSelection({ from: 1, to: 9 })
  })
  afterEach(() => {
    applyShortcutOverrides({})
    editor.destroy()
    host.remove()
  })

  /**
   * A keydown on the page, through ProseMirror's handlers (keymaps, our overrides). jsdom isn't a Mac, so the keymaps'
   * "Mod" is Ctrl — which the registry's ⌘ accepts too (`matchesKeys`).
   */
  const press = (init: KeyboardEventInit) =>
    editor.view.dom.dispatchEvent(
      new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })
    )
  const marks = () => (editor.getJSON().content?.[0].content?.[0].marks ?? []).map((m) => m.type)

  it('relabels and rematches, and an empty set brings the defaults back', () => {
    applyShortcutOverrides({
      bold: { key: 'j', modifiers: ['command', 'shift'] },
      moveBlockDown: { key: 'arrowDown', modifiers: ['option', 'command'] },
      nonsense: { key: 'x', modifiers: ['command'] }
    })
    expect(shortcutLabel('bold')).toBe('⇧⌘J')
    expect(shortcutLabel('moveBlockDown')).toBe('⌥⌘↓')
    expect(isRebound('bold')).toBe(true)
    expect(isRebound('italic')).toBe(false)
    expect(
      matchesShortcut(key({ metaKey: true, shiftKey: true, code: 'KeyJ', key: 'J' }), 'bold')
    ).toBe(true)
    expect(matchesShortcut(key({ metaKey: true, code: 'KeyB', key: 'b' }), 'bold')).toBe(false)
    expect(tiptapShortcut('bold')).toBe('Mod-b')
    applyShortcutOverrides({})
    expect(shortcutLabel('bold')).toBe('⌘B')
    expect(isRebound('bold')).toBe(false)
  })

  it('runs a rebound mark on its new keys, and its old keys do nothing', () => {
    applyShortcutOverrides({ bold: { key: 'j', modifiers: ['command'] } })
    press({ ctrlKey: true, code: 'KeyB', key: 'b' })
    expect(marks()).toEqual([])
    press({ ctrlKey: true, code: 'KeyJ', key: 'j' })
    expect(marks()).toEqual(['bold'])
    // Shortcuts nobody moved keep working.
    press({ ctrlKey: true, code: 'KeyI', key: 'i' })
    expect(marks()).toEqual(['bold', 'italic'])
  })

  it('two shortcuts can swap keys', () => {
    applyShortcutOverrides({
      bold: { key: 'i', modifiers: ['command'] },
      italic: { key: 'b', modifiers: ['command'] }
    })
    press({ ctrlKey: true, code: 'KeyI', key: 'i' })
    expect(marks()).toEqual(['bold'])
  })

  it('moves a block shortcut too (⌥⌘1 → ⌃⌘1)', () => {
    applyShortcutOverrides({ heading1: { key: '1', modifiers: ['control', 'command'] } })
    press({ ctrlKey: true, altKey: true, code: 'Digit1', key: '1' })
    expect(editor.getJSON().content?.[0].type).toBe('paragraph')
    press({ metaKey: true, ctrlKey: true, code: 'Digit1', key: '1' })
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'heading', attrs: { level: 1 } })
  })
})

/** Every string in a locale catalog. */
const strings = (node: unknown): string[] =>
  typeof node === 'string'
    ? [node]
    : node && typeof node === 'object'
      ? Object.values(node).flatMap(strings)
      : []

describe('fixed keys in panels', () => {
  it("are labelled in the registry's glyphs", () => {
    expect(keyLabel('escape')).toBe('⎋')
    expect(keyLabel('return')).toBe('↩')
    expect(keyLabel('return', ['command'])).toBe('⌘↩')
    expect(keyLabel('delete', ['shift', 'command'])).toBe('⇧⌘⌫')
  })

  it('never appear as literal key names in the copy', () => {
    for (const text of [...strings(en), ...strings(zh)]) {
      expect(text).not.toMatch(/⌘|⌥|⇧|\bEsc\b|\b(?:Enter|Return) to\b/u)
    }
  })
})
