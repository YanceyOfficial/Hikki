// Wire protocol between the web editor and the native (Swift) shell.
// Mirrored by HikkiCore/Sources/Bridge/BridgeMessage.swift — bump PROTOCOL_VERSION
// on both sides together whenever a message shape changes.
import type { JSONContent } from '@tiptap/core'

export const PROTOCOL_VERSION = 37

/** What the native side sends to open a page. The title is a page property, not part of `content`. */
export type PagePayload = {
  id: string
  title: string
  icon: string | null
  cover: string | null
  /** Locked pages are read-only (title, body, icon, cover) until unlocked natively. */
  locked?: boolean
  content: JSONContent | null
}

/** Editor-owned state, saved (debounced) by the native side. */
export type Snapshot = {
  docId: string
  title: string
  content: JSONContent
  text: string
  wordCount: number
}

/** `window.hikki.exportPage(page, format)`: a page as a Markdown or HTML document (a string). */
export type ExportFormat = 'markdown' | 'html'

/** `window.hikki.importDocument(text, format, fallbackTitle)`: a file's text as a new page. */
export type ImportFormat = 'markdown' | 'html' | 'text'

/** What `importDocument` returns: the new page's title and body (always fits the schema). */
export type ImportedPage = { title: string; content: JSONContent; text: string; wordCount: number }

export const COMMANDS = [
  'bold',
  'italic',
  'strike',
  'code',
  'heading1',
  'heading2',
  'heading3',
  'paragraph',
  'bulletList',
  'orderedList',
  'taskList',
  'blockquote',
  'codeBlock',
  'undo',
  'redo'
] as const
export type Command = (typeof COMMANDS)[number]

export type LogLevel = 'debug' | 'info' | 'warn' | 'error'

/** A heading of the open page, for the native inspector's outline (`id` is the block id to scroll to). */
export type OutlineHeading = { id: string | null; level: number; text: string }

