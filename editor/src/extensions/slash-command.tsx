import { Extension } from '@tiptap/core'
import { PluginKey } from '@tiptap/pm/state'
import Suggestion, { type SuggestionProps } from '@tiptap/suggestion'

import { filterBlockTypes, type BlockType } from '../blocks'
import { CommandList, handleListKey } from '../ui/CommandList'
import { FloatingLayer } from '../ui/floating'

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
        items: ({ query }) => filterBlockTypes(query),
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
              <CommandList
                items={props.items}
                selectedIndex={selected}
                onHover={(i) => {
                  selected = i
                  draw()
                }}
                onSelect={(i) => props.items[i] && props.command(props.items[i])}
              />,
              props.clientRect
            )
          }

          return {
            onStart: (props) => {
              layer = new FloatingLayer('hk-slash-menu w-[300px] max-w-[calc(100vw-16px)]')
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
                layer?.destroy()
                layer = null
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
