import { type Icon } from '@phosphor-icons/react'
import type { Editor } from '@tiptap/core'
import { cn } from 'cn'
import { useLayoutEffect, useRef, useState } from 'react'
import type { Root } from 'react-dom/client'

import { Button } from '@/components/ui/button'
import { InputGroup, InputGroupAddon, InputGroupInput } from '@/components/ui/input-group'
import { Kbd } from '@/components/ui/kbd'
import { Toggle } from '@/components/ui/toggle'
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip'

import { t } from '../core/i18n'
import { isSafeHref, normalizeHref } from '../core/links'
import { shortcutLabel } from '../core/shortcuts'
import type { PaletteColor } from '../extensions/colors'
import {
  CaretRightIcon,
  ChatTeardropTextIcon,
  CodeIcon,
  DotsThreeIcon,
  EraserIcon,
  LinkSimpleIcon,
  MathOperationsIcon,
  SparkleIcon,
  TextAaIcon,
  TextBIcon,
  TextItalicIcon,
  TextStrikethroughIcon,
  TextSubscriptIcon,
  TextSuperscriptIcon,
  TextUnderlineIcon
} from '../generated/icons'
import { useEditorSnapshot } from '../hooks/use-editor-snapshot'
import { AIPanel } from './ai-panel'
import { BlockTypeList, TURN_INTO } from './block-type-list'
import { ColorList, ColorSwatch } from './color-list'
import { usePresence } from './floating'
import { IconProvider } from './icons'
import { MenuRow } from './menu-row'

type Panel = 'ai' | 'turnInto' | 'color' | 'link' | 'more' | null

/**
 * What the menu shows; recomputed per transaction, re-rendered only on change. The selection counts only
 * while it is one (the menu's moment): a caret moving as the user types re-renders nothing.
 */
