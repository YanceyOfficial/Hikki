import { Extension, type Editor } from '@tiptap/core'
import FindAndReplace, {
  FindAndReplacePluginKey,
  type FindAndReplacePluginState
} from '@tiptap/extension-find-and-replace'
import { createRoot, type Root } from 'react-dom/client'

import { renderFindPanel } from '../components/find-panel'
import { matchesShortcut } from '../core/shortcuts'

export type FindMode = 'find' | 'replace' | 'next' | 'previous' | 'close'

/** The search as it stands, for a bar the native side draws (`setNativeFindReporter`). */
export type FindState = {
  open: boolean
  /** The Replace row is shown. */
  replace: boolean
  /** What is searched for — or about to be: `setSearchTerm` is debounced. */
  term: string
  replaceTerm: string
  caseSensitive: boolean
  wholeWord: boolean
  regex: boolean
  count: number
  /** The match stepped to, 0-based; null without matches. */
  current: number | null
}

/** What a native bar sets (`findSet`): any of the fields, the rest left as they are. */
export type FindOptions = Partial<
  Pick<FindState, 'term' | 'replaceTerm' | 'caseSensitive' | 'wholeWord' | 'regex' | 'replace'>
>

type FindStorage = {
  open: boolean
  replace: boolean
  /** Bumped to refocus (and select) the search field when Find is invoked again. */
  focusRequest: number
  /** Text to search for when opened from a selection. */
  prefill: string | null
  /** The term last asked for (the prefill, the panel's or the native bar's typing), ahead of the debounced search. */
  term: string
  /** The state last reported to the native bar, for sending only changes. */
  reported: string | null
  root: Root | null
  element: HTMLElement | null
}

declare module '@tiptap/core' {
  interface Storage {
    find: FindStorage
  }
}

/** Where the native side draws the find bar (a phone): told the state as it changes; null for the page's own panel. */
let nativeReporter: ((state: FindState) => void) | null = null

export function setNativeFindReporter(reporter: ((state: FindState) => void) | null): void {
  nativeReporter = reporter
}

/** The find plugin's own state (current within a transaction, unlike the extension's storage, synced after ours). */
function searchState(editor: Editor): FindAndReplacePluginState | undefined {
  return FindAndReplacePluginKey.getState(editor.state)
}

/** The meta keys a find transaction carries when the matches or the one stepped to may have changed. */
const MATCH_KEYS = ['searchTerm', 'caseSensitive', 'useRegex', 'wholeWord', 'currentIndex']

/**
 * Find and replace (Tiptap's extension, regex via RE2 — no catastrophic backtracking) with our panel at the
 * top right. ⌘F / ⌥⌘F / ⌘G / ⇧⌘G from the page or the native Edit menu (`window.hikki.find`).
 * Searching only decorates; replacing is an ordinary edit. Where the native side draws the bar (`setNativeFindReporter`,
 * a phone) the panel stays shut: the page reports the search (`findState`) and the bar drives it (`findSet`,
 * `findStep`, `findReplace`).
 */
export const Find = Extension.create<Record<string, never>, FindStorage>({
  name: 'find',

  addStorage() {
    return {
      open: false,
      replace: false,
      focusRequest: 0,
      prefill: null,
      term: '',
      reported: null,
      root: null,
      element: null
    }
  },

  addExtensions() {
    return [FindAndReplace.configure({ injectCSS: false, searchDebounceMs: 80 })]
  },

  onCreate() {
    const element = document.createElement('div')
    element.className = 'hk-find'
    document.body.append(element)
    this.storage.element = element
    this.storage.root = createRoot(element)
    renderFind(this.editor)
  },

  onTransaction({ transaction }) {
    const meta = transaction.getMeta(FindAndReplacePluginKey) as Record<string, unknown> | undefined
    if (!meta) return
    if (typeof meta.searchTerm === 'string') this.storage.term = meta.searchTerm
    if (!nativeReporter || !this.storage.open) return
    // The native bar can't follow the page's decorations: the match stepped to, or a new term's first, is brought
    // into view here (the panel does it in its own effect).
    if (MATCH_KEYS.some((key) => key in meta)) revealCurrentMatch(this.editor)
    report(this.editor)
  },

  onDestroy() {
    const { root, element } = this.storage
    // A bar still up for a page that is gone closes with it.
    if (this.storage.open && nativeReporter) {
      this.storage.open = false
      report(this.editor)
    }
    queueMicrotask(() => root?.unmount())
    element?.remove()
  }
})

function renderFind(editor: Editor) {
  const storage = editor.storage.find
  if (!storage.root) return
  // A fresh panel per Find request: it refocuses and starts from the prefill.
  renderFindPanel(storage.root, storage.focusRequest, {
    editor,
    // Where the native side draws the bar, the panel stays shut.
    open: storage.open && !nativeReporter,
    replace: storage.replace,
    initialText: storage.prefill ?? editor.storage.findAndReplace.searchTerm,
    onReplaceToggle: () => {
      storage.replace = !storage.replace
      renderFind(editor)
    },
    onClose: () => runFind(editor, 'close')
  })
}

