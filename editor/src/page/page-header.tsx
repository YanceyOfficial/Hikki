import { Image01Icon, SmileIcon, SquareLock02Icon } from '@hugeicons/core-free-icons'
import { cn } from 'cn'
import {
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  useSyncExternalStore,
  type ReactNode
} from 'react'
import { useTranslation } from 'react-i18next'

import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Popover as CoverPopover, PopoverContent, PopoverTrigger } from '@/components/ui/popover'
import { Separator } from '@/components/ui/separator'
import { Textarea } from '@/components/ui/textarea'

import { AnchoredPopover } from '../components/anchored-popover'
import { EmojiPickerPanel } from '../components/emoji-picker-panel'
import { Icon } from '../components/icons'
import { LazyLoadImage } from '../components/lazy-load-image'
import type { EditorBridge } from '../core/bridge'
import {
  coverBackground,
  coverImage,
  coverPosition,
  isImageCover,
  randomGradient,
  randomIcon,
  repositionedCover,
  withCoverPosition
} from '../lib/covers'
import { CoverPicker } from './cover-picker'

/** Notion-style page header: cover, icon, hover actions and the page title (a page property, not body content). */
export function PageHeader({ bridge }: { bridge: EditorBridge }) {
  const { t } = useTranslation()
  const page = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [iconAnchor, setIconAnchor] = useState<HTMLElement | null>(null)
  const [iconOpen, setIconOpen] = useState(false)
  // Reposition: the position being dragged (null when not repositioning).
  const [draftY, setDraftY] = useState<number | null>(null)
  const cover = draftY !== null && page.cover ? withCoverPosition(page.cover, draftY) : page.cover
  const background = coverBackground(cover)
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
      {/* iPhone: the page runs to the top of the screen (no native inset); a cover fills the room behind the
          status bar and the glass buttons, a page without one starts below them. */}
      {!background && <div aria-hidden style={{ height: 'var(--hk-bleed-top, 0px)' }} />}
      {background && (
        <Cover
          background={background}
          image={coverImage(cover)}
          repositioning={draftY !== null}
          onDrag={setDraftY}
        >
          {draftY !== null ? (
            <CoverActions>
              <CoverAction
                onClick={() => {
                  if (page.cover) bridge.setCover(withCoverPosition(page.cover, draftY))
                  setDraftY(null)
                }}
              >
                {t('page.savePosition')}
              </CoverAction>
              <Separator orientation="vertical" className="mx-0.5 h-4 self-center!" />
              <CoverAction onClick={() => setDraftY(null)}>
                {t('page.cancelReposition')}
              </CoverAction>
            </CoverActions>
          ) : (
            // Visible on hover (always on touch / while open).
            !frozen && (
              <CoverActions className="opacity-0 transition-opacity group-focus-within/cover:opacity-100 group-hover/cover:opacity-100 has-aria-expanded:opacity-100 touch:opacity-100">
                <CoverPopover>
                  <PopoverTrigger render={<CoverAction />}>{t('page.changeCover')}</PopoverTrigger>
                  <PopoverContent
                    align="end"
                    className="w-[440px] max-w-[calc(100vw-16px)] gap-0 p-0"
                  >
                    <CoverPicker
                      current={page.cover}
                      onSelect={(next) => bridge.setCover(next)}
                      onRemove={() => bridge.setCover(null)}
                      onUpload={uploadCover}
                    />
                  </PopoverContent>
                </CoverPopover>
                {isImageCover(page.cover) && (
                  <>
                    <Separator orientation="vertical" className="mx-0.5 h-4 self-center!" />
                    <CoverAction onClick={() => setDraftY(coverPosition(page.cover))}>
                      {t('page.reposition')}
                    </CoverAction>
                  </>
                )}
              </CoverActions>
            )
          )}
        </Cover>
      )}
      <div className={cn('hk-column', background ? 'pt-0' : 'pt-18')}>
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
              <Icon icon={SmileIcon} size={18} aria-hidden /> {t('page.addIcon')}
            </Button>
          )}
          {!background && !frozen && (
            <Button
              variant="ghost"
              size="sm"
              className="font-normal text-muted-foreground"
              onClick={() => bridge.setCover(randomGradient())}
            >
              <Icon icon={Image01Icon} size={18} aria-hidden /> {t('page.addCover')}
            </Button>
          )}
        </div>
        {page.readOnly && (
          <Alert className="mb-3" data-testid="read-only-notice">
            <Icon icon={SquareLock02Icon} aria-hidden />
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
          autoFocus={page.autoFocus}
          docId={page.docId}
        />
      </div>

      <AnchoredPopover
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
      </AnchoredPopover>
    </header>
  )
}

