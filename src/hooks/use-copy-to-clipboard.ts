import { useCallback, useEffect, useRef, useState } from 'react'

interface UseCopyToClipboardOptions {
  /** How long `copied` stays true after a successful copy, in ms. */
  resetDelayMs?: number
}

/**
 * Copies text to the clipboard and exposes a transient `copied` flag that
 * flips back to `false` after `resetDelayMs` - the "copy, then flash a
 * checkmark for a bit" state machine behind the code-block copy button.
 * Deliberately has no knowledge of DOM scanning/positioning so it can be
 * unit tested without mounting BlockNote.
 */
export function useCopyToClipboard({
  resetDelayMs = 1500
}: UseCopyToClipboardOptions = {}) {
  const [copied, setCopied] = useState(false)
  const timeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)

  useEffect(
    () => () => {
      if (timeoutRef.current) clearTimeout(timeoutRef.current)
    },
    []
  )

  const copy = useCallback(
    async (text: string) => {
      try {
        await navigator.clipboard.writeText(text)
      } catch (error) {
        // No toast system exists yet (tracked separately) to surface this to
        // the user - log it rather than fail with no trace at all.
        console.error('hikki: failed to copy code block to clipboard', error)
        return
      }

      setCopied(true)
      if (timeoutRef.current) clearTimeout(timeoutRef.current)
      timeoutRef.current = setTimeout(() => {
        setCopied(false)
        timeoutRef.current = null
      }, resetDelayMs)
    },
    [resetDelayMs]
  )

  return { copied, copy }
}
