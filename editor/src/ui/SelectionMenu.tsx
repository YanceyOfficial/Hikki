import {
  CaretRight,
  Check,
  Code,
  Eraser,
  type Icon,
  LinkSimple,
  TextB,
  TextItalic,
  TextStrikethrough,
  TextSubscript,
  TextSuperscript,
  TextUnderline
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'

import { Tooltip, TooltipContent, TooltipTrigger } from '@/components/ui/tooltip'

import { BLOCK_TYPES } from '../blocks'
import { PALETTE, type PaletteColor } from '../extensions/colors'
import { t } from '../i18n'
import { cn } from './cn'
import { useEditorSnapshot } from './use-editor-snapshot'

type Panel = 'turnInto' | 'color' | 'link' | null

const TURN_INTO = BLOCK_TYPES.filter((b) => b.turnInto)

/** Color names, spelled out so the l10n audit sees every key. */
const COLOR_LABEL: Record<PaletteColor, () => string> = {
  gray: () => t('color.gray'),
  brown: () => t('color.brown'),
  orange: () => t('color.orange'),
  yellow: () => t('color.yellow'),
  green: () => t('color.green'),
  blue: () => t('color.blue'),
  purple: () => t('color.purple'),
  pink: () => t('color.pink'),
  red: () => t('color.red')
}

/** What the menu shows; recomputed per transaction, re-rendered only on change. */
function snapshot(editor: Editor) {
  const style = editor.getAttributes('textStyle')
  const { from, to } = editor.state.selection
  return {
    selection: `${from}:${to}`,
    block: TURN_INTO.find((b) => b.isActive?.(editor))?.id ?? 'paragraph',
    bold: editor.isActive('bold'),
    italic: editor.isActive('italic'),
    underline: editor.isActive('underline'),
    strike: editor.isActive('strike'),
    code: editor.isActive('code'),
    subscript: editor.isActive('subscript'),
    superscript: editor.isActive('superscript'),
    link: (editor.getAttributes('link').href as string | undefined) ?? null,
    textColor: (style.textColor as PaletteColor | undefined) ?? null,
    bgColor: (style.bgColor as PaletteColor | undefined) ?? null
  }
}

/** Accepts "example.com" as https; keeps explicit schemes (the Link extension rejects unsafe ones). */
export function normalizeHref(raw: string): string | null {
  const value = raw.trim()
  if (!value) return null
  if (/^[a-z][a-z0-9+.-]*:/i.test(value)) return value
  if (value.startsWith('/') || value.startsWith('#')) return value
  return `https://${value}`
}

/**
 * The menu over a text selection (Notion-like): "Turn into", two rows of formatting, link and color.
 * Side panels open inside the menu element so focus never leaves it (BubbleMenu hides on blur otherwise).
 * Comment and AI rows come later.
 */
export function SelectionMenu({ editor }: { editor: Editor }) {
  const state = useEditorSnapshot(editor, snapshot)
  const [panel, setPanel] = useState<Panel>(null)
  const cardRef = useRef<HTMLDivElement>(null)
  const [panelLeft, setPanelLeft] = useState(false)

  useLayoutEffect(() => {
    const card = cardRef.current
    if (panel && card) setPanelLeft(card.getBoundingClientRect().right + 232 > window.innerWidth)
  }, [panel])

  // A new selection starts with the panels closed.
  const [lastSelection, setLastSelection] = useState(state.selection)
  if (lastSelection !== state.selection) {
    setLastSelection(state.selection)
    if (panel && panel !== 'link') setPanel(null)
  }

  const run = (apply: (chain: ReturnType<Editor['chain']>) => ReturnType<Editor['chain']>) =>
    apply(editor.chain().focus()).run()
  const toggle = (name: Panel) => setPanel((current) => (current === name ? null : name))
  const current = TURN_INTO.find((b) => b.id === state.block) ?? TURN_INTO[0]
  const CurrentIcon = current.icon

  return (
    <div className="relative" data-testid="selection-menu" onMouseDown={keepEditorFocus}>
      <div
        ref={cardRef}
        role="toolbar"
        aria-label={t('format.menu')}
        className="hk-pop-in w-[224px] rounded-xl bg-popover p-1 text-popover-foreground shadow-popover"
      >
        <button
          type="button"
          className={cn(rowClass, panel === 'turnInto' && 'bg-accent')}
          aria-haspopup="menu"
          aria-expanded={panel === 'turnInto'}
          onClick={() => toggle('turnInto')}
        >
          <CurrentIcon size={18} className="text-subtle-foreground" aria-hidden />
          <span className="flex-1 truncate">{current.label()}</span>
          <CaretRight size={14} className="text-muted-foreground" aria-hidden />
        </button>
        <div className="mx-1 my-1 h-px bg-border" />
        <div className="grid grid-cols-5 gap-0.5">
          <ColorButton
            textColor={state.textColor}
            bgColor={state.bgColor}
            active={panel === 'color'}
            onClick={() => toggle('color')}
          />
          <MarkButton
            icon={TextB}
            label={t('format.bold')}
            keys="⌘B"
            active={state.bold}
            onClick={() => run((c) => c.toggleBold())}
          />
          <MarkButton
            icon={TextItalic}
            label={t('format.italic')}
            keys="⌘I"
            active={state.italic}
            onClick={() => run((c) => c.toggleItalic())}
          />
          <MarkButton
            icon={TextUnderline}
            label={t('format.underline')}
            keys="⌘U"
            active={state.underline}
            onClick={() => run((c) => c.toggleUnderline())}
          />
          <MarkButton
            icon={Eraser}
            label={t('format.clear')}
            active={false}
            onClick={() => run((c) => c.unsetAllMarks())}
          />
          <MarkButton
            icon={LinkSimple}
            label={t('format.link')}
            active={!!state.link || panel === 'link'}
            onClick={() => toggle('link')}
          />
          <MarkButton
            icon={TextStrikethrough}
            label={t('format.strike')}
            keys="⌘⇧S"
            active={state.strike}
            onClick={() => run((c) => c.toggleStrike())}
          />
          <MarkButton
            icon={Code}
            label={t('format.code')}
            keys="⌘E"
            active={state.code}
            onClick={() => run((c) => c.toggleCode())}
          />
          <MarkButton
            icon={TextSuperscript}
            label={t('format.superscript')}
            keys="⌘."
            active={state.superscript}
            onClick={() => run((c) => c.toggleSuperscript())}
          />
          <MarkButton
            icon={TextSubscript}
            label={t('format.subscript')}
            keys="⌘,"
            active={state.subscript}
            onClick={() => run((c) => c.toggleSubscript())}
          />
        </div>
      </div>

      {panel && (
        <div
          className={cn(
            'absolute top-0 w-[224px] rounded-xl bg-popover p-1 text-popover-foreground shadow-popover',
            panelLeft ? 'right-full mr-1.5' : 'left-full ml-1.5'
          )}
          data-testid={`selection-menu-${panel}`}
        >
          {panel === 'turnInto' && (
            <div role="menu" aria-label={t('format.turnInto')}>
              <PanelTitle>{t('format.turnInto')}</PanelTitle>
              {TURN_INTO.map((block) => {
                const BlockIcon = block.icon
                const active = block.id === state.block
                return (
                  <button
                    key={block.id}
                    type="button"
                    role="menuitemradio"
                    aria-checked={active}
                    className={rowClass}
                    onClick={() => {
                      block.turnInto?.(editor.chain().focus()).run()
                      setPanel(null)
                    }}
                  >
                    <BlockIcon size={18} className="text-subtle-foreground" aria-hidden />
                    <span className="flex-1 truncate">{block.label()}</span>
                    {active && <Check size={14} aria-hidden />}
                  </button>
                )
              })}
            </div>
          )}
          {panel === 'color' && (
            <ColorPanel
              textColor={state.textColor}
              bgColor={state.bgColor}
              onText={(color) => run((c) => c.setTextColor(color))}
              onBackground={(color) => run((c) => c.setBackgroundColor(color))}
            />
          )}
          {panel === 'link' && (
            <LinkPanel
              href={state.link}
              onApply={(href) => {
                run((c) => c.extendMarkRange('link').setLink({ href }))
                setPanel(null)
              }}
              onRemove={() => {
                run((c) => c.extendMarkRange('link').unsetLink())
                setPanel(null)
              }}
              onCancel={() => {
                setPanel(null)
                editor.commands.focus()
              }}
            />
          )}
        </div>
      )}
    </div>
  )
}

const rowClass =
  'flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 text-left text-sm select-none hover:bg-accent coarse:h-10'

/** Buttons keep the editor's selection: no focus change on press (inputs are exempt). */
function keepEditorFocus(event: React.MouseEvent) {
  const target = event.target as HTMLElement
  if (!target.closest('input')) event.preventDefault()
}

function PanelTitle({ children }: { children: ReactNode }) {
  return (
    <div className="px-2 pt-1.5 pb-1 text-xs font-medium text-muted-foreground">{children}</div>
  )
}

function MarkButton({
  icon: Glyph,
  label,
  keys,
  active,
  onClick
}: {
  icon: Icon
  label: string
  keys?: string
  active: boolean
  onClick: () => void
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            type="button"
            aria-label={label}
            aria-pressed={active}
            className={cn(
              'grid h-8 cursor-pointer place-items-center rounded-md text-foreground transition-transform duration-100 hover:bg-accent active:scale-[0.97] coarse:h-10',
              active && 'bg-accent text-accent-strong'
            )}
            onClick={onClick}
          />
        }
      >
        <Glyph size={18} weight={active ? 'bold' : undefined} aria-hidden />
      </TooltipTrigger>
      <TooltipContent side="bottom">
        {label}
        {keys && <span className="text-background/60">{keys}</span>}
      </TooltipContent>
    </Tooltip>
  )
}

