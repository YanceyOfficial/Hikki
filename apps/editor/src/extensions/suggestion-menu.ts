import type { PluginKey } from '@tiptap/pm/state'
import { exitSuggestion, type SuggestionOptions, type SuggestionProps } from '@tiptap/suggestion'

import { handleListKey, renderCommandList, type CommandListItem } from '../components/command-list'
import { FloatingLayer } from '../components/floating'

/**
 * The popup for a typed trigger ("@" pages, ":" emoji): a CommandList under the caret, ↑↓/Enter/Tab or a tap to
 * pick, Escape or a press outside to close (the floating layers' dismiss bus). Opened by typing, so no motion beyond
 * the layer's own. The slash menu has its own (grouped, with a preview).
 */
export function suggestionMenu<T>(
  key: PluginKey,
  className: string,
  toItem: (item: T) => CommandListItem,
  emptyText: () => string,
  /** Draw nothing while nothing matches (":" also starts smileys and times, so an empty menu would be noise). */
  { hideWhenEmpty = false }: { hideWhenEmpty?: boolean } = {}
): SuggestionOptions<T, T>['render'] {
  return () => {
    let layer: FloatingLayer | null = null
    let selected = 0
    let current: SuggestionProps<T, T> | null = null

    const close = () => {
      if (current) exitSuggestion(current.editor.view, key)
    }

    const draw = () => {
      if (!layer || !current) return
      const props = current
      if (props.loading && props.items.length === 0) return
      layer.element.hidden = hideWhenEmpty && props.items.length === 0
      if (layer.element.hidden) return
      renderCommandList(
        layer,
        {
          items: props.items.map(toItem),
          selectedIndex: selected,
          emptyText: emptyText(),
          onHover: (i) => {
            selected = i
            draw()
          },
          onSelect: (i) => {
            if (props.items[i]) props.command(props.items[i])
          }
        },
        props.clientRect
      )
    }

    return {
      onStart: (props) => {
        layer = new FloatingLayer(className, { onDismiss: close })
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
        if (event.key === 'Escape' && !layer?.element.hidden) {
          close()
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
}
