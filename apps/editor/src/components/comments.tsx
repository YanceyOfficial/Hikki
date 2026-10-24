import type { Editor } from '@tiptap/core'
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from 'react'
import { createRoot } from 'react-dom/client'

import { Button } from '@/components/ui/button'

import { t } from '../core/i18n'
import { type CommentsHost, type ThreadItem } from '../extensions/comments'
import { ChatTeardropTextIcon } from '../generated/icons'
import { useMediaQuery } from '../hooks/use-media-query'
import { CARD, layoutStore, type Anchor, type Layout } from '../lib/comment-layout'
import { PHONE, UPRIGHT_PHONE } from '../lib/device'
import { BottomSheet } from './bottom-sheet'
import { Composer, ThreadCard } from './comment-thread'

/**
 * The layout, measured only when it may have changed: at once when the threads, the open one or the draft change
 * (or the window resizes, or the page moved — `hk-relayout`), and once a frame, after the browser's own layout,
 * while the document changes (typing). A selection that changes nothing of comments measures nothing.
 */
function useLayout(editor: Editor, column: HTMLElement): Layout {
  const store = useMemo(() => layoutStore(editor, column), [editor, column])
  return useSyncExternalStore(store.subscribe, store.get, store.get)
}

/**
 * Draws comments in the page: in a wide window every open thread is a card in the right margin, level with its
 * passage (the open one raised, with its reply field; cards that would overlap push down); in a narrow one each
 * block with comments gets a count badge at its right edge and the open thread shows as a card under its passage.
 * A comment being started shows its composer the same way. Mounted inside the text column, so it scrolls with it.
 */
export function renderComments(editor: Editor, host: CommentsHost): () => void {
  const parent = editor.view.dom.parentElement
  if (!parent) return () => {}
  const element = document.createElement('div')
  element.className = 'hk-comments-layer'
  parent.append(element)
  const root = createRoot(element)
  root.render(<CommentsLayer editor={editor} host={host} column={parent} />)
  return () => {
    queueMicrotask(() => root.unmount())
    element.remove()
  }
}

function CommentsLayer({
  editor,
  host,
  column
}: {
  editor: Editor
  host: CommentsHost
  column: HTMLElement
}) {
  const layout = useLayout(editor, column)
  // A phone (`PHONE` in lib/device: a touch screen in a narrow or short window): the open thread is a bottom sheet.
  const phone = useMediaQuery(PHONE)
  // A page with open threads makes room for their cards: its column moves left where the window allows (style.css).
  const has = layout.anchors.length > 0 || layout.draft !== null
  useEffect(() => {
    // The whole page (header and body) moves; measured again once it has.
    ;(column.closest('#page') ?? column).toggleAttribute('data-comments', has)
    const frame = requestAnimationFrame(() => column.dispatchEvent(new Event('hk-relayout')))
    return () => cancelAnimationFrame(frame)
  }, [column, has])
  return layout.wide && !phone ? (
    <Margin editor={editor} host={host} layout={layout} />
  ) : (
    <Narrow editor={editor} host={host} layout={layout} phone={phone} />
  )
}

/** Wide: a card per thread beside its passage, pushed down where they'd overlap. */
function Margin({ editor, host, layout }: { editor: Editor; host: CommentsHost; layout: Layout }) {
  // Card heights, kept by a ResizeObserver (so stacking knows where each card ends).
  const [heights, setHeights] = useState<Record<string, number>>({})
  const [observer] = useState(
    () =>
      new ResizeObserver((entries) =>
        setHeights((current) => {
          let next = current
          for (const entry of entries) {
            const id = (entry.target as HTMLElement).dataset.thread
            const height = (entry.target as HTMLElement).offsetHeight
            if (id && current[id] !== height) next = { ...next, [id]: height }
          }
          // Unchanged heights keep the same object: no render (a new one each time looped forever).
          return next
        })
      )
  )
  useEffect(() => () => observer.disconnect(), [observer])
  // One ref callback for every card: a new function per render would make React detach and attach it each commit,
  // observing the card again — and a newly observed element is always reported.
  const observe = useCallback(
    (element: HTMLDivElement | null) => {
      if (!element) return
      observer.observe(element)
      return () => observer.unobserve(element)
    },
    [observer]
  )
  const items: { id: string; top: number; node: React.ReactNode }[] = []
  const entries = [
    ...layout.anchors.map((a) => ({ id: a.thread.id, top: a.top, anchor: a })),
    ...(layout.draft ? [{ id: layout.draft.id, top: layout.draft.top, anchor: null }] : [])
  ].toSorted((a, b) => a.top - b.top)
  let bottom = -Infinity
  for (const entry of entries) {
    const top = Math.max(entry.top - 6, bottom + 8)
    bottom = top + (heights[entry.id] ?? 80)
    const active = entry.id === layout.active
    items.push({
      id: entry.id,
      top,
      node: entry.anchor ? (
        <ThreadCard
          editor={editor}
          host={host}
          thread={entry.anchor.thread}
          active={active}
          quote={false}
        />
      ) : (
        <Composer editor={editor} host={host} quote={null} />
      )
    })
  }
  return (
    <>
      {items.map((item) => (
        <div
          key={item.id}
          data-thread={item.id}
          ref={observe}
          className="absolute"
          style={{ left: layout.marginLeft, top: item.top, width: CARD }}
        >
          {item.node}
        </div>
      ))}
    </>
  )
}