/** The "A" swatch: shows the selection's current text and background color. */
function Swatch({
  text,
  background
}: {
  text: PaletteColor | null
  background: PaletteColor | null
}) {
  return (
    <span
      className="grid size-5 place-items-center rounded-[5px] border border-border text-xs font-semibold"
      data-text-color={text ?? undefined}
      data-bg-color={background ?? undefined}
    >
      A
    </span>
  )
}

function ColorButton({
  textColor,
  bgColor,
  active,
  onClick
}: {
  textColor: PaletteColor | null
  bgColor: PaletteColor | null
  active: boolean
  onClick: () => void
}) {
  return (
    <Tooltip>
      <TooltipTrigger
        render={
          <button
            type="button"
            aria-label={t('format.color')}
            aria-haspopup="menu"
            aria-expanded={active}
            className={cn(
              'grid h-8 cursor-pointer place-items-center rounded-md hover:bg-accent coarse:h-10',
              active && 'bg-accent'
            )}
            onClick={onClick}
          />
        }
      >
        <Swatch text={textColor} background={bgColor} />
      </TooltipTrigger>
      <TooltipContent side="bottom">{t('format.color')}</TooltipContent>
    </Tooltip>
  )
}

function ColorRow({
  color,
  selected,
  onPick,
  children
}: {
  color: PaletteColor | null
  selected: boolean
  onPick: () => void
  children: ReactNode
}) {
  return (
    <button
      type="button"
      role="menuitemradio"
      aria-checked={selected}
      className={rowClass}
      onClick={onPick}
    >
      {children}
      <span className="flex-1 truncate">{color ? COLOR_LABEL[color]() : t('color.default')}</span>
      {selected && <Check size={14} aria-hidden />}
    </button>
  )
}

