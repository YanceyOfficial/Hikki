import './style.css'
import { createRoot } from 'react-dom/client'

import { IconProvider } from './components/icons'
import { EditorBridge, type CommentAction } from './core/bridge'
import { exportPage, importDocument } from './core/convert'
import { installErrorForwarding } from './core/errors'
import { setLocale } from './core/i18n'
import type { PictureItem, PicturePlace } from './core/pictures'
import {
  PROTOCOL_VERSION,
  type AIChangeInput,
  type AIModelMenu,
  type AIStreamEvent,
  type ExportFormat,
  type ImportFormat,
  type PagePayload
} from './core/protocol'
import { applyShortcutOverrides, type ShortcutOverride } from './core/shortcuts'
import type { TouchBlockAction, TouchCommentScope, TouchMedia, TouchTool } from './core/touch-tools'
import { devTransport, webkitTransport } from './core/transport'
import type { AIAction } from './extensions/ai-review'
import type { ThreadItem } from './extensions/comments'
import { findShortcut, type FindMode } from './extensions/find'
import type { PageIndexEntry } from './extensions/page-links'
import type { SplitDropMode } from './extensions/split-drop'
import { setAIModels } from './lib/ai-models'
import type { DateSheetChange } from './lib/date-sheet'
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
  // A search result opened: land on its block, its words selected (folded terms, as the search index matched them).
  revealText: (terms: string[], blockId: string | null) => bridge.revealText(terms, blockId),
  // Screenshots (the native DEBUG hook HIKKI_DEBUG_AI_EDIT): those words selected and an AI action run on them.
  demoAI: (terms: string[], action: string) => bridge.demoAI(terms, action),
  // AI on the selection: the answer to an `aiRequest`, one event at a time.
  aiEvent: (event: AIStreamEvent) => bridge.aiEvent(event),
  // Ask AI's changes to the page (the chat's cards): offered in the page, one picked, approved / skipped, all approved;
  // and the page's blocks with their ids for the chat to propose them by.
  aiChanges: (docId: string, changes: AIChangeInput[]) => bridge.aiChanges(docId, changes),
  aiFocusChange: (id: string) => bridge.aiFocusChange(id),
  aiResolveChange: (id: string, verdict: 'approve' | 'skip') => bridge.aiResolveChange(id, verdict),
  aiApproveAll: () => bridge.aiApproveAll(),
  aiPageBlocks: (docId: string) => bridge.aiPageBlocks(docId),
  // The phone's keyboard bar (native): the "+" and "Aa" panels' contents, the page's state for them, and their tools.
  setKeyboardBar: (on: boolean) => bridge.setKeyboardBar(on),
  // How drawings behave here: the Mac keeps Excalidraw's Library (drawings/library.json in the workspace), a
  // phone-sized screen only looks at them.
  setDrawings: (settings: { library: boolean; readOnly: boolean }) => bridge.setDrawings(settings),
  touchBlockMenu: () => bridge.touchBlockMenu(),
  touchTurnIntoMenu: () => bridge.touchTurnIntoMenu(),
  touchState: () => bridge.touchState(),
  touchInsertBlock: (id: string) => bridge.touchInsertBlock(id),
  touchTurnInto: (id: string) => bridge.touchTurnInto(id),
  touchRun: (tool: TouchTool) => bridge.touchRun(tool),
  touchSetColor: (kind: 'text' | 'background', color: string | null) =>
    bridge.touchSetColor(kind, color),
  // Its AI and link fields (native, over the keyboard) and the ⋯ sheet of the caret's block.
  touchPrepare: () => bridge.touchPrepare(),
  touchAI: (action: AIAction) => bridge.touchAI(action),
  touchLink: (href: string | null) => bridge.touchLink(href),
  touchInsertMedia: (items: TouchMedia[]) => bridge.touchInsertMedia(items),
  insertPictures: (docId: string, items: PictureItem[], place: PicturePlace) =>
    bridge.insertPictures(docId, items, place),
  touchCommentQuote: (scope: TouchCommentScope) => bridge.touchCommentQuote(scope),
  touchComment: (scope: TouchCommentScope, body: string) => bridge.touchComment(scope, body),
  touchBlockInfo: () => bridge.touchBlockInfo(),
  touchBlockAction: (action: TouchBlockAction) => bridge.touchBlockAction(action),
  // The ⋯ sheet's Move to: the caret's block to the end of another page; true once it is there.
  touchMoveBlock: (target: string) => bridge.touchMoveBlock(target),
  touchBlockColor: (kind: 'text' | 'background', color: string | null) =>
    bridge.touchBlockColor(kind, color),
  touchBlockLink: () => bridge.touchBlockLink(),
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
  // Before a page switch's flush: an open drawing closed as Done closes it, its preview drawn.
  finishDrawing: () => bridge.finishDrawing(),
  focus: () => bridge.focus(),
  blur: () => bridge.blur(),
  focusTitle: () => bridge.focusTitle(),
  // Edit → Find… / Find and Replace… / Find Next / Find Previous.
  find: (mode: FindMode) => bridge.find(mode),
  // The page ⋯ menu's Cover…: the cover's sheet (its actions, or the picker on a page without a cover).
  editCover: () => bridge.editCover(),
  setNativeCover: (on: boolean) => bridge.setNativeCover(on),
  applyCover: (docId: string, cover: string | null) => bridge.applyCover(docId, cover),
  setNativeIcons: (on: boolean) => bridge.setNativeIcons(on),
  applyIcon: (id: string, icon: string | null) => bridge.applyIcon(id, icon),
  applyIconColor: (id: string, color: string | null) => bridge.applyIconColor(id, color),
  setNativeDates: (on: boolean) => bridge.setNativeDates(on),
  applyDate: (id: string, change: DateSheetChange) => bridge.applyDate(id, change),
  // Settings → Editor → Check spelling.
  setSpellcheck: (on: boolean) => bridge.setSpellcheck(on),
  // Comments: the open page's threads (native store), and a thread picked in the side panel.
  setComments: (docId: string, threads: ThreadItem[], device: string | null) =>
    bridge.setComments(docId, threads, device),
  openComment: (threadId: string | null) => bridge.openComment(threadId),
  setNativeComments: (on: boolean) => bridge.setNativeComments(on),
  commentAction: (action: CommentAction) => bridge.commentAction(action),
  // The split pane's editor: a loading page never takes the keyboard from the page beside it.
  setAutoFocus: (on: boolean) => bridge.setAutoFocus(on),
  // Settings → AI → Review style: inline (A) or diff (B); anything else reads as inline.
  setAIReviewStyle: (style: string) => bridge.setAIReviewStyle(style),
  // The models the AI panel may run one request on, and the default (Settings → AI, the chat's last pick).
  setAIModels: (menu: AIModelMenu) => setAIModels(menu),
  // Split view (Mac, a wide iPad): what a page dropped on the right edge does — open / replace / here / off.
  setSplitDrop: (mode: SplitDropMode) => bridge.setSplitDrop(mode),
  // Page → Lock / Unlock while the page is open.
  setLocked: (locked: boolean) => bridge.setLocked(locked),
  setOutlineRail: (visible: boolean) => bridge.setOutlineRail(visible),
  // Height of the native toolbar over the page: fixed panels (find) sit below it. `bottom`: the native bar floating
  // over the page's foot (iPhone, keyboard down) — a bottom sheet keeps its field above it.
  // `bleed` (iPhone): no native inset — the page itself makes the room, a cover filling it (`--hk-bleed-top`).
  setInsets: (insets: { top: number; bottom?: number; bleed?: boolean }) => {
    const root = document.documentElement.style
    root.setProperty('--hk-inset-top', `${Math.max(0, insets.top)}px`)
    root.setProperty('--hk-bleed-top', insets.bleed ? `${Math.max(0, insets.top)}px` : '0px')
    root.setProperty('--hk-inset-bottom', `${Math.max(0, insets.bottom ?? 0)}px`)
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
