import type { Editor } from '@tiptap/core'
import { useCallback, useRef, useSyncExternalStore } from 'react'

const shallowEqual = (a: Record<string, unknown>, b: Record<string, unknown>) => {
  const keys = Object.keys(a)
  return keys.length === Object.keys(b).length && keys.every((k) => Object.is(a[k], b[k]))
}

/**
 * Subscribes a component to the slice of editor state it shows (Tiptap's `useEditorState` idea for the
 * core editor): `select` runs on every transaction, but the component re-renders only when the selected
 * values change (shallow comparison). Pass a stable `select` (module-level function).
 */
export function useEditorSnapshot<T extends Record<string, unknown>>(
  editor: Editor,
  select: (editor: Editor) => T
): T {
  const cache = useRef<T | null>(null)

  const subscribe = useCallback(
    (notify: () => void) => {
      editor.on('transaction', notify)
      return () => {
        editor.off('transaction', notify)
      }
    },
    [editor]
  )
  const getSnapshot = useCallback(() => {
    const next = select(editor)
    if (cache.current && shallowEqual(cache.current, next)) return cache.current
    cache.current = next
    return next
  }, [editor, select])

  return useSyncExternalStore(subscribe, getSnapshot, getSnapshot)
}
