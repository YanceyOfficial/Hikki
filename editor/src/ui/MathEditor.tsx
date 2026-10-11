import katex from 'katex'
import { useMemo, useState } from 'react'

import { t } from '../i18n'

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
      <textarea
        // oxlint-disable-next-line jsx-a11y/no-autofocus -- the panel opens to type a formula
        autoFocus
        rows={multiline ? 3 : 1}
        className="min-h-9 w-full resize-none rounded-md border border-input bg-transparent px-2 py-1.5 font-mono text-sm outline-none focus:border-ring focus:ring-3 focus:ring-ring/50"
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
        <button
          type="button"
          className="inline-flex h-7 cursor-pointer items-center rounded-md bg-primary px-2.5 text-xs text-primary-foreground"
          onClick={() => onDone(latex)}
        >
          {t('math.done')}
        </button>
      </div>
    </div>
  )
}
