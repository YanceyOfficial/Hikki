import type { Editor } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { createEditor } from '../src/editor'

const key = (editor: Editor, k: string) => {
  const event = new KeyboardEvent('keydown', { key: k, bubbles: true, cancelable: true })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}
/** Suggestion resolves items asynchronously. */
const settle = () => new Promise((resolve) => setTimeout(resolve, 0))
const menu = () => document.querySelector('.hk-slash-menu')
const menuTitles = () => [...document.querySelectorAll('.hk-slash-menu .hk-command-title')].map((e) => e.textContent)

describe('editor blocks', () => {
  let host: HTMLElement
  let editor: Editor

  beforeEach(() => {
    host = document.createElement('div')
    document.body.append(host)
    editor = createEditor(host, null)
  })
  afterEach(() => {
    editor.destroy()
    host.remove()
    document.querySelectorAll('.hk-floating').forEach((e) => e.remove())
  })

  it('always starts with a title node followed by a paragraph', () => {
    expect(editor.getJSON().content?.map((n) => n.type)).toEqual(['title', 'paragraph'])
  })

  it('shows the title placeholder even when the caret is in the body, and the body hint only on the caret line', () => {
    editor.commands.insertContentAt(editor.state.doc.content.size, { type: 'paragraph' })
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize + 1)
    const placeholders = [...host.querySelectorAll('[data-placeholder]')].filter((e) => e.classList.contains('is-empty'))
    const hints = placeholders.map((e) => `${e.tagName.toLowerCase()}:${e.getAttribute('data-placeholder')}`)
    expect(hints).toContain('h1:Untitled')
    expect(hints.filter((h) => h.startsWith('p:') && h !== 'p:')).toEqual(["p:Type '/' for commands"])
  })

  it('Enter in the title moves into the body instead of splitting the title', () => {
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('My page')
    key(editor, 'Enter')
    editor.commands.insertContent('body')
    expect(editor.getJSON().content).toEqual([
      { type: 'title', content: [{ type: 'text', text: 'My page' }] },
      { type: 'paragraph', content: [{ type: 'text', text: 'body' }] },
    ])
  })

  it('title cannot hold marks', () => {
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('x')
    editor.commands.selectAll()
    editor.commands.setTextSelection({ from: 1, to: 2 })
    editor.commands.toggleBold()
    expect(editor.getJSON().content?.[0]).toEqual({ type: 'title', content: [{ type: 'text', text: 'x' }] })
  })

  it('"/" opens the block menu in the body, filters as you type, and Enter applies the block', async () => {
    const bodyStart = editor.state.doc.child(0).nodeSize + 1
    editor.commands.setTextSelection(bodyStart)
    editor.commands.insertContent('/')
    await settle()
    expect(menu()).not.toBeNull()
    expect(menuTitles()).toContain('Heading 1')

    editor.commands.insertContent('todo')
    await settle()
    expect(menuTitles()).toEqual(['To-do list'])

    key(editor, 'Enter')
    expect(menu()).toBeNull()
    expect(editor.getJSON().content?.[1]).toMatchObject({ type: 'taskList' })
    expect(editor.getText()).not.toContain('/todo')
  })

  it('arrow keys move the selection before Enter', async () => {
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize + 1)
    editor.commands.insertContent('/标题')
    await settle()
    expect(menuTitles()).toEqual(['Heading 1', 'Heading 2', 'Heading 3'])
    key(editor, 'ArrowDown')
    key(editor, 'Enter')
    expect(editor.getJSON().content?.[1]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
  })

  it('tapping a menu item applies it', async () => {
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize + 1)
    editor.commands.insertContent('/quote')
    await settle()
    ;(document.querySelector('.hk-slash-menu .hk-command-item') as HTMLElement).click()
    expect(editor.getJSON().content?.[1]).toMatchObject({ type: 'blockquote' })
  })

  it('Escape closes the menu and leaves the typed text', async () => {
    editor.commands.setTextSelection(editor.state.doc.child(0).nodeSize + 1)
    editor.commands.insertContent('/h')
    await settle()
    key(editor, 'Escape')
    expect(menu()).toBeNull()
    expect(editor.getText()).toContain('/h')
  })

  it('"/" does nothing inside the title', async () => {
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('/')
    await settle()
    expect(menu()).toBeNull()
  })
})
