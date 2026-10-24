import type { Editor } from '@tiptap/core'

import type { OutlineItem } from './headings'
import type { ToNativeMessage } from './protocol'
import type { Store } from './store'

/** How the page reaches the native shell (a WebKit script-message handler, or the browser's dev stand-in). */
export interface Transport {
  post(message: ToNativeMessage): Promise<unknown>
}

export type PageState = {
  docId: string | null
  title: string
  icon: string | null
  cover: string | null
  /** Changes only when a heading's id, level or text does (not on every keystroke). */
  headings: OutlineItem[]
  /** Bumped when the caret should move into the title (EdgeNavigation, native Rename). */
  focusTitleRequest: number
  /** With the latest request: select the whole title (Rename) instead of a caret at its end. */
  selectTitle: boolean
  /**
   * A new, empty page puts the caret in its title when it loads. Off for the split pane's editor: its page loading
   * must not take the keyboard from the page being typed in beside it.
   */
  autoFocus: boolean
  /**
   * The stored content didn't fit the schema (corrupt, or written by a newer Hikki): the page is shown
   * as far as possible but never saved, so the original stays intact on disk.
   */
  readOnly: boolean
  /** Locked by the user (Page → Lock): read-only until unlocked, unlike `readOnly` it can be lifted live. */
  locked: boolean
  /** The native inspector shows the outline: the page's own hover rail steps aside. */
  railHidden: boolean
  /** The heading the reader is in (index into `headings`, -1 above the first): the rail and the inspector mark it. */
  activeHeading: number
}

/**
 * What the bridge's parts (saving, comments, sheets, the outline) share of it: the page's state, its editor (null
 * between pages), whether the page may change, and the way to the native side.
 */
export type BridgeContext = {
  readonly page: Store<PageState>
  editor(): Editor | null
  /** Nothing about the page may change: its content doesn't fit the schema, or the user locked it. */
  frozen(): boolean
  /** Posts a message; a failure is logged (ids only), never thrown. */
  send(message: ToNativeMessage): Promise<boolean>
  readonly transport: Transport
}