function TitleField({
  bridge,
  title,
  focusRequest,
  selectOnFocus,
  autoFocus,
  docId,
  readOnly
}: {
  bridge: EditorBridge
  readOnly: boolean
  autoFocus: boolean
  title: string
  focusRequest: number
  selectOnFocus: boolean
  docId: string
}) {
  const { t } = useTranslation()
  const ref = useRef<HTMLTextAreaElement>(null)
  const composing = useRef(false)

  // Auto-grow to fit wrapped lines — again whenever the width changes or fonts arrive: measured once on a cold launch,
  // while the web view was still narrow, the title kept the height of several wrapped lines and pushed the body far
  // down the page.
  useLayoutEffect(() => {
    const el = ref.current
    if (!el) return
    fitTitle(el)
  }, [title])
  useEffect(() => {
    const el = ref.current
    if (!el) return
    let width = el.clientWidth
    const observer = new ResizeObserver(() => {
      if (el.clientWidth === width) return
      width = el.clientWidth
      fitTitle(el)
    })
    observer.observe(el)
    void document.fonts?.ready.then(() => fitTitle(el))
    return () => observer.disconnect()
  }, [])

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
    if (autoFocus && !title && ref.current && !matchMedia?.('(pointer: coarse)').matches)
      ref.current.focus()
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

/**
 * The cover picture (or gradient) with the controls over it. While repositioning, dragging it moves the
 * picture vertically, one pixel per pixel of drag (the image's overflow beyond the cover is measured once
 * the image has loaded); the position is reported in percent through `onDrag`.
 */
function Cover({
  background,
  image,
  repositioning,
  onDrag,
  children
}: {
  background: string
  /** An image cover is drawn as an <img> (see below); a gradient as the CSS background. */
  image: { src: string; y: number } | null
  repositioning: boolean
  onDrag: (y: number) => void
  children: ReactNode
}) {
  const { t } = useTranslation()
  const ref = useRef<HTMLDivElement>(null)
  const drag = useRef<{ pointerId: number; startY: number; startClientY: number } | null>(null)
  const overflow = useCoverOverflow(ref, image?.src ?? null)

  const onPointerDown = (event: React.PointerEvent<HTMLDivElement>) => {
    if (!repositioning || event.button !== 0) return
    // A press on the controls is theirs: capturing the pointer here would steal their click.
    if ((event.target as HTMLElement).closest('[data-slot="cover-actions"]')) return
    drag.current = {
      pointerId: event.pointerId,
      startY: image?.y ?? 50,
      startClientY: event.clientY
    }
    event.currentTarget.setPointerCapture?.(event.pointerId)
    event.preventDefault()
  }
  const onPointerMove = (event: React.PointerEvent<HTMLDivElement>) => {
    const d = drag.current
    if (!d || d.pointerId !== event.pointerId) return
    const height = event.currentTarget.getBoundingClientRect().height
    onDrag(repositionedCover(d.startY, event.clientY - d.startClientY, height, overflow))
  }
  const onPointerUp = (event: React.PointerEvent<HTMLDivElement>) => {
    if (drag.current?.pointerId === event.pointerId) drag.current = null
  }

  return (
    <div
      ref={ref}
      className={cn(
        'hk-cover group/cover relative',
        repositioning && 'cursor-grab touch-none select-none active:cursor-grabbing'
      )}
      style={image ? undefined : { background }}
      data-testid="cover"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onPointerCancel={onPointerUp}
    >
      {/* A picture as a CSS background was re-rasterized at every size while the window was resized (the cover
          flickered); an <img> on its own compositing layer is decoded once and scaled by the GPU. */}
      {image && (
        <LazyLoadImage
          src={image.src}
          alt=""
          imgTestId="cover-image"
          className="pointer-events-none absolute inset-0 select-none"
          imgClassName="[transform:translateZ(0)] [backface-visibility:hidden]"
          imgStyle={{ objectPosition: `50% ${image.y}%` }}
        />
      )}
      {repositioning && (
        <div className="pointer-events-none absolute inset-x-0 top-1/2 flex -translate-y-1/2 justify-center">
          <span className="hk-pop rounded-md bg-popover/90 px-3 py-1.5 text-sm text-popover-foreground shadow-sm">
            {t('page.repositionHint')}
          </span>
        </div>
      )}
      {children}
    </div>
  )
}

/**
 * How many pixels of the cover's image lie beyond the cover vertically (null until the image has loaded, or
 * for a gradient): what a reposition drag can travel.
 */
function useCoverOverflow(
  ref: React.RefObject<HTMLDivElement | null>,
  src: string | null
): number | null {
  // Measured for one picture; another picture's cover reads as unmeasured until its own load lands.
  const [measured, setMeasured] = useState<{ src: string; overflow: number } | null>(null)
  useEffect(() => {
    if (!src || typeof Image === 'undefined') return
    let cancelled = false
    const image = new Image()
    image.addEventListener(
      'load',
      () => {
        if (cancelled || !ref.current || !image.naturalWidth) return
        const { width, height } = ref.current.getBoundingClientRect()
        // `object-fit: cover`: the image fills the width (or the height, when it is the taller one).
        const scale = Math.max(width / image.naturalWidth, height / image.naturalHeight)
        setMeasured({ src, overflow: image.naturalHeight * scale - height })
      },
      { once: true }
    )
    image.src = src
    return () => {
      cancelled = true
    }
  }, [src, ref])
  return src && measured?.src === src ? measured.overflow : null
}

/**
 * Notion's cover controls: one white pill at the top right, the actions inside separated by hairlines, a
 * soft tint on the hovered one (no per-button borders).
 */
function CoverActions({ className, children }: { className?: string; children: ReactNode }) {
  return (
    <div
      role="group"
      data-slot="cover-actions"
      className={cn(
        'absolute top-[calc(var(--hk-bleed-top,0px)+0.75rem)] right-3 flex items-center gap-0.5 rounded-md bg-popover p-0.5 text-popover-foreground shadow-sm ring-1 ring-foreground/10',
        className
      )}
    >
      {children}
    </div>
  )
}

function CoverAction(props: React.ComponentProps<typeof Button>) {
  return (
    <Button
      variant="ghost"
      size="sm"
      {...props}
      className={cn(
        'h-7 rounded-sm px-2 font-normal text-subtle-foreground hover:bg-muted hover:text-foreground aria-expanded:bg-muted aria-expanded:text-foreground',
        props.className
      )}
    />
  )
}

/** The title's height to fit its wrapped lines. */
export function fitTitle(el: HTMLTextAreaElement): void {
  el.style.height = '0px'
  el.style.height = `${el.scrollHeight}px`
}
