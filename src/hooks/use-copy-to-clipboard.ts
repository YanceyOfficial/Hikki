import { useCallback, useEffect, useRef, useState } from 'react'

import { reportError } from '#lib/errors'

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
        reportError('HK-1007', {
          message: error instanceof Error ? error.message : String(error)
        })
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