function ColorPanel({
  textColor,
  bgColor,
  onText,
  onBackground
}: {
  textColor: PaletteColor | null
  bgColor: PaletteColor | null
  onText: (color: PaletteColor | null) => void
  onBackground: (color: PaletteColor | null) => void
}) {
  return (
    <div role="menu" aria-label={t('format.color')} className="max-h-[360px] overflow-y-auto">
      <PanelTitle>{t('color.text')}</PanelTitle>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`text-${color}`}
          color={color}
          selected={textColor === color}
          onPick={() => onText(color)}
        >
          <Swatch text={color} background={null} />
        </ColorRow>
      ))}
      <div className="mx-1 my-1 h-px bg-border" />
      <PanelTitle>{t('color.background')}</PanelTitle>
      {[null, ...PALETTE].map((color) => (
        <ColorRow
          key={`bg-${color}`}
          color={color}
          selected={bgColor === color}
          onPick={() => onBackground(color)}
        >
          <Swatch text={null} background={color} />
        </ColorRow>
      ))}
    </div>
  )
}

function LinkPanel({
  href,
  onApply,
  onRemove,
  onCancel
}: {
  href: string | null
  onApply: (href: string) => void
  onRemove: () => void
  onCancel: () => void
}) {
  const [value, setValue] = useState(href ?? '')
  const apply = () => {
    const normalized = normalizeHref(value)
    if (normalized) onApply(normalized)
    else if (href) onRemove()
  }
  return (
    <div className="flex flex-col gap-1 p-1">
      <div className="flex items-center gap-1.5">
        <LinkSimple size={16} className="flex-none text-muted-foreground" aria-hidden />
        <input
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel exists to type a link
          autoFocus
          className="h-8 min-w-0 flex-1 rounded-md border border-input bg-transparent px-2 text-sm outline-none focus:border-ring focus:ring-3 focus:ring-ring/50"
          placeholder={t('link.placeholder')}
          aria-label={t('format.link')}
          value={value}
          onChange={(e) => setValue(e.target.value)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return
            if (e.key === 'Enter') {
              e.preventDefault()
              apply()
            } else if (e.key === 'Escape') {
              e.preventDefault()
              onCancel()
            }
          }}
        />
      </div>
      <div className="flex justify-end gap-1">
        {href && (
          <>
            <a
              className="inline-flex h-7 items-center rounded-md px-2 text-xs text-muted-foreground hover:bg-accent"
              href={href}
              target="_blank"
              rel="noreferrer"
            >
              {t('link.open')}
            </a>
            <button
              type="button"
              className="inline-flex h-7 cursor-pointer items-center rounded-md px-2 text-xs text-destructive hover:bg-accent"
              onClick={onRemove}
            >
              {t('link.remove')}
            </button>
          </>
        )}
        <button
          type="button"
          className="inline-flex h-7 cursor-pointer items-center rounded-md bg-primary px-2.5 text-xs text-primary-foreground"
          onClick={apply}
        >
          {t('link.apply')}
        </button>
      </div>
    </div>
  )
}
