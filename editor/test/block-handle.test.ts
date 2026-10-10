import { describe, expect, it } from 'vitest'
import { createEditor } from '../src/editor'
import { blockHandleExtensions, isDraggableBlock } from '../src/extensions/block-handle'

describe('block handle', () => {
  it('offers every body block for dragging', () => {
    const editor = createEditor(document.createElement('div'), null)
    expect(isDraggableBlock(editor.state.doc.child(0))).toBe(true)
    expect(isDraggableBlock(null)).toBe(false)
    editor.destroy()
  })

  it('starts hidden so it never shows at the top-left before a block is hovered', () => {
    const host = document.createElement('div')
    document.body.append(host)
    const editor = createEditor(host, null)
    const grip = document.querySelector('.hk-drag-handle')
    // jsdom-like envs report pointer: fine as false, so build one explicitly.
    const [ext] = blockHandleExtensions(true)
    const rendered = (ext.options as { render: () => HTMLElement }).render()
    expect(rendered.classList.contains('hk-hidden')).toBe(true)
    expect(grip === null || grip.classList.contains('hk-hidden')).toBe(true)
    editor.destroy()
    host.remove()
  })

  it('is disabled for coarse (touch) pointers', () => {
    expect(blockHandleExtensions(false)).toEqual([])
    expect(blockHandleExtensions(true)).toHaveLength(1)
  })
})