/** Narrow: a count badge per block; the open thread (or a new comment) as a card under its passage — on a phone, in a
 * bottom sheet instead. */
function Narrow({
  editor,
  host,
  layout,
  phone
}: {
  editor: Editor
  host: CommentsHost
  layout: Layout
  phone: boolean
}) {
  const blocks = new Map<number, Anchor[]>()
  for (const anchor of layout.anchors)
    blocks.set(anchor.block, [...(blocks.get(anchor.block) ?? []), anchor])
  const open = layout.anchors.find((a) => a.thread.id === layout.active)
  const card = open ?? null
  // An upright phone's slim margin has no room: the badge sat over the words' ends. The passage's underline and wash
  // say there is a thread, and a tap on it opens it.
  const badges = !useMediaQuery(UPRIGHT_PHONE)
  return (
    <>
      {badges &&
        [...blocks.values()].map((anchors) => {
          const count = anchors.reduce((sum, a) => sum + a.thread.comments.length, 0)
          return (
            <Button
              key={anchors[0].block}
              variant="ghost"
              size="xs"
              className="absolute gap-1 bg-muted text-muted-foreground"
              style={{ left: layout.marginLeft, top: anchors[0].blockTop }}
              aria-label={t('comments.count', { count })}
              data-testid="comment-badge"
              onClick={() => editor.commands.commentOpen(anchors[0].thread.id)}
            >
              <ChatTeardropTextIcon className="size-3.5" aria-hidden />
              {count}
            </Button>
          )
        })}
      {phone ? (
        <CommentSheet
          editor={editor}
          host={host}
          thread={host.nativeThreads?.() ? null : (card?.thread ?? null)}
          draft={layout.draft?.quote ?? null}
        />
      ) : (
        <>
          {card && (
            <div className="absolute z-30" style={popoverStyle(card.left, card.bottom)}>
              <ThreadCard editor={editor} host={host} thread={card.thread} active quote />
            </div>
          )}
          {layout.draft && (
            <div
              className="absolute z-30"
              style={popoverStyle(layout.draft.left, layout.draft.bottom)}
            >
              <Composer editor={editor} host={host} quote={layout.draft.quote} />
            </div>
          )}
        </>
      )}
    </>
  )
}

/**
 * A phone's open thread, or a new comment, as a bottom sheet over the dimmed page (the shadcn Drawer): its grabber
 * and the scrim dismiss it, as Escape does; the reply field stays at its foot, above the keyboard. Opening it never
 * focuses a field (no keyboard) unless a new comment is being written; closing it never gives the page the caret back.
 */
function CommentSheet({
  editor,
  host,
  thread,
  draft
}: {
  editor: Editor
  host: CommentsHost
  thread: ThreadItem | null
  /** The quote of a comment being started. */
  draft: string | null
}) {
  const open = thread !== null || draft !== null
  // What it shows stays while it slides away.
  const [shown, setShown] = useState({ thread, draft })
  if (open && (shown.thread !== thread || shown.draft !== draft)) setShown({ thread, draft })
  const popup = useRef<HTMLDivElement>(null)
  const close = () => editor.commands.commentOpen(null)
  return (
    <BottomSheet
      open={open}
      onClose={close}
      title={t('comments.discussion')}
      titleHidden
      testId="comment-sheet"
      popupRef={popup}
      initialFocus={shown.draft === null ? () => popup.current : true}
    >
      {shown.draft === null ? (
        shown.thread && (
          <ThreadCard
            editor={editor}
            host={host}
            thread={shown.thread}
            active
            quote
            onClose={close}
            sheet
          />
        )
      ) : (
        <Composer editor={editor} host={host} quote={shown.draft} onClose={close} sheet />
      )}
    </BottomSheet>
  )
}

/** Under the passage, kept inside the window horizontally. */
function popoverStyle(left: number, bottom: number): React.CSSProperties {
  return {
    left: Math.max(0, Math.min(left - 16, window.innerWidth - 520)),
    top: bottom + 8,
    width: 'min(480px, calc(100vw - 32px))'
  }
}
