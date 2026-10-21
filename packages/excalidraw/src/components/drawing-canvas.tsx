import '@excalidraw/excalidraw/index.css'
import {
  Excalidraw,
  exportToBlob,
  getSceneVersion,
  MainMenu,
  TTDDialog,
  TTDDialogTrigger,
  WelcomeScreen
} from '@excalidraw/excalidraw'
import type {
  BinaryFileData,
  BinaryFiles,
  ExcalidrawImperativeAPI
} from '@excalidraw/excalidraw/types'
import {
  useCallback,
  useImperativeHandle,
  useRef,
  useState,
  type ReactElement,
  type RefObject
} from 'react'

import { libraryKeeper, type DrawingLibraryHost } from '../library'
import {
  checkPaste,
  inlineFiles,
  isDrawableType,
  isSafeLiveElement,
  safeDrawingLink,
  storedElements,
  usedFileIds,
  type DrawingData,
  type DrawingFileRef
} from '../scene'

export type { DrawingLibraryHost } from '../library'

/** What the drawing editor needs from the app; the package never talks to the native side itself. */
export type DrawingHost = {
  /** Stores a file (a picture placed in the drawing, the preview); resolves to its URL. */
  upload: (blob: Blob, extension: string) => Promise<string>
  /** Reads a stored file back (the editor's own assets only). */
  read: (src: string) => Promise<Blob>
  /** Opens a web address (an element's link, http or https only) in the browser. */
  openLink: (url: string) => void
  /** Text to diagram: the user's words as a Mermaid diagram (AI); null hides it. Rejects with a message to show. */
  diagram: ((prompt: string) => Promise<string>) | null
  /** Excalidraw's Library (shapes kept for every drawing); null: none — its button is hidden by the editor. */
  library: DrawingLibraryHost | null
  /** Excalidraw's language code (`excalidrawLanguage`). */
  language: string
  theme: 'light' | 'dark'
}

/** What the editor holding the canvas can ask of it. */
export type DrawingHandle = {
  /** The drawing as it stands: elements, and pictures stored through the host (new ones uploaded now). */
  data: () => Promise<DrawingData>
  /** A PNG of the drawing (transparent, twice the size), or null when it is empty. */
  preview: () => Promise<Blob | null>
  /** The live elements as they stand, at once (no pictures stored): for closing in a hurry. */
  elements: () => DrawingData['elements']
}

type Props = {
  initial: DrawingData
  host: DrawingHost
  handleRef: RefObject<DrawingHandle | null>
  /** The drawing changed (debounce on the caller's side): its live elements. */
  onChange?: (elements: DrawingData['elements']) => void
  /** Drawn at the top right, beside Excalidraw's own controls (the editor's Done button) — not in Excalidraw's phone
   * layout, whose toolbar fills the top: the editor puts it in a bar of its own there (`isCompactDrawing`). */
  topRight?: ReactElement
  /** Looked at only: Excalidraw's view mode (pan and zoom, nothing changes). */
  readOnly?: boolean
}

const extensionOf = (mimeType: string) =>
  ({ 'image/jpeg': 'jpg', 'image/svg+xml': 'svg' })[mimeType] ?? mimeType.split('/')[1] ?? 'png'

function dataURLOf(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.addEventListener('load', () => resolve(String(reader.result)))
    reader.addEventListener('error', () => reject(reader.error ?? new Error('unreadable file')))
    reader.readAsDataURL(blob)
  })
}

/** The pictures a stored drawing shows, read back as Excalidraw wants them (data URLs); unreadable ones are skipped. */
async function loadFiles(
  files: Record<string, DrawingFileRef>,
  host: DrawingHost
): Promise<BinaryFileData[]> {
  const loaded = await Promise.all(
    Object.entries(files).map(async ([id, ref]) => {
      try {
        const dataURL = (await dataURLOf(await host.read(ref.src))) as BinaryFileData['dataURL']
        return { id, mimeType: ref.mimeType, dataURL, created: 0 } as BinaryFileData
      } catch {
        return null
      }
    })
  )
  return loaded.filter((file): file is BinaryFileData => file !== null)
}

/** In place of a web page in a frame (Excalidraw draws one only when this returns nothing). */
const blockedEmbed = () => <span hidden />

/**
 * Excalidraw, as a page's drawing opens in it: the page's language and theme, no file menu (the page is where it is
 * kept), Text to diagram through the host's AI. Fills its parent.
 */
