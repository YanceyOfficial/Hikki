import { act, cleanup, fireEvent, screen } from '@testing-library/react'
import type { Editor, JSONContent } from '@tiptap/core'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'

import { openBlockMenu } from '../src/components/block-menu'
import { createEditor } from '../src/core/editor'
import { BlockHighlightKey, setBlockHighlight } from '../src/extensions/block-highlight'
import {
  deleteUnit,
  duplicateUnit,
  handleUnitAtPos,
  moveUnit,
  unitAtPos,
  unitTextRange
} from '../src/extensions/block-units'
import { doc, settle, stripIds } from './helpers'

let host: HTMLElement
let editor: Editor

beforeEach(() => {
  host = document.createElement('div')
  document.body.append(host)
})
afterEach(() => {
  cleanup()
  editor?.destroy()
  host.remove()
  document.querySelectorAll('.hk-block-menu, .hk-slash-menu').forEach((e) => e.remove())
})

/** A real keydown through ProseMirror's handlers (as the keyboard sends it). */
const press = (init: KeyboardEventInit) => {
  const event = new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })
  editor.view.someProp('handleKeyDown', (f) => f(editor.view, event))
}

/** "Mod" is ⌘ on Apple platforms, Ctrl elsewhere (the test environment). */
const mod = /Mac|iPhone|iPad/u.test(navigator.platform) ? { metaKey: true } : { ctrlKey: true }

const para = (text: string) => ({ type: 'paragraph', content: [{ type: 'text', text }] })
const withId = (id: string, text: string) => ({ ...para(text), attrs: { id } })
const texts = () =>
  stripIds(editor.getJSON()).content.map(
    (n: JSONContent) => editor.schema.nodeFromJSON(n).textContent
  )

const toggleWith = (summary: string, ...content: object[]) => ({
  type: 'details',
  content: [
    { type: 'detailsSummary', content: [{ type: 'text', text: summary }] },
    { type: 'detailsContent', content }
  ]
})

/** Position of the first occurrence of `text`. */
function posOf(text: string): number {
  let found = -1
  editor.state.doc.descendants((node, pos) => {
    if (found === -1 && node.isText && node.text?.includes(text)) found = pos
    return found === -1
  })
  return found
}