/** The search as it stands (see `FindState`). */
export function findState(editor: Editor): FindState {
  const storage = editor.storage.find
  const search = searchState(editor)
  return {
    open: storage.open,
    replace: storage.replace,
    term: storage.term,
    replaceTerm: search?.replaceTerm ?? '',
    caseSensitive: search?.caseSensitive ?? false,
    wholeWord: search?.wholeWord ?? false,
    regex: search?.useRegex ?? false,
    count: search?.results.length ?? 0,
    current: storage.open ? (search?.currentIndex ?? null) : null
  }
}

/** Tells the native bar the state, when it changed since last told. */
function report(editor: Editor) {
  if (!nativeReporter) return
  const storage = editor.storage.find
  const state = findState(editor)
  const key = JSON.stringify(state)
  if (key === storage.reported) return
  storage.reported = key
  nativeReporter(state)
}

/** The current match, brought to the middle of the view (stepping, or a new term's first match). */
export function revealCurrentMatch(editor: Editor): void {
  const search = searchState(editor)
  const match = search?.results[search.currentIndex ?? 0]
  if (!match) return
  let node: Node | null = null
  try {
    node = editor.view.domAtPos(match.from).node
  } catch {
    return
  }
  const element = node instanceof Element ? node : node?.parentElement
  element?.scrollIntoView?.({
    block: 'center',
    behavior: matchMedia?.('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'
  })
}

/** Opens, steps through or closes find (keyboard, native menu, bridge). */
export function runFind(editor: Editor, mode: FindMode): void {
  const storage = editor.storage.find
  switch (mode) {
    case 'find':
    case 'replace': {
      // Opening starts from the selected text, like the system find. Once open, the selection is just
      // the current match: it must not replace the term (it may differ in case).
      if (!storage.open) {
        const { from, to, empty } = editor.state.selection
        const selected = empty ? '' : editor.state.doc.textBetween(from, to, ' ')
        storage.prefill =
          selected && !selected.includes('\n') && selected.length <= 200 ? selected : null
        if (storage.prefill) {
          storage.term = storage.prefill
          editor.commands.setSearchTerm(storage.prefill)
        }
      } else {
        storage.prefill = null
      }
      // ⌘F opens find alone, ⌘R with Replace; once open, ⌘F only refocuses and keeps the Replace row the reader
      // toggled on (ISSUE-229: a toggled-on row came back with the next ⌘F after closing).
      storage.replace = mode === 'replace' || (storage.open && storage.replace)
      storage.open = true
      storage.focusRequest += 1
      break
    }
    case 'next':
      if (!storage.open) return runFind(editor, 'find')
      editor.commands.goToNextResult()
      break
    case 'previous':
      if (!storage.open) return runFind(editor, 'find')
      editor.commands.goToPreviousResult()
      break
    case 'close':
      if (!storage.open) return
      storage.open = false
      storage.replace = false
      storage.term = ''
      editor.commands.clearSearch()
      // The native bar closing must not bring the page's keyboard up.
      if (!nativeReporter) editor.commands.focus()
      break
  }
  renderFind(editor)
  report(editor)
}

/** The native bar's term, replacement and options, as far as given; nothing while find is closed. */
export function findSet(editor: Editor, options: FindOptions): void {
  const storage = editor.storage.find
  if (!storage.open) return
  if (options.term !== undefined && options.term !== storage.term) {
    storage.term = options.term
    editor.commands.setSearchTerm(options.term)
  }
  const chain = editor.chain()
  if (options.replaceTerm !== undefined) chain.setReplaceTerm(options.replaceTerm)
  if (options.caseSensitive !== undefined) chain.setCaseSensitive(options.caseSensitive)
  if (options.wholeWord !== undefined) chain.setWholeWord(options.wholeWord)
  if (options.regex !== undefined) chain.setUseRegex(options.regex)
  chain.run()
  if (options.replace !== undefined) storage.replace = options.replace
  report(editor)
}

/** The native bar's ‹ › : the next (1) or previous (-1) match, brought into view. */
export function findStep(editor: Editor, direction: 1 | -1): void {
  runFind(editor, direction > 0 ? 'next' : 'previous')
}

/** The native bar's Replace / Replace All: the current match, or every one (an ordinary edit). */
export function findReplace(editor: Editor, all: boolean): void {
  if (!editor.storage.find.open) return
  if (all) editor.commands.replaceAll()
  else editor.commands.replace()
  report(editor)
}

/** ⌘F / ⌥⌘F / ⌘G / ⇧⌘G (from the registry): the page sees these before the native menu does. */
export function findShortcut(event: KeyboardEvent): FindMode | null {
  if (matchesShortcut(event, 'findReplace')) return 'replace'
  if (matchesShortcut(event, 'find')) return 'find'
  if (matchesShortcut(event, 'findPrevious')) return 'previous'
  if (matchesShortcut(event, 'findNext')) return 'next'
  return null
}
