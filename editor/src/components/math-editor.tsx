import katex from 'katex'
import { useMemo, useState } from 'react'

import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'

import { t } from '../core/i18n'
import type { FloatingAnchor, FloatingLayer } from './floating'

type Props = {
  initial: string
  /** Block formulas: Enter makes a new line, ⌘/Ctrl+Enter is Done. */
  multiline: boolean
  onDone: (latex: string) => void
  onCancel: () => void
}

/** LaTeX source with a live KaTeX preview. KaTeX's output is markup it generates (no `trust`), so it is safe. */
export function MathEditor({ initial, multiline, onDone, onCancel }: Props) {
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
      <Textarea
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type a formula
        autoFocus
        rows={multiline ? 3 : 1}
        className="min-h-9 px-2 py-1.5 font-mono text-sm md:text-sm"
        placeholder={t('math.placeholder')}
        aria-label={t('math.label')}
        value={latex}
        onChange={(e) => setLatex(e.target.value)}
        onKeyDown={(e) => {
          if (e.nativeEvent.isComposing) return
          if (e.key === 'Escape') {
            e.preventDefault()
            onCancel()
          } else if (e.key === 'Enter' && (!multiline || e.metaKey || e.ctrlKey)) {
            e.preventDefault()
            onDone(latex)
          }
        }}
      />
      {preview && (
        <div
          className="max-h-40 overflow-auto rounded-md bg-muted px-2 py-1.5 text-center"
          // oxlint-disable-next-line react/no-danger -- KaTeX-generated markup, no user HTML
          dangerouslySetInnerHTML={{ __html: preview }}
        />
      )}
      <div className="flex items-center justify-between">
        <span className="text-xs text-muted-foreground">
          {multiline ? t('math.hintBlock') : t('math.hintInline')}
        </span>
        <Button size="xs" onClick={() => onDone(latex)}>
          {t('math.done')}
        </Button>
      </div>
    </div>
  )
}

/** Shows the editor in its floating layer beside the formula (the extension holds no JSX). */
export function renderMathEditor(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(<MathEditor {...props} />, anchor)
}
