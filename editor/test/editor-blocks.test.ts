import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { settle } from './helpers'

const key = (editor: Editor, k: string) => {
  const event = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}
const menu = () => document.querySelector('.hk-slash-menu')
const menuTitles = () =>
  [...document.querySelectorAll('.hk-slash-menu [role=option]')].map((e) =>
    e.getAttribute('aria-label')
  )

describe('slash menu', () => {
  let host: HTMLElement
  let editor: Editor

  beforeEach(() => {
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
  })
  afterEach(() => {
    editor.destroy()
    host.remove()
    document.querySelectorAll('.hk-slash-menu').forEach((e) => e.remove())
  })

  it('opens on "/", filters as you type, and Enter applies the block', async () => {
    editor.commands.insertContent('/')
    await settle()
    expect(menu()).not.toBeNull()
    expect(menuTitles()).toContain('Heading 1')

    editor.commands.insertContent('todo')
    await settle()
    expect(menuTitles()).toEqual(['To-do list'])

    key(editor, 'Enter')
    expect(menu()).toBeNull()
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'taskList' })
    expect(editor.getText()).not.toContain('/todo')
  })

  it('arrow keys move the selection before Enter', async () => {
    editor.commands.insertContent('/标题')
    await settle()
    expect(menuTitles()).toEqual(['Heading 1', 'Heading 2', 'Heading 3', 'Heading 4'])
    key(editor, 'ArrowDown')
    key(editor, 'Enter')
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
  })

  it('tapping a menu item applies it', async () => {
    editor.commands.insertContent('/quote')
    await settle()
    ;(document.querySelector('.hk-slash-menu [role=option]') as HTMLElement).click()
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'blockquote' })
  })

  it('Escape closes the menu and leaves the typed text', async () => {
    editor.commands.insertContent('/h')
    await settle()
    key(editor, 'Escape')
    expect(menu()).toBeNull()
    expect(editor.getText()).toContain('/h')
  })

  it('groups the catalog under section headers, with Markdown shortcuts', async () => {
    editor.commands.insertContent('/')
    await settle()
    const groups = [...document.querySelectorAll('.hk-slash-menu [role=group]')].map((g) =>
      g.getAttribute('aria-label')
    )
    expect(groups).toEqual(['Basic blocks', 'Lists', 'Media', 'Embeds', 'Other', 'Advanced'])
    const todo = document.querySelector('.hk-slash-menu [aria-label="To-do list"]')
    expect(todo?.textContent).toContain('[]')
  })

  it('a query flattens the list into a ranking (no section headers)', async () => {
    editor.commands.insertContent('/list')
    await settle()
    expect(document.querySelectorAll('.hk-slash-menu [role=group]')).toHaveLength(0)
    expect(menuTitles()).toEqual(expect.arrayContaining(['Bulleted list', 'Numbered list']))
  })

  it('keyboard order follows the grouped display order', async () => {
    editor.commands.insertContent('/')
    await settle()
    const shown = menuTitles()
    for (let i = 0; i < shown.indexOf('Bulleted list'); i++) key(editor, 'ArrowDown')
    key(editor, 'Enter')
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'bulletList' })
  })

  it('"Close menu" closes it and keeps the text', async () => {
    editor.commands.insertContent('/h')
    await settle()
    const close = [...document.querySelectorAll('.hk-slash-menu button')].find((b) =>
      b.textContent?.includes('Close menu')
    ) as HTMLElement
    close.click()
    await settle()
    expect(menu()).toBeNull()
    expect(editor.getText()).toContain('/h')
  })

  it('shows a preview of the selected block after a short delay', async () => {
    editor.commands.insertContent('/')
    await settle()
    expect(document.querySelector('[data-testid=slash-preview]')).toBeNull()
    await new Promise((r) => setTimeout(r, 500))
    await settle()
    expect(document.querySelector('[data-testid=slash-preview]')?.textContent).toContain(
      'Plain text'
    )
  })

  it('multi-word queries keep the menu open ("/block equation")', async () => {
    editor.commands.insertContent('/block equation')
    await settle()
    expect(menuTitles()).toEqual(['Block equation'])
  })

  it('a space right after "/" closes it', async () => {
    editor.commands.insertContent('/ ')
    await settle()
    expect(menu()).toBeNull()
  })

  it('does not open inside a code block', async () => {
    editor.commands.setCodeBlock()
    editor.commands.insertContent('/')
    await settle()
    expect(menu()).toBeNull()
  })

  it('shows the body hint only on the caret line', () => {
    editor.commands.insertContentAt(editor.state.doc.content.size, { type: 'paragraph' })
    editor.commands.setTextSelection(1)
    const hints = [...host.querySelectorAll('p.is-empty')].map((e) =>
      e.getAttribute('data-placeholder')
    )
    expect(hints).toEqual(["Type '/' for commands"])
  })
})
