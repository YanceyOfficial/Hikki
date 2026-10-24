import type { Transaction } from '@tiptap/pm/state'
import { afterEach, describe, expect, it } from 'vitest'

import { createEditor } from '../src/core/editor'
import { changedRanges, visitChanged } from '../src/lib/changed-ranges'
import { doc } from './helpers'

let editor: ReturnType<typeof createEditor> | null = null
afterEach(() => {
  editor?.destroy()
  editor = null
})

const paragraphs = (n: number) => doc(...Array.from({ length: n }, (_, i) => `line ${i}`))

/** Runs `change` and returns the transactions it dispatched. */
function capture(change: () => void): Transaction[] {
  const seen: Transaction[] = []
  const record = ({ transaction }: { transaction: Transaction }) => void seen.push(transaction)
  editor!.on('transaction', record)
  change()
  editor!.off('transaction', record)
  return seen
}

describe('changed ranges', () => {
  it('a keystroke in a long page is visited where it happened, not page-wide', () => {
    editor = createEditor(document.createElement('div'), paragraphs(500))
    const transactions = capture(() => editor!.commands.insertContentAt(40, 'x'))
    const ranges = changedRanges(transactions, editor.state.doc)
    expect(ranges).not.toBeNull()
    let visited = 0
    visitChanged(editor.state.doc, ranges, () => {
      visited += 1
      return true
    })
    expect(visited).toBeLessThan(10)
  })

  it('mark steps count where they acted (they move nothing)', () => {
    editor = createEditor(document.createElement('div'), paragraphs(20))
    const transactions = capture(() =>
      editor!.chain().setTextSelection({ from: 100, to: 104 }).toggleBold().run()
    )
    const ranges = changedRanges(transactions, editor.state.doc)!
    expect(ranges.some(({ from, to }) => from <= 100 && to >= 104)).toBe(true)
  })

  it('without ranges, the whole page is walked', () => {
    editor = createEditor(document.createElement('div'), paragraphs(3))
    let visited = 0
    visitChanged(editor.state.doc, null, () => {
      visited += 1
      return true
    })
    // Three paragraphs and their text.
    expect(visited).toBe(6)
  })
})
