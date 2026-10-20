import { Extension } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

import { t } from '../core/i18n'
import { parsePageLink } from './page-links'

/**
 * What a page dropped on this editor's right edge does (`window.hikki.setSplitDrop`): `open` it beside (no split yet),
 * `replace` what the right side shows (the left page, while split), show it `here` (the right side's own editor), or
 * nothing (`off`: no split view on this device).
 */
export type SplitDropMode = 'off' | 'open' | 'replace' | 'here'

/** What the right-edge drop needs from the host (the bridge). */
export type SplitDropHost = {
  mode: () => SplitDropMode
  /** Open this page in the pane on the right. */
  open: (pageId: string) => void
  /** `replace` and `here`: a page is held over the edge (or no longer) — the app outlines the whole right side instead
   * of this editor drawing a zone over part of it (on the left page it read as a third column). */
  hover: (active: boolean) => void
}

/** The zone's label, spelled out per mode so the l10n audit sees every key. */
const HINT: Record<Exclude<SplitDropMode, 'off'>, () => string> = {
  open: () => t('split.drop.open'),
  replace: () => t('split.drop.replace'),
  here: () => t('split.drop.here')
}

/** Only drags that carry a URL (a page's link) — dragged text and blocks never show the zone. */
const carriesURL = (event: DragEvent) =>
  Array.from(event.dataTransfer?.types ?? []).includes('text/uri-list')

/** How wide the right-edge zone is: a quarter of the page, within these bounds. */
const ZONE_MIN = 96
const ZONE_MAX = 240

export function inSplitZone(clientX: number, width: number): boolean {
  const zone = Math.max(ZONE_MIN, Math.min(ZONE_MAX, width / 4))
  return clientX >= width - zone
}

/** The page a drag carries, from its URL list or text (a sidebar row or a tab carries the page's link). */
export function draggedPage(data: DataTransfer | null): string | null {
  if (!data) return null
  const uris = data
    .getData('text/uri-list')
    .split(/\r?\n/u)
    .filter((line) => line && !line.startsWith('#'))
  for (const text of [...uris, data.getData('text/plain')]) {
    const target = text ? parsePageLink(text) : null
    if (target) return target.pageId
  }
  return null
}

/**
 * Split view by drag (Mac/iPad): a page dragged from the sidebar or a tab over the right edge of a page shows where it
 * would open ("Open on the right"); dropped there it opens in the split pane instead of becoming a link. Anywhere else
 * a dropped page is a link, as before (page links' `handleDrop`). Listens on the document in the capture phase, ahead of
 * ProseMirror, and only for drags that carry a URL — dragged text and blocks never show it.
 */
export function SplitDrop(host: SplitDropHost) {
  const inZone = (event: DragEvent) =>
    host.mode() !== 'off' && carriesURL(event) && inSplitZone(event.clientX, window.innerWidth)

  return Extension.create({
    name: 'splitDrop',

    addProseMirrorPlugins() {
      return [
        new Plugin({
          key: new PluginKey('splitDrop'),
          view: () => {
            const hint = document.createElement('div')
            hint.className = 'hk-split-drop hk-pop-toggle'
            hint.dataset.open = 'false'
            hint.setAttribute('aria-hidden', 'true')
            const label = document.createElement('span')
            hint.append(label)
            document.body.append(hint)

            let hovering = false
            const show = (open: boolean) => {
              const mode = host.mode()
              const outlined = mode === 'replace' || mode === 'here'
              if (outlined || hovering) {
                const active = open && outlined
                if (active !== hovering) host.hover(active)
                hovering = active
                if (outlined) open = false
              }
              if (open && mode !== 'off') label.textContent = HINT[mode]()
              if (hint.dataset.open !== String(open)) hint.dataset.open = String(open)
            }

            const onOver = (event: DragEvent) => {
              const open = inZone(event)
              show(open)
              if (!open) return
              // Ours: no drop cursor in the text, and the drop is allowed over the page's margins too.
              event.preventDefault()
              event.stopPropagation()
              if (event.dataTransfer) event.dataTransfer.dropEffect = 'copy'
            }
            const onDrop = (event: DragEvent) => {
              const open = inZone(event)
              show(false)
              if (!open) return
              const pageId = draggedPage(event.dataTransfer)
              if (!pageId) return
              event.preventDefault()
              event.stopPropagation()
              host.open(pageId)
            }
            const onLeave = (event: DragEvent) => {
              // Left the window (no element entered next).
              if (!event.relatedTarget) show(false)
            }
            const onEnd = () => show(false)

            document.addEventListener('dragover', onOver, true)
            document.addEventListener('drop', onDrop, true)
            document.addEventListener('dragleave', onLeave, true)
            document.addEventListener('dragend', onEnd, true)
            return {
              destroy() {
                document.removeEventListener('dragover', onOver, true)
                document.removeEventListener('drop', onDrop, true)
                document.removeEventListener('dragleave', onLeave, true)
                document.removeEventListener('dragend', onEnd, true)
                hint.remove()
              }
            }
          }
        })
      ]
    }
  })
}
