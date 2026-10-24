import katex from 'katex'
import { useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'

import { t } from '../core/i18n'
import type { FloatingAnchor, FloatingLayer } from './floating'
import { IconProvider } from './icons'

type Props = {
  initial: string
  /** A block formula: the preview is set in display mode. */
  multiline: boolean
  onDone: (latex: string) => void
}

/**
 * LaTeX source on the left, its live KaTeX preview on the right (stacked in a narrow window). Enter makes a new line
 * — formulas are written over several (an array, cases) — and ⌘/Ctrl+Enter or Done finishes. KaTeX's output is
 * markup it generates (no `trust`), so it is safe.
 */
export function MathEditor({ initial, multiline, onDone }: Props) {
  const [latex, setLatex] = useState(initial)
  const preview = useMemo(() => {
    if (!latex.trim()) return null
    return katex.renderToString(latex, {
      displayMode: multiline,
      throwOnError: false,
      strict: 'ignore'
    })
  }, [latex, multiline])

  return (
    <div className="flex flex-col gap-2" data-testid="math-editor">
      <div className="grid gap-2 sm:grid-cols-2">
        <Textarea
          // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type a formula
          autoFocus
          rows={6}
          className="max-h-60 min-h-24 px-2 py-1.5 font-mono text-sm md:text-sm"
          placeholder={t('math.placeholder')}
          aria-label={t('math.label')}
          value={latex}
          onChange={(e) => setLatex(e.target.value)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return
            // Escape is the layers' bus (onDismiss cancels): it never reaches the field.
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) {
              e.preventDefault()
              onDone(latex)
            }
          }}
        />
        <div
          className="flex max-h-60 min-h-24 items-center justify-center overflow-auto rounded-md bg-muted px-2 py-1.5"
          data-testid="math-preview"
          // oxlint-disable-next-line react/no-danger -- KaTeX-generated markup, no user HTML
          dangerouslySetInnerHTML={{ __html: preview ?? '' }}
        />
      </div>
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">{t('math.hint')}</span>
        <Button size="xs" onClick={() => onDone(latex)}>
          {t('math.done')}
        </Button>
      </div>
    </div>
  )
}

/** Shows the editor in its floating layer beside the formula (the extension holds no JSX). */
export function renderMathEditor(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(
    <IconProvider>
      <MathEditor {...props} />
    </IconProvider>,
    anchor
  )
}
