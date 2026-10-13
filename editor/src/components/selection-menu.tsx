import {
  CaretRightIcon,
  CheckIcon,
  CodeIcon,
  DotsThreeIcon,
  EraserIcon,
  LinkSimpleIcon,
  MathOperationsIcon,
  TextAaIcon,
  TextBIcon,
  TextItalicIcon,
  TextStrikethroughIcon,
  TextSubscriptIcon,
  TextSuperscriptIcon,
  TextUnderlineIcon,
  type Icon
} from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { cn } from 'cn'
import { useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import type { Root } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import { InputGroup, InputGroupAddon, InputGroupInput } from '@/components/ui/input-group'
import { Kbd } from '@/components/ui/kbd'
import { Toggle } from '@/components/ui/toggle'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

import { BLOCK_TYPES } from '../core/blocks'
import { t } from '../core/i18n'
import { isSafeHref, normalizeHref } from '../core/links'
import { shortcutLabel } from '../core/shortcuts'
import { colorLabel, PALETTE, type PaletteColor } from '../extensions/colors'
import { useEditorSnapshot } from '../hooks/use-editor-snapshot'
import { usePresence } from './floating'
import { IconProvider } from './icons'

type Panel = 'turnInto' | 'color' | 'link' | 'more' | null

const TURN_INTO = BLOCK_TYPES.filter((b) => b.turnInto)

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
  // The side panel stays in the tree through its leave motion, showing whatever it last showed.
  const panelRef = useRef<HTMLDivElement>(null)
  const panelShown = usePresence(panel !== null, panelRef)
  const [shownPanel, setShownPanel] = useState(panel)
  if (panel && panel !== shownPanel) setShownPanel(panel)
  const current = TURN_INTO.find((b) => b.id === state.block) ?? TURN_INTO[0]
  const CurrentIcon = current.icon

  return (
    <div className="relative" data-testid="selection-menu" onMouseDown={keepEditorFocus}>
      <div
        ref={cardRef}
        role="toolbar"
        aria-label={t('format.menu')}
        className="hk-pop w-[224px] rounded-xl bg-popover p-1 text-popover-foreground shadow-popover"
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
          <CaretRightIcon size={14} className="text-muted-foreground" aria-hidden />
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
            icon={TextBIcon}
            label={t('format.bold')}
            keys={shortcutLabel('bold')}
            active={state.bold}
            onClick={() => run((c) => c.toggleBold())}
          />
          <MarkButton
            icon={TextItalicIcon}
            label={t('format.italic')}
            keys={shortcutLabel('italic')}
            active={state.italic}
            onClick={() => run((c) => c.toggleItalic())}
          />
          <MarkButton
            icon={TextUnderlineIcon}
            label={t('format.underline')}
            keys={shortcutLabel('underline')}
            active={state.underline}
            onClick={() => run((c) => c.toggleUnderline())}
          />
          <MarkButton
            icon={EraserIcon}
            label={t('format.clear')}
            active={false}
            onClick={() => run((c) => c.unsetAllMarks())}
          />
          <MarkButton
            icon={LinkSimpleIcon}
            label={t('format.link')}
            active={!!state.link || panel === 'link'}
            onClick={() => toggle('link')}
          />
          <MarkButton
            icon={TextStrikethroughIcon}
            label={t('format.strike')}
            keys={shortcutLabel('strikethrough')}
            active={state.strike}
            onClick={() => run((c) => c.toggleStrike())}
          />
          <MarkButton
            icon={CodeIcon}
            label={t('format.code')}
            keys={shortcutLabel('inlineCode')}
            active={state.code}
            onClick={() => run((c) => c.toggleCode())}
          />
          <MarkButton
            icon={MathOperationsIcon}
            label={t('format.math')}
            active={false}
            onClick={() => {
              const { from, to } = editor.state.selection
              const latex = editor.state.doc.textBetween(from, to, ' ')
              run((c) => c.insertContentAt({ from, to }, { type: 'inlineMath', attrs: { latex } }))
            }}
          />
          <MarkButton
            icon={DotsThreeIcon}
            label={t('format.more')}
            active={panel === 'more' || state.superscript || state.subscript}
            onClick={() => toggle('more')}
          />
        </div>
      </div>

      {panelShown && shownPanel && (
        <div
          ref={panelRef}
          className={cn(
            // Scrolls on its own (wheel and trackpad stay inside, the page doesn't move).
            'hk-pop absolute top-0 max-h-[min(440px,calc(100vh-96px))] w-[224px] overflow-y-auto overscroll-contain rounded-xl bg-popover p-1 text-popover-foreground shadow-popover',
            panelLeft ? 'right-full mr-1.5 [--hk-pop-origin:top_right]' : 'left-full ml-1.5'
          )}
          data-testid={`selection-menu-${shownPanel}`}
        >
          {shownPanel === 'turnInto' && (
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
                      block.after?.(editor)
                      setPanel(null)
                    }}
                  >
                    <BlockIcon size={18} className="text-subtle-foreground" aria-hidden />
                    <span className="flex-1 truncate">{block.label()}</span>
                    {active && <CheckIcon size={14} aria-hidden />}
                  </button>
                )
              })}
            </div>
          )}
          {shownPanel === 'more' && (
            <div role="menu" aria-label={t('format.more')}>
              <button
                type="button"
                role="menuitemcheckbox"
                aria-checked={state.superscript}
                className={rowClass}
                onClick={() => run((c) => c.toggleSuperscript())}
              >
                <TextSuperscriptIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.superscript')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('superscript')}</span>
              </button>
              <button
                type="button"
                role="menuitemcheckbox"
                aria-checked={state.subscript}
                className={rowClass}
                onClick={() => run((c) => c.toggleSubscript())}
              >
                <TextSubscriptIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.subscript')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('subscript')}</span>
              </button>
              <button
                type="button"
                role="menuitem"
                className={rowClass}
                onClick={() => {
                  setPanel(null)
                  editor.commands.editRuby()
                }}
              >
                <TextAaIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.ruby')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('ruby')}</span>
              </button>
            </div>
          )}
          {shownPanel === 'color' && (
            <ColorPanel
              textColor={state.textColor}
              bgColor={state.bgColor}
              onText={(color) => run((c) => c.setTextColor(color))}
              onBackground={(color) => run((c) => c.setBackgroundColor(color))}
            />
          )}
          {shownPanel === 'link' && (
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
  'flex h-8 w-full cursor-pointer items-center gap-2.5 rounded-md px-2 text-left text-sm select-none transition-colors duration-(--motion-pop-out) ease-out hover:bg-accent coarse:h-10'

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
          <Toggle
            size="sm"
            aria-label={label}
            pressed={active}
            onPressedChange={() => onClick()}
            className="size-8 min-w-8 px-0 text-foreground hover:bg-accent aria-pressed:bg-accent aria-pressed:text-foreground coarse:size-10"
          />
        }
      >
        <Glyph size={18} weight={active ? 'bold' : undefined} aria-hidden />
      </TooltipTrigger>
      <TooltipContent side="bottom">
        {label}
        {keys && <Kbd>{keys}</Kbd>}
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
          <Button
            variant="ghost"
            size="icon-sm"
            aria-label={t('format.color')}
            aria-haspopup="menu"
            aria-expanded={active}
            className={cn('hover:bg-accent coarse:size-10', active && 'bg-accent')}
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
      <span className="flex-1 truncate">{color ? colorLabel(color) : t('color.default')}</span>
      {selected && <CheckIcon size={14} aria-hidden />}
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
    <div role="menu" aria-label={t('format.color')}>
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
      <InputGroup className="h-8 shadow-none">
        <InputGroupAddon>
          <LinkSimpleIcon aria-hidden />
        </InputGroupAddon>
        <InputGroupInput
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel exists to type a link
          autoFocus
          className="md:text-sm"
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
      </InputGroup>
      <div className="flex justify-end gap-1">
        {href && (
          <>
            {isSafeHref(href) && (
              <Button
                variant="ghost"
                size="xs"
                className="text-muted-foreground"
                nativeButton={false}
                render={<a href={href} target="_blank" rel="noreferrer" />}
              >
                {t('link.open')}
              </Button>
            )}
            <Button variant="ghost" size="xs" className="text-destructive" onClick={onRemove}>
              {t('link.remove')}
            </Button>
          </>
        )}
        <Button size="xs" onClick={apply}>
          {t('link.apply')}
        </Button>
      </div>
    </div>
  )
}

/** Draws the menu into the extension's React root (the BubbleMenu element; the extension holds no JSX). */
export function renderSelectionMenu(root: Root, editor: Editor): void {
  root.render(
    <IconProvider>
      <TooltipProvider delay={500}>
        <SelectionMenu editor={editor} />
      </TooltipProvider>
    </IconProvider>
  )
}
