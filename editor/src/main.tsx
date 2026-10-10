import './style.css'
import { createRoot } from 'react-dom/client'

import { EditorBridge } from './bridge'
import { installErrorForwarding } from './errors'
import { Outline } from './page/Outline'
import { PageHeader } from './page/PageHeader'
import { PROTOCOL_VERSION, type PagePayload } from './protocol'
import { devTransport, webkitTransport } from './transport'

const native = webkitTransport()
const transport = native ?? devTransport()
// Forward errors only when hosted natively; in the browser the devtools console already has them.
if (native) installErrorForwarding(native)

const bridge = new EditorBridge(document.getElementById('editor')!, transport)
createRoot(document.getElementById('header')!).render(<PageHeader bridge={bridge} />)
createRoot(document.getElementById('outline')!).render(<Outline bridge={bridge} />)

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
  blur: () => bridge.blur()
}

if (!native) bridge.loadDocument({ id: 'dev', title: '', icon: null, cover: null, content: null })
void transport.post({ type: 'ready', protocolVersion: PROTOCOL_VERSION })
