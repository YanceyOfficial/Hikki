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
    <a
      href={hash}
      data-testid={`page-mention-${docId}`}
      className="no-underline!"
    >
      <span className="hover:bg-muted inline-flex items-center gap-0.5 rounded-md px-1">
        <span className="shrink-0">
          {icon ?? <FileText className="size-3.5" />}
        </span>
        <span className="truncate">{title}</span>
        {resolvedHeadingText && (
          <span className="truncate"> ({resolvedHeadingText})</span>
        )}
      </span>
    </a>
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
