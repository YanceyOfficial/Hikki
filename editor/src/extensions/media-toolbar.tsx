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

import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { Toggle } from '@/components/ui/toggle'

import { t } from '../i18n'
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

/** The toolbar's alignment switches: pressed = the image's current alignment. */
const align =
  'size-8 min-w-8 px-0 text-foreground hover:bg-accent aria-pressed:bg-accent aria-pressed:text-foreground'

/** Over a selected image: alignment, view full size (Quick Look, for our assets), delete. */
function MediaToolbar({ editor, host }: { editor: Editor; host: MediaHost | null }) {
  const state = useEditorSnapshot(editor, selectedImage)
  const setAlign = (value: 'left' | 'center' | 'right') =>
    editor.chain().focus().updateAttributes('image', { align: value }).run()
  return (
    <div
      role="toolbar"
      aria-label={t('media.imageToolbar')}
      className="hk-pop flex items-center gap-0.5 rounded-lg bg-popover p-1 shadow-popover"
      onMouseDown={(e) => e.preventDefault()}
    >
      <Toggle
        size="sm"
        aria-label={t('media.alignLeft')}
        pressed={state.align === 'left'}
        onPressedChange={() => setAlign('left')}
        className={align}
      >
        <TextAlignLeftIcon size={16} aria-hidden />
      </Toggle>
      <Toggle
        size="sm"
        aria-label={t('media.alignCenter')}
        pressed={state.align === 'center'}
        onPressedChange={() => setAlign('center')}
        className={align}
      >
        <TextAlignCenterIcon size={16} aria-hidden />
      </Toggle>
      <Toggle
        size="sm"
        aria-label={t('media.alignRight')}
        pressed={state.align === 'right'}
        onPressedChange={() => setAlign('right')}
        className={align}
      >
        <TextAlignRightIcon size={16} aria-hidden />
      </Toggle>
      {state.src?.startsWith('hikki-editor://assets/') && host && (
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={t('media.view')}
          onClick={() => host.openAsset(state.src!)}
        >
          <ArrowsOutIcon size={16} aria-hidden />
        </Button>
      )}
      <Separator orientation="vertical" className="mx-0.5 data-[orientation=vertical]:h-5" />
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={t('media.delete')}
        onClick={() => editor.chain().focus().deleteSelection().run()}
      >
        <TrashIcon size={16} aria-hidden />
      </Button>
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
