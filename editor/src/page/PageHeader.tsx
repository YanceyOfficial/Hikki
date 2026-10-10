import { useCallback, useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from 'react'
import type { EditorBridge } from '../bridge'
import { EmojiPickerPanel } from '../ui/EmojiPickerPanel'
import { Popover } from '../ui/Popover'
import { CoverPicker } from './CoverPicker'
import { coverBackground, randomGradient, randomIcon } from './covers'

/** Notion-style page header: cover, icon, hover actions and the page title (a page property, not body content). */
export function PageHeader({ bridge }: { bridge: EditorBridge }) {
  const page = useSyncExternalStore(bridge.page.subscribe, bridge.page.get)
  const [iconAnchor, setIconAnchor] = useState<HTMLElement | null>(null)
  const [coverAnchor, setCoverAnchor] = useState<HTMLElement | null>(null)
  const [iconOpen, setIconOpen] = useState(false)
  const [coverOpen, setCoverOpen] = useState(false)
  const background = coverBackground(page.cover)
  const closeIcon = useCallback(() => setIconOpen(false), [])
  const closeCover = useCallback(() => setCoverOpen(false), [])

  if (!page.docId) return null

  const uploadCover = async (file: File) => {
    const ext = file.name.split('.').pop()?.toLowerCase() || file.type.split('/')[1] || 'png'
    bridge.setCover(await bridge.saveAsset(file, ext))
    setCoverOpen(false)
  }

  return (
    <header className={`hk-page-header ${background ? 'has-cover' : ''} ${page.icon ? 'has-icon' : ''}`}>
      {background && (
        <div className="hk-cover" style={{ background }} data-testid="cover">
          <div className="hk-cover-actions">
            <button type="button" className="hk-chip" ref={setCoverAnchor} onClick={() => setCoverOpen((o) => !o)}>Change cover</button>
            <button type="button" className="hk-chip" onClick={() => bridge.setCover(null)}>Remove</button>
          </div>
        </div>
      )}
      <div className="hk-column">
        {page.icon && (
          <button type="button" className="hk-page-icon" ref={setIconAnchor} aria-label="Change icon" onClick={() => setIconOpen((o) => !o)}>
            {page.icon}
          </button>
        )}
        <div className="hk-header-actions">
          {!page.icon && (
            <button type="button" className="hk-ghost" ref={setIconAnchor} onClick={() => bridge.setIcon(randomIcon())}>
              <span aria-hidden>☺︎</span> Add icon
            </button>
          )}
          {!background && (
            <button type="button" className="hk-ghost" onClick={() => bridge.setCover(randomGradient())}>
              <span aria-hidden>▨</span> Add cover
            </button>
          )}
        </div>
        <TitleField bridge={bridge} title={page.title} focusRequest={page.focusTitleRequest} docId={page.docId} />
      </div>

      <Popover anchor={iconAnchor} open={iconOpen && !!page.icon} onClose={closeIcon} label="Choose icon" className="hk-emoji-popover">
        <EmojiPickerPanel
          onSelect={(emoji) => { bridge.setIcon(emoji); setIconOpen(false) }}
          onRandom={() => bridge.setIcon(randomIcon())}
          onRemove={() => { bridge.setIcon(null); setIconOpen(false) }}
        />
      </Popover>
      <Popover anchor={coverAnchor} open={coverOpen && !!background} onClose={closeCover} label="Choose cover" placement="bottom-end" className="hk-cover-popover">
        <CoverPicker
          current={page.cover}
          onSelect={(cover) => bridge.setCover(cover)}
          onRemove={() => { bridge.setCover(null); setCoverOpen(false) }}
          onUpload={uploadCover}
        />
      </Popover>
    </header>
  )
}

function TitleField({ bridge, title, focusRequest, docId }: { bridge: EditorBridge; title: string; focusRequest: number; docId: string }) {
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
      className="hk-title"
      rows={1}
      value={title}
      placeholder="Untitled"
      aria-label="Page title"
      spellCheck={false}
      onChange={(e) => bridge.setTitle(e.target.value)}
      onCompositionStart={() => { composing.current = true }}
      onCompositionEnd={() => { composing.current = false }}
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