describe('block units', () => {
  it('a paragraph is its own unit; a list item is the unit inside a list', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        para('alone'),
        { type: 'bulletList', content: [{ type: 'listItem', content: [para('item')] }] }
      ]
    })
    expect(unitAtPos(editor.state, posOf('alone'))?.node.type.name).toBe('paragraph')
    expect(unitAtPos(editor.state, posOf('item'))?.node.type.name).toBe('listItem')
  })

  it('text in a table cell or a toggle summary belongs to the whole table / toggle', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        {
          type: 'table',
          content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [para('cell')] }] }]
        },
        {
          type: 'details',
          content: [
            { type: 'detailsSummary', content: [{ type: 'text', text: 'summary' }] },
            { type: 'detailsContent', content: [para('inside')] }
          ]
        }
      ]
    })
    expect(unitAtPos(editor.state, posOf('cell'))?.node.type.name).toBe('table')
    expect(unitAtPos(editor.state, posOf('summary'))?.node.type.name).toBe('details')
    expect(unitAtPos(editor.state, posOf('inside'))?.node.type.name).toBe('paragraph')
  })

  it('the handle of a block inside a toggle, quote or callout is the outermost container’s', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        toggleWith('summary', para('in toggle')),
        { type: 'blockquote', content: [para('quote one'), para('quote two')] },
        { type: 'callout', content: [para('in callout'), toggleWith('inner', para('deep'))] },
        {
          type: 'bulletList',
          content: [
            {
              type: 'listItem',
              content: [
                para('item'),
                { type: 'bulletList', content: [{ type: 'listItem', content: [para('nested')] }] }
              ]
            }
          ]
        },
        {
          type: 'columns',
          content: [
            { type: 'column', content: [para('left')] },
            { type: 'column', content: [para('right')] }
          ]
        }
      ]
    })
    const handle = (text: string) => handleUnitAtPos(editor.state, posOf(text))
    expect(handle('in toggle')?.node.type.name).toBe('details')
    expect(handle('summary')?.node.type.name).toBe('details')
    expect(handle('quote two')?.node.type.name).toBe('blockquote')
    expect(handle('quote two')?.pos).toBe(handle('quote one')?.pos)
    expect(handle('in callout')?.node.type.name).toBe('callout')
    // Nested containers: the outermost one.
    expect(handle('deep')?.node.type.name).toBe('callout')
    // List items keep their own handles, nested ones too; so do blocks in columns.
    expect(handle('nested')?.node.textContent).toBe('nested')
    expect(handle('nested')?.node.type.name).toBe('listItem')
    expect(handle('left')?.node.type.name).toBe('paragraph')
    // Drops and caret commands still see the block inside.
    expect(unitAtPos(editor.state, posOf('in toggle'))?.node.type.name).toBe('paragraph')
  })

  it('in columns, every point finds a block of that column — never the whole row', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        {
          type: 'columns',
          content: [
            { type: 'column', content: [para('left one'), para('left two')] },
            { type: 'column', content: [{ type: 'horizontalRule' }, para('right')] }
          ]
        }
      ]
    })
    const { doc: page } = editor.state
    const columns = page.child(0)
    const left = columns.child(0)
    // Gaps inside the left column: at its start, between its blocks.
    const leftStart = 2
    const between = leftStart + left.child(0).nodeSize
    const rightStart = 1 + left.nodeSize + 1
    const names = (pos: number) => {
      const unit = handleUnitAtPos(editor.state, pos)
      return unit ? `${unit.node.type.name}:${unit.node.textContent}` : null
    }
    expect(names(leftStart)).toBe('paragraph:left one')
    expect(names(between)).toBe('paragraph:left two')
    expect(names(rightStart)).toBe('horizontalRule:')
    // Between the two columns: the next column's first block.
    expect(names(1 + left.nodeSize)).toBe('horizontalRule:')
    // At the row's very start: the first column's first block; past a column's last block: that block.
    expect(names(1)).toBe('paragraph:left one')
    expect(names(1 + left.nodeSize - 1)).toBe('paragraph:left two')
  })

  it('the text range of a unit spans its text blocks and leaves code out', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        {
          type: 'bulletList',
          content: [
            {
              type: 'listItem',
              content: [
                para('first'),
                { type: 'bulletList', content: [{ type: 'listItem', content: [para('nested')] }] }
              ]
            }
          ]
        },
        { type: 'codeBlock', content: [{ type: 'text', text: 'code' }] }
      ]
    })
    const range = unitTextRange(unitAtPos(editor.state, posOf('first'))!)!
    expect(editor.state.doc.textBetween(range.from, range.to, '|')).toBe('first|nested')
    expect(unitTextRange(unitAtPos(editor.state, posOf('code'))!)).toBeNull()
  })

  it('moves a block to a gap, never into itself', () => {
    editor = createEditor(host, doc('one', 'two', 'three'))
    const one = unitAtPos(editor.state, posOf('one'))!
    const end = editor.state.doc.content.size
    editor.view.dispatch(moveUnit(editor.state, one, end)!)
    expect(texts()).toEqual(['two', 'three', 'one'])
    const unit = unitAtPos(editor.state, posOf('one'))!
    expect(moveUnit(editor.state, unit, unit.pos)).toBeNull()
    expect(moveUnit(editor.state, unit, unit.pos + unit.node.nodeSize)).toBeNull()
  })

  it('a list item dragged out of its list lands as its own blocks', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        para('top'),
        {
          type: 'bulletList',
          content: [
            { type: 'listItem', content: [para('a')] },
            { type: 'listItem', content: [para('b')] }
          ]
        }
      ]
    })
    const b = unitAtPos(editor.state, posOf('b'))!
    editor.view.dispatch(moveUnit(editor.state, b, 0)!)
    // (StarterKit keeps a trailing empty paragraph after a list.)
    expect(
      editor
        .getJSON()
        .content?.map((n) => n.type)
        .slice(0, 3)
    ).toEqual(['paragraph', 'paragraph', 'bulletList'])
    expect(texts()[0]).toBe('b')
  })

  it('duplicates below and deletes, keeping a line to type on', () => {
    editor = createEditor(host, doc('only'))
    const unit = unitAtPos(editor.state, posOf('only'))!
    editor.view.dispatch(duplicateUnit(editor.state, unit))
    expect(texts()).toEqual(['only', 'only'])
    const ids = editor.getJSON().content?.map((n) => n.attrs?.id)
    // Wait for UniqueID to stamp the copy.
    expect(new Set(ids).size === 2 || ids?.[1] == null).toBe(true)
    editor.view.dispatch(deleteUnit(editor.state, unitAtPos(editor.state, 1)!))
    editor.view.dispatch(deleteUnit(editor.state, unitAtPos(editor.state, 1)!))
    expect(editor.getJSON().content?.map((n) => n.type)).toEqual(['paragraph'])
  })

  it('⌘⇧↓ moves the block at the caret down, ⌘D duplicates it', () => {
    editor = createEditor(host, doc('first', 'second'))
    editor.commands.setTextSelection(posOf('first'))
    press({ key: 'ArrowDown', ...mod, shiftKey: true })
    expect(texts()).toEqual(['second', 'first'])
    press({ key: 'd', ...mod })
    expect(texts()).toEqual(['second', 'first', 'first'])
  })
})

