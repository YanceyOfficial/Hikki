import { describe, expect, it } from 'vitest'
import { createEditor } from '../src/editor'
import { blockHandleExtensions, isDraggableBlock } from '../src/extensions/block-handle'

describe('block handle', () => {
  it('never offers the title for dragging', () => {
    const editor = createEditor(document.createElement('div'), null)
    const [title, paragraph] = [editor.state.doc.child(0), editor.state.doc.child(1)]
    expect(isDraggableBlock(title)).toBe(false)
    expect(isDraggableBlock(paragraph)).toBe(true)
    expect(isDraggableBlock(null)).toBe(false)
    editor.destroy()
  })

  it('is disabled for coarse (touch) pointers', () => {
    expect(blockHandleExtensions(false)).toEqual([])
    expect(blockHandleExtensions(true)).toHaveLength(1)
  })
})
