import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore
} from 'react'

import { Button } from '@/components/ui/button'
import { ButtonGroup } from '@/components/ui/button-group'
import { Popover as CoverPopover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'

import type { EditorBridge } from '../bridge'
import { cn, ui } from '../ui/cn'
import { EmojiPickerPanel } from '../ui/EmojiPickerPanel'
import { Popover } from '../ui/Popover'
import { CoverPicker } from './CoverPicker'
import { coverBackground, randomGradient, randomIcon } from './covers'

/** Notion-style page header: cover, icon, hover actions and the page title (a page property, not body content). */
export function PageHeader({ bridge }: { bridge: EditorBridge }) {
  const page = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [iconAnchor, setIconAnchor] = useState<HTMLElement | null>(null)
  const [iconOpen, setIconOpen] = useState(false)
  const background = coverBackground(page.cover)
  const closeIcon = useCallback(() => setIconOpen(false), [])

  if (!page.docId) return null

  const uploadCover = async (file: File) => {
    const ext = file.name.split('.').pop()?.toLowerCase() || file.type.split('/')[1] || 'png'
    bridge.setCover(await bridge.saveAsset(file, ext))
  }

  return (
    <header className="group/header relative">
      {background && (
        <div
          className="group/cover relative h-[30vh] max-h-[280px] min-h-[140px]"
          style={{ background }}
          data-testid="cover"
        >
          {/* Notion-style button group, top right; visible on hover (always on touch / while open). */}
          <ButtonGroup className="absolute top-3 right-3 opacity-0 transition-opacity group-focus-within/cover:opacity-100 group-hover/cover:opacity-100 has-aria-expanded:opacity-100 touch:opacity-100">
            <CoverPopover>
              <PopoverTrigger
                render={
                  <Button
                    variant="outline"
                    size="sm"
                    className="bg-popover text-popover-foreground shadow-sm dark:bg-popover"
                  />
                }
              >
                Change cover
              </PopoverTrigger>
              <PopoverContent align="end" className="w-[440px] max-w-[calc(100vw-16px)] gap-0 p-0">
                <CoverPicker
                  current={page.cover}
                  onSelect={(cover) => bridge.setCover(cover)}
                  onRemove={() => bridge.setCover(null)}
                  onUpload={uploadCover}
                />
              </PopoverContent>
            </CoverPopover>
            <Button
              variant="outline"
              size="sm"
              className="bg-popover text-popover-foreground shadow-sm dark:bg-popover"
              onClick={() => bridge.setCover(null)}
            >
              Remove
            </Button>
          </ButtonGroup>
        </div>
      )}
      <div className={cn(ui.column, background ? 'pt-0' : 'pt-18')}>
        {page.icon && (
          <button
            type="button"
            className={cn(
              '-ml-0.5 mb-1 block size-[78px] cursor-pointer rounded-lg font-emoji text-[78px] leading-none hover:bg-accent',
              background && 'relative -mt-[39px]'
            )}
            ref={setIconAnchor}
            aria-label="Change icon"
            onClick={() => setIconOpen((o) => !o)}
          >
            {page.icon}
          </button>
        )}
        <div className="mt-2 mb-1 -ml-1.5 flex min-h-7 gap-1 opacity-0 transition-opacity group-hover/header:opacity-100 focus-within:opacity-100 touch:opacity-100">
          {!page.icon && (
            <button
              type="button"
              className={ui.ghost}
              ref={setIconAnchor}
              onClick={() => bridge.setIcon(randomIcon())}
            >
              <span aria-hidden>☺︎</span> Add icon
            </button>
          )}
          {!background && (
            <button
              type="button"
              className={ui.ghost}
              onClick={() => bridge.setCover(randomGradient())}
            >
              <span aria-hidden>▨</span> Add cover
            </button>
          )}
        </div>
        <TitleField
          bridge={bridge}
          title={page.title}
          focusRequest={page.focusTitleRequest}
          docId={page.docId}
        />
      </div>

      <Popover
        anchor={iconAnchor}
        open={iconOpen && !!page.icon}
        onClose={closeIcon}
        label="Choose icon"
        className="w-[400px]"
      >
        <EmojiPickerPanel
          onSelect={(emoji) => {
            bridge.setIcon(emoji)
            setIconOpen(false)
          }}
          onRandom={() => bridge.setIcon(randomIcon())}
          onRemove={() => {
            bridge.setIcon(null)
            setIconOpen(false)
          }}
        />
      </Popover>
    </header>
  )
}

function TitleField({
  bridge,
  title,
  focusRequest,
  docId
}: {
  bridge: EditorBridge
  title: string
  focusRequest: number
  docId: string
}) {
  const ref = useRef<HTMLTextAreaElement>(null)
  const composing = useRef(false)

  // Auto-grow to fit wrapped lines.
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    el.style.height = '0px'
    el.style.height = `${el.scrollHeight}px`
  }, [title])

  // Caret into the title, at its end (ArrowUp / Backspace from the top of the body).
  useEffect(() => {
    if (!focusRequest || !ref.current) return
    const el = ref.current
    el.focus()
    el.setSelectionRange(el.value.length, el.value.length)
  }, [focusRequest])

  // New, empty pages start with the caret in the title.
  useEffect(() => {
    if (!title && ref.current && !matchMedia?.('(pointer: coarse)').matches) ref.current.focus()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [docId])

  return (
    <textarea
      ref={ref}
      className="mb-2 block w-full resize-none overflow-hidden border-0 bg-transparent py-[3px] text-4xl leading-tight font-bold tracking-[-0.01em] text-foreground outline-none placeholder:text-placeholder max-sm:text-3xl"
      rows={1}
      value={title}
      placeholder="Untitled"
      aria-label="Page title"
      spellCheck={false}
      onChange={(e) => bridge.setTitle(e.target.value)}
      onCompositionStart={() => {
        composing.current = true
      }}
      onCompositionEnd={() => {
        composing.current = false
      }}
      onKeyDown={(e) => {
        // Never act on Enter while an IME (pinyin) is composing — that Enter commits the candidate.
        if (composing.current || e.nativeEvent.isComposing) return
        const el = e.currentTarget
        const atEnd = el.selectionStart === el.value.length && el.selectionEnd === el.value.length
        if (e.key === 'Enter') {
          e.preventDefault()
          bridge.enterFromTitle()
        } else if (e.key === 'ArrowDown' && atEnd) {
          e.preventDefault()
          bridge.focusBodyStart()
        }
      }}
    />
  )
}