describe('block handle', () => {
  it('goes while text is selected and may come back once the selection collapses', () => {
    editor = createEditor(host, doc('first line', 'second line'))
    const handle = document.querySelector('.hk-block-handle') as HTMLElement
    // Shown by a hover (not reproducible in this DOM): stand in for it.
    handle.dataset.hidden = 'false'
    editor.commands.setTextSelection({ from: posOf('first'), to: posOf('first') + 5 })
    expect(handle.dataset.hidden).toBe('true')
    handle.dataset.hidden = 'false'
    editor.commands.setTextSelection(posOf('second'))
    expect(handle.dataset.hidden).toBe('false')
  })

  it('stays hidden while typing, and when the page scrolls meanwhile', () => {
    editor = createEditor(host, doc('first line', 'second line'))
    const handle = document.querySelector('.hk-block-handle') as HTMLElement
    // Shown by a hover on "first" (not reproducible in this DOM): stand in for it.
    const controls = (
      editor.view as unknown as { pluginViews: { unit?: unknown }[] }
    ).pluginViews.find((view) => 'unit' in view)!
    controls.unit = unitAtPos(editor.state, posOf('first'))
    handle.dataset.hidden = 'false'
    editor.view.dom.dispatchEvent(new KeyboardEvent('keydown', { key: 'x' }))
    expect(handle.dataset.hidden).toBe('true')
    editor.commands.insertContentAt(posOf('first'), 'x')
    expect(handle.dataset.hidden).toBe('true')
    window.dispatchEvent(new Event('scroll'))
    expect(handle.dataset.hidden).toBe('true')
  })
})

const openMenu = (text: string) => {
  const unit = unitAtPos(editor.state, posOf(text))!
  act(() => openBlockMenu(editor, unit, new DOMRect(10, 10, 20, 20)))
}

