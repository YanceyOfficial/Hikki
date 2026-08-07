import { createReactInlineContentSpec } from '@blocknote/react'
import { useAtomValue } from 'jotai'
import { FileText } from 'lucide-react'

import { resolvePageMentionDisplay } from '#lib/page-mention'
import { docMetasAtom } from '#lib/store'
import { cn } from '#lib/utils'

export function PageMentionRender(props: {
  inlineContent: { props: { docId: string } }
}) {
  const { docId } = props.inlineContent.props
  const metas = useAtomValue(docMetasAtom)
  const { title, icon, isBroken } = resolvePageMentionDisplay(docId, metas)

  if (isBroken) {
    return (
      <span
        data-testid={`page-mention-broken-${docId}`}
        className="bg-muted/60 text-muted-foreground decoration-muted-foreground/50 mx-0.5 inline-flex max-w-fit items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm line-through"
      >
        {title}
      </span>
    )
  }

  return (
    <span
      data-testid={`page-mention-${docId}`}
      role="link"
      tabIndex={0}
      onClick={() => {
        window.location.hash = `#/doc/${docId}`
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault()
          window.location.hash = `#/doc/${docId}`
        }
      }}
      className={cn(
        'bg-muted mx-0.5 inline-flex max-w-fit cursor-pointer items-center gap-1 rounded-md px-1.5 py-0.5 align-baseline text-sm font-medium transition-colors',
        'hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <span className="shrink-0">
        {icon ?? <FileText className="size-3.5" />}
      </span>
      <span className="truncate">{title}</span>
    </span>
  )
}

export function createPageMentionSpec() {
  return createReactInlineContentSpec(
    {
      type: 'pageMention',
      propSchema: {
        docId: { default: '' }
      },
      content: 'none'
    } as const,
    {
      render: PageMentionRender
    }
  )
}
