import {
  COMPACT_DRAWING_QUERY,
  excalidrawLanguage,
  setDrawingAssetPath,
  type DrawingData,
  type StoredElement
} from '@hikki/excalidraw'
import type { DrawingHandle, DrawingHost } from '@hikki/excalidraw/canvas'
import { Component, Suspense, lazy, useEffect, useRef, useState, type ReactNode } from 'react'
import { flushSync } from 'react-dom'
import { createRoot } from 'react-dom/client'

import { reportError } from '../core/errors'
import i18n, { t } from '../core/i18n'
import type { DrawingEditorHost } from '../extensions/drawing'
import { useMediaQuery } from '../hooks/use-media-query'
import { leave } from './floating'
import { Button } from './ui/button'

// Excalidraw's fonts, all of them bundled with the editor (`@hikki/excalidraw/vite-plugin`): never a CDN.
setDrawingAssetPath(new URL('./excalidraw/', document.baseURI).href)

/** Excalidraw and its stylesheet load the first time a drawing opens (a chunk of their own), never with the page. */
const DrawingCanvas = lazy(() =>
  import('@hikki/excalidraw/canvas').then((module) => ({ default: module.DrawingCanvas }))
)

/** How long the drawing rests before its changes go into the page. */
const SYNC_DELAY = 600

const DARK = '(prefers-color-scheme: dark)'

function useTheme(): 'light' | 'dark' {
  const [dark, setDark] = useState(() => window.matchMedia?.(DARK).matches ?? false)
  useEffect(() => {
    const query = window.matchMedia?.(DARK)
    const changed = () => setDark(query.matches)
    query?.addEventListener('change', changed)
    return () => query?.removeEventListener('change', changed)
  }, [])
  return dark ? 'dark' : 'light'
}

/** Excalidraw failed to load or to draw: reported, and the drawing closes (the block keeps what it had). */
class CanvasBoundary extends Component<
  { onFail: () => void; children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false }
  static getDerivedStateFromError() {
    return { failed: true }
  }
  componentDidCatch(error: unknown) {
    reportError('drawingLoadFailed', error)
    this.props.onFail()
  }
  render() {
    return this.state.failed ? null : this.props.children
  }
}

type Props = {
  data: DrawingData
  host: DrawingEditorHost
  title: string
  handleRef: { current: DrawingHandle | null }
  onChange: (data: DrawingData) => void
  onDone: (data: DrawingData, preview: Blob | null) => Promise<void>
  /** Excalidraw couldn't load: close without writing anything. */
  onFail: () => void
  /** Opened to look at only (a phone-sized screen): Excalidraw's view mode, and Close in place of Done, which writes nothing. */
  readOnly?: boolean
  /** A diagram to open an empty drawing with (`insertDiagram`). */
  mermaid?: string
}

function DrawingEditor({
  data,
  host,
  title,
  handleRef,
  onChange,
  onDone,
  onFail,
  readOnly = false,
  mermaid
}: Props) {
  // Decided once per opening: the app offers a Library or not (`window.hikki.setDrawings`); never to look at.
  const [library] = useState(() => (readOnly ? null : (host.library?.() ?? null)))
  const theme = useTheme()
  const compact = useMediaQuery(COMPACT_DRAWING_QUERY)
  const [saving, setSaving] = useState(false)
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null)
  useEffect(() => () => clearTimeout(timer.current ?? undefined), [])

  const sync = async () => {
    const handle = handleRef.current
    if (!handle) return
    try {
      onChange(await handle.data())
    } catch (error) {
      reportError('uploadFailed', error, { kind: 'drawing' })
    }
  }
  const changed = () => {
    clearTimeout(timer.current ?? undefined)
    timer.current = setTimeout(() => void sync(), SYNC_DELAY)
  }
  const done = async () => {
    const handle = handleRef.current
    if (!handle || saving) return
    clearTimeout(timer.current ?? undefined)
    setSaving(true)
    try {
      await onDone(await handle.data(), await handle.preview())
    } catch (error) {
      // A picture placed in it couldn't be stored: the drawing stays open, nothing is lost.
      reportError('uploadFailed', error, { kind: 'drawing' })
      setSaving(false)
    }
  }

  const doneButton = readOnly ? (
    <Button size="sm" variant="secondary" onClick={onFail}>
      {t('drawing.close')}
    </Button>
  ) : (
    <Button size="sm" disabled={saving} onClick={() => void done()}>
      {t('drawing.done')}
    </Button>
  )

  const canvasHost: DrawingHost = {
    upload: host.upload,
    read: host.read,
    openLink: host.openLink,
    diagram: host.diagram,
    library,
    language: excalidrawLanguage(i18n.language),
    theme
  }
  return (
    <div
      className="hk-drawing-editor flex h-full flex-col bg-background"
      // Without a Library (iOS) its button goes (style.css).
      data-library={library ? 'on' : 'off'}
      // Clear of what stays over the page (the Mac's toolbar; a phone's status bar and home indicator).
      style={{
        paddingTop: 'max(var(--hk-inset-top, 0px), env(safe-area-inset-top, 0px))',
        paddingBottom: 'max(var(--hk-inset-bottom, 0px), env(safe-area-inset-bottom, 0px))'
      }}
      role="dialog"
      aria-modal="true"
      aria-label={title}
    >
      {compact && (
        <div className="flex h-12 flex-none items-center justify-between gap-2 px-4">
          <span className="truncate text-md font-medium text-foreground">{title}</span>
          {doneButton}
        </div>
      )}
      <CanvasBoundary onFail={onFail}>
        <Suspense
          fallback={
            <div className="flex flex-1 items-center justify-center text-md text-muted-foreground">
              {t('drawing.loading')}
            </div>
          }
        >
          <DrawingCanvas
            initial={data}
            host={canvasHost}
            handleRef={handleRef}
            onChange={readOnly ? undefined : changed}
            topRight={doneButton}
            readOnly={readOnly}
            mermaid={mermaid}
          />
        </Suspense>
      </CanvasBoundary>
    </div>
  )
}

export type DrawingOverlay = {
  /** The drawing's live elements now (null before Excalidraw has loaded). */
  elements: () => StoredElement[] | null
  /** What Done hands over — the drawing, its pictures stored, and its preview — or null before Excalidraw has
   * loaded. Rejects when a picture can't be stored. */
  done: () => Promise<{ data: DrawingData; preview: Blob | null } | null>
  destroy: () => void
}

/**
 * The drawing editor over the whole window (`hk-pop` in and out). Its changes reach `onChange` once it rests;
 * Done hands over the drawing and its preview. Escape stays Excalidraw's (it leaves a tool or a selection), so the
 * layer is not on the dismiss bus: the page closes it (`closeDrawing`) when it goes away.
 */
export function renderDrawingOverlay(props: Omit<Props, 'handleRef'>): DrawingOverlay {
  const element = document.createElement('div')
  element.className = 'hk-pop fixed inset-0 z-50'
  element.style.setProperty('--hk-pop-dy', '0px')
  document.body.append(element)
  const root = createRoot(element)
  const handleRef: { current: DrawingHandle | null } = { current: null }
  flushSync(() => root.render(<DrawingEditor {...props} handleRef={handleRef} />))
  let destroyed = false
  return {
    elements: () => handleRef.current?.elements() ?? null,
    done: async () => {
      const handle = handleRef.current
      return handle ? { data: await handle.data(), preview: await handle.preview() } : null
    },
    destroy: () => {
      if (destroyed) return
      destroyed = true
      leave(element, () => {
        root.unmount()
        element.remove()
      })
    }
  }
}
