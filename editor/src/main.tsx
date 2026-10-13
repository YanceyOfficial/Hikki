import './style.css'
import { createRoot } from 'react-dom/client'

import { IconProvider } from './components/icons'
import { EditorBridge } from './core/bridge'
import { installErrorForwarding } from './core/errors'
import { setLocale } from './core/i18n'
import { PROTOCOL_VERSION, type PagePayload } from './core/protocol'
import { devTransport, webkitTransport } from './core/transport'
import { findShortcut, type FindMode } from './extensions/find'
import type { PageIndexEntry } from './extensions/page-links'
import { Outline } from './page/outline'
import { PageHeader } from './page/page-header'

const native = webkitTransport()
const transport = native ?? devTransport()
// Forward errors only when hosted natively; in the browser the devtools console already has them.
if (native) installErrorForwarding(native)

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
  exec: (command: string) => bridge.exec(command),
  flush: () => bridge.flush(),
  focus: () => bridge.focus(),
  blur: () => bridge.blur(),
  focusTitle: () => bridge.focusTitle(),
  // Edit → Find… / Find and Replace… / Find Next / Find Previous.
  find: (mode: FindMode) => bridge.find(mode),
  // Settings → Editor → Check spelling.
  setSpellcheck: (on: boolean) => bridge.setSpellcheck(on),
  // Page → Lock / Unlock while the page is open.
  setLocked: (locked: boolean) => bridge.setLocked(locked),
  // Height of the native toolbar over the page: fixed panels (find) sit below it.
  setInsets: (insets: { top: number }) => {
    document.documentElement.style.setProperty('--hk-inset-top', `${Math.max(0, insets.top)}px`)
  },
  setLocale: (tag: string) => setLocale(tag),
  // Settings → Appearance → Color tone: theme.css keys its [data-tone] palettes on this attribute.
  setTone: (tone: string) => {
    document.documentElement.dataset.tone = tone
  }
}

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
