import type { AIAction } from '../extensions/ai-review'
import type { ThreadItem } from '../extensions/comments'
import type { FindMode } from '../extensions/find'
import type { PageIndexEntry } from '../extensions/page-links'
import type { SplitDropMode } from '../extensions/split-drop'
import type { AIPageBlock } from '../lib/ai-content'
import type { DateSheetChange } from '../lib/date-sheet'
import type { IconStyle } from '../lib/sf-icons'
import type { CommentAction } from './bridge-comments'
import type { TouchTarget } from './bridge-touch'
import type { PictureItem, PicturePlace } from './pictures'
import type {
  AIChangeInput,
  AIModelMenu,
  AIStreamEvent,
  ExportFormat,
  ImportFormat,
  ImportedPage,
  PagePayload,
  Snapshot
} from './protocol'
import type { ShortcutOverride } from './shortcuts'
import type {
  TouchBlock,
  TouchBlockAction,
  TouchBlockGroup,
  TouchBlockInfo,
  TouchCommentScope,
  TouchMedia,
  TouchState,
  TouchTool
} from './touch-tools'

/**
 * `window.hikki`: what the native shell calls in the page (callAsyncJavaScript) — the other half of the bridge
 * protocol, whose messages the page posts are `ToNativeMessage` (protocol.ts). The Swift side calls these by name, so
 * a change here is a protocol change: bump `PROTOCOL_VERSION` and `BridgeProtocol.version` together.
 */
export interface HikkiAPI {
  protocolVersion: number

  // The page
  loadDocument(page: PagePayload): void
  /** The open page changed on disk (another device); false when it wasn't applied (unsaved edits win). */
  reload(page: PagePayload): boolean
  /** The sidebar's pages, for naming links to them. */
  setPages(pages: PageIndexEntry[]): void
  scrollToBlock(id: string): boolean
  /** A search result opened: its block, its words selected (folded terms, as the search index matched them). */
  revealText(terms: string[], blockId: string | null): boolean
  restoreScroll(top: number): void
  jumpToHeading(id: string): boolean
  exec(command: string): boolean
  flush(): Snapshot | null
  finishDrawing(): Promise<void>
  focus(): void
  blur(): void
  focusTitle(): void
  find(mode: FindMode): boolean
  setLocked(locked: boolean): void
  setAutoFocus(on: boolean): void
  setOutlineRail(visible: boolean): void
  setSplitDrop(mode: SplitDropMode): void
  setDrawings(settings: { library: boolean; readOnly: boolean }): void

  // Import / export (convert.ts)
  exportPage(page: PagePayload, format: ExportFormat): string
  importDocument(text: string, format: ImportFormat, fallbackTitle: string): ImportedPage

  // AI
  demoAI(terms: string[], action: string): boolean
  aiEvent(event: AIStreamEvent): void
  aiChanges(docId: string, changes: AIChangeInput[], focusFirst?: boolean): boolean
  aiFocusChange(id: string): boolean
  aiResolveChange(id: string, verdict: 'approve' | 'skip'): boolean
  aiApproveAll(): boolean
  aiPageBlocks(docId: string): AIPageBlock[] | null
  insertPictures(docId: string, items: PictureItem[], place: PicturePlace): boolean
  setAIReviewStyle(style: string): void
  setAIModels(menu: AIModelMenu): void

  // The phone's keyboard bar
  setKeyboardBar(on: boolean): void
  touchBlockMenu(): TouchBlockGroup[]
  touchTurnIntoMenu(): TouchBlock[]
  touchState(): TouchState | null
  touchInsertBlock(id: string): boolean
  touchTurnInto(id: string): boolean
  touchRun(tool: TouchTool): boolean
  touchSetColor(kind: 'text' | 'background', color: string | null): boolean
  touchPrepare(scope?: 'word' | 'block'): TouchTarget | null
  touchAI(action: AIAction): boolean
  touchLink(href: string | null): boolean
  touchInsertMedia(items: TouchMedia[]): boolean
  touchCommentQuote(scope: TouchCommentScope): string | null
  touchComment(scope: TouchCommentScope, body: string): boolean
  touchBlockInfo(): TouchBlockInfo | null
  touchBlockAction(action: TouchBlockAction): boolean
  touchMoveBlock(target: string): Promise<boolean>
  touchBlockColor(kind: 'text' | 'background', color: string | null): boolean
  touchBlockLink(): { href: string; label: string } | null

  // Sheets drawn natively
  editCover(): boolean
  setNativeCover(on: boolean): void
  applyCover(docId: string, cover: string | null): boolean
  setNativeIcons(on: boolean): void
  applyIcon(id: string, icon: string | null): boolean
  applyIconColor(id: string, color: string | null): boolean
  setNativeDates(on: boolean): void
  applyDate(id: string, change: DateSheetChange): boolean

  // Comments
  setComments(docId: string, threads: ThreadItem[], device: string | null): void
  openComment(threadId: string | null): void
  setNativeComments(on: boolean): void
  commentAction(action: CommentAction): boolean

  // Settings and the page's surroundings
  setSpellcheck(on: boolean): void
  setInsets(insets: { top: number; bottom?: number; bleed?: boolean }): void
  setTextScale(scale: number): void
  setIconStyle(style: IconStyle): void
  setLocale(tag: string): string
  setShortcuts(overrides: Record<string, ShortcutOverride>): void
  setTone(tone: string): void
}
