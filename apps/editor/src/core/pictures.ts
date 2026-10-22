import type { Editor } from '@tiptap/core'
import type { Node as PMNode } from '@tiptap/pm/model'

import { localAssetSrc } from '../extensions/media'
import { insertBlocksAt } from './touch-tools'

/** A picture the chat made, stored in the workspace's assets; `alt` is what it was asked to draw. */
export type PictureItem = { src: string; alt: string }

/** Where they go (`PicturePlace` natively): after a block — in place of it while it is an empty line — or in place
 * of the picture being changed. Null, or a block that is gone: at the caret. */
export type PicturePlace = { blockId: string | null; replace: boolean } | null

/**
 * Pictures from the chat put into the page, one undo step: in place of the picture they change (`replace`, when that
 * block is still a picture), else where "+" puts blocks from the place's block — or from the caret when there is none.
 * Only workspace pictures go in (`localAssetSrc`); the description stays on each as its `alt`.
 */
export function insertPictures(editor: Editor, items: PictureItem[], place: PicturePlace): boolean {
  if (!editor.isEditable) return false
  const image = editor.schema.nodes.image
  const nodes = items.flatMap((item) => {
    const src = localAssetSrc(item.src)
    return src && image ? [image.create({ src, alt: item.alt.slice(0, 1000) })] : []
  })
  if (nodes.length === 0) return false
  const { state } = editor
  const found = place?.blockId ? blockById(state.doc, place.blockId) : null
  const tr = state.tr
  if (found && place?.replace && found.node.type === image) {
    tr.replaceWith(found.pos, found.pos + found.node.nodeSize, nodes)
  } else if (found && !found.node.isTextblock) {
    // A block without text (a picture, an embed): right after it.
    tr.insert(found.pos + found.node.nodeSize, nodes)
  } else {
    insertBlocksAt(tr, nodes, found ? tr.doc.resolve(found.pos + 1) : state.selection.$from)
  }
  editor.view.dispatch(tr.scrollIntoView())
  return true
}

function blockById(doc: PMNode, id: string): { node: PMNode; pos: number } | null {
  let found: { node: PMNode; pos: number } | null = null
  doc.descendants((node, pos) => {
    if (found) return false
    if (node.attrs.id === id) found = { node, pos }
    return !found
  })
  return found
}