export function DrawingCanvas({ initial, host, handleRef, onChange, topRight, readOnly }: Props) {
  const api = useRef<ExcalidrawImperativeAPI | null>(null)
  /** Pictures already stored, by file id: kept as they are, new ones are uploaded once. */
  const stored = useRef<Record<string, DrawingFileRef>>({ ...initial.files })
  const lastVersion = useRef(-1)
  const [library] = useState(() => (host.library ? libraryKeeper(host.library) : null))

  // The drawing loads once per opening, the Library with it.
  const [initialData] = useState(() => async () => ({
    elements: storedElements(initial.elements) as never,
    files: Object.fromEntries((await loadFiles(initial.files, host)).map((f) => [f.id, f])),
    libraryItems: ((await library?.load()) ?? []) as never,
    scrollToContent: true,
    appState: { viewBackgroundColor: 'transparent' }
  }))

  useImperativeHandle(handleRef, () => ({
    elements: () => storedElements(api.current?.getSceneElements() ?? initial.elements),
    data: async () => {
      const editor = api.current
      if (!editor) return initial
      const elements = storedElements(editor.getSceneElements())
      const files: BinaryFiles = editor.getFiles()
      const refs: Record<string, DrawingFileRef> = {}
      for (const id of usedFileIds(elements)) {
        const kept = stored.current[id]
        if (kept) {
          refs[id] = kept
          continue
        }
        const file = inlineFiles({ [id]: files[id] })[id]
        if (!file) continue
        const blob = await (await fetch(file.dataURL)).blob()
        const src = await host.upload(blob, extensionOf(file.mimeType))
        refs[id] = { src, mimeType: file.mimeType }
        stored.current[id] = refs[id]
      }
      return { elements, files: refs }
    },
    preview: async () => {
      const editor = api.current
      if (!editor) return null
      const elements = editor.getSceneElements()
      if (elements.length === 0) return null
      return exportToBlob({
        elements,
        files: editor.getFiles(),
        mimeType: 'image/png',
        exportPadding: 16,
        appState: { exportBackground: false, exportWithDarkMode: false, exportScale: 2 }
      })
    }
  }))

  const changed = useCallback(
    (elements: Parameters<NonNullable<Parameters<typeof Excalidraw>[0]['onChange']>>[0]) => {
      // Nothing that loads a page stays in a drawing, however it came in (a library, a paste, an element changed
      // in place, a link typed in): kinds that load pages go, links that aren't the web's are cleared, `customData`
      // is dropped — then the next change saves what is left.
      if (elements.some((element) => !isSafeLiveElement(element))) {
        api.current?.updateScene({
          elements: elements
            .filter((element) => isDrawableType(element.type))
            .map((element) =>
              isSafeLiveElement(element)
                ? element
                : { ...element, link: safeDrawingLink(element.link), customData: undefined }
            )
        })
        return
      }
      const version = getSceneVersion(elements)
      if (version === lastVersion.current) return
      const first = lastVersion.current === -1
      lastVersion.current = version
      // The first call is the drawing as loaded, not a change.
      if (!first) onChange?.(storedElements(elements))
    },
    [onChange]
  )

  const { diagram } = host
  return (
    <Excalidraw
      excalidrawAPI={(instance) => {
        api.current = instance
      }}
      initialData={initialData}
      theme={host.theme}
      langCode={host.language}
      autoFocus
      viewModeEnabled={readOnly}
      onChange={changed}
      onLibraryChange={library ? (items) => library.changed(items) : undefined}
      renderTopRightUI={topRight ? (isMobile) => (isMobile ? null : topRight) : undefined}
      aiEnabled={diagram !== null}
      // Scenes are hostile (synced, imported, pasted): no web pages in frames, links only to the web and through the
      // app, pasted content checked like stored content.
      validateEmbeddable={false}
      renderEmbeddable={blockedEmbed}
      onLinkOpen={(element, event) => {
        event.preventDefault()
        const url = safeDrawingLink(element.link)
        if (url) host.openLink(url)
      }}
      onPaste={checkPaste}
      UIOptions={{
        canvasActions: {
          loadScene: false,
          saveToActiveFile: false,
          export: false,
          saveAsImage: false,
          toggleTheme: null,
          changeViewBackgroundColor: false
        }
      }}
    >
      <MainMenu>
        <MainMenu.DefaultItems.SearchMenu />
        <MainMenu.DefaultItems.Help />
        <MainMenu.DefaultItems.ClearCanvas />
      </MainMenu>
      <WelcomeScreen>
        <WelcomeScreen.Hints.ToolbarHint />
        <WelcomeScreen.Hints.HelpHint />
      </WelcomeScreen>
      {diagram && (
        <>
          <TTDDialogTrigger />
          <TTDDialog
            onTextSubmit={async (input) => {
              try {
                return { generatedResponse: await diagram(input) }
              } catch (error) {
                return { error: error instanceof Error ? error : new Error(String(error)) }
              }
            }}
          />
        </>
      )}
    </Excalidraw>
  )
}
