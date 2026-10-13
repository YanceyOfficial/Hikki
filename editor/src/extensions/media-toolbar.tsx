import {
  ArrowsOutIcon,
  TextAlignCenterIcon,
  TextAlignLeftIcon,
  TextAlignRightIcon,
  TrashIcon
} from '@phosphor-icons/react'
import { Extension, type Editor } from '@tiptap/core'
import { BubbleMenuPlugin } from '@tiptap/extension-bubble-menu'
import { NodeSelection, PluginKey } from '@tiptap/pm/state'
import { createRoot, type Root } from 'react-dom/client'

import { t } from '../i18n'
import { cn } from '../ui/cn'
import { IconProvider } from '../ui/icons'
import { useEditorSnapshot } from '../ui/use-editor-snapshot'
import type { MediaHost } from './media'
import { safeMediaSrc } from './media'

export const MediaToolbarKey = new PluginKey('mediaToolbar')

function selectedImage(editor: Editor) {
  const { selection } = editor.state
  const node =
    selection instanceof NodeSelection && selection.node.type.name === 'image'
      ? selection.node
      : null
  return {
    align: (node?.attrs.align as string | undefined) ?? 'center',
    src: node ? safeMediaSrc(node.attrs.src, 'image') : null
  }
}

const button = (active: boolean) =>
  cn(
    'grid size-8 cursor-pointer place-items-center rounded-md text-foreground hover:bg-accent active:scale-[0.97]',
    active && 'bg-accent text-accent-strong'
  )

/** Over a selected image: alignment, view full size (Quick Look, for our assets), delete. */
function MediaToolbar({ editor, host }: { editor: Editor; host: MediaHost | null }) {
  const state = useEditorSnapshot(editor, selectedImage)
  const align = (value: 'left' | 'center' | 'right') =>
    editor.chain().focus().updateAttributes('image', { align: value }).run()
  return (
    <div
      role="toolbar"
      aria-label={t('media.imageToolbar')}
      className="hk-pop flex items-center gap-0.5 rounded-lg bg-popover p-1 shadow-popover"
      onMouseDown={(e) => e.preventDefault()}
    >
      <button
        type="button"
        aria-label={t('media.alignLeft')}
        aria-pressed={state.align === 'left'}
        className={button(state.align === 'left')}
        onClick={() => align('left')}
      >
        <TextAlignLeftIcon size={16} aria-hidden />
      </button>
      <button
        type="button"
        aria-label={t('media.alignCenter')}
        aria-pressed={state.align === 'center'}
        className={button(state.align === 'center')}
        onClick={() => align('center')}
      >
        <TextAlignCenterIcon size={16} aria-hidden />
      </button>
      <button
        type="button"
        aria-label={t('media.alignRight')}
        aria-pressed={state.align === 'right'}
        className={button(state.align === 'right')}
        onClick={() => align('right')}
      >
        <TextAlignRightIcon size={16} aria-hidden />
      </button>
      {state.src?.startsWith('hikki-editor://assets/') && host && (
        <button
          type="button"
          aria-label={t('media.view')}
          className={button(false)}
          onClick={() => host.openAsset(state.src!)}
        >
          <ArrowsOutIcon size={16} aria-hidden />
        </button>
      )}
      <div className="mx-0.5 h-5 w-px bg-border" />
      <button
        type="button"
        aria-label={t('media.delete')}
        className={button(false)}
        onClick={() => editor.chain().focus().deleteSelection().run()}
      >
        <TrashIcon size={16} aria-hidden />
      </button>
    </div>
  )
}

export function mediaToolbarExtension(host: MediaHost | null) {
  return Extension.create<
    Record<string, never>,
    { element: HTMLDivElement | null; root: Root | null }
  >({
    name: 'mediaToolbar',
    addStorage: () => ({ element: null, root: null }),
    addProseMirrorPlugins() {
      const element = document.createElement('div')
      element.className = 'hk-media-toolbar fixed top-0 left-0 z-40 w-max'
      this.storage.element = element
      return [
        BubbleMenuPlugin({
          pluginKey: MediaToolbarKey,
          editor: this.editor,
          element,
          appendTo: () => document.body,
          options: {
            strategy: 'fixed',
            placement: 'top',
            offset: 8,
            flip: { padding: 8 },
            shift: { padding: 8 }
          },
          shouldShow: ({ editor, state }) =>
            editor.isEditable &&
            state.selection instanceof NodeSelection &&
            state.selection.node.type.name === 'image'
        })
      ]
    },
    onCreate() {
      const element = this.storage.element
      if (!element) return
      const root = createRoot(element)
      root.render(
        <IconProvider>
          <MediaToolbar editor={this.editor} host={host} />
        </IconProvider>
      )
      this.storage.root = root
    },
    onDestroy() {
      const { root, element } = this.storage
      queueMicrotask(() => root?.unmount())
      element?.remove()
    }
  })
}