export type ToNativeMessage =
  | { type: 'ready'; protocolVersion: number }
  | { type: 'changed'; snapshot: Snapshot }
  | { type: 'activeFormats'; active: Command[] }
  /** The open page's outline and size, for the native inspector: on load, then throttled as it changes. */
  | {
      type: 'pageInfo'
      docId: string
      headings: OutlineHeading[]
      words: number
      characters: number
    }
  /**
   * AI on the selection: `action` is a preset (`improve`, `fix`, `shorter`, `longer`, `tone:<tone>`,
   * `translate:<language>`, `explain`, `summarize`), `custom` with the user's `instruction`, or `diagram` — a drawing's
   * Text to diagram: the `instruction` drawn as Mermaid (the answer's text), no `units` (`core/diagram.ts`). `units` are the selected
   * parts of each block as inline HTML; `answer` asks for prose (explain, summarize) rather than replacement blocks.
   * Replies arrive through `window.hikki.aiEvent`.
   */
  | {
      type: 'aiRequest'
      id: string
      action: string
      instruction?: string
      answer: boolean
      units: { key: string; html: string }[]
      context: { title: string; before: string; after: string; previous?: string }
      /** A picture or a PDF the question is about (the block menu's Ask AI on an image or a file): the workspace asset
       * (`hikki-editor://assets/<name>`) the native side reads and sends along; `units` is then empty. */
      media?: AIMediaRef
      /** A model picked for this request in the AI panel (`AIModelMenu`); absent: the default. */
      model?: string
    }
  /** Where the page is scrolled (throttled): each tab gets its place back when it is shown again. */
  | { type: 'scroll'; docId: string; top: number }
  /** Stop an AI request (the review was closed, or the page changed under it). */
  | { type: 'aiCancel'; id: string }
  /** The model judged a request in the user's own words (`custom`, `ask`) more than an edit of the selection or a short
   * answer (`{"handoff": …}`): the app continues it in the chat — `instruction` as the question, `selection` (the
   * passage's text) as its context. */
  | { type: 'aiHandoff'; docId: string; instruction: string; selection: string }
  /** Ask for pictures ("/" AI pictures, a selection's Pictures…, an image's Edit with AI): the app opens the chat set
   * up for them. They go in after `blockId` (in place of it while it is an empty line) or, `mode: 'replace'`, in place
   * of the picture at `url` being changed; `selection` is the passage they are of. */
  | {
      type: 'aiPictures'
      docId: string
      blockId: string | null
      mode: 'after' | 'replace'
      selection?: string
      url?: string
    }
  /** A change Ask AI proposed (`window.hikki.aiChanges`) was reviewed in the page, or went stale; with the block's text
   * before and after, for the chat's reviewed stack. */
  | {
      type: 'aiChange'
      docId: string
      id: string
      status: AIChangeStatus
      before?: string
      after?: string
    }
  /** The change shown in the page (its bar open) is now this one; none when absent. */
  | { type: 'aiChangeFocus'; docId: string; id?: string }
  /** The heading the reader is in (scroll-spy) changed: the inspector's outline marks it; null above the first. */
  | { type: 'activeHeading'; docId: string; id: string | null }
  /** Comments (the native store, `comments/<page id>.json`): a thread started on a passage — or, with `blockId`, on a
   * whole block without text — with its first comment, … */
  | {
      type: 'commentCreate'
      docId: string
      threadId: string
      quote: string
      body: string
      blockId?: string
    }
  /** …a reply, resolving / reopening, deleting a comment or (no `commentId`) the thread. */
  | { type: 'commentReply'; docId: string; threadId: string; body: string }
  | { type: 'commentResolve'; docId: string; threadId: string; resolved: boolean }
  | { type: 'commentDelete'; docId: string; threadId: string; commentId?: string }
  /** A comment's words rewritten. */
  | { type: 'commentEdit'; docId: string; threadId: string; commentId: string; body: string }
  /** The thread open in the page changed (null: none) — only where the native side draws threads itself
   * (`setNativeComments`, a phone): it shows the thread in a sheet of its own. */
  | { type: 'commentThread'; docId: string; threadId: string | null }
  /** The cover's sheet, where the native side draws it (`setNativeCover`, a phone): its actions (a long press on the
   * cover, the ⋯ menu's Cover… on a page with one) or the picker. `bff` is the editor's backend (Unsplash), null
   * when this build has none. The pick comes back as `window.hikki.applyCover`. */
  | {
      type: 'coverSheet'
      docId: string
      cover: string | null
      mode: 'actions' | 'picker'
      bff: string | null
    }
  /** An icon's sheet, where the native side draws it (`setNativeIcons`, a phone): the page's icon or a callout's (with
   * its background colour). `id` names this opening; picks come back as `window.hikki.applyIcon(id, …)` /
   * `applyIconColor(id, …)`. */
  | {
      type: 'iconSheet'
      docId: string
      id: string
      kind: 'page' | 'callout'
      icon: string | null
      color: string | null
    }
  /** A date chip opened for editing, where the native side draws its sheet (`setNativeDates`, a phone). The answer
   * comes back as `window.hikki.applyDate(id, change)` (null removes the chip). */
  | {
      type: 'dateSheet'
      docId: string
      id: string
      date: string
      time: string | null
      remind: number | null
      done: boolean
    }
  /** The selected text (debounced; "" when nothing is): Ask AI offers it as context. Capped at 4000 characters. */
  | { type: 'selection'; docId: string; text: string }
  /** A bottom sheet opened or closed (a touch screen's cover, icon or comment sheet): the native bars beside the page
   * step aside meanwhile (an iPhone Duo's vertical bar), so the sheet has the whole width. */
  | { type: 'sheet'; open: boolean }
  /** Something over the whole page opened or closed (a drawing's editor): the native bars over the page (iPhone's
   * navigation and floating bars) step aside meanwhile. */
  | { type: 'fullScreen'; open: boolean }
  | { type: 'log'; level: LogLevel; message: string; context?: Record<string, string> }
  /** A confirmation or note for the user ("Link copied"), already in the page's language: the app shows it as a toast. */
  | { type: 'toast'; kind: 'success' | 'info' | 'warning' | 'error'; message: string }
  /** A failure with its code (design/errors.json): the app logs it with an incident id and shows its message. `detail`
   * is technical (an error's own message), never page content. */
  | { type: 'reportError'; code: number; detail?: string; context?: Record<string, string> }
  /** Saved immediately (not debounced) — metadata has its own write path. */
  | { type: 'setIcon'; docId: string; icon: string | null }
  | { type: 'setCover'; docId: string; cover: string | null }
  /** Replies with the asset URL to use (e.g. `hikki-editor://assets/<name>`). */
  | { type: 'saveAsset'; fileExtension: string; dataBase64: string }
  /** Chunked upload (video, audio, attachments, large images): begin replies with an id, finish with the URL. */
  | { type: 'beginUpload'; fileExtension: string; size: number }
  | { type: 'uploadChunk'; id: string; dataBase64: string }
  | { type: 'finishUpload'; id: string }
  | { type: 'cancelUpload'; id: string }
  /** Opens an attachment with the system (Quick Look), never in the web view. */
  | { type: 'openAsset'; url: string; name?: string | null }
  /** A page link was clicked; `block` for a link to a block inside the page. */
  | { type: 'openPage'; id: string; block?: string }
  /** A page dropped on the right edge of the page (split view): open it in the pane on the right. */
  | { type: 'openInSplit'; id: string }
  /** While split: a page held over the left page's right edge would replace the right side — the app outlines it. */
  | { type: 'splitDropHover'; active: boolean }
  /** Any other link was clicked: the system opens it. */
  | { type: 'openLink'; url: string }
  /** Furigana: replies with `text` split into runs — `{ text, reading? }`, a reading per kanji run — or null. */
  | { type: 'suggestReading'; text: string }
  /** A link card's details: replies `{title, description, icon}` (each may be null), or null when the page can't be read. */
  | { type: 'linkPreview'; url: string }
  /** Excalidraw's Library (where `setDrawings` says the app keeps one): replies `{items}` — the stored items, `[]` when there are none — or null
   * when they can't be read. */
  | { type: 'drawingLibrary' }
  /** Block menu → Move to: append `blocks` to page `target`; the reply is true once they are there (then they leave
   * this page). `text` / `words`: what they add to its text and word count. */
  | {
      type: 'moveBlocks'
      docId: string
      target: string
      blocks: unknown[]
      text: string
      words: number
    }
  /** The Library changed: its items, checked (`storedLibraryItems`), replace the stored ones. */
  | { type: 'saveDrawingLibrary'; items: unknown[] }

