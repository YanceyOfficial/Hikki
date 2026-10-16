import {
  ArrowRight01Icon,
  Copy01Icon,
  Delete02Icon,
  Link01Icon,
  PaintBrush01Icon,
  RepeatIcon,
  SparklesIcon
} from '@hugeicons/core-free-icons'
import type { Editor } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { cn } from 'cn'
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'

import { Input } from '@/components/ui/input'

import { t } from '../core/i18n'
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
import { blockLabel, copyLink } from '../extensions/page-links'
import { AIPanel } from './ai-panel'
import { BlockTypeList, TURN_INTO } from './block-type-list'
import { ColorList } from './color-list'
import { FloatingLayer, usePresence } from './floating'
import { GlidingHighlight } from './gliding-highlight'
import { Icon } from './icons'
import { MenuRow } from './menu-row'

let open: { layer: FloatingLayer; close: () => void } | null = null

/** A link to a block (`hikki://page/<page>#<block>`) and the page's title, for blocks without text of their own. */
export type BlockLink = { href: string; pageLabel: string }
/** Set by the bridge, which knows the page. */
let blockLink: ((blockId: string) => BlockLink | null) | null = null
export function setBlockLinkBuilder(builder: ((blockId: string) => BlockLink | null) | null): void {
  blockLink = builder
}

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
    <BlockMenu
      editor={editor}
      unit={unit}
      follow={follow}
      onEscape={(handler) => {
        escape = handler
      }}
      onClose={close}
    />,
    () => anchor
  )
}

type Submenu = 'ai' | 'turnInto' | 'color'

type Item = {
  id: string
  label: string
  icon: ReactNode
  keys?: string
  submenu?: Submenu
  destructive?: boolean
  run?: () => void
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
  const typeName = TURN_INTO.find((b) => b.id === unitTypeId(editor, unit))?.label()
  const colorable = BLOCK_COLOR_TYPES.includes(unit.node.type.name)

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
  const link = blockId ? blockLink?.(blockId) : null

  // AI works on the block's text (not on code).
  const hasAIText = unitTextRange(unit) !== null
  const runAI = (action: AIAction) => {
    const now = follow.current
    const aiRange = now ? unitTextRange(now) : null
    onClose()
    if (!aiRange) return
    editor.view.dispatch(
      editor.state.tr.setSelection(TextSelection.create(editor.state.doc, aiRange.from, aiRange.to))
    )
    editor.view.focus()
    editor.commands.aiRun(action)
  }

  const items: Item[] = [
    ...(hasAIText
      ? [
          {
            id: 'ai',
            label: t('ai.menu'),
            icon: <Icon icon={SparklesIcon} size={18} />,
            submenu: 'ai' as const
          }
        ]
      : []),
    {
      id: 'turnInto',
      label: t('blockMenu.turnInto'),
      icon: <Icon icon={RepeatIcon} size={18} />,
      submenu: 'turnInto'
    },
    ...(colorable
      ? [
          {
            id: 'color',
            label: t('blockMenu.color'),
            icon: <Icon icon={PaintBrush01Icon} size={18} />,
            submenu: 'color' as const
          }
        ]
      : []),
    ...(link
      ? [
          {
            id: 'copyLink',
            label: t('blockMenu.copyLink'),
            icon: <Icon icon={Link01Icon} size={18} />,
            // A ready hyperlink (the block's text) plus the URL: pasting it lands as a link.
            run: act((now) => void copyLink(link.href, blockLabel(now.node) ?? link.pageLabel))
          }
        ]
      : []),
    {
      id: 'duplicate',
      label: t('blockMenu.duplicate'),
      icon: <Icon icon={Copy01Icon} size={18} />,
      keys: shortcutLabel('duplicateBlock'),
      run: act((now) => editor.view.dispatch(duplicateUnit(editor.state, now)))
    },
    {
      id: 'delete',
      label: t('blockMenu.delete'),
      icon: <Icon icon={Delete02Icon} size={18} />,
      keys: 'Del',
      destructive: true,
      run: act((now) => editor.view.dispatch(deleteUnit(editor.state, now)))
    }
  ]

  // With a query: matching actions and Turn-into targets, flat.
  const visible: Item[] = (() => {
    const q = query.trim().toLowerCase()
    if (!q) return items
    const turnInto = TURN_INTO.map((block) => ({
      id: `turn-${block.id}`,
      label: `${t('blockMenu.turnInto')} › ${block.label()}`,
      icon: <Icon icon={block.icon} size={18} />,
      run: act((now) => turnUnitInto(editor, now, block.id))
    }))
    return [...items.filter((i) => !i.submenu), ...turnInto].filter((i) =>
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
        {typeName && !query && (
          <div className="px-2 pt-1 pb-1 text-xs font-medium text-muted-foreground">{typeName}</div>
        )}
        <div
          ref={listRef}
          className="relative max-h-[min(420px,calc(100vh-160px))] overflow-y-auto overscroll-contain"
        >
          <GlidingHighlight listRef={listRef} index={selected} />
          {visible.length === 0 && (
            <div className="px-2 py-1.5 text-sm text-muted-foreground">{t('editor.noResults')}</div>
          )}
          {visible.map((item, i) => (
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
              {item.keys && <span className="text-xs text-placeholder">{item.keys}</span>}
              {item.submenu && <Icon icon={ArrowRight01Icon} size={14} aria-hidden />}
            </MenuRow>
          ))}
        </div>
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
              <AIPanel autoFocus={false} onRun={runAI} onCancel={() => setSubmenu(null)} />
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

/** The catalog id of the unit's kind (read from the document, no selection needed). */
export function unitTypeId(editor: Editor, unit: BlockUnit): string | null {
  const { node } = unit
  switch (node.type.name) {
    case 'paragraph':
      return 'paragraph'
    case 'heading':
      return `heading${node.attrs.level as number}`
    case 'listItem':
      return editor.state.doc.resolve(unit.pos).parent.type.name === 'orderedList'
        ? 'orderedList'
        : 'bulletList'
    case 'taskItem':
      return 'taskList'
    case 'blockquote':
      return 'blockquote'
    case 'codeBlock':
      return 'codeBlock'
    case 'details':
      return 'toggle'
    case 'callout':
      return 'callout'
    default:
      return null
  }
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
