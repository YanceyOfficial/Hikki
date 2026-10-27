import { useState } from 'react'

import { Button } from '@/components/ui/button'

import { t } from '../core/i18n'
import { CheckIcon, CopyIcon, GlobeIcon } from '../generated/icons'
import type { FloatingAnchor, FloatingLayer } from './floating'
import { LinkPanel } from './selection-menu'

type Props = {
  href: string
  /** What the card names: the page's title for a page link, else the address itself. */
  display: string
  /** The card's editor is open (Edit was pressed): the link field in the card's place. */
  editing: boolean
  onEdit: () => void
  onApply: (href: string) => void
  onRemove: () => void
  onCancel: () => void
  onEnter: () => void
  onLeave: () => void
}

/**
 * Notion's link card: hovering a link shows where it goes, with Copy and Edit; Edit turns the card into the link
 * field (`LinkPanel`, the selection menu's), with Remove link. Drawn by `extensions/link-hover.ts`.
 */
export function LinkCard({
  href,
  display,
  editing,
  onEdit,
  onApply,
  onRemove,
  onCancel,
  onEnter,
  onLeave
}: Props) {
  const [copied, setCopied] = useState(false)
  const copy = () => {
    void navigator.clipboard?.writeText(href)
    setCopied(true)
    setTimeout(() => setCopied(false), 1200)
  }
  return (
    <div data-testid="link-card" onMouseEnter={onEnter} onMouseLeave={onLeave}>
      {editing ? (
        <div className="w-80">
          <LinkPanel href={href} onApply={onApply} onRemove={onRemove} onCancel={onCancel} />
        </div>
      ) : (
        <div className="flex items-center gap-1 text-sm">
          <GlobeIcon size={16} className="shrink-0 text-muted-foreground" aria-hidden />
          <span className="max-w-64 truncate text-muted-foreground" title={href}>
            {display}
          </span>
          <Button
            variant="ghost"
            size="icon-xs"
            className="shrink-0 text-muted-foreground"
            aria-label={t('link.copy')}
            onClick={copy}
          >
            {copied ? <CheckIcon aria-hidden /> : <CopyIcon aria-hidden />}
          </Button>
          <Button variant="ghost" size="xs" className="shrink-0" onClick={onEdit}>
            {t('link.edit')}
          </Button>
        </div>
      )}
    </div>
  )
}

export function renderLinkCard(layer: FloatingLayer, props: Props, anchor: FloatingAnchor): void {
  layer.render(<LinkCard {...props} />, anchor)
}
