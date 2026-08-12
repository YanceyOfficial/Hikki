import { createReactInlineContentSpec } from '@blocknote/react'
import { useAtomValue } from 'jotai'
import { FileText } from 'lucide-react'
import { useEffect } from 'react'

import { headingCacheAtom, loadHeadings } from '#lib/heading-mention-cache'
import {
  resolveHeadingMentionText,
  resolvePageMentionDisplay
} from '#lib/page-mention'
import { docMetasAtom } from '#lib/store'
import { cn } from '#lib/utils'

export function PageMentionRender(props: {
  inlineContent: {
    props: { docId: string; headingId?: string; headingText?: string }
  }
}) {
  const { docId, headingId = '', headingText = '' } = props.inlineContent.props
  const metas = useAtomValue(docMetasAtom)
  const { title, icon, isBroken } = resolvePageMentionDisplay(docId, metas)
  const updatedAt = metas.find((m) => m.id === docId)?.updatedAt ?? ''

  const headingCache = useAtomValue(headingCacheAtom)[docId]
  useEffect(() => {
    if (headingId && !isBroken) void loadHeadings(docId, updatedAt)
  }, [docId, headingId, isBroken, updatedAt])
  const resolvedHeadingText =
    headingId &&
    headingCache?.status === 'loaded' &&
    headingCache.updatedAt === updatedAt
      ? resolveHeadingMentionText(
          headingId,
          headingText,
          headingCache.headings.map((h) => h.id)
        )
      : null

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

  const hash = resolvedHeadingText
    ? `#/doc/${docId}?heading=${headingId}`
    : `#/doc/${docId}`

  return (
    <span
      data-testid={`page-mention-${docId}`}
      role="link"
      tabIndex={0}
      onClick={() => {
        window.location.hash = hash
      }}
      onKeyDown={(event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault()
          window.location.hash = hash
        }
      }}
      className={cn(
        'page-mention-pill bg-muted mx-0.5 inline-flex max-w-fit cursor-pointer items-center rounded-md px-1.5 py-0.5 align-baseline text-sm font-medium transition-colors',
        'hover:bg-accent hover:text-accent-foreground'
      )}
    >
      <span className="mr-1 shrink-0">
        {icon ?? <FileText className="size-3.5" />}
      </span>
      <span className="truncate">{title}</span>
      {resolvedHeadingText && (
        <span className="page-mention-suffix">
          <span
            className="page-mention-suffix-inner"
            data-testid="page-mention-heading-suffix"
          >
            #{resolvedHeadingText}
          </span>
        </span>
      )}
    </span>
  )
}

export function createPageMentionSpec() {
  return createReactInlineContentSpec(
    {
      type: 'pageMention',
      propSchema: {
        docId: { default: '' },
        headingId: { default: '' },
        headingText: { default: '' }
      },
      content: 'none'
    } as const,
    {
      render: PageMentionRender
    }
  )
}
