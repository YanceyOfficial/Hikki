import './style.css'
import { EditorBridge } from './bridge'
import { installErrorForwarding } from './errors'
import { PROTOCOL_VERSION } from './protocol'
import { consoleTransport, webkitTransport } from './transport'

const native = webkitTransport()
const transport = native ?? consoleTransport()
// Forward errors only when hosted natively; in the browser the devtools console already has them.
if (native) installErrorForwarding(native)

const bridge = new EditorBridge(document.getElementById('editor')!, transport)

// The native shell drives everything through this object (callAsyncJavaScript).
declare global { interface Window { hikki: unknown } }
window.hikki = {
  protocolVersion: PROTOCOL_VERSION,
  loadDocument: (doc: Parameters<EditorBridge['loadDocument']>[0]) => bridge.loadDocument(doc),
  exec: (command: string) => bridge.exec(command),
  flush: () => bridge.flush(),
  focus: () => bridge.focus(),
  blur: () => bridge.blur(),
}

if (!native) bridge.loadDocument({ id: 'dev', content: null })
void transport.post({ type: 'ready', protocolVersion: PROTOCOL_VERSION })
