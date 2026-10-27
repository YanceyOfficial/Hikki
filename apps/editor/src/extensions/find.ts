import { Extension, type Editor } from '@tiptap/core'
import FindAndReplace from '@tiptap/extension-find-and-replace'
import { createRoot, type Root } from 'react-dom/client'

import { renderFindPanel } from '../components/find-panel'
import { matchesShortcut } from '../core/shortcuts'

export type FindMode = 'find' | 'replace' | 'next' | 'previous' | 'close'

type FindStorage = {
  open: boolean
  replace: boolean
  /** Bumped to refocus (and select) the search field when Find is invoked again. */
  focusRequest: number
  /** Text to search for when opened from a selection. */
  prefill: string | null
  root: Root | null
  element: HTMLElement | null
}

declare module '@tiptap/core' {
  interface Storage {
    find: FindStorage
  }
}

/**
 * Find and replace (Tiptap's extension, regex via RE2 — no catastrophic backtracking) with our panel at the
 * top right. ⌘F / ⌥⌘F / ⌘G / ⇧⌘G from the page or the native Edit menu (`window.hikki.find`).
 * Searching only decorates; replacing is an ordinary edit.
 */
export const Find = Extension.create<Record<string, never>, FindStorage>({
  name: 'find',

  addStorage() {
    return {
      open: false,
      replace: false,
      focusRequest: 0,
      prefill: null,
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

  onDestroy() {
    const { root, element } = this.storage
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
    open: storage.open,
    replace: storage.replace,
    initialText: storage.prefill ?? editor.storage.findAndReplace.searchTerm,
    onReplaceToggle: () => {
      storage.replace = !storage.replace
      renderFind(editor)
    },
    onClose: () => runFind(editor, 'close')
  })
}

/** The current match, brought to the middle of the view (stepping, or a new term's first match). */
export function revealCurrentMatch(editor: Editor): void {
  const { results, currentIndex } = editor.storage.findAndReplace as {
    results: { from: number }[]
    currentIndex: number | null
  }
  const match = results[currentIndex ?? 0]
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
        if (storage.prefill) editor.commands.setSearchTerm(storage.prefill)
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
      editor.commands.clearSearch()
      editor.commands.focus()
      break
  }
  renderFind(editor)
}

/** ⌘F / ⌥⌘F / ⌘G / ⇧⌘G (from the registry): the page sees these before the native menu does. */
export function findShortcut(event: KeyboardEvent): FindMode | null {
  if (matchesShortcut(event, 'findReplace')) return 'replace'
  if (matchesShortcut(event, 'find')) return 'find'
  if (matchesShortcut(event, 'findPrevious')) return 'previous'
  if (matchesShortcut(event, 'findNext')) return 'next'
  return null
}
