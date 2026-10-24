import type { Editor } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { cn } from 'cn'
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'

import { Input } from '@/components/ui/input'

import { blockCounts, blockKindLabel, unitTypeId } from '../core/block-kinds'
import { blockLinkFor } from '../core/block-link'
import { TURN_INTO } from '../core/blocks'
import { notify, reportError } from '../core/errors'
import { t } from '../core/i18n'
import { isWebURL } from '../core/links'
import { shortcutLabel } from '../core/shortcuts'
import type { AIAction } from '../extensions/ai-review'
import { setBlockHighlight } from '../extensions/block-highlight'
import {
  deleteUnit,
  duplicateUnit,
  firstTextPos,
  followNode,
  unitTextRange,
  type BlockUnit,
  type Followed
} from '../extensions/block-units'
import { BLOCK_COLOR_TYPES, type PaletteColor } from '../extensions/colors'
import { blockQuote } from '../extensions/comments'
import { openEmbedPanel, type EmbedHost } from '../extensions/embed'
import { openCaptionPanel } from '../extensions/embed-caption'
import { moveBlockHost, moveUnitTo } from '../extensions/move-block'
import { blockLabel, copyLink } from '../extensions/page-links'
import {
  ArrowBendUpRightIcon,
  ArrowSquareOutIcon,
  ArrowsClockwiseIcon,
  ArrowsLeftRightIcon,
  CaretRightIcon,
  ChatTeardropTextIcon,
  CopyIcon,
  LinkIcon,
  LinkSimpleIcon,
  PaintBrushIcon,
  SparkleIcon,
  SubtitlesIcon,
  TrashIcon
} from '../generated/icons'
import { mediaRef } from '../lib/ai-content'
import { AIPanel } from './ai-panel'
import { BlockTypeList } from './block-type-list'
import { ColorList } from './color-list'
import { FloatingLayer, usePresence } from './floating'
import { GlidingHighlight } from './gliding-highlight'
import { IconProvider } from './icons'
import { MenuRow } from './menu-row'
import { PagePicker } from './page-picker'

let open: { layer: FloatingLayer; close: () => void } | null = null

/** Opens the block menu for `unit` below `anchor` (the grip). One at a time. */
export function openBlockMenu(editor: Editor, unit: BlockUnit, anchor: DOMRect): void {
  open?.close()
  // What Escape means inside the menu (a submenu closes first); set by the menu while it is mounted.
  let escape: (() => boolean) | null = null
  // Escape or a press anywhere outside closes it (and the press does what it does): the layers' bus.
  const layer = new FloatingLayer('hk-block-menu', {
    bare: true,
    onDismiss: (reason) => {
      if (reason === 'escape' && escape?.()) return 'keep'
      close()
      if (reason === 'escape' && !editor.isDestroyed) editor.view.focus()
    }
  })
  // The block, wherever later edits (a remote reload) put it; gone with it, or with the editor, the menu goes.
  const follow = followNode(editor, unit.pos, () => close())
  // The block is tinted while its menu is open (a decoration: the same for every block type).
  setBlockHighlight(editor.view, { menu: { from: unit.pos, to: unit.pos + unit.node.nodeSize } })
  let closed = false
  function close() {
    if (closed) return
    closed = true
    follow.stop()
    if (!editor.isDestroyed) setBlockHighlight(editor.view, { menu: null })
    layer.destroy()
    if (open?.layer === layer) open = null
  }
  open = { layer, close }
  layer.render(
    <IconProvider>
      <BlockMenu
        editor={editor}
        unit={unit}
        follow={follow}
        onEscape={(handler) => {
          escape = handler
        }}
        onClose={close}
      />
    </IconProvider>,
    () => anchor
  )
}

type Submenu = 'ai' | 'turnInto' | 'color' | 'moveTo'

type Item = {
  id: string
  label: string
  icon: ReactNode
  keys?: string
  submenu?: Submenu
  destructive?: boolean
  run?: () => void
  /** Rows of one section sit together; a line parts sections (Notion's). */
  section: number
}

/** The embed extension's host (where an original page opens), or null without one. */
function embedHost(editor: Editor): EmbedHost | null {
  const embed = editor.extensionManager.extensions.find((e) => e.name === 'embed')
  return (embed?.options as { host?: EmbedHost | null } | undefined)?.host ?? null
}