describe('block menu', () => {
  it('turns the block into another kind', async () => {
    editor = createEditor(host, doc('make me a heading'))
    openMenu('make me')
    act(() => void fireEvent.mouseMove(screen.getByRole('menuitem', { name: /Turn into/u })))
    act(() => screen.getByRole('menuitemradio', { name: /Heading 2/u }).click())
    expect(editor.getJSON().content?.[0]).toMatchObject({ type: 'heading', attrs: { level: 2 } })
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })

  it('colours the whole block (text and background)', () => {
    editor = createEditor(host, doc('paint'))
    openMenu('paint')
    act(() => void fireEvent.mouseMove(screen.getByRole('menuitem', { name: /Color/u })))
    const red = screen.getAllByRole('menuitemradio', { name: /Red/u })
    act(() => red[1].click())
    expect(editor.getJSON().content?.[0].attrs?.blockBackground).toBe('red')
    expect(editor.getHTML()).toContain('data-block-bg="red"')
  })

  it('asks AI about the whole block: its text is selected and the request carries it', () => {
    const requests: { action: string; units: { html: string }[] }[] = []
    editor = createEditor(host, doc('fix this sentense'), {
      ai: { request: (m) => requests.push(m), cancel: () => {}, title: () => 'Notes' }
    })
    openMenu('fix this')
    act(() => void fireEvent.mouseMove(screen.getByRole('menuitem', { name: /Ask AI/u })))
    act(() => screen.getByRole('menuitem', { name: /Fix spelling/u }).click())
    expect(requests).toHaveLength(1)
    expect(requests[0].action).toBe('fix')
    expect(requests[0].units.map((u) => u.html)).toEqual(['fix this sentense'])
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })

  it('offers no AI for a block without text it can edit', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [{ type: 'codeBlock', content: [{ type: 'text', text: 'let x = 1' }] }]
    })
    openMenu('let x')
    expect(screen.queryByRole('menuitem', { name: /Ask AI/u })).toBeNull()
  })

  it('search finds actions and turn-into targets; Enter runs the first', () => {
    editor = createEditor(host, doc('find'))
    openMenu('find')
    const input = screen.getByPlaceholderText('Search actions…')
    act(() => void fireEvent.change(input, { target: { value: 'quote' } }))
    act(() => void fireEvent.keyDown(input, { key: 'Enter' }))
    expect(editor.getJSON().content?.[0].type).toBe('blockquote')
  })

  it('tints the block while open — any block type, via a decoration — and clears it after', () => {
    editor = createEditor(host, {
      type: 'doc',
      content: [
        {
          type: 'table',
          content: [{ type: 'tableRow', content: [{ type: 'tableCell', content: [para('cell')] }] }]
        }
      ]
    })
    openMenu('cell')
    expect(
      host.querySelector(
        'table.hk-block-selected, .tableWrapper.hk-block-selected, .hk-block-selected'
      )
    ).not.toBeNull()
    // A redraw (an edit elsewhere) keeps the tint: it isn't a class on the DOM node.
    editor.view.dispatch(editor.state.tr.insertText('!', editor.state.doc.content.size - 3))
    expect(host.querySelector('.hk-block-selected')).not.toBeNull()
    act(() => void fireEvent.pointerDown(document.body))
    expect(host.querySelector('.hk-block-selected')).toBeNull()
  })

  it('a press outside closes it', () => {
    editor = createEditor(host, doc('x'))
    openMenu('x')
    expect(document.querySelector('.hk-block-menu')).not.toBeNull()
    act(() => void fireEvent.pointerDown(document.body))
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })

  it('acts on its block where it is now, after the page was replaced under it', () => {
    // A saved page: its blocks carry ids.
    const saved = [withId('a', 'alpha'), withId('b', 'bravo'), withId('c', 'charlie')]
    editor = createEditor(host, { type: 'doc', content: saved })
    openMenu('bravo')
    // A remote reload (as bridge.reload applies it): the same blocks with a line prepended.
    const reloaded = { type: 'doc', content: [withId('n', 'NEW FIRST LINE'), ...saved] }
    act(() => void editor.chain().setMeta('addToHistory', false).setContent(reloaded).run())
    act(() => screen.getByRole('menuitem', { name: /Delete/u }).click())
    expect(texts()).toEqual(['NEW FIRST LINE', 'alpha', 'charlie'])
  })

  it('closes when its block is gone', () => {
    editor = createEditor(host, doc('alpha', 'bravo'))
    openMenu('bravo')
    const unit = unitAtPos(editor.state, posOf('bravo'))!
    act(() => editor.view.dispatch(deleteUnit(editor.state, unit)))
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })

  it('goes with its editor', () => {
    editor = createEditor(host, doc('alpha'))
    openMenu('alpha')
    act(() => editor.destroy())
    expect(document.querySelector('.hk-block-menu')).toBeNull()
  })

  it('Escape closes the submenu first, then the menu, giving the page its focus back', () => {
    editor = createEditor(host, doc('alpha'))
    openMenu('alpha')
    act(() => void fireEvent.mouseMove(screen.getByRole('menuitem', { name: /Turn into/u })))
    expect(screen.queryByRole('menuitemradio', { name: /Heading 2/u })).not.toBeNull()
    act(
      () =>
        void fireEvent.keyDown(screen.getByPlaceholderText('Search actions…'), { key: 'Escape' })
    )
    expect(document.querySelector('.hk-block-menu')).not.toBeNull()
    expect(screen.getByRole('menuitem', { name: /Turn into/u }).getAttribute('aria-expanded')).toBe(
      'false'
    )
    act(
      () =>
        void fireEvent.keyDown(screen.getByPlaceholderText('Search actions…'), { key: 'Escape' })
    )
    expect(document.querySelector('.hk-block-menu')).toBeNull()
    expect(editor.view.hasFocus()).toBe(true)
  })
})

describe('slash menu', () => {
  it('closes when the page is pressed outside it', async () => {
    editor = createEditor(host, null)
    editor.commands.setTextSelection(1)
    editor.commands.insertContent('/')
    await settle()
    expect(document.querySelector('.hk-slash-menu')).not.toBeNull()
    act(() => void fireEvent.pointerDown(document.body))
    await settle()
    expect(document.querySelector('.hk-slash-menu')).toBeNull()
  })
})

describe('drag source decoration', () => {
  it('never throws when the source range no longer matches one node', () => {
    // The controls exist only with a fine pointer.
    const original = window.matchMedia
    window.matchMedia = ((q: string) =>
      ({ matches: q.includes('fine'), media: q }) as MediaQueryList) as typeof window.matchMedia
    editor = createEditor(host, doc('a', 'b'))
    window.matchMedia = original
    expect(BlockHighlightKey.getState(editor.state)?.source).toBeNull()
    const end = editor.state.doc.content.size
    expect(() =>
      setBlockHighlight(editor.view, { source: { from: end, to: end + 3 } })
    ).not.toThrow()
    expect(() => setBlockHighlight(editor.view, { source: { from: 0, to: 3 } })).not.toThrow()
    setBlockHighlight(editor.view, { source: { from: 0, to: 3 } })
    editor.view.dispatch(editor.state.tr.delete(0, 3))
    expect(() => editor.view.dispatch(editor.state.tr.insertText('x', 1))).not.toThrow()
  })
})
