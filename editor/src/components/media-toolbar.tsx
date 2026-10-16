import {
  ArrowExpandIcon,
  Delete02Icon,
  TextAlignCenterIcon,
  TextAlignLeftIcon,
  TextAlignRightIcon
} from '@hugeicons/core-free-icons'
import type { Editor } from '@tiptap/core'
import { NodeSelection } from '@tiptap/pm/state'
import type { Root } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import { Separator } from '@/components/ui/separator'
import { Toggle } from '@/components/ui/toggle'

import { t } from '../core/i18n'
import { safeMediaSrc, type MediaHost } from '../extensions/media'
import { useEditorSnapshot } from '../hooks/use-editor-snapshot'
import { Icon } from './icons'

type Props = { editor: Editor; host: MediaHost | null }

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
export function MediaToolbar({ editor, host }: Props) {
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
        <Icon icon={TextAlignLeftIcon} size={16} aria-hidden />
      </Toggle>
      <Toggle
        size="sm"
        aria-label={t('media.alignCenter')}
        pressed={state.align === 'center'}
        onPressedChange={() => setAlign('center')}
        className={align}
      >
        <Icon icon={TextAlignCenterIcon} size={16} aria-hidden />
      </Toggle>
      <Toggle
        size="sm"
        aria-label={t('media.alignRight')}
        pressed={state.align === 'right'}
        onPressedChange={() => setAlign('right')}
        className={align}
      >
        <Icon icon={TextAlignRightIcon} size={16} aria-hidden />
      </Toggle>
      {state.src?.startsWith('hikki-editor://assets/') && host && (
        <Button
          variant="ghost"
          size="icon-sm"
          aria-label={t('media.view')}
          onClick={() => host.openAsset(state.src!)}
        >
          <Icon icon={ArrowExpandIcon} size={16} aria-hidden />
        </Button>
      )}
      <Separator orientation="vertical" className="mx-0.5 data-[orientation=vertical]:h-5" />
      <Button
        variant="ghost"
        size="icon-sm"
        aria-label={t('media.delete')}
        onClick={() => editor.chain().focus().deleteSelection().run()}
      >
        <Icon icon={Delete02Icon} size={16} aria-hidden />
      </Button>
    </div>
  )
}

/** Draws the toolbar into the media toolbar extension's React root (the BubbleMenu element). */
export function renderMediaToolbar(root: Root, props: Props): void {
  root.render(<MediaToolbar {...props} />)
}
