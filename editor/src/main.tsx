import './style.css'
import { createRoot } from 'react-dom/client'

import { IconProvider } from './components/icons'
import { EditorBridge } from './core/bridge'
import { exportPage, importDocument } from './core/convert'
import { installErrorForwarding } from './core/errors'
import { setLocale } from './core/i18n'
import {
  PROTOCOL_VERSION,
  type AIStreamEvent,
  type ExportFormat,
  type ImportFormat,
  type PagePayload
} from './core/protocol'
import { applyShortcutOverrides, type ShortcutOverride } from './core/shortcuts'
import { devTransport, webkitTransport } from './core/transport'
import type { AIReviewStyle } from './extensions/ai-review'
import { findShortcut, type FindMode } from './extensions/find'
import type { PageIndexEntry } from './extensions/page-links'
import type { SplitDropMode } from './extensions/split-drop'
import { installScrollContainment } from './lib/scroll-containment'
import { Outline } from './page/outline'
import { PageHeader } from './page/page-header'

const native = webkitTransport()
const transport = native ?? devTransport()
// Forward errors only when hosted natively; in the browser the devtools console already has them.
if (native) installErrorForwarding(native)
// A scroll over a popup never moves the page behind it.
installScrollContainment()

const bridge = new EditorBridge(document.getElementById('editor')!, transport)
createRoot(document.getElementById('header')!).render(
  <IconProvider>
    <PageHeader bridge={bridge} />
  </IconProvider>
)
createRoot(document.getElementById('outline')!).render(
  <IconProvider>
    <Outline bridge={bridge} />
  </IconProvider>
)

// The native shell drives everything through this object (callAsyncJavaScript).
declare global {
  interface Window {
    hikki: unknown
  }
}
window.hikki = {
  protocolVersion: PROTOCOL_VERSION,
  loadDocument: (page: PagePayload) => bridge.loadDocument(page),
  // The open page changed on disk (another device); false when it wasn't applied (unsaved edits win).
  reload: (page: PagePayload) => bridge.reload(page),
  // The sidebar's pages, for naming links to them; and a block to land on after a link.
  setPages: (pages: PageIndexEntry[]) => bridge.setPages(pages),
  scrollToBlock: (id: string) => bridge.scrollToBlock(id),
  // AI on the selection: the answer to an `aiRequest`, one event at a time.
  aiEvent: (event: AIStreamEvent) => bridge.aiEvent(event),
  // A tab shown again scrolls back to where it was.
  restoreScroll: (top: number) => bridge.restoreScroll(top),
  // The inspector's outline: a heading to the top of the page, marked as the one being read.
  jumpToHeading: (id: string) => bridge.jumpToHeading(id),
  // Page ⋯ → Export / File → Import: a page as Markdown or HTML, and a file's text as a new page (convert.ts).
  exportPage: (page: PagePayload, format: ExportFormat) => exportPage(page, format),
  importDocument: (text: string, format: ImportFormat, fallbackTitle: string) =>
    importDocument(text, format, fallbackTitle),
  exec: (command: string) => bridge.exec(command),
  flush: () => bridge.flush(),
  focus: () => bridge.focus(),
  blur: () => bridge.blur(),
  focusTitle: () => bridge.focusTitle(),
  // Edit → Find… / Find and Replace… / Find Next / Find Previous.
  find: (mode: FindMode) => bridge.find(mode),
  // Settings → Editor → Check spelling.
  setSpellcheck: (on: boolean) => bridge.setSpellcheck(on),
  // The split pane's editor: a loading page never takes the keyboard from the page beside it.
  setAutoFocus: (on: boolean) => bridge.setAutoFocus(on),
  // Settings → AI → Review style: inline (A), diff (B) or bubble (C).
  setAIReviewStyle: (style: AIReviewStyle) => bridge.setAIReviewStyle(style),
  // Split view (Mac, a wide iPad): what a page dropped on the right edge does — open / replace / here / off.
  setSplitDrop: (mode: SplitDropMode) => bridge.setSplitDrop(mode),
  // Page → Lock / Unlock while the page is open.
  setLocked: (locked: boolean) => bridge.setLocked(locked),
  setOutlineRail: (visible: boolean) => bridge.setOutlineRail(visible),
  // Height of the native toolbar over the page: fixed panels (find) sit below it.
  setInsets: (insets: { top: number }) => {
    document.documentElement.style.setProperty('--hk-inset-top', `${Math.max(0, insets.top)}px`)
  },
  setLocale: (tag: string) => setLocale(tag),
  // Settings → Shortcuts: the user's rebindings (only those; the rest keep the registry's keys).
  setShortcuts: (overrides: Record<string, ShortcutOverride>) => applyShortcutOverrides(overrides),
  // Settings → Appearance → Color tone: theme.css keys its [data-tone] palettes on this attribute.
  setTone: (tone: string) => {
    document.documentElement.dataset.tone = tone
  }
}

// A press in the blank space under the page's last block opens a line there (Notion's). Only presses on the page's
// own background count — not the header, not a block, not a floating panel.
const editorHost = document.getElementById('editor')!
const pageBackground = new Set<EventTarget | null>([
  editorHost,
  document.getElementById('page'),
  document.body,
  document.documentElement
])
document.addEventListener('mousedown', (event) => {
  if (event.button !== 0 || !pageBackground.has(event.target)) return
  const content = editorHost.querySelector('.tiptap')
  if (!content || event.clientY <= content.getBoundingClientRect().bottom) return
  if (bridge.focusEnd()) event.preventDefault()
})

// ⌘F and friends reach the page before the native menu; handled here, the menu never fires.
document.addEventListener(
  'keydown',
  (event) => {
    const mode = findShortcut(event)
    if (mode && bridge.find(mode)) event.preventDefault()
  },
  true
)

if (!native) bridge.loadDocument({ id: 'dev', title: '', icon: null, cover: null, content: null })
void transport.post({ type: 'ready', protocolVersion: PROTOCOL_VERSION })
