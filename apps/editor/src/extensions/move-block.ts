import type { Editor, JSONContent } from '@tiptap/core'

import { blockTexts, wordCount } from '../core/extract'
import { deleteUnit, followNode, type BlockUnit } from './block-units'
import type { PageIndexEntry } from './page-links'

/** Where blocks can go (the bridge): the sidebar's pages, and the app that appends them to one. */
export type MoveBlockHost = {
  pages: () => PageIndexEntry[]
  currentPageId: () => string | null
  /** Appends `blocks` to the end of page `target` (the app writes it, and any editor showing it reloads); true once
   * they are there. `text` / `words`: what they add to the page's text and word count. */
  move: (target: string, blocks: JSONContent[], text: string, words: number) => Promise<boolean>
}

let host: MoveBlockHost | null = null
export function setMoveBlockHost(next: MoveBlockHost | null): void {
  host = next
}
export const moveBlockHost = (): MoveBlockHost | null => host

/** List items travel in a list of their own kind; everything else as it is. */
const LIST_OF: Record<string, string> = { listItem: 'bulletList', taskItem: 'taskList' }

/**
 * A unit as the target page takes it: a list item wrapped in its list (an ordered one keeps its kind), comment marks
 * left behind (their threads belong to this page).
 */
export function movedContent(editor: Editor, unit: BlockUnit): JSONContent {
  const json = stripComments(unit.node.toJSON() as JSONContent)
  const list = LIST_OF[unit.node.type.name]
  if (!list) return json
  const parent = editor.state.doc.resolve(unit.pos).parent.type.name
  return { type: parent === 'orderedList' ? 'orderedList' : list, content: [json] }
}

function stripComments(node: JSONContent): JSONContent {
  const marks = node.marks?.filter((m) => m.type !== 'comment')
  const { marks: _, content, ...rest } = node
  return {
    ...rest,
    ...(marks?.length ? { marks } : {}),
    ...(content ? { content: content.map(stripComments) } : {})
  }
}

/**
 * Moves the block to the end of page `target`: the app adds it there first, and only then does it leave this page
 * (one undo step) — a failure leaves it where it was, never lost. The block is followed through the wait (edits
 * meanwhile move it; gone meanwhile, there is nothing more to do here).
 */
export async function moveUnitTo(
  editor: Editor,
  unit: BlockUnit,
  target: string
): Promise<boolean> {
  if (!host || !editor.isEditable || target === host.currentPageId()) return false
  const block = movedContent(editor, unit)
  const text = blockTexts({ type: 'doc', content: [block] }).join('\n')
  const follow = followNode(editor, unit.pos, () => {})
  try {
    if (!(await host.move(target, [block], text, wordCount(text)))) return false
    const now = follow.current
    if (now && !editor.isDestroyed) editor.view.dispatch(deleteUnit(editor.state, now))
    return true
  } finally {
    follow.stop()
  }
}
