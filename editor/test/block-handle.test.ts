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

  it('is disabled for coarse (touch) pointers', () => {
    expect(blockHandleExtensions(false)).toEqual([])
    expect(blockHandleExtensions(true)).toHaveLength(1)
  })
})
