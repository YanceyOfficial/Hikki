import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import {
  codeFor,
  matchesShortcut,
  SHORTCUTS,
  shortcutLabel,
  tiptapShortcut
} from '../src/core/shortcuts'
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
