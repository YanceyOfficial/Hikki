import {
  ArrowsInLineHorizontalIcon,
  ColumnsPlusLeftIcon,
  ColumnsPlusRightIcon,
  DotsSixIcon,
  DotsSixVerticalIcon,
  EraserIcon,
  PaintBucketIcon,
  PlusIcon,
  RowsPlusBottomIcon,
  RowsPlusTopIcon,
  SortAscendingIcon,
  SortDescendingIcon,
  SquareSplitHorizontalIcon,
  TrashIcon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import type { CellSelection } from '@tiptap/pm/tables'
import { useState, type ReactNode } from 'react'

import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuSub,
  DropdownMenuSubContent,
  DropdownMenuSubTrigger,
  DropdownMenuTrigger
} from '@/components/ui/dropdown-menu'
import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

import { colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import {
  addColumnAtEnd,
  addRowAtEnd,
  clearCells,
  hasMergedCells,
  selectColumn,
  selectRow,
  setCellBackground,
  sortColumn
} from '../extensions/table-ops'
import { t } from '../i18n'
import { cn } from './cn'

export type TableHover = {
  tablePos: number
  row: number
  col: number
  cell: HTMLElement
  table: HTMLTableElement
}

type Props = {
  editor: Editor
  hover: TableHover | null
  cellSelection: CellSelection | null
  onPointerEnter: () => void
  onPointerLeave: () => void
  onMenuChange: (open: boolean) => void
}

type Menu = 'row' | 'col' | null

/** The part of the table that is visible (its wrapper scrolls horizontally). */
function visibleRect(table: HTMLTableElement): DOMRect {
  const rect = table.getBoundingClientRect()
  const wrapper = table.closest('.tableWrapper')?.getBoundingClientRect()
  if (!wrapper) return rect
  const left = Math.max(rect.left, wrapper.left)
  const right = Math.min(rect.right, wrapper.right)
  return new DOMRect(left, rect.top, Math.max(0, right - left), rect.height)
}

/**
 * Notion-like table controls: a grip on the hovered row (left) and column (top) opening their menus,
 * "+" bars on the bottom and right edges, and a bar over a multi-cell selection (merge, split, color).
 */
export function TableOverlay({
  editor,
  hover,
  cellSelection,
  onPointerEnter,
  onPointerLeave,
  onMenuChange
}: Props) {
  const [menu, setMenu] = useState<Menu>(null)
  const pointer = { onMouseEnter: onPointerEnter, onMouseLeave: onPointerLeave }
  const openMenu = (which: Menu, open: boolean) => {
    if (open && hover) {
      if (which === 'row') selectRow(editor, hover.tablePos, hover.row)
      else selectColumn(editor, hover.tablePos, hover.col)
    }
    setMenu(open ? which : null)
    onMenuChange(open)
  }
  const done = () => openMenu(null, false)

  const multiCell = cellSelection && !menu && cellCount(cellSelection) > 1

  return (
    <>
      {hover && (
        <>
          <RowGrip
            hover={hover}
            open={menu === 'row'}
            pointer={pointer}
            onOpenChange={(o) => openMenu('row', o)}
          >
            <RowMenu editor={editor} hover={hover} onDone={done} />
          </RowGrip>
          <ColumnGrip
            hover={hover}
            open={menu === 'col'}
            pointer={pointer}
            onOpenChange={(o) => openMenu('col', o)}
          >
            <ColumnMenu editor={editor} hover={hover} onDone={done} />
          </ColumnGrip>
          <EdgeBars editor={editor} hover={hover} pointer={pointer} />
        </>
      )}
      {multiCell && <CellBar editor={editor} selection={cellSelection} />}
    </>
  )
}

function cellCount(selection: CellSelection): number {
  let count = 0
  selection.forEachCell(() => {
    count += 1
  })
  return count
}

type Pointer = { onMouseEnter: () => void; onMouseLeave: () => void }

const gripClass =
  'fixed z-30 grid cursor-pointer place-items-center rounded-sm border border-border bg-background text-muted-foreground shadow-xs hover:bg-accent hover:text-foreground data-[popup-open]:bg-primary data-[popup-open]:text-primary-foreground'

function RowGrip({
  hover,
  open,
  pointer,
  onOpenChange,
  children
}: {
  hover: TableHover
  open: boolean
  pointer: Pointer
  onOpenChange: (open: boolean) => void
  children: ReactNode
}) {
  const row = hover.cell.parentElement?.getBoundingClientRect()
  const table = visibleRect(hover.table)
  if (!row) return null
  return (
    <DropdownMenu open={open} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger
        render={
          <button
            type="button"
            aria-label={t('table.rowMenu')}
            className={cn(gripClass, 'h-6 w-3.5')}
            style={{ left: table.left - 18, top: row.top + row.height / 2 - 12 }}
            {...pointer}
          />
        }
      >
        <DotsSixVerticalIcon size={12} weight="bold" aria-hidden />
      </DropdownMenuTrigger>
      <DropdownMenuContent side="right" align="start" className="w-52">
        {children}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function ColumnGrip({
  hover,
  open,
  pointer,
  onOpenChange,
  children
}: {
  hover: TableHover
  open: boolean
  pointer: Pointer
  onOpenChange: (open: boolean) => void
  children: ReactNode
}) {
  const cell = hover.cell.getBoundingClientRect()
  const table = visibleRect(hover.table)
  const center = cell.left + cell.width / 2
  if (center < table.left || center > table.right) return null
  return (
    <DropdownMenu open={open} onOpenChange={onOpenChange}>
      <DropdownMenuTrigger
        render={
          <button
            type="button"
            aria-label={t('table.columnMenu')}
            className={cn(gripClass, 'h-3.5 w-6')}
            style={{ left: center - 12, top: table.top - 9 }}
            {...pointer}
          />
        }
      >
        <DotsSixIcon size={12} weight="bold" aria-hidden />
      </DropdownMenuTrigger>
      <DropdownMenuContent side="bottom" align="start" className="w-52">
        {children}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}

function ColorItems({ editor, onDone }: { editor: Editor; onDone: () => void }) {
  return (
    <DropdownMenuSub>
      <DropdownMenuSubTrigger>
        <PaintBucketIcon aria-hidden />
        {t('table.color')}
      </DropdownMenuSubTrigger>
      <DropdownMenuSubContent className="w-44">
        {[null, ...PALETTE].map((color: PaletteColor | null) => (
          <DropdownMenuItem
            key={color ?? 'default'}
            onClick={() => {
              setCellBackground(editor, color)
              onDone()
            }}
          >
            <span
              className="size-4 rounded-[4px] border border-border"
              data-bg-color={color ?? undefined}
              aria-hidden
            />
            {colorLabel(color)}
          </DropdownMenuItem>
        ))}
      </DropdownMenuSubContent>
    </DropdownMenuSub>
  )
}

function RowMenu({
  editor,
  hover,
  onDone
}: {
  editor: Editor
  hover: TableHover
  onDone: () => void
}) {
  const act = (run: () => unknown) => () => {
    run()
    onDone()
  }
  const chain = () => editor.chain().focus()
  return (
    <>
      <DropdownMenuItem onClick={act(() => chain().addRowBefore().run())}>
        <RowsPlusTopIcon aria-hidden />
        {t('table.insertAbove')}
      </DropdownMenuItem>
      <DropdownMenuItem onClick={act(() => chain().addRowAfter().run())}>
        <RowsPlusBottomIcon aria-hidden />
        {t('table.insertBelow')}
      </DropdownMenuItem>
      {hover.row === 0 && (
        <DropdownMenuCheckboxItem
          checked={hover.table.rows[0]?.cells[0]?.tagName === 'TH'}
          onClick={act(() => chain().toggleHeaderRow().run())}
        >
          {t('table.headerRow')}
        </DropdownMenuCheckboxItem>
      )}
      <DropdownMenuSeparator />
      <ColorItems editor={editor} onDone={onDone} />
      <DropdownMenuItem onClick={act(() => clearCells(editor))}>
        <EraserIcon aria-hidden />
        {t('table.clear')}
      </DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuItem variant="destructive" onClick={act(() => chain().deleteRow().run())}>
        <TrashIcon aria-hidden />
        {t('table.deleteRow')}
      </DropdownMenuItem>
    </>
  )
}

function ColumnMenu({
  editor,
  hover,
  onDone
}: {
  editor: Editor
  hover: TableHover
  onDone: () => void
}) {
  const act = (run: () => unknown) => () => {
    run()
    onDone()
  }
  const chain = () => editor.chain().focus()
  const table = editor.state.doc.nodeAt(hover.tablePos)
  const sortable = !!table && !hasMergedCells(table)
  return (
    <>
      <DropdownMenuItem onClick={act(() => chain().addColumnBefore().run())}>
        <ColumnsPlusLeftIcon aria-hidden />
        {t('table.insertLeft')}
      </DropdownMenuItem>
      <DropdownMenuItem onClick={act(() => chain().addColumnAfter().run())}>
        <ColumnsPlusRightIcon aria-hidden />
        {t('table.insertRight')}
      </DropdownMenuItem>
      {hover.col === 0 && (
        <DropdownMenuCheckboxItem
          checked={hover.table.rows[1]?.cells[0]?.tagName === 'TH'}
          onClick={act(() => chain().toggleHeaderColumn().run())}
        >
          {t('table.headerColumn')}
        </DropdownMenuCheckboxItem>
      )}
      <DropdownMenuSeparator />
      <DropdownMenuItem
        disabled={!sortable}
        onClick={act(() => sortColumn(editor, hover.tablePos, hover.col, 'asc'))}
      >
        <SortAscendingIcon aria-hidden />
        {t('table.sortAscending')}
      </DropdownMenuItem>
      <DropdownMenuItem
        disabled={!sortable}
        onClick={act(() => sortColumn(editor, hover.tablePos, hover.col, 'desc'))}
      >
        <SortDescendingIcon aria-hidden />
        {t('table.sortDescending')}
      </DropdownMenuItem>
      <DropdownMenuSeparator />
      <ColorItems editor={editor} onDone={onDone} />
      <DropdownMenuItem onClick={act(() => clearCells(editor))}>
        <EraserIcon aria-hidden />
        {t('table.clear')}
      </DropdownMenuItem>
      <DropdownMenuSeparator />
      <DropdownMenuItem variant="destructive" onClick={act(() => chain().deleteColumn().run())}>
        <TrashIcon aria-hidden />
        {t('table.deleteColumn')}
      </DropdownMenuItem>
    </>
  )
}

function EdgeBars({
  editor,
  hover,
  pointer
}: {
  editor: Editor
  hover: TableHover
  pointer: Pointer
}) {
  const table = visibleRect(hover.table)
  const bar =
    'fixed z-30 grid cursor-pointer place-items-center rounded-sm bg-accent text-muted-foreground opacity-60 transition-opacity duration-(--motion-pop-in) hover:opacity-100 hover:text-foreground'
  return (
    <>
      <EdgeButton
        label={t('table.addRow')}
        className={cn(bar, 'h-4')}
        style={{ left: table.left, top: table.bottom + 3, width: table.width }}
        pointer={pointer}
        onClick={() => addRowAtEnd(editor, hover.tablePos)}
      />
      <EdgeButton
        label={t('table.addColumn')}
        className={cn(bar, 'w-4')}
        style={{ left: table.right + 3, top: table.top, height: table.height }}
        pointer={pointer}
        onClick={() => addColumnAtEnd(editor, hover.tablePos)}
      />
    </>
  )
}

function EdgeButton({
  label,
  className,
  style,
  pointer,
  onClick
}: {
  label: string
  className: string
  style: React.CSSProperties
  pointer: Pointer
  onClick: () => void
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            type="button"
            aria-label={label}
            className={className}
            style={style}
            onMouseDown={(e) => e.preventDefault()}
            onClick={onClick}
            {...pointer}
          />
        }
      >
        <PlusIcon size={12} weight="bold" aria-hidden />
      </TooltipTrigger>
      <TooltipContent>{label}</TooltipContent>
    </Tooltip>
  )
}

/** Over a multi-cell selection: merge, split, color, clear. */
function CellBar({ editor, selection }: { editor: Editor; selection: CellSelection }) {
  let rect: DOMRect | null = null
  selection.forEachCell((_node, pos) => {
    const dom = editor.view.nodeDOM(pos)
    if (!(dom instanceof HTMLElement)) return
    const r = dom.getBoundingClientRect()
    rect = rect
      ? new DOMRect(
          Math.min(rect.left, r.left),
          Math.min(rect.top, r.top),
          Math.max(rect.right, r.right) - Math.min(rect.left, r.left),
          Math.max(rect.bottom, r.bottom) - Math.min(rect.top, r.top)
        )
      : r
  })
  if (!rect) return null
  const { left, top } = rect as DOMRect
  const button =
    'inline-flex h-7 cursor-pointer items-center gap-1.5 rounded-md px-2 text-xs text-foreground hover:bg-accent disabled:cursor-default disabled:opacity-40'
  return (
    <div
      className="hk-pop fixed z-30 flex items-center gap-0.5 rounded-lg bg-popover p-1 shadow-popover"
      // Clear of the column grip that sits on the table's top edge.
      style={{ left, top: Math.max(8, top - 50) }}
      data-testid="table-cell-bar"
      onMouseDown={(e) => e.preventDefault()}
    >
      <button
        type="button"
        className={button}
        disabled={!editor.can().mergeCells()}
        onClick={() => editor.chain().focus().mergeCells().run()}
      >
        <ArrowsInLineHorizontalIcon size={14} aria-hidden />
        {t('table.merge')}
      </button>
      <button
        type="button"
        className={button}
        disabled={!editor.can().splitCell()}
        onClick={() => editor.chain().focus().splitCell().run()}
      >
        <SquareSplitHorizontalIcon size={14} aria-hidden />
        {t('table.split')}
      </button>
      <DropdownMenu>
        <DropdownMenuTrigger render={<button type="button" className={button} />}>
          <PaintBucketIcon size={14} aria-hidden />
          {t('table.color')}
        </DropdownMenuTrigger>
        <DropdownMenuContent className="w-44">
          {[null, ...PALETTE].map((color: PaletteColor | null) => (
            <DropdownMenuItem
              key={color ?? 'default'}
              onClick={() => setCellBackground(editor, color)}
            >
              <span
                className="size-4 rounded-[4px] border border-border"
                data-bg-color={color ?? undefined}
                aria-hidden
              />
              {colorLabel(color)}
            </DropdownMenuItem>
          ))}
        </DropdownMenuContent>
      </DropdownMenu>
      <button type="button" className={button} onClick={() => clearCells(editor)}>
        <EraserIcon size={14} aria-hidden />
        {t('table.clear')}
      </button>
    </div>
  )
}
