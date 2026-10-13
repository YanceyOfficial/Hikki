import { ImageIcon, LockSimpleIcon, SmileyIcon } from '@phosphor-icons/react'
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore
} from 'react'
import { useTranslation } from 'react-i18next'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { ButtonGroup } from '@/components/ui/button-group'
import { Popover as CoverPopover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Textarea } from '@/components/ui/textarea'

import type { EditorBridge } from '../bridge'
import { cn, ui } from '../ui/cn'
import { EmojiPickerPanel } from '../ui/EmojiPickerPanel'
import { Popover } from '../ui/Popover'
import { CoverPicker } from './CoverPicker'
import { coverBackground, randomGradient, randomIcon } from './covers'

/** Notion-style page header: cover, icon, hover actions and the page title (a page property, not body content). */
export function PageHeader({ bridge }: { bridge: EditorBridge }) {
  const { t } = useTranslation()
  const page = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [iconAnchor, setIconAnchor] = useState<HTMLElement | null>(null)
  const [iconOpen, setIconOpen] = useState(false)
  const background = coverBackground(page.cover)
  // Nothing in the header may change on a locked (or unreadable) page.
  const frozen = page.readOnly || page.locked
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
          {!frozen && (
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
                  {t('page.changeCover')}
                </PopoverTrigger>
                <PopoverContent
                  align="end"
                  className="w-[440px] max-w-[calc(100vw-16px)] gap-0 p-0"
                >
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
                {t('page.remove')}
              </Button>
            </ButtonGroup>
          )}
        </div>
      )}
      <div className={cn(ui.column, background ? 'pt-0' : 'pt-18')}>
        {page.icon && (
          <button
            type="button"
            className={cn(
              '-ml-0.5 mb-1 block size-[78px] rounded-lg font-emoji text-[78px] leading-none',
              !frozen && 'cursor-pointer hover:bg-accent',
              background && 'relative -mt-[39px]'
            )}
            ref={setIconAnchor}
            aria-label={t('page.changeIcon')}
            disabled={frozen}
            onClick={() => setIconOpen((o) => !o)}
          >
            {page.icon}
          </button>
        )}
        <div className="mt-2 mb-1 -ml-1.5 flex min-h-7 gap-1 opacity-0 transition-opacity group-hover/header:opacity-100 focus-within:opacity-100 touch:opacity-100">
          {!page.icon && !frozen && (
            <Button
              variant="ghost"
              size="sm"
              className="font-normal text-muted-foreground"
              ref={setIconAnchor}
              onClick={() => bridge.setIcon(randomIcon())}
            >
              <SmileyIcon size={18} aria-hidden /> {t('page.addIcon')}
            </Button>
          )}
          {!background && !frozen && (
            <Button
              variant="ghost"
              size="sm"
              className="font-normal text-muted-foreground"
              onClick={() => bridge.setCover(randomGradient())}
            >
              <ImageIcon size={18} aria-hidden /> {t('page.addCover')}
            </Button>
          )}
        </div>
        {page.readOnly && (
          <Alert className="mb-3" data-testid="read-only-notice">
            <LockSimpleIcon aria-hidden />
            <AlertTitle>{t('page.readOnlyTitle')}</AlertTitle>
            <AlertDescription>{t('page.readOnlyDescription')}</AlertDescription>
          </Alert>
        )}
        <TitleField
          bridge={bridge}
          readOnly={frozen}
          title={page.title}
          focusRequest={page.focusTitleRequest}
          selectOnFocus={page.selectTitle}
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
  selectOnFocus,
  docId,
  readOnly
}: {
  bridge: EditorBridge
  readOnly: boolean
  title: string
  focusRequest: number
  selectOnFocus: boolean
  docId: string
}) {
  const { t } = useTranslation()
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
    if (selectOnFocus) el.select()
    else el.setSelectionRange(el.value.length, el.value.length)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [focusRequest])

  // New, empty pages start with the caret in the title.
  useEffect(() => {
    if (!title && ref.current && !matchMedia?.('(pointer: coarse)').matches) ref.current.focus()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [docId])

  return (
    <Textarea
      ref={ref}
      data-page-title
      className="mb-2 block min-h-0 w-full resize-none overflow-hidden rounded-none border-0 bg-transparent px-0 py-[3px] text-4xl leading-tight font-bold tracking-[-0.01em] text-foreground shadow-none placeholder:text-placeholder focus-visible:ring-0 max-sm:text-3xl md:text-4xl dark:bg-transparent"
      rows={1}
      value={title}
      readOnly={readOnly}
      placeholder={t('page.untitled')}
      aria-label={t('page.titleLabel')}
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