function BlockMenu({
  editor,
  unit,
  follow,
  onEscape,
  onClose
}: {
  editor: Editor
  /** The block as it was when the menu opened: what the menu shows. */
  unit: BlockUnit
  /** The block now: what actions run on. */
  follow: Followed<BlockUnit>
  /** Gives the menu's answer to Escape (true when it handled it: closed a submenu); the bus asks it. */
  onEscape: (handler: (() => boolean) | null) => void
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState(0)
  const [submenu, setSubmenu] = useState<Submenu | null>(null)
  const listRef = useRef<HTMLDivElement>(null)
  const submenuRef = useRef<HTMLDivElement>(null)
  // The submenu stays in the tree through its leave motion, showing whatever it last showed.
  const submenuShown = usePresence(submenu !== null, submenuRef)
  const [shownSubmenu, setShownSubmenu] = useState(submenu)
  if (submenu && submenu !== shownSubmenu) setShownSubmenu(submenu)

  // A long submenu opened near the bottom of the window moves up so all of it is reachable.
  useLayoutEffect(() => {
    const panel = submenuRef.current
    if (!panel || !submenu) return
    panel.style.top = '0px'
    const rect = panel.getBoundingClientRect()
    const limit = (window.visualViewport?.height ?? window.innerHeight) - 8
    if (rect.bottom > limit)
      panel.style.top = `${-Math.min(rect.bottom - limit, Math.max(0, rect.top - 8))}px`
  }, [submenu])
  const inputRef = useRef<HTMLInputElement>(null)
  const turnable = TURN_INTO.some((b) => b.id === unitTypeId(editor, unit))
  const kind = blockKindLabel(unit.node, editor.state.doc.resolve(unit.pos))
  const colorable = BLOCK_COLOR_TYPES.includes(unit.node.type.name)
  const editable = editor.isEditable
  const counts = blockCounts(unit.node)
  // Move to: any other page the sidebar knows.
  const mover = moveBlockHost()
  const movable = editable && !!mover

  useEffect(() => {
    inputRef.current?.focus()
  }, [])
  useEffect(() => {
    onEscape(() => {
      if (!submenu) return false
      setSubmenu(null)
      return true
    })
    return () => onEscape(null)
  }, [onEscape, submenu])

  /** Colours the block where it is now. */
  const paint = (attrs: Record<string, PaletteColor | null>) =>
    act((now) =>
      editor.view.dispatch(
        editor.state.tr.setNodeMarkup(now.pos, undefined, { ...now.node.attrs, ...attrs })
      )
    )()

  /** Runs on the block where it is now (the menu closed itself if it is gone), then closes. */
  const act = (run: (unit: BlockUnit) => void) => () => {
    const now = follow.current
    if (now) run(now)
    onClose()
    if (!editor.isDestroyed) editor.view.focus()
  }
  const blockId = unit.node.attrs.id as string | null | undefined
  const link = blockId ? blockLinkFor(blockId) : null

  // AI works on the block's text (not on code), or reads its picture or PDF.
  const hasAIText = unitTextRange(unit) !== null
  const media = hasAIText ? null : mediaRef(unit.node)
  const runAI = (action: AIAction) => {
    const now = follow.current
    if (media) {
      onClose()
      if (now) editor.commands.aiRunMedia(now.pos, action)
      return
    }
    const aiRange = now ? unitTextRange(now) : null
    onClose()
    if (!aiRange) return
    editor.view.dispatch(
      editor.state.tr.setSelection(TextSelection.create(editor.state.doc, aiRange.from, aiRange.to))
    )
    editor.view.focus()
    editor.commands.aiRun(action)
  }

  // An embed's own actions (Notion's): another link, a caption, the original page.
  const embed = unit.node.type.name === 'embed'
  const original = embed ? (unit.node.attrs.original as string | null) : null
  const host = embed ? embedHost(editor) : null
  // A comment on the block's text (a passage), or — a block without text — on the whole block.
  const commentable = editable && (hasAIText || typeof blockId === 'string')
  const startComment = () => {
    const now = follow.current
    onClose()
    if (!now || editor.isDestroyed) return
    const range = unitTextRange(now)
    if (range) {
      editor.view.dispatch(
        editor.state.tr.setSelection(TextSelection.create(editor.state.doc, range.from, range.to))
      )
      editor.commands.commentStart()
    } else {
      editor.commands.commentStartBlock(now.pos, blockQuote(now.node, kind))
    }
  }

  const items: Item[] = [
    ...(embed && editable
      ? [
          {
            id: 'replace',
            label: t('blockMenu.replace'),
            icon: <ArrowsLeftRightIcon size={18} />,
            section: 0,
            run: () => {
              const now = follow.current
              onClose()
              if (now) openEmbedPanel(editor, 'generic', now.pos)
            }
          },
          {
            id: 'caption',
            label: t('blockMenu.caption'),
            icon: <SubtitlesIcon size={18} />,
            section: 0,
            run: () => {
              const now = follow.current
              onClose()
              if (now) openCaptionPanel(editor, now.pos)
            }
          }
        ]
      : []),
    ...(original && isWebURL(original) && host
      ? [
          {
            id: 'openOriginal',
            label: t('blockMenu.openInBrowser'),
            icon: <ArrowSquareOutIcon size={18} />,
            section: 0,
            run: act(() => host.openExternal(original))
          },
          {
            id: 'copyOriginal',
            label: t('blockMenu.copyOriginal'),
            icon: <LinkIcon size={18} />,
            section: 0,
            run: act(() => {
              void navigator.clipboard
                ?.writeText(original)
                .then(() => notify('success', t('blockMenu.linkCopied')))
                .catch((error: unknown) => reportError('copyFailed', error))
            })
          }
        ]
      : []),
    ...(turnable
      ? [
          {
            id: 'turnInto',
            label: t('blockMenu.turnInto'),
            icon: <ArrowsClockwiseIcon size={18} />,
            submenu: 'turnInto' as const,
            section: 1
          }
        ]
      : []),
    ...(colorable
      ? [
          {
            id: 'color',
            label: t('blockMenu.color'),
            icon: <PaintBrushIcon size={18} />,
            submenu: 'color' as const,
            section: 1
          }
        ]
      : []),
    ...(link
      ? [
          {
            id: 'copyLink',
            label: t('blockMenu.copyLink'),
            icon: <LinkSimpleIcon size={18} />,
            section: 2,
            // A ready hyperlink (the block's text) plus the URL: pasting it lands as a link.
            run: act((now) => void copyLink(link.href, blockLabel(now.node) ?? link.pageLabel))
          }
        ]
      : []),
    {
      id: 'duplicate',
      label: t('blockMenu.duplicate'),
      icon: <CopyIcon size={18} />,
      keys: shortcutLabel('duplicateBlock'),
      section: 2,
      run: act((now) => editor.view.dispatch(duplicateUnit(editor.state, now)))
    },
    ...(movable
      ? [
          {
            id: 'moveTo',
            label: t('blockMenu.moveTo'),
            icon: <ArrowBendUpRightIcon size={18} />,
            submenu: 'moveTo' as const,
            section: 2
          }
        ]
      : []),
    {
      id: 'delete',
      label: t('blockMenu.delete'),
      icon: <TrashIcon size={18} />,
      keys: 'Del',
      destructive: true,
      section: 2,
      run: act((now) => editor.view.dispatch(deleteUnit(editor.state, now)))
    },
    ...(commentable
      ? [
          {
            id: 'comment',
            label: t('blockMenu.comment'),
            icon: <ChatTeardropTextIcon size={18} />,
            keys: shortcutLabel('comment'),
            section: 3,
            run: startComment
          }
        ]
      : []),
    ...(editable && (hasAIText || media)
      ? [
          {
            id: 'ai',
            label: t('ai.menu'),
            icon: <SparkleIcon size={18} />,
            submenu: 'ai' as const,
            section: 4
          }
        ]
      : [])
  ]

  // With a query: matching actions and Turn-into targets, flat.
  const visible: Item[] = (() => {
    const q = query.trim().toLowerCase()
    if (!q) return items
    const turnInto = TURN_INTO.map((block) => ({
      id: `turn-${block.id}`,
      label: `${t('blockMenu.turnInto')} › ${block.label()}`,
      icon: <block.icon size={18} />,
      run: act((now) => turnUnitInto(editor, now, block.id)),
      section: 1
    }))
    return [...items.filter((i) => !i.submenu), ...(turnable ? turnInto : [])].filter((i) =>
      i.label.toLowerCase().includes(q)
    )
  })()

  const choose = (index: number) => {
    const item = visible[index]
    if (!item) return
    if (item.submenu) setSubmenu(item.submenu)
    else item.run?.()
  }

  return (
    <div
      className="relative"
      onKeyDown={(e) => {
        if (e.nativeEvent.isComposing) return
        // Escape is the layers' bus (onDismiss in openBlockMenu): it never reaches here.
        if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
          e.preventDefault()
          const step = e.key === 'ArrowDown' ? 1 : -1
          setSelected((i) => (i + step + visible.length) % Math.max(1, visible.length))
        } else if (e.key === 'Enter' || (e.key === 'ArrowRight' && visible[selected]?.submenu)) {
          e.preventDefault()
          choose(selected)
        } else if (e.key === 'ArrowLeft' && submenu) {
          setSubmenu(null)
        }
      }}
    >
      <div
        role="menu"
        aria-label={t('blockMenu.label')}
        className="flex w-64 flex-col rounded-xl bg-popover p-1 text-popover-foreground shadow-popover"
      >
        <Input
          ref={inputRef}
          className="m-1 mb-1.5 h-8 w-auto md:text-sm"
          placeholder={t('blockMenu.search')}
          aria-label={t('blockMenu.search')}
          value={query}
          onChange={(e) => {
            setQuery(e.target.value)
            setSelected(0)
            setSubmenu(null)
          }}
        />
        {!query && (
          <div
            className="px-2 pt-1 pb-1 text-xs font-medium text-muted-foreground"
            data-testid="block-menu-kind"
          >
            {kind}
          </div>
        )}
        <div
          ref={listRef}
          className="relative max-h-[min(420px,calc(100vh-160px))] overflow-y-auto overscroll-contain"
        >
          <GlidingHighlight listRef={listRef} index={selected} />
          {visible.length === 0 && (
            <div className="px-2 py-1.5 text-sm text-muted-foreground">{t('editor.noResults')}</div>
          )}
          {visible.map((item, i) => [
            !query && i > 0 && visible[i - 1].section !== item.section && (
              <div key={`line-${item.id}`} role="separator" className="mx-2 my-1 h-px bg-border" />
            ),
            <MenuRow
              key={item.id}
              glide
              role="menuitem"
              aria-haspopup={item.submenu ? 'menu' : undefined}
              aria-expanded={item.submenu ? submenu === item.submenu : undefined}
              data-index={i}
              className={cn(
                '[&_svg]:text-subtle-foreground',
                item.destructive && 'text-destructive [&_svg]:text-destructive'
              )}
              onMouseMove={() => {
                setSelected(i)
                if (item.submenu) setSubmenu(item.submenu)
                else if (submenu) setSubmenu(null)
              }}
              onClick={() => choose(i)}
            >
              <span aria-hidden className="flex">
                {item.icon}
              </span>
              <span className="flex-1 truncate">{item.label}</span>
              {item.keys && <span className="text-xs text-muted-foreground">{item.keys}</span>}
              {item.submenu && <CaretRightIcon size={14} aria-hidden />}
            </MenuRow>
          ])}
        </div>
        {counts && !query && (
          <div
            className="mt-1 border-t border-border px-2 pt-1.5 pb-1 text-xs text-muted-foreground"
            data-testid="block-menu-counts"
          >
            {t('blockMenu.words', { count: counts.words })}
            {', '}
            {t('blockMenu.characters', { count: counts.characters })}
          </div>
        )}
      </div>
      {submenuShown && shownSubmenu && (
        <div
          ref={submenuRef}
          role="menu"
          className="hk-pop absolute top-0 left-full ml-1.5 flex max-h-[min(460px,calc(100vh-120px))] w-56 flex-col overflow-y-auto overscroll-contain rounded-xl bg-popover p-1 text-popover-foreground shadow-popover"
        >
          {shownSubmenu === 'ai' && (
            // Its field keeps its own keys (the menu's arrows and Escape stay out of the typing).
            <div onKeyDown={(e) => e.stopPropagation()}>
              <AIPanel
                autoFocus={false}
                media={media !== null}
                onRun={runAI}
                onCancel={() => setSubmenu(null)}
              />
            </div>
          )}
          {shownSubmenu === 'moveTo' && mover && (
            // Its field keeps its own keys, as the AI panel's does.
            <div onKeyDown={(e) => e.stopPropagation()}>
              <PagePicker
                title={t('blockMenu.moveTo')}
                pages={mover.pages().filter((p) => p.id !== mover.currentPageId())}
                onPick={(page) => {
                  const now = follow.current
                  onClose()
                  if (now) void moveUnitTo(editor, now, page.id)
                }}
              />
            </div>
          )}
          {shownSubmenu === 'turnInto' && (
            <BlockTypeList
              title={t('blockMenu.turnInto')}
              current={unitTypeId(editor, unit)}
              onPick={(block) => act((now) => turnUnitInto(editor, now, block.id))()}
            />
          )}
          {shownSubmenu === 'color' && (
            <ColorList
              kind="block"
              text={unit.node.attrs.blockColor as PaletteColor | null}
              background={unit.node.attrs.blockBackground as PaletteColor | null}
              onText={(color) => paint({ blockColor: color })}
              onBackground={(color) => paint({ blockBackground: color })}
            />
          )}
        </div>
      )}
    </div>
  )
}

/** Puts the caret inside the unit (before a turn-into command). */
function withCaretIn(editor: Editor, unit: BlockUnit): Editor {
  const text = firstTextPos(unit)
  if (text !== null && editor.state.selection.from !== text) {
    editor.view.dispatch(editor.state.tr.setSelection(TextSelection.create(editor.state.doc, text)))
  }
  return editor
}

function turnUnitInto(editor: Editor, unit: BlockUnit, id: string) {
  const block = TURN_INTO.find((b) => b.id === id)
  if (!block) return
  withCaretIn(editor, unit)
  block.turnInto?.(editor.chain().focus()).run()
  block.after?.(editor)
}