function snapshot(editor: Editor) {
  const style = editor.getAttributes('textStyle')
  const { from, to } = editor.state.selection
  return {
    selection: from === to ? '' : `${from}:${to}`,
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
 * "Ask AI" opens the AI actions (`AIReview` shows the result under the selection).
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

  // A new selection starts with the panels closed — the link panel too: a link typed for one selection
  // never lands on the next (a selection collapsing on a click elsewhere is a change as well).
  const [lastSelection, setLastSelection] = useState(state.selection)
  if (lastSelection !== state.selection) {
    setLastSelection(state.selection)
    if (panel) setPanel(null)
  }

  const run = (apply: (chain: ReturnType<Editor['chain']>) => ReturnType<Editor['chain']>) =>
    apply(editor.chain().focus()).run()
  const toggle = (name: Panel) => setPanel((current) => (current === name ? null : name))
  // The rows with a caret open their panel on hover (a menu's submenu); a click also puts the caret in its field.
  const [clicked, setClicked] = useState(false)
  const hover = (name: Panel) => {
    if (panel !== name) {
      setClicked(false)
      setPanel(name)
    }
  }
  // The side panel stays in the tree through its leave motion, showing whatever it last showed.
  const panelRef = useRef<HTMLDivElement>(null)
  const panelShown = usePresence(panel !== null, panelRef)
  const [shownPanel, setShownPanel] = useState(panel)
  if (panel && panel !== shownPanel) setShownPanel(panel)
  // A short window: the panel would run past its foot (and be cut off), so it moves up as far as it must — never
  // under the toolbar.
  const [panelShift, setPanelShift] = useState(0)
  useLayoutEffect(() => {
    const element = panelRef.current
    if (!panelShown || !shownPanel || !element) return
    setPanelShift(
      panelShiftFor(element, window.visualViewport?.height ?? window.innerHeight, insetTop())
    )
  }, [panelShown, shownPanel])
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
        <MenuRow
          aria-haspopup="menu"
          aria-expanded={panel === 'ai'}
          data-testid="selection-menu-ask-ai"
          onMouseEnter={() => hover('ai')}
          onClick={() => {
            setClicked(true)
            setPanel('ai')
          }}
        >
          <SparkleIcon size={18} weight="fill" className="text-primary" aria-hidden />
          <span className="flex-1 truncate">{t('ai.menu')}</span>
          <CaretRightIcon size={14} className="text-muted-foreground" aria-hidden />
        </MenuRow>
        <MenuRow
          data-testid="selection-menu-comment"
          onMouseEnter={() => {
            if (panel === 'ai' || panel === 'turnInto') setPanel(null)
          }}
          onClick={() => editor.commands.commentStart()}
        >
          <ChatTeardropTextIcon size={18} className="text-subtle-foreground" aria-hidden />
          <span className="flex-1 truncate">{t('comments.menu')}</span>
          <span className="text-xs text-placeholder">{shortcutLabel('comment')}</span>
        </MenuRow>
        <MenuRow
          aria-haspopup="menu"
          aria-expanded={panel === 'turnInto'}
          onMouseEnter={() => hover('turnInto')}
          onClick={() => setPanel('turnInto')}
        >
          <CurrentIcon size={18} className="text-subtle-foreground" aria-hidden />
          <span className="flex-1 truncate">{current.label()}</span>
          <CaretRightIcon size={14} className="text-muted-foreground" aria-hidden />
        </MenuRow>
        <div className="mx-1 my-1 h-px bg-border" />
        <div
          className="grid grid-cols-5 gap-0.5"
          // Leaving the rows for the buttons closes a panel the rows opened.
          onMouseEnter={() => {
            if (panel === 'ai' || panel === 'turnInto') setPanel(null)
          }}
        >
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
            'hk-pop absolute max-h-[min(440px,calc(100vh-96px))] w-[224px] overflow-y-auto overscroll-contain rounded-xl bg-popover p-1 text-popover-foreground shadow-popover',
            panelLeft ? 'right-full mr-1.5 [--hk-pop-origin:top_right]' : 'left-full ml-1.5'
          )}
          style={{ top: panelShift }}
          data-testid={`selection-menu-${shownPanel}`}
        >
          {shownPanel === 'ai' && (
            <AIPanel
              autoFocus={clicked}
              onRun={(action) => {
                setPanel(null)
                editor.commands.aiRun(action)
              }}
              onCancel={() => {
                setPanel(null)
                editor.commands.focus()
              }}
            />
          )}
          {shownPanel === 'turnInto' && (
            <div role="menu" aria-label={t('format.turnInto')}>
              <BlockTypeList
                title={t('format.turnInto')}
                current={state.block}
                onPick={(block) => {
                  block.turnInto?.(editor.chain().focus()).run()
                  block.after?.(editor)
                  setPanel(null)
                }}
              />
            </div>
          )}
          {shownPanel === 'more' && (
            <div role="menu" aria-label={t('format.more')}>
              <MenuRow
                role="menuitemcheckbox"
                aria-checked={state.superscript}
                onClick={() => run((c) => c.toggleSuperscript())}
              >
                <TextSuperscriptIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.superscript')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('superscript')}</span>
              </MenuRow>
              <MenuRow
                role="menuitemcheckbox"
                aria-checked={state.subscript}
                onClick={() => run((c) => c.toggleSubscript())}
              >
                <TextSubscriptIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.subscript')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('subscript')}</span>
              </MenuRow>
              <MenuRow
                role="menuitem"
                onClick={() => {
                  setPanel(null)
                  editor.commands.editRuby()
                }}
              >
                <TextAaIcon size={18} className="text-subtle-foreground" aria-hidden />
                <span className="flex-1 truncate">{t('format.ruby')}</span>
                <span className="text-xs text-placeholder">{shortcutLabel('ruby')}</span>
              </MenuRow>
            </div>
          )}
          {shownPanel === 'color' && (
            <div role="menu" aria-label={t('format.color')}>
              <ColorList
                kind="mark"
                text={state.textColor}
                background={state.bgColor}
                onText={(color) => run((c) => c.setTextColor(color))}
                onBackground={(color) => run((c) => c.setBackgroundColor(color))}
              />
            </div>
          )}
          {shownPanel === 'link' && (
            <LinkPanel
              // Its field starts from the selection it was opened for.
              key={`${state.selection}:${state.link ?? ''}`}
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

/** Buttons keep the editor's selection: no focus change on press (inputs are exempt). */
function keepEditorFocus(event: React.MouseEvent) {
  const target = event.target as HTMLElement
  if (!target.closest('input')) event.preventDefault()
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
        <ColorSwatch text={textColor} background={bgColor} />
      </TooltipTrigger>
      <TooltipContent side="bottom">{t('format.color')}</TooltipContent>
    </Tooltip>
  )
}

export function LinkPanel({
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

/** The toolbar's height over the page (`setInsets`). */
const insetTop = () =>
  Number.parseFloat(
    getComputedStyle(document.documentElement).getPropertyValue('--hk-inset-top')
  ) || 0

/**
 * How far up a side panel moves so its foot stays 8 px inside a window `height` tall, its top at least 8 px under
 * the toolbar (`top`). Measured from its menu's top and its own height (not its box: `hk-pop` scales it in).
 */
export function panelShiftFor(element: HTMLElement, height: number, top: number): number {
  const menuTop = element.offsetParent?.getBoundingClientRect().top ?? 0
  const overflow = menuTop + element.offsetHeight - (height - 8)
  if (overflow <= 0) return 0
  return -Math.min(overflow, Math.max(0, menuTop - (top + 8)))
}
