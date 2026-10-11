import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import Suggestion, { exitSuggestion, type SuggestionProps } from '@tiptap/suggestion'

import { BLOCK_GROUPS, filterBlockTypes, type BlockType } from '../blocks'
import { handleListKey } from '../ui/CommandList'
import { FloatingLayer } from '../ui/floating'
import { SlashMenu } from '../ui/SlashMenu'

/** The menu's items: grouped (catalog sections in order) without a query, ranked with one. */
export function slashItems(query: string): BlockType[] {
  const items = filterBlockTypes(query)
  if (query.trim()) return items
  return items.toSorted((a, b) => BLOCK_GROUPS.indexOf(a.group) - BLOCK_GROUPS.indexOf(b.group))
}

export const SlashCommandKey = new PluginKey('slashCommand')

/** "/" opens the block menu; typing filters it; ↑↓/Enter or tap picks; Esc closes. */
export const SlashCommand = Extension.create({
  name: 'slashCommand',

  addProseMirrorPlugins() {
    return [
      Suggestion<BlockType, BlockType>({
        editor: this.editor,
        pluginKey: SlashCommandKey,
        char: '/',
        allow: ({ state, range }) => {
          const $from = state.doc.resolve(range.from)
          return $from.parent.type.name !== 'codeBlock'
        },
        items: ({ query }) => slashItems(query),
        command: ({ editor, range, props }) => {
          props.apply(editor.chain().focus().deleteRange(range)).run()
        },
        render: () => {
          let layer: FloatingLayer | null = null
          let selected = 0
          let current: SuggestionProps<BlockType, BlockType> | null = null

          const draw = () => {
            if (!layer || !current) return
            const props = current
            // Items load asynchronously; don't flash "No results" while the first batch is in flight.
            if (props.loading && props.items.length === 0) return
            layer.render(
              <SlashMenu
                items={props.items}
                query={props.query}
                selectedIndex={selected}
                onHover={(i) => {
                  selected = i
                  draw()
                }}
                onSelect={(i) => props.items[i] && props.command(props.items[i])}
                onClose={() => exitSuggestion(props.editor.view, SlashCommandKey)}
              />,
              props.clientRect
            )
          }

          return {
            onStart: (props) => {
              layer = new FloatingLayer('hk-slash-menu', { bare: true })
              current = props
              selected = 0
              draw()
            },
            onUpdate: (props) => {
              current = props
              selected = 0
              draw()
            },
            onKeyDown: ({ event }) => {
              if (!current) return false
              if (event.key === 'Escape') {
                exitSuggestion(current.editor.view, SlashCommandKey)
                return true
              }
              const items = current.items
              return handleListKey(
                event.key,
                items.length,
                selected,
                (i) => {
                  selected = i
                  draw()
                },
                (i) => current!.command(items[i])
              )
            },
            onExit: () => {
              layer?.destroy()
              layer = null
              current = null
            }
          }
        }
      })
    ]
  }
})
