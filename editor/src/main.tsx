import './style.css'
import { createRoot } from 'react-dom/client'

import { EditorBridge } from './bridge'
import { installErrorForwarding } from './errors'
import { setLocale } from './i18n'
import { Outline } from './page/Outline'
import { PageHeader } from './page/PageHeader'
import { PROTOCOL_VERSION, type PagePayload } from './protocol'
import { devTransport, webkitTransport } from './transport'
import { IconProvider } from './ui/icons'

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
  exec: (command: string) => bridge.exec(command),
  flush: () => bridge.flush(),
  focus: () => bridge.focus(),
  blur: () => bridge.blur(),
  focusTitle: () => bridge.focusTitle(),
  setLocale: (tag: string) => setLocale(tag)
}

if (!native) bridge.loadDocument({ id: 'dev', title: '', icon: null, cover: null, content: null })
void transport.post({ type: 'ready', protocolVersion: PROTOCOL_VERSION })
