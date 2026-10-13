import {
  ArrowsClockwiseIcon,
  CaretRightIcon,
  CheckIcon,
  CopyIcon,
  LinkSimpleIcon,
  PaintBrushIcon,
  TrashIcon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { TextSelection } from '@tiptap/pm/state'
import { cn } from 'cn'
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'

import { Input } from '@/components/ui/input'

import { BLOCK_TYPES } from '../core/blocks'
import { t } from '../core/i18n'
import { shortcutLabel } from '../core/shortcuts'
import { setBlockHighlight } from '../extensions/block-highlight'
import { deleteUnit, duplicateUnit, firstTextPos, type BlockUnit } from '../extensions/block-units'
import { BLOCK_COLOR_TYPES, colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import { blockLabel, copyLink } from '../extensions/page-links'
import { FloatingLayer, usePresence } from './floating'
import { GlidingHighlight } from './gliding-highlight'
import { IconProvider } from './icons'

const TURN_INTO = BLOCK_TYPES.filter((b) => b.turnInto)

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
  const layer = new FloatingLayer('hk-block-menu', { bare: true })
  // The block is tinted while its menu is open (a decoration: the same for every block type).
  setBlockHighlight(editor.view, { menu: { from: unit.pos, to: unit.pos + unit.node.nodeSize } })
  const close = () => {
    document.removeEventListener('pointerdown', onOutside, true)
    if (!editor.isDestroyed) setBlockHighlight(editor.view, { menu: null })
    layer.destroy()
    if (open?.layer === layer) open = null
  }
  // A press anywhere outside the menu closes it (and does what it does).
  const onOutside = (event: PointerEvent) => {
    if (!layer.element.contains(event.target as Node)) close()
  }
  document.addEventListener('pointerdown', onOutside, true)
  open = { layer, close }
  layer.render(
    <IconProvider>
      <BlockMenu editor={editor} unit={unit} onClose={close} />
    </IconProvider>,
    () => anchor
  )
}

type Item = {
  id: string
  label: string
  icon: ReactNode
  keys?: string
  submenu?: 'turnInto' | 'color'
  destructive?: boolean
  run?: () => void
}

function BlockMenu({
  editor,
  unit,
  onClose
}: {
  editor: Editor
  unit: BlockUnit
  onClose: () => void
}) {
  const [query, setQuery] = useState('')
  const [selected, setSelected] = useState(0)
  const [submenu, setSubmenu] = useState<'turnInto' | 'color' | null>(null)
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

  const act = (run: () => void) => () => {
    run()
    onClose()
    editor.view.focus()
  }
  const blockId = unit.node.attrs.id as string | null | undefined
  const link = blockId ? blockLink?.(blockId) : null

  const items: Item[] = [
    {
      id: 'turnInto',
      label: t('blockMenu.turnInto'),
      icon: <ArrowsClockwiseIcon size={18} />,
      submenu: 'turnInto'
    },
    ...(colorable
      ? [
          {
            id: 'color',
            label: t('blockMenu.color'),
            icon: <PaintBrushIcon size={18} />,
            submenu: 'color' as const
          }
        ]
      : []),
    ...(link
      ? [
          {
            id: 'copyLink',
            label: t('blockMenu.copyLink'),
            icon: <LinkSimpleIcon size={18} />,
            // A ready hyperlink (the block's text) plus the URL: pasting it lands as a link.
            run: act(() => void copyLink(link.href, blockLabel(unit.node) ?? link.pageLabel))
          }
        ]
      : []),
    {
      id: 'duplicate',
      label: t('blockMenu.duplicate'),
      icon: <CopyIcon size={18} />,
      keys: shortcutLabel('duplicateBlock'),
      run: act(() => editor.view.dispatch(duplicateUnit(editor.state, unit)))
    },
    {
      id: 'delete',
      label: t('blockMenu.delete'),
      icon: <TrashIcon size={18} />,
      keys: 'Del',
      destructive: true,
      run: act(() => editor.view.dispatch(deleteUnit(editor.state, unit)))
    }
  ]

  // With a query: matching actions and Turn-into targets, flat.
  const visible: Item[] = (() => {
    const q = query.trim().toLowerCase()
    if (!q) return items
    const turnInto = TURN_INTO.map((block) => ({
      id: `turn-${block.id}`,
      label: `${t('blockMenu.turnInto')} › ${block.label()}`,
      icon: <block.icon size={18} />,
      run: act(() => turnUnitInto(editor, unit, block.id))
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
        if (e.key === 'Escape') {
          e.preventDefault()
          if (submenu) setSubmenu(null)
          else {
            onClose()
            editor.view.focus()
          }
        } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
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
          className="mb-1 h-8 md:text-sm"
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
            <button
              key={item.id}
              type="button"
              role="menuitem"
              aria-haspopup={item.submenu ? 'menu' : undefined}
              aria-expanded={item.submenu ? submenu === item.submenu : undefined}
              data-index={i}
              className={cn(
                'relative flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 text-left text-sm select-none [&_svg]:text-subtle-foreground',
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
              {item.submenu && <CaretRightIcon size={14} aria-hidden />}
            </button>
          ))}
        </div>
      </div>
      {submenuShown && shownSubmenu && (
        <div
          ref={submenuRef}
          role="menu"
          className="hk-pop absolute top-0 left-full ml-1.5 flex max-h-[min(460px,calc(100vh-120px))] w-56 flex-col overflow-y-auto overscroll-contain rounded-xl bg-popover p-1 text-popover-foreground shadow-popover"
        >
          {shownSubmenu === 'turnInto' ? (
            <TurnIntoList editor={editor} unit={unit} onDone={act(() => {})} />
          ) : (
            <ColorList editor={editor} unit={unit} onDone={act(() => {})} />
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

function TurnIntoList({
  editor,
  unit,
  onDone
}: {
  editor: Editor
  unit: BlockUnit
  onDone: () => void
}) {
  const current = unitTypeId(editor, unit)
  return (
    <>
      <div className="px-2 pt-1.5 pb-1 text-xs font-medium text-muted-foreground">
        {t('blockMenu.turnInto')}
      </div>
      {TURN_INTO.map((block) => (
        <button
          key={block.id}
          type="button"
          role="menuitemradio"
          aria-checked={block.id === current}
          className="flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 text-left text-sm transition-colors duration-(--motion-pop-out) ease-out hover:bg-accent"
          onClick={() => {
            turnUnitInto(editor, unit, block.id)
            onDone()
          }}
        >
          <block.icon size={18} className="text-subtle-foreground" aria-hidden />
          <span className="flex-1 truncate">{block.label()}</span>
          {block.id === current && <CheckIcon size={14} aria-hidden />}
        </button>
      ))}
    </>
  )
}

function ColorRow({
  label,
  checked,
  onClick,
  children
}: {
  label: string
  checked: boolean
  onClick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      role="menuitemradio"
      aria-checked={checked}
      className="flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 py-1 text-left text-sm hover:bg-accent"
      onClick={onClick}
    >
      {children}
      <span className="flex-1 truncate">{label}</span>
      {checked && <CheckIcon size={14} aria-hidden />}
    </button>
  )
}

function ColorList({
  editor,
  unit,
  onDone
}: {
  editor: Editor
  unit: BlockUnit
  onDone: () => void
}) {
  const set = (attrs: Record<string, PaletteColor | null>) => {
    const node = editor.state.doc.nodeAt(unit.pos)
    if (!node) return
    editor.view.dispatch(
      editor.state.tr.setNodeMarkup(unit.pos, undefined, { ...node.attrs, ...attrs })
    )
    onDone()
  }
  const text = unit.node.attrs.blockColor as PaletteColor | null
  const background = unit.node.attrs.blockBackground as PaletteColor | null
  return (
    <>
      <div className="px-2 pt-1.5 pb-1 text-xs font-medium text-muted-foreground">
        {t('color.text')}
      </div>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`t-${color}`}
          label={colorLabel(color)}
          checked={text === color}
          onClick={() => set({ blockColor: color })}
        >
          <span
            className="grid size-5 place-items-center rounded-[5px] border border-border text-xs font-semibold"
            data-text-color={color ?? undefined}
          >
            A
          </span>
        </ColorRow>
      ))}
      <div className="mx-1 my-1 h-px bg-border" />
      <div className="px-2 pt-1.5 pb-1 text-xs font-medium text-muted-foreground">
        {t('color.background')}
      </div>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`b-${color}`}
          label={colorLabel(color)}
          checked={background === color}
          onClick={() => set({ blockBackground: color })}
        >
          <span
            className="size-5 rounded-[5px] border border-border"
            data-block-bg={color ?? undefined}
          />
        </ColorRow>
      ))}
    </>
  )
}