/**
 * What the AI panel may run one request on (`window.hikki.setAIModels`): the default (`choice`: "auto" or a model id),
 * the model Auto runs on now (null: no API key, nothing to choose), then the models with a key in the chat menu's
 * groups.
 */
export type AIModelMenu = {
  choice: string
  auto: string | null
  groups: { kind: 'favorites' | 'recommended' | 'other'; models: { id: string; name: string }[] }[]
  /** Pictures can be made (an OpenAI key is set; absent from an older app: no). */
  pictures?: boolean
}

/** A file Ask AI reads (`aiRequest.media`): `kind` says how it goes to the model. */
export type AIMediaRef = { url: string; kind: 'image' | 'pdf'; name?: string | null }

export type AIChangeStatus = 'pending' | 'approved' | 'skipped' | 'edited' | 'stale'

/**
 * A change to the page an Ask AI answer proposes (`window.hikki.aiChanges`), by block id: `rewrite` sets `block`'s
 * text to `html`; `insert` adds a block of `type` with `html` after `after` (none: the top); `move` puts `block` after
 * `after`; `delete` removes `block`.
 */
export type AIChangeInput = {
  id: string
  kind: 'rewrite' | 'insert' | 'move' | 'delete'
  block?: string
  after?: string
  html?: string
  type?: string
  title: string
  why?: string
  status: AIChangeStatus
}

/** What `window.hikki.aiEvent` delivers for an `aiRequest`: the answer as it is written, then done or an error. */
export type AIStreamEvent =
  | { id: string; type: 'text'; delta: string }
  | { id: string; type: 'searching'; query?: string | null }
  | { id: string; type: 'citation'; url: string; title?: string | null }
  | { id: string; type: 'done' }
  | {
      id: string
      type: 'error'
      /** missingKey | unauthorized | rateLimited | unavailable | offline | rejected | invalidResponse */
      code: string
      provider?: string | null
      message?: string | null
    }
